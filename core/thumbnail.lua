-- v0.26: miniaturas raster REAIS e pequenas, amostradas diretamente dos tiles.
-- Sem varrer imagens inteiras; cache invalidado por identidade/revisão dos tiles.
-- Separar miniatura da camada (RGBA bruto) da miniatura da máscara (cinza).
local Doc = require('core.doc')
local T = {}
local floor, min, max = math.floor, math.min, math.max
local TILE = Doc.TILE

local function integer(n)
  return type(n)=='number' and n==floor(n) and n>=1 and n<=128
end

local function source(layer, kind)
  if kind=='layer' then return layer,layer.tiles,layer.revisions end
  assert(kind=='mask','tipo de miniatura desconhecido')
  local mask=assert(layer.mask,'camada ou grupo sem máscara')
  return mask,mask.tiles,mask.revisions
end

-- Snapshot conserva as referências originais: desfazer/refazer ou troca de
-- ImageData invalidam a miniatura sem depender da flag dirty da GPU.
function T.signature(doc, layer, kind, width, height)
  assert(integer(width) and integer(height),'dimensões inválidas')
  local obj,tiles,revisions=source(layer,kind)
  local keys={}
  for key in pairs(tiles) do keys[#keys+1]=key end
  table.sort(keys)
  local state={doc.w,doc.h,width,height,kind,obj}
  if kind=='mask' then
    state[#state+1]=obj.default
    state[#state+1]=obj.inverted
    state[#state+1]=obj.enabled
  end
  for _,key in ipairs(keys) do
    state[#state+1]=key
    state[#state+1]=tiles[key]
    state[#state+1]=(revisions and revisions[key]) or 0
  end
  return state
end

function T.same(a,b)
  if not a or not b or #a~=#b then return false end
  for i=1,#a do if a[i]~=b[i] then return false end end
  return true
end

-- Mantém a proporção do documento: não distorce imagens retrato/paisagem.
-- O custo de render é O(width * height) independentemente dos megapixels.
function T.render(doc, layer, kind, width, height)
  assert(type(doc)=='table' and doc.w>0 and doc.h>0,'documento inválido')
  assert(integer(width) and integer(height),'dimensões inválidas')
  local obj,tiles=source(layer,kind)
  local out=love.image.newImageData(width,height)
  local scale=min(width/doc.w,height/doc.h)
  local dw=max(1,min(width,floor(doc.w*scale+0.5)))
  local dh=max(1,min(height,floor(doc.h*scale+0.5)))
  local sx=floor((width-dw)/2)
  local sy=floor((height-dh)/2)
  for y=0,dh-1 do
    local py=min(doc.h-1,floor((y+0.5)*doc.h/dh))
    local ty=floor(py/TILE)
    for x=0,dw-1 do
      local px=min(doc.w-1,floor((x+0.5)*doc.w/dw))
      local tile=tiles[floor(px/TILE)..','..ty]
      if kind=='layer' then
        if tile then
          out:setPixel(sx+x,sy+y,tile:getPixel(px%TILE,py%TILE))
        end
      else
        local v=tile and select(1,tile:getPixel(px%TILE,py%TILE)) or obj.default
        -- Retrato da cobertura efetiva, mesmo se máscara desativada: o
        -- botão de ativação decide composição; a miniatura conserva o mapa.
        if obj.inverted then v=1-v end
        out:setPixel(sx+x,sy+y,v,v,v,1)
      end
    end
  end
  return out
end
return T
