-- Transformação raster com prévia não destrutiva (v0.24–v0.33).
-- Sessão em modo Pixelado (compatibilidade) ou Suave (bilinear premultiplied
-- com cobertura subpixel). A aplicação é um único gesto no histórico.
local Doc=require('core.doc')
local Selection=require('core.selection')
local Mask=require('core.mask')
local Hist=require('core.history')
local T={}
local abs,cos,sin,floor,ceil,min,max=math.abs,math.cos,math.sin,math.floor,math.ceil,math.min,math.max
local LIMIT=1000000
local TILE=Doc.TILE
local function finite(n)
  return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge
end
local function validScale(n)
  return finite(n) and abs(n)>=0.125 and abs(n)<=8
end
local function srcPixel(layer,x,y)
  local tx,ty=floor(x/TILE),floor(y/TILE)
  local tile=layer.tiles[tx..','..ty]
  if tile then return tile:getPixel(x%TILE,y%TILE) end
  return 0,0,0,0
end
local function ensureImage(s)
  if not love.graphics or not love.graphics.newImage then return nil end
  if not s.previewImage then
    s.previewImage=love.graphics.newImage(s.source)
  end
  -- Sem interpolação explícita (transformações de seleção), mantém nearest.
  -- Sessões de PNG podem alternar entre nearest e linear sem recriar a GPU.
  local filter=s.interpolation=='smooth' and 'linear' or 'nearest'
  if s.previewFilter~=filter then
    s.previewImage:setFilter(filter,filter)
    s.previewFilter=filter
  end
  return s.previewImage
end

function T.begin(doc,layer,selection,opts)
  opts=opts or {}
  assert(opts.interpolation==nil or opts.interpolation=='smooth' or
    opts.interpolation=='pixelated','interpolação desconhecida')
  assert(doc and type(doc.layers)=='table' and type(layer)=='table','documento/camada inválidos')
  Hist.assertUnlocked(doc.history)
  assert(doc.history.stroke==nil,'termine a pincelada antes de transformar')
  assert(doc.layers[doc.sel]==layer,'transforme apenas a camada ativa')
  selection=selection or doc.selection
  assert(selection,'selecione uma área antes de transformar')
  Selection.validate(doc,selection)
  local w,h=selection.w,selection.h
  assert(w<=8192 and h<=8192 and w*h<=LIMIT,'área maior que o limite de 1 milhão de pixels')
  local source=love.image.newImageData(w,h)
  local occupied=false
  for yy=0,h-1 do
    for xx=0,w-1 do
      local x,y=selection.x+xx,selection.y+yy
      if Selection.contains(selection,x,y) then
        local r,g,b,a=srcPixel(layer,x,y)
        if a>0 then
          source:setPixel(xx,yy,r,g,b,a)
          occupied=true
        end
      end
    end
  end
  return {doc=doc,layer=layer,selection=selection,source=source,
    x=selection.x,y=selection.y,w=w,h=h,hasPixels=occupied,
    dx=0,dy=0,scaleX=1,scaleY=1,angle=0,active=true,
    interpolation=opts.interpolation or 'pixelated'}
end

function T.setInterpolation(s,mode)
  assert(s and s.active,'transformação encerrada')
  assert(mode=='smooth' or mode=='pixelated','interpolação desconhecida')
  s.interpolation=mode
  return mode
end

function T.set(s,dx,dy,scaleX,scaleY,angle)
  assert(s and s.active,'transformação encerrada')
  assert(finite(dx) and finite(dy) and abs(dx)<=65536 and abs(dy)<=65536,
    'deslocamento inválido')
  assert(validScale(scaleX) and validScale(scaleY),'escala inválida')
  assert(finite(angle) and abs(angle)<=math.pi*2000,'rotação inválida')
  s.dx,s.dy,s.scaleX,s.scaleY,s.angle=dx,dy,scaleX,scaleY,angle
  return s
end

local function point(s,x,y)
  local cx,cy=s.x+s.w/2,s.y+s.h/2
  local u,v=(x-cx)*s.scaleX,(y-cy)*s.scaleY
  return cx+s.dx+u*cos(s.angle)-v*sin(s.angle),
    cy+s.dy+u*sin(s.angle)+v*cos(s.angle)
end
function T.bounds(s)
  assert(s and s.active,'transformação encerrada')
  local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for _,pair in ipairs({{s.x,s.y},{s.x+s.w,s.y},{s.x+s.w,s.y+s.h},{s.x,s.y+s.h}}) do
    local x,y=point(s,pair[1],pair[2])
    x0=min(x0,x);y0=min(y0,y);x1=max(x1,x);y1=max(y1,y)
  end
  return {x=x0,y=y0,w=x1-x0,h=y1-y0}
