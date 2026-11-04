-- Paint-Lua v0.28: miniaturas compostas de obras, inclusive grupos e máscaras.
-- Amostra no máximo 192x192 pixels e nunca aloca um canvas de largura x altura.
-- As regiões compostas ficam limitadas a um tile de 256x256 por vez.
local Composite = require('core.composite')
local Doc = require('core.doc')
local Preview = {}
local floor, min, max = math.floor, math.min, math.max
local TILE=Doc.TILE
local MAX_SIDE=192

local function valid(n)
  return type(n)=='number' and n==floor(n) and n>=1 and n<=MAX_SIDE
end

function Preview.render(doc, width, height)
  assert(type(doc)=='table' and type(doc.w)=='number' and type(doc.h)=='number'
    and doc.w>=1 and doc.h>=1, 'documento inválido')
  assert(valid(width) and valid(height), 'miniatura deve ter entre 1 e 192 pixels por lado')
  local image=love.image.newImageData(width,height)
  local fit=min(width/doc.w,height/doc.h)
  local dw=max(1,min(width,floor(doc.w*fit+0.5)))
  local dh=max(1,min(height,floor(doc.h*fit+0.5)))
  local left=floor((width-dw)/2)
  local top=floor((height-dh)/2)
  local requests={}
  for y=0,dh-1 do
    local sy=min(doc.h-1,floor((y+0.5)*doc.h/dh))
    local ty=floor(sy/TILE)
    for x=0,dw-1 do
      local sx=min(doc.w-1,floor((x+0.5)*doc.w/dw))
      local tx=floor(sx/TILE)
      local key=tx..','..ty
      local entry=requests[key]
      if not entry then
        entry={tx=tx,ty=ty,samples={}}
        requests[key]=entry
      end
      entry.samples[#entry.samples+1]={x=left+x,y=top+y,sx=sx,sy=sy}
    end
  end
  -- Tile sem pixels em nenhuma camada é comprovadamente transparente.
  -- Não precisa chamar o compositor para cada pixel vazio da imagem.
  for key,request in pairs(requests) do
    local occupied=false
    for _,layer in ipairs(doc.layers) do
      if layer.tiles[key] then occupied=true;break end
    end
    if occupied then
      local x,y=request.tx*TILE,request.ty*TILE
      local w,h=min(TILE,doc.w-x),min(TILE,doc.h-y)
      local composited=Composite.flattenRegion(doc,x,y,w,h)
      for _,p in ipairs(request.samples) do
        image:setPixel(p.x,p.y,composited:getPixel(p.sx-x,p.sy-y))
      end
    end
  end
  return image
end

return Preview
