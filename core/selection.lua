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