end
function T.inverse(s,x,y)
  local cx,cy=s.x+s.w/2,s.y+s.h/2
  local u,v=x-cx-s.dx,y-cy-s.dy
  return cx+(u*cos(s.angle)+v*sin(s.angle))/s.scaleX,
    cy+(-u*sin(s.angle)+v*cos(s.angle))/s.scaleY
end

function T.cancel(s)
  if not s or not s.active then return false end
  s.active=false
  if s.previewImage and s.previewImage.release then s.previewImage:release() end
  s.previewImage=nil
  s.previewFilter=nil
  return true
end

local function setPixel(s,x,y,r,g,b,a)
  local layer=s.layer
  local tx,ty=floor(x/TILE),floor(y/TILE)
  local tile,key=Doc.getTile(layer,tx,ty,a>0)
  if not tile then return end
  Hist.touch(s.doc.history,layer,key)
  -- A imagem do tile já existia: histórico captura antes de editar.
  tile:setPixel(x%TILE,y%TILE,r,g,b,a)
  Doc.markDirty(layer,key)
end

-- Amostragem bilinear em RGBA pré-multiplicado: pixels transparentes
-- nunca introduzem RGB escuro ou de cores estranhas no contorno.
-- u/v são coordenadas relativas à borda superior esquerda do ImageData.
local function bilinear(img,w,h,u,v)
  local ix,iy=floor(u-0.5),floor(v-0.5)
  local fx,fy=u-0.5-ix,v-0.5-iy
  local x0,x1=max(0,min(w-1,ix)),max(0,min(w-1,ix+1))
  local y0,y1=max(0,min(h-1,iy)),max(0,min(h-1,iy+1))
  local r00,g00,b00,a00=img:getPixel(x0,y0)
  local r10,g10,b10,a10=img:getPixel(x1,y0)
  local r01,g01,b01,a01=img:getPixel(x0,y1)
  local r11,g11,b11,a11=img:getPixel(x1,y1)
  local w00,w10=(1-fx)*(1-fy),fx*(1-fy)
  local w01,w11=(1-fx)*fy,fx*fy
  local a=a00*w00+a10*w10+a01*w01+a11*w11
  if a<=0 then return 0,0,0,0 end
  return (r00*a00*w00+r10*a10*w10+r01*a01*w01+r11*a11*w11)/a,
    (g00*a00*w00+g10*a10*w10+g01*a01*w01+g11*a11*w11)/a,
    (b00*a00*w00+b10*a10*w10+b01*a01*w01+b11*a11*w11)/a,a
end

-- Retorna RGBA, e também a cobertura da SELEÇÃO (separada da opacidade).
-- Em regiões internas, uma amostra bilinear é suficiente. Próximo a bordas
-- oblíquas/irregulares, 4x4 subamostras evitam serrilhados sem reamostrar
-- todo um canvas grande 16 vezes.
local function smoothPixel(s,x,y)
  local sel=s.selection
  local sx,sy=T.inverse(s,x+0.5,y+0.5)
  local u,v=sx-s.x,sy-s.y
  local c,si=abs(cos(s.angle)),abs(sin(s.angle))
  local padU=(c+si)/(2*abs(s.scaleX))
  local padV=(c+si)/(2*abs(s.scaleY))
  if u < -padU or v < -padV or u > s.w+padU or v > s.h+padV then
    return 0,0,0,0,0
  end
  local aroundEdge=(u<padU or u>s.w-padU or v<padV or v>s.h-padV)
  if not aroundEdge and (sel.kind=='wand' or sel.kind=='polygon') then
    local ix,iy=floor(sx),floor(sy)
    local center=Selection.contains(sel,ix,iy)
    aroundEdge = Selection.contains(sel,ix-1,iy)~=center or
      Selection.contains(sel,ix+1,iy)~=center or
      Selection.contains(sel,ix,iy-1)~=center or
      Selection.contains(sel,ix,iy+1)~=center
  end
  local oblique=abs(sin(s.angle*2))>1e-8
  local aligned=(abs(s.scaleX)==1 and abs(s.scaleY)==1 and
    s.dx==floor(s.dx) and s.dy==floor(s.dy) and not oblique)
  -- Transformação por um número inteiro de pixels conserva RGB/alpha exatos.
  local n=(aroundEdge and not aligned) and 4 or 1
  local pr,pg,pb,alpha,coverage=0,0,0,0,0
  for iy=0,n-1 do
    for ix=0,n-1 do
      local ux,uy=T.inverse(s,x+(ix+0.5)/n,y+(iy+0.5)/n)
      local tx,ty=ux-s.x,uy-s.y
      if tx>=0 and ty>=0 and tx<s.w and ty<s.h
        and Selection.contains(sel,floor(ux),floor(uy)) then
        coverage=coverage+1
        local r,g,b,a=bilinear(s.source,s.w,s.h,tx,ty)
        alpha=alpha+a
        pr=pr+r*a;pg=pg+g*a;pb=pb+b*a
      end
    end
  end
  if alpha<=0 then return 0,0,0,0,coverage/(n*n) end
  return pr/alpha,pg/alpha,pb/alpha,alpha/(n*n),coverage/(n*n)
