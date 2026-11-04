-- Renderização na tela: converte tiles alterados em Images e desenha camadas visíveis.
local Doc = require('core.doc')
local BlendModes = require('core.blend')
local Composite = require('core.composite')
local floor, min, max = math.floor, math.min, math.max
local R = {}
local BLEND = {normal = 'alpha', multiply = 'multiply', screen = 'screen', darken = 'darken', lighten = 'lighten'}
-- Em modos que não mapeiam exatamente para o blend nativo do LÖVE,
-- ou quando há máscaras, desenhar tiles já compostos pela CPU.
local compositeStates=setmetatable({}, {__mode='k'})
local function needsComposited(doc)
  if next(doc.groups or {}) then return true end
  for _, layer in ipairs(doc.layers) do
    if layer.clipped then return true end
    if layer.visible and layer.opacity>0 and
      (layer.mask or not BlendModes.legacy[layer.blend]) then return true end
  end
  return false
end

local function R_drawComposited(doc, px,py,zoom,clip)
  assert(type(zoom)=='number' and zoom>0 and clip and clip.w>0 and clip.h>0,
    'viewport inválida')
  local state=compositeStates[doc]
  if not state then
    state={cpu=Composite.newCache(doc,{maxTiles=64}), gpu={}}
    compositeStates[doc]=state
  end
  love.graphics.setScissor(clip.x,clip.y,clip.w,clip.h)
  love.graphics.setBlendMode('alpha')
  love.graphics.setColor(1,1,1,1)
  local step=Doc.TILE*zoom
  local tx0=max(0,floor((clip.x-px)/step))
  local ty0=max(0,floor((clip.y-py)/step))
  local tx1=min(floor((doc.w-1)/Doc.TILE),floor((clip.x+clip.w-px)/step))
  local ty1=min(floor((doc.h-1)/Doc.TILE),floor((clip.y+clip.h-py)/step))
  local seen={}
  for ty=ty0,ty1 do
    for tx=tx0,tx1 do
      local key=tx..','..ty
      seen[key]=true
      local previous=state.cpu:stats().recompositions
      local pixels=state.cpu:_get(tx,ty)
      local changed=state.cpu:stats().recompositions>previous
        or (doc.history and (doc.history.stroke or doc.history._fillLock))
      local img=state.gpu[key]
      if not img then
        img=love.graphics.newImage(pixels)
        state.gpu[key]=img
      elseif changed then
        img:replacePixels(pixels)
      end
      love.graphics.draw(img, px+tx*step,py+ty*step,0,zoom,zoom)
    end
  end
  -- GPU armazena somente tiles que continuam na viewport.
  for key,img in pairs(state.gpu) do
    if not seen[key] then
      if img.release then img:release() end
      state.gpu[key]=nil
    end
  end
  love.graphics.setBlendMode('alpha')
  love.graphics.setColor(1,1,1,1)
end

local function R_clearComposited(doc)
  local state=compositeStates[doc]
  if not state then return end
  for _,img in pairs(state.gpu) do if img.release then img:release() end end
  state.cpu:clear()
  compositeStates[doc]=nil
end

local function inViewport(key, px, py, zoom, clip)
  if not clip then return true end
  -- Coordenadas inválidas: não arrisque perder atualização necessária.
  if not px or not py or not zoom or zoom <= 0 then return true end
  local tx, ty = Doc.parseKey(key)
  if not tx then return true end
  local side = Doc.TILE * zoom
  local x, y = px + tx * side, py + ty * side
  return x < clip.x + clip.w and y < clip.y + clip.h
    and x + side > clip.x and y + side > clip.y
end

-- Sem argumentos extras, conserva o comportamento da v0.10 (todos os tiles sujos).
-- Com (px, py, zoom, clip) converte apenas tiles visíveis; os outros PERMANECEM
-- sujos para atualização quando a viewport se mover.
function R.refresh(doc, px, py, zoom, clip)
  for _, layer in ipairs(doc.layers) do
    local pending = {}
    for key in pairs(layer.dirty) do
      local tile = layer.tiles[key]
      local img = layer.images[key]
      if tile and not inViewport(key, px, py, zoom, clip) then
        pending[key] = true
      elseif tile then
        if img then img:replacePixels(tile)
        else layer.images[key] = love.graphics.newImage(tile) end
      elseif img then
        layer.images[key] = nil
        if img.release then img:release() end
      end
    end
    layer.dirty = pending
  end
end

-- Libera explicitamente imagens de tiles fora da viewport para reduzir a VRAM.
-- Seus ImageData de origem NÃO são perdidos; ao reaparecerem, R.refresh refaz
-- as Images marcadas como sujas. Use apenas se desejar um cache GPU limitado.
function R.evictOutside(doc, px, py, zoom, clip)
  assert(clip and type(clip) == 'table', 'clip obrigatório')
  local evicted = 0
  for _, layer in ipairs(doc.layers) do
    for key, img in pairs(layer.images) do
      if not inViewport(key, px, py, zoom, clip) then
        layer.images[key] = nil
        if layer.tiles[key] then layer.dirty[key] = true end
        if img.release then img:release() end
        evicted = evicted + 1
      end
    end
  end
  return evicted
end

R.drawComposited=R_drawComposited
R.clearComposited=R_clearComposited

function R.draw(doc, px, py, zoom, clip)
  if needsComposited(doc) then return R.drawComposited(doc,px,py,zoom,clip) end
  -- Ao retornar ao caminho nativo, libera o cache composto previamente usado.
  if compositeStates[doc] then R.clearComposited(doc) end
  love.graphics.setScissor(clip.x, clip.y, clip.w, clip.h)
  for _, layer in ipairs(doc.layers) do
    if layer.visible and layer.opacity > 0 then
      love.graphics.setBlendMode(BLEND[layer.blend] or 'alpha')
      love.graphics.setColor(1, 1, 1, layer.opacity / 100)
      for key, img in pairs(layer.images) do
        if inViewport(key, px, py, zoom, clip) then
          local tx, ty = Doc.parseKey(key)
          local x, y = px + tx * Doc.TILE * zoom, py + ty * Doc.TILE * zoom
          love.graphics.draw(img, x, y, 0, zoom, zoom)
        end
      end
    end
  end
  love.graphics.setBlendMode('alpha')
  love.graphics.setColor(1, 1, 1, 1)
end

return R
