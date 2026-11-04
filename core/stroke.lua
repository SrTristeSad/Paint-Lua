-- Traço contínuo para caneta/toque: suavização, espaçamento estável entre eventos,
-- pressão e histórico transacional. Sem dependência da UI nem de love.graphics.
-- Referência conceitual: PhotoCraft crates/paint/src/dynamics.rs.
--
-- API:
--   local s = Stroke.new(doc, layer, doc.history, opts)
--   s:push(x, y, pressure, timeMs, tiltX, tiltY) -- tilt opcional: -1..1
--   s:finish()                      -- termina e cria UMA entrada de undo
--   s:cancel()                      -- reverte os pixels, sem alterar undo/redo
--
-- opts.smoothing = {mode="exponential"|"pulled", amount=0..1,
--                   zoom=1, adjustForZoom=false, catchUpOnEnd=true}
-- opts adicionais: tip, angle, tiltScale, flow, scatter, seed,
-- dualBrush, paper, mix ou wetPaint; consulte README.
-- Quando flow é especificado, a cobertura acumula num buffer por gesto, mas a
-- opacidade do traço é limitada por alpha (com pressão: maior alpha atingido).
-- Sem smoothing, a trajetória é fiel aos eventos. As mesmas coordenadas em
-- blocos diferentes geram o mesmo espaçamento, inclusive em cruzamento de tiles.
local Brush = require("core.brush")
local Hist = require("core.history")
local Doc = require("core.doc")
local Curve = require("core.curve")
local Tip = require("core.tip")
local Texture = require("core.texture")
local Mixer = require("core.mixer")
local Stroke = {}
Stroke.__index = Stroke

local function finite(x)
  return type(x) == "number" and x == x and x > -math.huge and x < math.huge
end
local function valid01(x)
  return finite(x) and x >= 0 and x <= 1
end
local function copy(t)
  if type(t) ~= "table" then return t end
  -- Máscaras raster de seleção são imutáveis enquanto há gesto ativo:
  -- não duplicar centenas de milhares de pixels por pincelada.
  if t.kind == 'wand' and t.mask then return t end
  local result = {}
  for k, v in pairs(t) do result[k] = copy(v) end
  return result
end
local function config(s)
  if s == nil then return {mode = "exponential", amount = 0, catchUpOnEnd = true} end
  if type(s) == "number" then s = {amount = s} end
  assert(type(s) == "table", "configuração de estabilização inválida")
  local mode = s.mode or "exponential"
  local amount = s.amount or 0
  local zoom = s.zoom or 1
  assert(mode == "exponential" or mode == "pulled", "tipo de estabilização inválido")
  assert(valid01(amount), "estabilização deve estar entre 0 e 1")
  assert(finite(zoom) and zoom > 0, "zoom de estabilização inválido")
  return {mode = mode, amount = amount, zoom = zoom,
    adjustForZoom = s.adjustForZoom == true, catchUpOnEnd = s.catchUpOnEnd ~= false}
end