end

-- Uma seleção movida vira uma máscara raster (inclusive laços e varinha).
-- A máscara e o resultado permanecem temporários até o commit.
function T.commit(s)
  assert(s and s.active,'transformação encerrada')
  local doc,layer,sel=s.doc,s.layer,s.selection
  Hist.assertUnlocked(doc.history)
  assert(doc.layers[doc.sel]==layer and doc.selection==sel,
    'camada ou seleção mudou durante a prévia')
  assert(doc.history.stroke==nil,'outra operação de pincel em andamento')
  local b=T.bounds(s)
  local x0,y0=max(0,floor(b.x)),max(0,floor(b.y))
  local x1,y1=min(doc.w,ceil(b.x+b.w)),min(doc.h,ceil(b.y+b.h))
  local count=0
  if x1<=x0 or y1<=y0 then return nil,'transformação fora do canvas' end
  assert((x1-x0)*(y1-y0)<=LIMIT,'destino excede 1 milhão de pixels')
  local selectionMask=Mask.new(0)
  local bx0,by0,bx1,by1=doc.w,doc.h,-1,-1
  -- Coleta destino antes de tocar o documento. Assim, nenhuma origem é
  -- contaminada pelo próprio resultado (sobreposições/rotação).
  local writes={}
  for y=y0,y1-1 do
    for x=x0,x1-1 do
      local r,g,b,a,coverage
      if s.interpolation=='smooth' then
        r,g,b,a,coverage=smoothPixel(s,x,y)
      else
        local sx,sy=T.inverse(s,x+0.5,y+0.5)
        local ix,iy=floor(sx),floor(sy)
        if ix>=sel.x and iy>=sel.y and ix<sel.x+s.w and iy<sel.y+s.h
          and Selection.contains(sel,ix,iy) then
          r,g,b,a=s.source:getPixel(ix-sel.x,iy-sel.y)
          coverage=1
        end
      end
      if coverage and coverage>0 then
        local m=Mask.getTile(selectionMask,floor(x/TILE),floor(y/TILE),true)
        m:setPixel(x%TILE,y%TILE,1,1,1,1)
        bx0=min(bx0,x);by0=min(by0,y);bx1=max(bx1,x);by1=max(by1,y)
        if a>0 then writes[#writes+1]={x,y,r,g,b,a} end
      end
    end
  end
  if bx1<bx0 then return nil,'nenhum pixel selecionado no canvas' end
  local newSel={kind='wand',x=bx0,y=by0,w=bx1-bx0+1,h=by1-by0+1,mask=selectionMask}
  local h=doc.history
  Hist.begin(h)
  local ok,err=pcall(function()
    -- Primeiro recorta a fonte apenas dentro da seleção.
    for y=sel.y,sel.y+sel.h-1 do
      for x=sel.x,sel.x+sel.w-1 do
        if Selection.contains(sel,x,y) then
          local _,_,_,a=srcPixel(layer,x,y)
          if a>0 then setPixel(s,x,y,0,0,0,0) end
        end
      end
    end
    -- Depois cola, com composição source-over dos pixels sobreviventes.
    for _,p in ipairs(writes) do
      local x,y,sr,sg,sb,sa=p[1],p[2],p[3],p[4],p[5],p[6]
      local dr,dg,db,da=srcPixel(layer,x,y)
      local outA=sa+da*(1-sa)
      if outA>0 then
        setPixel(s,x,y,(sr*sa+dr*da*(1-sa))/outA,
          (sg*sa+dg*da*(1-sa))/outA,(sb*sa+db*da*(1-sa))/outA,outA)
        count=count+1
      end
    end
  end)
  if not ok then
    Hist.rollback(h)
    return nil,'transformação cancelada: '..tostring(err)
  end
  -- Histórico misto: gesto de pixels e nova máscara de seleção em um undo.
  Hist.commit(h,nil,{selectionBefore=sel})
  doc.selection=newSel
  T.cancel(s)
  return count,newSel
end

function T.drawPreview(s,x,y)
  if not s or not s.active or not love.graphics then return end
  local g=love.graphics
  local img=ensureImage(s)
  if not img then return end
  local cx,cy=s.x+s.w/2,s.y+s.h/2
  g.push()
  g.translate(x+cx+s.dx,y+cy+s.dy)
  g.rotate(s.angle)
  g.scale(s.scaleX,s.scaleY)
  g.setColor(1,1,1,0.75)
  g.draw(img,-s.w/2,-s.h/2)
  g.pop()
  local b=T.bounds(s)
  g.setColor(0.25,0.84,1,1)
  g.rectangle('line',x+b.x,y+b.y,b.w,b.h)
  g.setColor(1,1,1,1)
end
return T
