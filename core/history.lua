-- Histórico de desfazer/refazer, com limite opcional de retenção de snapshots.
-- Os estados de tiles são capturados uma vez por gesto. No undo/redo, as
-- referências dos ImageData são TRANSFERIDAS: nenhum clone extra é necessário.
-- Um item de estrutura guarda referências de camadas (não congela seus pixels).
local H = {}

local DEFAULT_MAX_ENTRIES = 100
local DEFAULT_MAX_BYTES = 128 * 1024 * 1024 -- estimativa em RGBA8, não RAM real

function H.new()
  return {undo = {}, redo = {}, stroke = nil,
    maxEntries = DEFAULT_MAX_ENTRIES, maxBytes = DEFAULT_MAX_BYTES}
end

-- Evita que uma edição interrompa outra enquanto o balde cooperativo está
-- suspenso. O token é privado ao job do balde; APIs normais não o possuem.
function H.assertUnlocked(h, token)
  assert(h._fillLock == nil or h._fillLock == token,
    'documento ocupado por preenchimento cooperativo')
end

local function validLimit(n, integer)
  return type(n) == 'number' and n == n and n < math.huge and n > -math.huge
    and n >= (integer and 1 or 0) and (not integer or n == math.floor(n))
end

-- Contagem de bytes nominais RGBA8 de snapshots e camadas removidas.
-- Camadas ainda no documento não são atribuídas ao histórico: snapshots
-- estruturais apontam para as mesmas camadas, sem cópia dos seus pixels.
-- Esta é uma estimativa conservadora dos buffers, não uma medição de RAM.
local function imageBytes(image)
  if not image or not image.getWidth or not image.getHeight then return 0 end
  return image:getWidth() * image:getHeight() * 4
end

local function liveLayers(h)
  if not h._owner then return nil end
  local live = {}
  for _, layer in ipairs(h._owner.layers) do
    live[layer] = true
    if layer.mask then live[layer.mask] = true end
  end
  for _,g in pairs(h._owner.groups or {}) do
    if g.mask then live[g.mask] = true end
  end
  return live
end

local function itemBytes(item, live)
  local bytes = 0
  if item.structure then
    local seen = {}
    for i, layer in ipairs(item.snap.layers) do
      if not live or not live[layer] then
        for _, tile in pairs(layer.tiles) do
          if not seen[tile] then
            seen[tile] = true
            bytes = bytes + imageBytes(tile)
          end
        end
      end
      local mask = item.snap.props[i].mask
      if mask and (not live or not live[mask]) then
        for _, tile in pairs(mask.tiles) do
          if not seen[tile] then
            seen[tile] = true
            bytes = bytes + imageBytes(tile)
          end
        end
      end
    end
    for _,g in pairs(item.snap.groups or {}) do
      local mask=g.mask
      if mask and (not live or not live[mask]) then
        for _,tile in pairs(mask.tiles) do
          if not seen[tile] then seen[tile]=true; bytes=bytes+imageBytes(tile) end
        end
      end
    end
  else
    for _, entry in ipairs(item) do
      bytes = bytes + imageBytes(entry.before)
    end
  end
  return bytes
end

local function stackBytes(stack, live)
  local total = 0
  for _, item in ipairs(stack) do total = total + itemBytes(item, live) end
  return total
end

-- Mantém pelo menos o item mais recente, mesmo se ele isoladamente superar
-- o orçamento de bytes: uma pincelada grande ainda poderá ser desfeita.
local function trim(h)
  while #h.undo > h.maxEntries do table.remove(h.undo, 1) end
  local live = liveLayers(h)
  local bytes = stackBytes(h.undo, live)
  while bytes > h.maxBytes and #h.undo > 1 do
    bytes = bytes - itemBytes(table.remove(h.undo, 1), live)
  end
end

-- Para operações estruturais que alteram as camadas APÓS recordStructure.
function H.prune(h)
  H.assertUnlocked(h)
  trim(h)
end

-- H.setLimits(history, {maxEntries=100, maxBytes=128*1024*1024}).
-- nil preserva o valor corrente; ambos os limites são configuráveis.
function H.setLimits(h, options)
  H.assertUnlocked(h)
  assert(h.stroke == nil, 'não altere limites durante um gesto')
  assert(type(options) == 'table', 'limites devem ser uma tabela')
  local entries = options.maxEntries
  local bytes = options.maxBytes
  if entries ~= nil then
    assert(validLimit(entries, true), 'maxEntries deve ser inteiro >= 1')
  end
  if bytes ~= nil then
    assert(validLimit(bytes, false), 'maxBytes deve ser número >= 0')
  end
  if entries ~= nil then h.maxEntries = entries end
  if bytes ~= nil then h.maxBytes = bytes end
  trim(h)
  return H.stats(h)
end

-- Estimativa por snapshots, em unidades equivalentes a bytes RGBA8.
-- Não inclui overhead Lua, buffers de desenho vivos nem caches GPU.
function H.stats(h)
  local live = liveLayers(h)
  local u, r = stackBytes(h.undo, live), stackBytes(h.redo, live)
  return {undoEntries = #h.undo, redoEntries = #h.redo,
    undoBytes = u, redoBytes = r, totalBytes = u + r,
    maxEntries = h.maxEntries, maxBytes = h.maxBytes}
end

---------------------------------------------------------------- traços

function H.begin(h, token)
  H.assertUnlocked(h, token)
  assert(h.stroke == nil, 'já há um traço em andamento')
  h.stroke = {entries = {}, touched = {}}
end

