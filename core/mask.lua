-- Máscara raster por camada. Valor cinza 0 esconde, 1 revela.
-- Tiles ausentes usam máscara.default (0 ou 1 por padrão).
-- Cada tile presente usa RGBA=(v,v,v,1); r é a fonte canônica da cobertura.
local Doc = require('core.doc')
local M = {}
local floor, max, min = math.floor, math.max, math.min
local function level(v)
  assert(type(v)=='number' and v == v and v ~= math.huge and v ~= -math.huge
    and v>=0 and v<=1, 'cobertura de máscara deve estar entre 0 e 1')
  return v
end
function M.new(default)
  default = default == nil and 1 or level(default)
  return {enabled=true, inverted=false, default=default, tiles={}, revisions={}}
end
function M.markDirty(mask, key)
  mask.revisions = mask.revisions or {}
  mask.revisions[key] = (mask.revisions[key] or 0) + 1
end
function M.getTile(mask, tx, ty, create)
  local key = tx .. ',' .. ty
  local tile = mask.tiles[key]
  if not tile and create then
    tile = love.image.newImageData(Doc.TILE, Doc.TILE)
    if mask.default ~= 0 then
      local v = mask.default
      for y=0, Doc.TILE-1 do
        for x=0, Doc.TILE-1 do tile:setPixel(x,y,v,v,v,1) end
      end
    end
    mask.tiles[key]=tile
  end
  return tile,key
end
function M.value(mask,x,y)
  if not mask or not mask.enabled then return 1 end
  local tile = M.getTile(mask,floor(x/Doc.TILE),floor(y/Doc.TILE),false)
  local v = tile and select(1,tile:getPixel(x%Doc.TILE,y%Doc.TILE)) or mask.default
  if mask.inverted then v=1-v end
  return max(0,min(1,v))
end
function M.duplicate(src)
  if not src then return nil end
  local dest=M.new(src.default)
  dest.enabled=src.enabled
  dest.inverted=src.inverted
  for key, tile in pairs(src.tiles) do
    dest.tiles[key]=tile:clone()
    M.markDirty(dest,key)
  end
  return dest
end
return M
