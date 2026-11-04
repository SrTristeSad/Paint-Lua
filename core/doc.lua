-- Documento, camadas e tiles.
-- Cada camada guarda pixels em tiles de 256x256 (ImageData), criados sob demanda.
-- Tiles inexistentes são transparentes e não ocupam memória.
local Hist = require("core.history")

local Doc = {}
Doc.TILE = 256

function Doc.parseKey(key)
  local a, b = key:match("^(-?%d+),(-?%d+)$")
  return tonumber(a), tonumber(b)
end

-- Incrementa uma revisão INDEPENDENTE do sinal dirty consumido pela GPU.
-- O cache CPU observa revisões sem consultar hashes de pixels.
function Doc.markDirty(layer, key)
  layer.dirty[key] = true
  layer.revisions = layer.revisions or {}
  layer.revisions[key] = (layer.revisions[key] or 0) + 1
end

function Doc.getTile(layer, tx, ty, create)
  local key = tx .. "," .. ty
  local t = layer.tiles[key]
  if not t and create then
    t = love.image.newImageData(Doc.TILE, Doc.TILE)
    layer.tiles[key] = t
  end
  return t, key
end

function Doc.newLayer(name)
  return {
    name = name,
    visible = true,
    opacity = 100,     -- 0..100
    blend = "normal",  -- normal | multiply | screen | darken | lighten
    tiles = {},        -- "tx,ty" -> ImageData
    images = {},       -- "tx,ty" -> love.graphics.Image (cache de tela)
    dirty = {},        -- "tx,ty" -> true quando precisa atualizar a imagem
    revisions = {},    -- "tx,ty" -> versão de pixels para cache CPU
    mask = nil,        -- máscara de cobertura opcional (core.mask)
    clipped = false,   -- alfa recortado pela camada base inferior no mesmo grupo
    groupId = nil,     -- identificador do grupo imediato
  }
end

function Doc.duplicateLayer(src)
  local L = Doc.newLayer(src.name .. " cópia")
  L.visible = src.visible
  L.opacity = src.opacity
  L.blend = src.blend
  L.mask = require('core.mask').duplicate(src.mask)
  L.clipped, L.groupId = src.clipped or false, src.groupId
  for key, t in pairs(src.tiles) do
    L.tiles[key] = t:clone()
    Doc.markDirty(L, key)
  end
  return L
end

function Doc.new(w, h, name)
  local doc = {
    name = name,
    w = w,
    h = h,
    layers = {Doc.newLayer("Fundo"), Doc.newLayer("Camada 1")},
    groups = {},       -- id -> {id, parentId, name, visible, opacity, blend, mask}
    nextGroupId = 1,
    sel = 2,
    selection = nil,   -- {x, y, w, h} em coordenadas do documento, ou nil
    tool = "brush",
    size = 8,
    opacity = 100,
    color = nil,       -- definido pelo editor a partir da paleta
    history = Hist.new(),
  }
  -- Permite estimar somente as camadas efetivamente retidas pelo histórico,
  -- sem contar novamente as ImageData que ainda fazem parte do documento.
  doc.history._owner = doc
  return doc
end

return Doc