function Stroke.new(doc, layer, history, opts)
  assert(type(doc) == "table" and type(doc.layers) == "table", "documento inválido")
  assert(type(opts) == "table", "opções do pincel inválidas")
  history = history or doc.history
  assert(history == doc.history and history.stroke == nil, "já há um traço em andamento")
  local found = false
  for _, L in ipairs(doc.layers) do
    if L == layer then found = true; break end
  end
  if not found and opts._groupMaskId then
    local group=doc.groups and doc.groups[opts._groupMaskId]
    found=opts.target=='mask' and group and group.mask and group.mask==layer.mask
  end
  assert(found, "camada ou máscara de grupo não pertence ao documento")
  assert(opts.target == nil or opts.target == "mask", "destino de traço inválido")
  if opts.target == "mask" then
    assert(layer.mask ~= nil, "camada não possui máscara")
    assert(opts.mix == nil and opts.wetPaint == nil,
      "mistura e tinta úmida não são suportadas em máscaras")
    assert(opts.maskValue == nil or valid01(opts.maskValue),
      "maskValue deve estar entre 0 e 1")
  end
  assert(finite(opts.size) and opts.size > 0 and opts.size <= 5000, "tamanho inválido")
  assert(valid01(opts.alpha), "opacidade de pincel inválida")
  assert(valid01(opts.hardness), "dureza inválida")
  assert(type(opts.color) == "table" and valid01(opts.color[1])
    and valid01(opts.color[2]) and valid01(opts.color[3]), "cor inválida")
  local spacing = opts.spacing or 0.15
  assert(finite(spacing) and spacing > 0 and spacing <= 2, "espaçamento inválido")
  assert(opts.eraser == nil or type(opts.eraser) == "boolean", "borracha inválida")
  assert(opts.alphaLock == nil or type(opts.alphaLock) == 'boolean',
    'alphaLock deve ser booleano')
  if opts.flow ~= nil then assert(valid01(opts.flow), "fluxo inválido") end
  if opts.scatter ~= nil then
    assert(finite(opts.scatter) and opts.scatter >= 0 and opts.scatter <= 10,
      "dispersão inválida")
  end
  if opts.seed ~= nil then
    assert(finite(opts.seed) and opts.seed >= 0 and opts.seed <= 4294967295
      and opts.seed == math.floor(opts.seed), "semente de dispersão inválida")
  end
  if opts.angle ~= nil then assert(finite(opts.angle), "ângulo de ponta inválido") end
  if opts.tiltScale ~= nil then assert(valid01(opts.tiltScale), "escala de tilt inválida") end
  for _, name in ipairs({"tiltX", "tiltY"}) do
    if opts[name] ~= nil then
      assert(finite(opts[name]) and opts[name] >= -1 and opts[name] <= 1,
        "inclinação de caneta inválida")
    end
  end
  if opts.pressureMinSize ~= nil then
    assert(valid01(opts.pressureMinSize), "pressão mínima de tamanho inválida")
  end
  if opts.pressureMinOpacity ~= nil then
    assert(valid01(opts.pressureMinOpacity), "pressão mínima de opacidade inválida")
  end
  local o = copy(opts) -- o chamador pode editar configurações após iniciar o traço
  if o.selection == nil and doc.selection then o.selection = doc.selection end
  if o.target == "mask" then o._maskTarget = layer.mask end
  for _, key in ipairs({"pressureCurve", "pressureSizeCurve", "pressureOpacityCurve"}) do
    if o[key] ~= nil then
      -- Compilar uma vez, em vez de recalcular as tangentes a cada carimbo.
      if getmetatable(opts[key]) == Curve then
        o[key] = Curve.new(opts[key].points)
      else
        o[key] = Curve.new(o[key])
      end
    end
  end
  if o.tip then o.tip = Tip.prepare(o.tip) end
  if o.dualBrush then o.dualBrush=Texture.prepareDual(o.dualBrush) end
  if o.paper then o.paper=Texture.preparePaper(o.paper) end
  if o.mix then o.mix=Mixer.prepare(o.mix) end
  if o.wetPaint then
    assert(not o.eraser and not o.mix,
      'tinta úmida não pode ser combinada com borracha ou mix')
    o.wetPaint=Mixer.prepareWet(o.wetPaint)
    o._wetState=Mixer.newWetState(o.color)
  end
  -- O acumulador de fluxo só é ativado por opção explícita: os traços de
  -- projetos antigos continuam com a composição tradicional dos carimbos.
  if o.flow ~= nil or o.wetPaint then o._ink = {} end
  -- Geometria e texturas preparadas uma vez por gesto, jamais no laço de pixels.
  o._brushPrepared = true
  o._shapeCache = {built = 0, reused = 0}
  local smooth = config(o.smoothing)
  o.smoothing = nil -- não é uma propriedade do Brush.dab
  o.pressureStart, o.pressureEnd = nil, nil
  local s = setmetatable({doc = doc, layer = layer, history = history, opts = o,
    smooth = smooth, distanceStep = math.max(1, opts.size * spacing),
    carry = 0, lastInput = nil, lastPath = nil, lastStamp = nil,
    stampCount = 0, baseTiltX = opts.tiltX or 0, baseTiltY = opts.tiltY or 0,
    closed = false}, Stroke)
  Hist.begin(history)
  return s