-- Guarda o estado do tile antes da primeira alteração no traço atual.
function H.touch(h, layer, key, token)
  H.assertUnlocked(h, token)
  local s = h.stroke
  if not s then return end
  local lt = s.touched[layer]
  if not lt then
    lt = {}
    s.touched[layer] = lt
  end
  if lt[key] then return end
  lt[key] = true
  local existing = layer.tiles[key]
  s.entries[#s.entries + 1] = {layer = layer, key = key, before = existing and existing:clone() or false}
end

-- O snapshot da máscara é separado do snapshot RGBA da camada.
function H.touchMask(h, mask, key)
  H.assertUnlocked(h)
  local st = assert(h.stroke, 'pintura de máscara sem gesto')
  local touched = st.touched[mask]
  if not touched then touched = {}; st.touched[mask] = touched end
  if touched[key] then return end
  touched[key] = true
  local tile = mask.tiles[key]
  st.entries[#st.entries+1] = {maskTarget=mask, key=key,
    before=tile and tile:clone() or false}
end

-- Reverte o gesto em curso (para falha durante a pintura de máscara).
function H.rollback(h)
  H.assertUnlocked(h)
  local st=h.stroke
  if not st then return false end
  for _, e in ipairs(st.entries) do
    local target=e.maskTarget or e.layer
    target.tiles[e.key] = e.before or nil
    if e.maskTarget then
      require('core.mask').markDirty(target,e.key)
    else
      require('core.doc').markDirty(target,e.key)
    end
  end
  h.stroke=nil
  return true
end

function H.commit(h, token)
  H.assertUnlocked(h, token)
  local s = h.stroke
  h.stroke = nil
  if s and #s.entries > 0 then
    h.undo[#h.undo + 1] = s.entries
    h.redo = {}
    trim(h)
  end
end

---------------------------------------------------------------- estrutura

-- Captura a lista de camadas e as propriedades de cada uma.
function H.capture(doc)
  local layers, props = {}, {}
  for i, L in ipairs(doc.layers) do
    layers[i] = L
    props[i] = {visible = L.visible, opacity = L.opacity, blend = L.blend, name = L.name,
      clipped = L.clipped or false, groupId = L.groupId,
      mask = L.mask, maskEnabled = L.mask and L.mask.enabled,
      maskInverted = L.mask and L.mask.inverted,
      maskDefault = L.mask and L.mask.default}
  end
  local groups = {}
  for id, g in pairs(doc.groups or {}) do
    groups[id] = {id=id, parentId=g.parentId, name=g.name, visible=g.visible,
      opacity=g.opacity, blend=g.blend, mask=g.mask,
      maskEnabled=g.mask and g.mask.enabled, maskInverted=g.mask and g.mask.inverted,
      maskDefault=g.mask and g.mask.default}
  end
  return {layers = layers, props = props, sel = doc.sel,
    groups = groups, nextGroupId = doc.nextGroupId or 1}
end

local function restore(doc, snap)
  doc.layers = {}
  for i, L in ipairs(snap.layers) do
    doc.layers[i] = L
    local p = snap.props[i]
    L.visible, L.opacity, L.blend, L.name = p.visible, p.opacity, p.blend, p.name
    L.clipped, L.groupId = p.clipped or false, p.groupId
    L.mask = p.mask
    if p.mask then
      p.mask.enabled, p.mask.inverted, p.mask.default =
        p.maskEnabled, p.maskInverted, p.maskDefault
    end
  end
  doc.groups = {}
  for id, g in pairs(snap.groups or {}) do
    doc.groups[id] = {id=id, parentId=g.parentId, name=g.name, visible=g.visible,
      opacity=g.opacity, blend=g.blend, mask=g.mask}
    if g.mask then
      g.mask.enabled, g.mask.inverted, g.mask.default =
        g.maskEnabled, g.maskInverted, g.maskDefault
    end
  end
  doc.nextGroupId = snap.nextGroupId or 1
  doc.sel = snap.sel
end

-- Chamar ANTES de alterar a estrutura. Limpa o refazer.
function H.recordStructure(doc)
  local h = doc.history
  H.assertUnlocked(h)
  assert(h.stroke == nil, 'não altere camadas durante um gesto')
  h.undo[#h.undo + 1] = {structure = true, snap = H.capture(doc)}
  h.redo = {}
  trim(h)
end

---------------------------------------------------------------- desfazer / refazer

local function apply(entry)
  local target = entry.maskTarget or entry.layer
  target.tiles[entry.key] = entry.before or nil
  if entry.maskTarget then
    require('core.mask').markDirty(target, entry.key)
  else
    require('core.doc').markDirty(target, entry.key)
  end
end

-- Tira um item de `from`, move a referência atual a `to` e aplica o item.
-- O tile substituído deixa de pertencer ao documento, logo pode ser guardado
-- no histórico sem cópia. Gestos seguintes já isolam o estado via H.touch.
local function step(doc, from, to)
  local item = table.remove(from)
  if not item then return false end

  if item.structure then
    to[#to + 1] = {structure = true, snap = H.capture(doc)}
    restore(doc, item.snap)
    return true
  end

  local current = {}
  for i, e in ipairs(item) do
    local cur = (e.maskTarget or e.layer).tiles[e.key]
    current[i] = {layer = e.layer, maskTarget = e.maskTarget,
      key = e.key, before = cur or false}
  end
  to[#to + 1] = current
  for _, e in ipairs(item) do
    apply(e)
  end
  return true
end

function H.undo(doc)
  H.assertUnlocked(doc.history)
  assert(doc.history.stroke == nil, 'não desfaça durante um gesto')
  return step(doc, doc.history.undo, doc.history.redo)
end

function H.redo(doc)
  H.assertUnlocked(doc.history)
  assert(doc.history.stroke == nil, 'não refaça durante um gesto')
  local changed = step(doc, doc.history.redo, doc.history.undo)
  if changed then trim(doc.history) end
  return changed
end

return H
