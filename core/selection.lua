-- Seleções raster do Paint-Lua v0.23.
-- Retângulos continuam a usar {x,y,w,h}; formas complexas são imutáveis
-- depois de atribuídas ao documento e podem ser guardadas no histórico.
local Doc=require('core.doc')
local Mask=require('core.mask')
local Job=require('core.job')
local S={}
local floor,min,max,abs=math.floor,math.min,math.max,math.abs
local T=Doc.TILE
local MAX_POINTS=4096
local MAX_WAND_PIXELS=2000000 -- evita processar imagens enormes sem limite
local function finite(x)
  return type(x)=='number' and x==x and x>-math.huge and x<math.huge
end
local function int(x,a,b)
  return finite(x) and x==floor(x) and x>=a and x<=b
end

function S.rect(doc,x0,y0,x1,y1)
  assert(doc and int(doc.w,1,65536) and int(doc.h,1,65536),'documento inválido')
  assert(finite(x0) and finite(y0) and finite(x1) and finite(y1),'coordenadas inválidas')
  local a,b=floor(min(x0,x1)),floor(min(y0,y1))
  local c,d=floor(max(x0,x1))+1,floor(max(y0,y1))+1
  a=max(0,a);b=max(0,b);c=min(doc.w,c);d=min(doc.h,d)
  if c<=a or d<=b then return nil end
  return {x=a,y=b,w=c-a,h=d-b}
end