end

-- Interface conveniente para máscaras. As cores RGB não participam da máscara;
-- maskValue controla a cobertura. Borracha escreve preto (0), independentemente
-- do default ou do estado de inversão da máscara.
function Stroke.newMask(doc, layer, history, opts)
  assert(type(opts) == "table", "opções de pincel inválidas")
  local options = copy(opts)
  options.target = "mask"
  options.color = options.color or {1, 1, 1}
  if options.selection == nil and doc.selection then
    options.selection = copy(doc.selection)
  end
  return Stroke.new(doc, layer, history, options)
end

-- Pinta diretamente a máscara de um grupo reutilizando o mesmo rasterizador,
-- pressão, estabilização e transação usados por Stroke.newMask.
-- Um proxy leve expõe somente a máscara e nunca contém pixels de camada.
function Stroke.newGroupMask(doc, groupId, history, opts)
  assert(type(doc)=='table' and type(doc.groups)=='table'
    and doc.groups[groupId] and doc.groups[groupId].mask,
    'grupo sem máscara válido')
  assert(type(opts)=='table','opções de pincel inválidas')
  local options=copy(opts)
  options.target='mask'
  options._groupMaskId=groupId
  options.color=options.color or {1,1,1}
  if options.selection==nil and doc.selection then
    options.selection=copy(doc.selection)
  end
  return Stroke.new(doc,{mask=doc.groups[groupId].mask},history,options)
end

function Stroke:_stamp(p)
  self.opts.pressure = p.p
  self.opts.tiltX, self.opts.tiltY = p.tx, p.ty
  self.opts.dabIndex = self.stampCount
  if self.opts.target == "mask" then
    -- Uma falha de gravação não pode deixar uma máscara parcialmente aplicada.
    local ok, err = pcall(Brush.dab, self.doc, self.layer, self.history,
      p.x, p.y, self.opts)
    if not ok then
      Hist.rollback(self.history)
      self.closed = true
      error(err, 0)
    end
  else
    Brush.dab(self.doc, self.layer, self.history, p.x, p.y, self.opts)
  end
  self.lastStamp = p
  self.stampCount = self.stampCount + 1
end

function Stroke:_follow(p)
  local last = self.lastPath
  if not last then
    self:_stamp(p)
    self.lastPath = p
    return
  end
  local dx, dy = p.x - last.x, p.y - last.y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist == 0 then
    self.lastPath = p
    return
  end
  assert(finite(dist) and (dist + self.carry) / self.distanceStep <= 100000,
    "segmento longo demais; envie pontos intermediários")
  local offset = self.distanceStep - self.carry
  while offset <= dist + 1e-9 do
    local t = math.min(1, offset / dist)
    self:_stamp({x = last.x + dx * t, y = last.y + dy * t,
      p = last.p + (p.p - last.p) * t,
      tx = last.tx + (p.tx - last.tx) * t,
      ty = last.ty + (p.ty - last.ty) * t})
    offset = offset + self.distanceStep
  end
  self.carry = (self.carry + dist) % self.distanceStep
  if self.carry >= self.distanceStep - 1e-9 then self.carry = 0 end
  self.lastPath = p
end

