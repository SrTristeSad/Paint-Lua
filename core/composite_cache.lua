-- Cache de tiles da composição CPU, v0.15.
-- Não reutiliza a tabela layer.dirty: Render.refresh pode limpá-la.
-- Snapshot depende da ordem/propriedades de camadas e da revisão/identidade
-- de cada ImageData naquele tile. Pixels modificados devem usar Doc.markDirty.
local Doc = require('core.doc')
local Composite = require('core.composite')
local floor, min = math.floor, math.min
local T = Doc.TILE
local Cache = {}
Cache.__index = Cache

local function validInt(n)
  return type(n)=='number' and n == floor(n) and n >= 0 and n < math.huge
end

local function tileBounds(doc, tx, ty)
  assert(validInt(tx) and validInt(ty) and tx * T < doc.w and ty * T < doc.h,
    'tile fora dos limites')
  local x, y = tx*T, ty*T
  return x, y, min(T, doc.w-x), min(T, doc.h-y)
end

local function signature(doc, key)
  local layers = {}
  -- A ordem é importante mesmo se nenhuma camada tiver pixels naquele tile.
  for i, layer in ipairs(doc.layers) do
    local m = layer.mask
    layers[i] = {
      layer, layer.visible, layer.opacity, layer.blend,
      layer.tiles[key], (layer.revisions and layer.revisions[key]) or 0,
      m, m and m.enabled, m and m.inverted, m and m.default,
      m and m.tiles[key], m and ((m.revisions and m.revisions[key]) or 0),
      layer.clipped or false, layer.groupId
    }
  end
  -- Propriedades dos grupos precisam invalidar até tiles em que todos os
  -- membros estejam vazios: um cache anterior não pode sobreviver a undo/redo.
  local ids = {}
  for id in pairs(doc.groups or {}) do ids[#ids+1] = id end
  table.sort(ids)
  for _,id in ipairs(ids) do
    local g = doc.groups[id]
    local m=g.mask
    layers[#layers+1] = {g, g.visible, g.opacity, g.blend, g.name, id,
      g.parentId, m, m and m.enabled, m and m.inverted, m and m.default,
      m and m.tiles[key], m and ((m.revisions and m.revisions[key]) or 0)}
  end
  return layers
end

local function same(a,b)
  if #a ~= #b then return false end
  for i=1,#a do
    local x,y = a[i],b[i]
    for j=1,16 do if x[j] ~= y[j] then return false end end
  end
  return true
end

local function bytes(data)
  return data:getWidth() * data:getHeight() * 4
end

function Cache.new(doc, options)
  assert(type(doc)=='table' and type(doc.layers)=='table'
    and validInt(doc.w) and validInt(doc.h) and doc.w>0 and doc.h>0,
    'documento inválido')
  options = options or {}
  assert(type(options)=='table','opções devem ser uma tabela')
  local maxTiles = options.maxTiles or 16
  assert(validInt(maxTiles) and maxTiles >= 1 and maxTiles <= 4096,
    'maxTiles deve ser inteiro entre 1 e 4096')
  return setmetatable({doc=doc,maxTiles=maxTiles, entries={}, count=0, used=0,
      tick=0,hits=0,misses=0,evictions=0,recompositions=0},Cache)
end

-- Interno. Não exponha a ImageData retornada: é usada como backing do cache.
function Cache:_get(tx,ty)
  local x,y,w,h = tileBounds(self.doc,tx,ty)
  local key=tx..','..ty
  local hst = self.doc.history
  -- Durante strokes ou jobs de preenchimento uma revisão pode preceder
  -- pixels ainda não escritos. Produza o resultado, mas não o guarde.
  if hst and (hst.stroke or hst._fillLock) then
    return Composite.flattenRegion(self.doc,x,y,w,h)
  end
  local sig=signature(self.doc,key)
  local e=self.entries[key]
  self.tick=self.tick+1
  if e and same(e.sig,sig) then
    self.hits=self.hits+1
    e.last=self.tick
    return e.data
  end
  self.misses=self.misses+1
  local result=Composite.flattenRegion(self.doc,x,y,w,h)
  self.recompositions=self.recompositions+1
  if e then
    self.used=self.used-bytes(e.data)
  else
    self.count=self.count+1
  end
  self.entries[key]={sig=sig,data=result,last=self.tick}
  self.used=self.used+bytes(result)
  if self.count>self.maxTiles then
    local oldestKey,oldest
    for k,v in pairs(self.entries) do
      if k~=key and (not oldest or v.last<oldest) then
        oldestKey,oldest=k,v.last
      end
    end
    if oldestKey then
      self.used=self.used-bytes(self.entries[oldestKey].data)
      self.entries[oldestKey]=nil
      self.count=self.count-1
      self.evictions=self.evictions+1
    end
  end
  return result
end

-- Retorno independente: editar o resultado nunca corrompe o cache.
function Cache:tile(tx,ty)
  return self:_get(tx,ty):clone()
end

-- Retorna a imagem recortada, usando o cache por tile de 256x256.
-- Mesmo com tiles vazios, respeita toda a região e mantém transparência.
function Cache:region(x,y,w,h)
  local d=self.doc
  assert(validInt(x) and validInt(y) and validInt(w) and validInt(h)
    and w>0 and h>0 and x+w<=d.w and y+h<=d.h,
    'região fora dos limites')
  local result=love.image.newImageData(w,h)
  local tx0,ty0=floor(x/T),floor(y/T)
  local tx1,ty1=floor((x+w-1)/T),floor((y+h-1)/T)
  for ty=ty0,ty1 do
    for tx=tx0,tx1 do
      local tile=self:_get(tx,ty)
      local x0,y0=math.max(tx*T,x),math.max(ty*T,y)
      local x1,y1=math.min((tx+1)*T,x+w),math.min((ty+1)*T,y+h)
      for py=y0,y1-1 do
        for px=x0,x1-1 do
          result:setPixel(px-x,py-y,tile:getPixel(px-tx*T,py-ty*T))
        end
      end
    end
  end
  return result
end

function Cache:clear()
  self.entries={}
  self.count=0
  self.used=0
end

function Cache:stats()
  return {tiles=self.count,maxTiles=self.maxTiles,estimatedBytes=self.used,
    hits=self.hits,misses=self.misses,evictions=self.evictions,
    recompositions=self.recompositions}
end

return Cache