function S.polygon(doc,points)
  assert(doc and int(doc.w,1,65536) and int(doc.h,1,65536),'documento inválido')
  assert(type(points)=='table' and #points>=3 and #points<=MAX_POINTS,
    'laço deve ter entre 3 e 4096 vértices')
  local p,x0,y0,x1,y1={},doc.w,doc.h,0,0
  for i,point in ipairs(points) do
    assert(type(point)=='table' and finite(point[1]) and finite(point[2]),
      'ponto de laço inválido')
    local x= max(0,min(doc.w,floor(point[1]+0.5)))
    local y= max(0,min(doc.h,floor(point[2]+0.5)))
    if i==1 or x~=p[#p][1] or y~=p[#p][2] then
      p[#p+1]={x,y}
      x0=min(x0,x);y0=min(y0,y);x1=max(x1,x);y1=max(y1,y)
    end
  end
  if #p<3 or x0==x1 or y0==y1 then return nil end
  local selection={kind='polygon',x=x0,y=y0,w=x1-x0,h=y1-y0,points=p}
  return selection
end

-- Ray casting com interseções horizontais por linha, em cache limitado.
-- Evita percorrer milhares de vértices em CADA pixel de uma pincelada.
local function polygonInside(sel,x,y)
  local row=floor(y)
  local rows=sel._scanRows
  if not rows then rows={};sel._scanRows=rows;sel._scanCount=0 end
  local crossings=rows[row]
  if not crossings then
    crossings={}
    local prev=sel.points[#sel.points]
    for _,p in ipairs(sel.points) do
      local ay,by=p[2],prev[2]
      if (ay>y)~=(by>y) then
        crossings[#crossings+1]=p[1]+(y-ay)*(prev[1]-p[1])/(by-ay)
      end
      prev=p
    end
    table.sort(crossings)
    if sel._scanCount<256 then
      rows[row]=crossings
      sel._scanCount=sel._scanCount+1
    end
  end
  -- Número de cruzamentos à direita determina a paridade (par/ímpar).
  local lo,hi=1,#crossings
  while lo<=hi do
    local mid=floor((lo+hi)/2)
    if crossings[mid]<=x then lo=mid+1 else hi=mid-1 end
  end
  return (#crossings-lo+1)%2==1
end

function S.contains(sel,x,y)
  if not sel then return true end
  if not finite(x) or not finite(y) then return false end
  x=floor(x);y=floor(y)
  if x<sel.x or y<sel.y or x>=sel.x+sel.w or y>=sel.y+sel.h then return false end
  if sel.kind=='polygon' then
    return polygonInside(sel,x+0.5,y+0.5)
  elseif sel.kind=='wand' then
    return Mask.value(sel.mask,x,y)>0.5
  end
  return sel.kind==nil or sel.kind=='rect'
end

-- Para máscaras menores, gera segmentos exatos do contorno uma única vez.
-- Retorna nil em regiões grandes/complexas para evitar custo de RAM/FPS.
function S.outline(sel,maxArea,maxSegments)
  if not sel or sel.kind~='wand' then return nil end
  maxArea=maxArea or 262144
  maxSegments=maxSegments or 4096
  if sel.w*sel.h>maxArea then return nil end
  local lines={}
  for y=sel.y,sel.y+sel.h-1 do
    for x=sel.x,sel.x+sel.w-1 do
      if S.contains(sel,x,y) then
        local function add(a,b,c,d)
          lines[#lines+1]={a,b,c,d}
          if #lines>maxSegments then return false end
          return true
        end
        if not S.contains(sel,x,y-1) and not add(x,y,x+1,y) then return nil end
        if not S.contains(sel,x+1,y) and not add(x+1,y,x+1,y+1) then return nil end
        if not S.contains(sel,x,y+1) and not add(x+1,y+1,x,y+1) then return nil end
        if not S.contains(sel,x-1,y) and not add(x,y+1,x,y) then return nil end
      end
    end
  end
  return lines
end


-- Contornos incrementais para máscaras raster extensas/esparsas (v0.37).
-- Ao contrário de outline(), percorre só os tiles materializados, mesmo
-- quando a bbox abrange um canvas enorme. O resultado é reutilizável entre
-- zoom, rotação e pan: todas as linhas estão em coordenadas do documento.
-- Para máscaras invertidas, percorre também o perímetro externo selecionado.
local function addOutlineLine(job,x0,y0,x1,y1)
  local horizontal=(y0==y1)
  local runs=horizontal and job.horizontalRuns or job.verticalRuns
  local key=horizontal and y0 or x0
  local prev=runs[key]
  local old=prev and job.lines[prev]
  if old and ((horizontal and old[3]==x0 and old[4]==y0)
    or (not horizontal and old[3]==x0 and old[4]==y0)) then
    old[3],old[4]=x1,y1
    return true
  end
  if #job.lines>=job.maxSegments then
    job.done=true;job.truncated=true
    return false
  end
  job.lines[#job.lines+1]={x0,y0,x1,y1}
  runs[key]=#job.lines
  return true
end

function S.startOutline(sel,opts)
  assert(sel and sel.kind=='wand' and sel.mask and
    type(sel.mask.tiles)=='table','contorno exige máscara de seleção')
  opts=opts or {}
  local maxSegments=opts.maxSegments or 8192
  assert(int(maxSegments,1,65536),'limite de segmentos inválido')
  local keys={}
  for key,tile in pairs(sel.mask.tiles) do
    local tx,ty=Doc.parseKey(key)
    assert(tx and ty and tile,'tile da seleção inválido')
    keys[#keys+1]={tx=tx,ty=ty,tile=tile}
  end
  table.sort(keys,function(a,b)
    return a.ty<b.ty or (a.ty==b.ty and a.tx<b.tx)
  end)
  return {selection=sel,keys=keys,index=1,px=0,py=0,
    borderSide=1,borderPos=0,borderStart=nil,
    phase=sel.mask.inverted and 'border' or 'tiles',
    lines={},horizontalRuns={},verticalRuns={},
    maxSegments=maxSegments,scanned=0,done=false,truncated=false}
end

-- Cada chamada processa no máximo budget pontos (o default é um lote pequeno
-- para não travar quadros). Linhas já calculadas são exatas; nenhuma moldura
-- inventada é usada quando ainda restam tiles por examinar.
function S.stepOutline(job,budget)
  assert(type(job)=='table' and job.selection and job.lines,
    'sessão de contorno inválida')
  budget=budget or 8192
  assert(int(budget,1,131072),'orçamento de contorno inválido')
  if job.done then return true,job.lines end
  local sel=job.selection
  local remaining=budget
  while remaining>0 and not job.done do
    if job.phase=='border' then
      if job.borderSide>4 then
        job.phase='tiles'
      else
        local side=job.borderSide
        local horizontal=side<=2
        local length=horizontal and sel.w or sel.h
        local p=job.borderPos
        if p>=length then
          if job.borderStart~=nil then
            local first=job.borderStart
            local a,b,c,d
            if side==1 then a,b,c,d=sel.x+first,sel.y,sel.x+p,sel.y
            elseif side==2 then a,b,c,d=sel.x+first,sel.y+sel.h,sel.x+p,sel.y+sel.h
            elseif side==3 then a,b,c,d=sel.x,sel.y+first,sel.x,sel.y+p
            else a,b,c,d=sel.x+sel.w,sel.y+first,sel.x+sel.w,sel.y+p end
            addOutlineLine(job,a,b,c,d)
            job.borderStart=nil
          end
          job.borderSide=side+1
          job.borderPos=0
        else
          local x,y
          if side==1 then x,y=sel.x+p,sel.y
          elseif side==2 then x,y=sel.x+p,sel.y+sel.h-1
          elseif side==3 then x,y=sel.x,sel.y+p
          else x,y=sel.x+sel.w-1,sel.y+p end
          local selected=S.contains(sel,x,y)
          if selected then
            if job.borderStart==nil then job.borderStart=p end
          elseif job.borderStart~=nil then
            local first=job.borderStart
            local a,b,c,d
            if side==1 then a,b,c,d=sel.x+first,sel.y,sel.x+p,sel.y
            elseif side==2 then a,b,c,d=sel.x+first,sel.y+sel.h,sel.x+p,sel.y+sel.h
            elseif side==3 then a,b,c,d=sel.x,sel.y+first,sel.x,sel.y+p
            else a,b,c,d=sel.x+sel.w,sel.y+first,sel.x+sel.w,sel.y+p end
            addOutlineLine(job,a,b,c,d)
            job.borderStart=nil
          end
          job.borderPos=p+1
          job.scanned=job.scanned+1
          remaining=remaining-1
        end
      end
    else
      local entry=job.keys[job.index]
      if not entry then
        job.done=true
      else
        local x,y=entry.tx*T+job.px,entry.ty*T+job.py
        local inside=x>=sel.x and y>=sel.y
          and x<sel.x+sel.w and y<sel.y+sel.h
        if inside and select(1,entry.tile:getPixel(job.px,job.py))>0.5 then
          -- Examina apenas os pixels da máscara positiva armazenada.
          -- Em uma máscara invertida, esses pixels representam furos.
          local inverted=sel.mask.inverted
          if S.contains(sel,x,y-1)==inverted then
            addOutlineLine(job,x,y,x+1,y)
          end
          if not job.done and S.contains(sel,x+1,y)==inverted then
            addOutlineLine(job,x+1,y,x+1,y+1)
          end
          if not job.done and S.contains(sel,x,y+1)==inverted then
            addOutlineLine(job,x,y+1,x+1,y+1)
          end
          if not job.done and S.contains(sel,x-1,y)==inverted then
            addOutlineLine(job,x,y,x,y+1)
          end
        end
        job.px=job.px+1
        if job.px>=T then
          job.px=0
          job.py=job.py+1
          if job.py>=T then
            job.py=0
            job.index=job.index+1
          end
        end
        job.scanned=job.scanned+1
        remaining=remaining-1
      end
    end
  end
  return job.done,job.lines
end

function S.validate(doc,sel)
  if sel==nil then return true end
  assert(type(sel)=='table' and int(sel.x,0,doc.w-1) and int(sel.y,0,doc.h-1)
    and int(sel.w,1,doc.w) and int(sel.h,1,doc.h)
    and sel.x+sel.w<=doc.w and sel.y+sel.h<=doc.h,
    'limites de seleção inválidos')
  local kind=sel.kind
  assert(kind==nil or kind=='rect' or kind=='polygon' or kind=='wand',
    'tipo de seleção desconhecido')
  if kind=='polygon' then
    assert(type(sel.points)=='table' and #sel.points>=3 and
      #sel.points<=MAX_POINTS,'vértices de laço inválidos')
    for _,p in ipairs(sel.points) do
      assert(type(p)=='table' and int(p[1],0,doc.w)
        and int(p[2],0,doc.h),'ponto fora do documento')
    end
  elseif kind=='wand' then
    local mask=sel.mask
    assert(type(mask)=='table' and mask.default==0 and mask.enabled==true
      and type(mask.inverted)=='boolean' and type(mask.tiles)=='table',
      'máscara de varinha inválida')
    local tiles=0
    for key,tile in pairs(mask.tiles) do
      local tx,ty=Doc.parseKey(key)
      assert(tx and ty and key==tx..','..ty
        and int(tx,0,floor((doc.w-1)/T)) and int(ty,0,floor((doc.h-1)/T)),
        'tile de seleção inválido')
      assert(tile and tile:getWidth()==T and tile:getHeight()==T,
        'dimensões da seleção inválidas')
      tiles=tiles+1
      assert(tiles<=MAX_WAND_PIXELS,'máscara de seleção excessiva')
    end
  end
  return true
end

local function layerPixel(layer,x,y)
  local tx,ty=floor(x/T),floor(y/T)
  local tile=layer.tiles[tx..','..ty]
  if tile then return tile:getPixel(x-tx*T,y-ty*T) end
  return 0,0,0,0
end

local function flood(doc,layer,seedX,seedY,tolerance,yieldEvery,maxPixels)
  assert(doc and int(doc.w,1,65536) and int(doc.h,1,65536),'documento inválido')
  assert(type(layer)=='table' and type(layer.tiles)=='table','camada inválida')
  assert(finite(seedX) and finite(seedY),'origem inválida')
  tolerance=tolerance or 0.08
  assert(finite(tolerance) and tolerance>=0 and tolerance<=1,'tolerância inválida')
  maxPixels=maxPixels or MAX_WAND_PIXELS
  assert(int(maxPixels,1,MAX_WAND_PIXELS),'limite de pixels inválido')
  seedX,seedY=floor(seedX),floor(seedY)
  if seedX<0 or seedY<0 or seedX>=doc.w or seedY>=doc.h then return nil end
  local tr,tg,tb,ta=layerPixel(layer,seedX,seedY)
  local mask=Mask.new(0)
  local selected={kind='wand',x=seedX,y=seedY,w=1,h=1,mask=mask}
  local xMin,xMax,yMin,yMax=seedX,seedX,seedY,seedY
  local count,units=0,0
  local function checkpoint()
    if not yieldEvery then return end
    units=units+1
    if units>=yieldEvery then
      units=0
      coroutine.yield(math.min(0.99,count/maxPixels))
    end
  end
  local function marked(x,y)
    local tile=mask.tiles[floor(x/T)..','..floor(y/T)]
    return tile~=nil and select(1,tile:getPixel(x%T,y%T))>0.5
  end
  local function matches(x,y)
    if x<0 or x>=doc.w or y<0 or y>=doc.h or marked(x,y) then return false end
    checkpoint()
    local r,g,b,a=layerPixel(layer,x,y)
    return max(abs(r-tr),abs(g-tg),abs(b-tb),abs(a-ta))<=tolerance
  end
  local function mark(x,y)
    count=count+1
    assert(count<=maxPixels,'varinha excedeu o limite de '..maxPixels..' pixels')
    local tile=Mask.getTile(mask,floor(x/T),floor(y/T),true)
    tile:setPixel(x%T,y%T,1,1,1,1)
    xMin=min(xMin,x);xMax=max(xMax,x);yMin=min(yMin,y);yMax=max(yMax,y)
  end
  local queue={{seedX,seedY}};local head=1
  while head<=#queue do
    local seed=queue[head];queue[head]=false;head=head+1
    local x,y=seed[1],seed[2]
    if matches(x,y) then
      local left,right=x,x
      while left>0 and matches(left-1,y) do left=left-1 end
      while right+1<doc.w and matches(right+1,y) do right=right+1 end
      for px=left,right do mark(px,y);checkpoint() end
      for dir=-1,1,2 do
        local ny=y+dir
        if ny>=0 and ny<doc.h then
          local px=left
          while px<=right do
            if matches(px,ny) then
              queue[#queue+1]={px,ny}
              repeat px=px+1 until px>right or not matches(px,ny)
            else px=px+1 end
          end
        end
      end
    end
  end
  selected.x=xMin;selected.y=yMin
  selected.w=xMax-xMin+1;selected.h=yMax-yMin+1
  return selected
end


-- Inverte regiões sem alocar máscara para o canvas inteiro.
-- Usa o bit inverted já serializado pelo formato NPNT5.
function S.invert(doc,sel)
  assert(doc and int(doc.w,1,65536) and int(doc.h,1,65536),'documento inválido')
  if not sel then return S.rect(doc,0,0,doc.w-1,doc.h-1) end
  S.validate(doc,sel)
  if (sel.kind==nil or sel.kind=='rect') and sel.x==0 and sel.y==0
    and sel.w==doc.w and sel.h==doc.h then return nil end
  local mask
  if sel.kind=='wand' then
    -- Não modificar a máscara original: histórico usa objetos imutáveis.
    mask=Mask.new(0)
    mask.tiles=sel.mask.tiles
    mask.revisions=sel.mask.revisions
    mask.inverted=not sel.mask.inverted
    if not mask.inverted then
      local x0,y0,x1,y1=doc.w,doc.h,-1,-1
      local checked=0
      for key,tile in pairs(mask.tiles) do
        local tx,ty=Doc.parseKey(key)
        checked=checked+1
        if checked>256 then return nil,'Inversão limitada a 256 tiles' end
        for y=0,T-1 do
          local py=ty*T+y
          if py<doc.h then
            for x=0,T-1 do
              local px=tx*T+x
              if px<doc.w and select(1,tile:getPixel(x,y))>0.5 then
                x0=min(x0,px);y0=min(y0,py)
                x1=max(x1,px);y1=max(y1,py)
              end
            end
          end
        end
      end
      if x1<0 then return nil end
      return {kind='wand',x=x0,y=y0,w=x1-x0+1,h=y1-y0+1,mask=mask}
    end
  else
    if sel.w*sel.h>2000000 then
      return nil,'Inversão limitada a 2 milhões de pixels da seleção original'
    end
    mask=Mask.new(0)
    for y=sel.y,sel.y+sel.h-1 do
      for x=sel.x,sel.x+sel.w-1 do
        if S.contains(sel,x,y) then
          local tile=Mask.getTile(mask,floor(x/T),floor(y/T),true)
          tile:setPixel(x%T,y%T,1,1,1,1)
        end
      end
    end
    mask.inverted=true
  end
  return {kind='wand',x=0,y=0,w=doc.w,h=doc.h,mask=mask}
end


-- Operações booleanas sobre seleções. Um resultado vazio é uma máscara vazia,
-- NÃO nil: nil no Paint-Lua significa pintar sem restrição.
-- Seleções invertidas usam o bit inverted do NPNT5 e tiles de exceção.
local MODES={replace=true,add=true,subtract=true,intersect=true}
local MAX_COMBINE_PIXELS=2000000
local MAX_COMBINE_TILES=256
local function combineBool(a,b,mode)
  if mode=='add' then return a or b end
  if mode=='subtract' then return a and not b end
  return a and b -- intersect
end
local function isFullInverse(doc,sel)
  return sel.kind=='wand' and sel.mask.inverted and
    sel.x==0 and sel.y==0 and sel.w==doc.w and sel.h==doc.h
end

function S.combine(doc,previous,incoming,mode)
  assert(doc and int(doc.w,1,65536) and int(doc.h,1,65536),'documento inválido')
  assert(MODES[mode],'modo de combinação inválido')
  if previous then S.validate(doc,previous) end
  if incoming then S.validate(doc,incoming) end
  if mode=='replace' then return incoming end
  if not incoming then return nil,'Nova região vazia' end
  if not previous then
    if mode=='add' then return incoming end
    return nil,'Selecione uma área antes de subtrair ou intersectar'
  end

  -- Fora dos tiles candidatos, a seleção positiva é falsa; uma
  -- máscara invertida de tela inteira tem valor padrão verdadeiro.
  local aDefault=isFullInverse(doc,previous)
  local bDefault=isFullInverse(doc,incoming)
  for _,sel in ipairs({previous,incoming}) do
    if sel.kind=='wand' and sel.mask.inverted and
      not isFullInverse(doc,sel) then
      return nil,'Máscara inversa parcial não é combinável'
    end
  end
  local resultDefault=combineBool(aDefault,bDefault,mode)
  local keys={}
  local totalTiles=0
  local totalPixels=0
  local function addTile(tx,ty)
    local key=tx..','..ty
    if keys[key] then return true end
    local w=min(T,doc.w-tx*T)
    local h=min(T,doc.h-ty*T)
    if w<=0 or h<=0 then return end
    totalTiles=totalTiles+1
    totalPixels=totalPixels+w*h
    if totalTiles>MAX_COMBINE_TILES or totalPixels>MAX_COMBINE_PIXELS then
      return nil,'Combinação excede 2 milhões de pixels / 256 tiles'
    end
    keys[key]={tx=tx,ty=ty,w=w,h=h}
    return true
  end
  local function collect(sel)
    if sel.kind=='wand' then
      for key in pairs(sel.mask.tiles) do
        local tx,ty=Doc.parseKey(key)
        local ok,err=addTile(tx,ty)
        if not ok then return nil,err end
      end
    else
      local tx0,ty0=floor(sel.x/T),floor(sel.y/T)
      local tx1,ty1=floor((sel.x+sel.w-1)/T),floor((sel.y+sel.h-1)/T)
      for ty=ty0,ty1 do
        for tx=tx0,tx1 do
          local ok,err=addTile(tx,ty)
          if not ok then return nil,err end
        end
      end
    end
    return true
  end
  local ok,err=collect(previous)
  if not ok then return nil,err end
  ok,err=collect(incoming)
  if not ok then return nil,err end

  local mask=Mask.new(0)
  mask.inverted=resultDefault
  local x0,y0,x1,y1=doc.w,doc.h,-1,-1
  local sorted={}
  for _,info in pairs(keys) do sorted[#sorted+1]=info end
  table.sort(sorted,function(a,b)
    return a.ty==b.ty and a.tx<b.tx or a.ty<b.ty
  end)
  for _,info in ipairs(sorted) do
    local tile=nil
    for yy=0,info.h-1 do
      local y=info.ty*T+yy
      for xx=0,info.w-1 do
        local x=info.tx*T+xx
        local present=combineBool(S.contains(previous,x,y),
          S.contains(incoming,x,y),mode)
        if present~=resultDefault then
          if not tile then tile=Mask.getTile(mask,info.tx,info.ty,true) end
          tile:setPixel(xx,yy,1,1,1,1)
          if not resultDefault then
            x0=min(x0,x);y0=min(y0,y)
            x1=max(x1,x);y1=max(y1,y)
          end
        end
      end
    end
  end
  if resultDefault or x1<0 then
    -- Máscara vazia continua selecionando ZERO pixels; nil não serviria.
    return {kind='wand',x=0,y=0,w=doc.w,h=doc.h,mask=mask}
  end
  return {kind='wand',x=x0,y=y0,w=x1-x0+1,h=y1-y0+1,mask=mask}
end

function S.wand(doc,layer,x,y,tolerance,opts)
  opts=opts or {}
  return flood(doc,layer,x,y,tolerance,nil,opts.maxPixels)
end

function S.newWandJob(doc,layer,x,y,tolerance,opts)
  opts=opts or {}
  local every=opts.yieldEvery or 512
  assert(int(every,1,65536),'yieldEvery inválido')
  -- Só a seleção final é atribuída ao doc; cancelar não modifica o documento.
  return Job.new(function()
    return flood(doc,layer,x,y,tolerance,every,opts.maxPixels)
  end)
end
return S