-- Retorna a posição filtrada; nil se o modo "pulled" ainda não liberou o cursor.
function Stroke:_filtered(p)
  local last = self.lastPath
  if not last or self.smooth.amount == 0 then return p end
  local s = self.smooth
  local f
  if s.mode == "pulled" then
    local len = s.amount * 100
    if s.adjustForZoom then len = len / s.zoom end
    local dx, dy = p.x - last.x, p.y - last.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= len then return nil end
    f = (d - len) / d
  else
    -- Um passo padrão vale ~16ms; tempos explícitos reduzem dependência da
    -- frequência de amostragem do tablet. Para dt=0 aplica um passo.
    local dt = self.lastInput and p.time and self.lastInput.time
      and p.time - self.lastInput.time or nil
    local steps = dt and dt > 0 and math.min(dt / 16, 64) or 1
    f = 1 - math.min(0.95, s.amount) ^ steps
  end
  return {x = last.x + (p.x - last.x) * f,
    y = last.y + (p.y - last.y) * f,
    p = last.p + (p.p - last.p) * f,
    tx = last.tx + (p.tx - last.tx) * f,
    ty = last.ty + (p.ty - last.ty) * f}
end

-- Cada evento é validado antes de modificar o estado/pixels.
function Stroke:push(x, y, pressure, timeMs, tiltX, tiltY)
  assert(not self.closed, "o traço já foi encerrado")
  assert(finite(x) and finite(y) and math.abs(x) <= 10000000
    and math.abs(y) <= 10000000, "posição inválida")
  if pressure == nil then pressure = 1 end
  assert(valid01(pressure), "pressão deve estar entre 0 e 1")
  if timeMs ~= nil then
    assert(finite(timeMs) and timeMs >= 0, "tempo inválido")
    if self.lastInput and self.lastInput.time then
      assert(timeMs >= self.lastInput.time, "tempo dos eventos fora de ordem")
    end
  end
  if tiltX == nil then tiltX = self.baseTiltX end
  if tiltY == nil then tiltY = self.baseTiltY end
  assert(finite(tiltX) and tiltX >= -1 and tiltX <= 1
    and finite(tiltY) and tiltY >= -1 and tiltY <= 1,
    "inclinação deve estar entre -1 e 1")
  local p = {x = x, y = y, p = pressure, time = timeMs,
    tx = tiltX, ty = tiltY}
  local filtered = self:_filtered(p)
  if filtered then self:_follow(filtered) end
  self.lastInput = p
  return filtered and filtered.x or nil, filtered and filtered.y or nil
end

-- Recarrega o pincel durante o gesto, sem modificar as opções do chamador.
-- Um traço novo cria seu próprio reservatório.
function Stroke:loadWet(color)
  assert(not self.closed and self.opts._wetState,
    'traço sem tinta úmida ativa')
  Mixer.loadWet(self.opts._wetState,color)
end

function Stroke:cleanWet()
  assert(not self.closed and self.opts._wetState,
    'traço sem tinta úmida ativa')
  Mixer.cleanWet(self.opts._wetState)
end

function Stroke:finish()
  assert(not self.closed, "o traço já foi encerrado")
  if self.lastInput and self.smooth.catchUpOnEnd then
    self:_follow(self.lastInput)
  end
  local last = self.lastPath
  if last and self.lastStamp and
      (math.abs(last.x - self.lastStamp.x) > 1e-7
        or math.abs(last.y - self.lastStamp.y) > 1e-7
        or math.abs(last.p - self.lastStamp.p) > 1e-7
        or math.abs(last.tx - self.lastStamp.tx) > 1e-7
        or math.abs(last.ty - self.lastStamp.ty) > 1e-7) then
    self:_stamp(last)
  end
  Hist.commit(self.history)
  self.opts._ink = nil
  self.opts._wetState = nil
  self.closed = true
end

function Stroke:cancel()
  assert(not self.closed, "o traço já foi encerrado")
  Hist.rollback(self.history)
  self.opts._ink = nil
  self.opts._wetState = nil
  self.closed = true
end

return Stroke
