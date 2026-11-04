-- Pincel por carimbos (dabs) circulares com dureza e interpolação entre pontos.
-- Opções (o):
--   size       diâmetro em px do documento
--   alpha      opacidade do traço, 0..1
--   color      {r, g, b} em 0..1
--   eraser     true para apagar em vez de pintar
--   hardness   0..1, fração do raio com opacidade total (resto cai linearmente)
--   selection  {x, y, w, h} ou nil; pixels fora da seleção não mudam
--   pressure   0..1 (caneta); pressureSize/pressureOpacity ativam a dinâmica
--   pressureMinSize/pressureMinOpacity são pisos relativos (0..1)
--   spacing    proporção do diâmetro entre carimbos; padrão 0.15
--   pressureCurve / pressureSizeCurve / pressureOpacityCurve:
--              pontos {{0,0}, {0.5,0.2}, {1,1}} ou Curve.new(pontos)
--   symmetry   {mode="vertical"|"horizontal"|"dual"|"diagonal", center={x,y}, angle=0}
--   tip        Tip.new(w,h,data) ou {width=w,height=h,data={...}}, máscara 0..1
--   angle      ângulo em graus da ponta amostrada
--   tiltX/Y    inclinação da caneta, -1..1; tiltScale = 0..1 (achatamento)
--   scatter    dispersão entre 0 e 10, seed inteiro e dabIndex para reprodução
--   dualBrush  {tip=Tip,scale=1,angle=0,depth=1,mode="multiply"}
--   paper      {tip=Tip,scale=1,offsetX=0,offsetY=0,depth=1,mode="multiply"}
--              scale é o tamanho em pixels de cada texel, fixo no documento
--   mix        {strength=0..1,radius=0..8}: coleta cores da camada ativa
--   wetPaint   {wet=0..1,load=0..1,mix=0..1,flow=0..1,radius=0..8}
--              reservatório com coleta e desgaste por carimbo; incompatível
--              com mix e eraser; em Stroke o estado é mantido entre eventos
--   flow       0..1; em Brush.dab/line reduz a tinta de cada carimbo
--              em Stroke.new permite teto de opacidade por gesto via _ink
--
-- Dois caminhos de carimbo:
--   * LuaJIT com FFI: escreve direto nos bytes do tile (getFFIPointer). Rápido.
--   * Lua puro: getPixel/setPixel. Lento, mas é a referência e o fallback.
-- Se o caminho FFI falhar em tempo de execução, o módulo passa a usar Lua puro.
local Doc = require("core.doc")
local Hist = require("core.history")
local Symmetry = require("core.symmetry")
local Curve = require("core.curve")
local Tip = require("core.tip")
local Texture = require("core.texture")
local Mixer = require("core.mixer")
local Mask = require("core.mask")
local Selection = require("core.selection")

local T = Doc.TILE
local B = {}
local TILT_FIELDS = {"tiltX", "tiltY"}

local okffi, ffi = pcall(require, "ffi")
local HAS_JIT = okffi and type(jit) == "table"

-- Limites do carimbo dentro do documento e da seleção. Retorna nil se vazio.
local function bounds(doc, cx, cy, r, selection)
  local x0 = math.max(0, math.floor(cx - r))
  local y0 = math.max(0, math.floor(cy - r))
  local x1 = math.min(doc.w - 1, math.ceil(cx + r))
  local y1 = math.min(doc.h - 1, math.ceil(cy + r))
  if selection then
    x0 = math.max(x0, selection.x)
    y0 = math.max(y0, selection.y)
    x1 = math.min(x1, selection.x + selection.w - 1)
    y1 = math.min(y1, selection.y + selection.h - 1)
  end
  if x0 > x1 or y0 > y1 then return nil end
  return x0, y0, x1, y1
end

---------------------------------------------------------------- Lua puro

-- Modelo geométrico único para Lua e FFI, mantendo o caminho original
-- exatamente igual quando não houver ponta amostrada, ângulo ou inclinação.
local function makeShape(o, r)
  local tip = o.tip
  local tx, ty = o.tiltX or 0, o.tiltY or 0
  local strength = math.min(1, math.sqrt(tx * tx + ty * ty))
  local flatten = math.max(0.15, 1 - (o.tiltScale or 0) * strength)
  local angle = o.angle or 0
  if strength > 0 and o.tiltScale and o.tiltScale > 0 then
    local tiltAngle = math.atan2 and math.atan2(ty, tx) or math.atan(ty / (tx == 0 and 1e-20 or tx))
    if not math.atan2 and tx < 0 then tiltAngle = tiltAngle + math.pi end
    angle = angle + math.deg(tiltAngle)
  end
  local hard = r * o.hardness
  local fall = math.max(r - hard, 1e-6)
  local function round(d)
    if d > r then return 0 end
    if d > hard then return 1 - (d - hard) / fall end
    return 1
  end
  local dual = o.dualBrush
  local function finishShape(base, extent)
    if not dual or dual.depth==0 then return base, extent end
    local secondary=Texture.dualSampler(dual,r)
    return function(dx, dy)
      local v=base(dx,dy)
      if v<=0 then return v end
      return Texture.combine(v,secondary(dx,dy),dual.depth,dual.mode)
    end,extent
  end
  if not tip and flatten == 1 then
    return finishShape(function(dx, dy)
      return round(math.sqrt(dx * dx + dy * dy))
    end, r)
  end
  local radians = math.rad(angle)
  local cosA, sinA = math.cos(radians), math.sin(radians)
  if tip then
    local largest = math.max(tip.width, tip.height)
    local hw = r * tip.width / largest
    local hh = r * tip.height / largest * flatten
    return finishShape(function(dx, dy)
      local x = dx * cosA + dy * sinA
      local y = (-dx * sinA + dy * cosA)
      return Tip.sample(tip, x / (2 * hw) + 0.5, y / (2 * hh) + 0.5)
    end, r * math.sqrt(2))
  end
  return finishShape(function(dx, dy)
    local x = dx * cosA + dy * sinA
    local y = (-dx * sinA + dy * cosA) / flatten
    return round(math.sqrt(x * x + y * y))
  end, r)
end

-- Sorteio pseudoaleatório local por índice, sem alterar math.randomseed do editor.
-- A seed e o índice do carimbo dão sempre o mesmo deslocamento.
-- Cache local ao gesto: a forma geométrica não depende da posição do carimbo.
-- A chave contém TODOS os parâmetros usados por makeShape. Um único slot mantém
-- memória O(1), inclusive em traços com pressão/tamanho variáveis.
-- Opções passadas diretamente a Brush.dab não recebem campos novos.
local function shapeFor(o, r)
  local cache = o._shapeCache
  if not cache then return makeShape(o, r) end
  local previous = cache.last
  if previous and previous.size == o.size and previous.hardness == o.hardness
      and previous.tip == o.tip and previous.angle == o.angle
      and previous.tiltX == o.tiltX and previous.tiltY == o.tiltY
      and previous.tiltScale == o.tiltScale and previous.dualBrush == o.dualBrush
      and (not o.tip or (previous.tipWidth == o.tip.width
        and previous.tipHeight == o.tip.height))
      and (not o.dualBrush or (previous.dualAngle == o.dualBrush.angle
        and previous.dualScale == o.dualBrush.scale
        and previous.dualDepth == o.dualBrush.depth
        and previous.dualMode == o.dualBrush.mode
        and previous.dualTip == o.dualBrush.tip)) then
    cache.reused = (cache.reused or 0) + 1
    return previous.coverage, previous.extent
  end
  local coverage, extent = makeShape(o, r)
  cache.last = {size = o.size, hardness = o.hardness, tip = o.tip,
    angle = o.angle, tiltX = o.tiltX, tiltY = o.tiltY,
    tiltScale = o.tiltScale, dualBrush = o.dualBrush,
    tipWidth = o.tip and o.tip.width, tipHeight = o.tip and o.tip.height,
    dualAngle = o.dualBrush and o.dualBrush.angle,
    dualScale = o.dualBrush and o.dualBrush.scale,
    dualDepth = o.dualBrush and o.dualBrush.depth,
    dualMode = o.dualBrush and o.dualBrush.mode,
    dualTip = o.dualBrush and o.dualBrush.tip,
    coverage = coverage, extent = extent}
  cache.built = (cache.built or 0) + 1
  return coverage, extent
end

local function scatterPosition(cx, cy, o)
  local amount = o.scatter or 0
  assert(type(amount) == "number" and amount == amount
    and amount >= 0 and amount <= 10, "dispersão inválida")
  if amount == 0 then return cx, cy end
  local index, seed = o.dabIndex or 0, o.seed or 0
  assert(type(index) == "number" and index >= 0 and index == math.floor(index)
    and index <= 100000000, "índice de carimbo inválido")
  assert(type(seed) == "number" and seed >= 0 and seed <= 4294967295
    and seed == math.floor(seed), "semente de dispersão inválida")
  local state = (seed + index * 2654435761) % 4294967296
  state = (1664525 * state + 1013904223) % 4294967296
  local radius = math.sqrt(state / 4294967296) * amount * o.size / 2
  state = (1664525 * state + 1013904223) % 4294967296
  local theta = 2 * math.pi * (state / 4294967296)
  return cx + radius * math.cos(theta), cy + radius * math.sin(theta)
end

local function dabLua(doc, layer, h, cx, cy, o)
  local r = o.size / 2
  if r <= 0 then return end
  local coverage, extent = shapeFor(o, r)
  local x0, y0, x1, y1 = bounds(doc, cx, cy, extent, o.selection)
  if not x0 then return end

  local c = o.eraser and o.color or Mixer.pick(doc,layer,cx,cy,o.color,o.mix)
  local paper = o.paper
  local flow = o.flow or 1
  local ink = o._ink

  for ty = math.floor(y0 / T), math.floor(y1 / T) do
    for tx = math.floor(x0 / T), math.floor(x1 / T) do
      local existing, key = Doc.getTile(layer, tx, ty, false)
      -- Apagar uma região ainda transparente não exige memória, snapshot nem GPU.
      if not (o.eraser and not existing) and not (o.alphaLock and not existing) then
      local tile, accum

      local ox, oy = tx * T, ty * T
      local ax0, ay0 = math.max(x0, ox), math.max(y0, oy)
      local ax1, ay1 = math.min(x1, ox + T - 1), math.min(y1, oy + T - 1)

      for py = ay0, ay1 do
        local rowStart, rowEnd = ax0, ax1
        -- Pontas calculadas são sempre contidas no círculo de raio r,
        -- mesmo após achatamento/rotação. Poupa sqrt e amostragens fora dele.
        -- Pontas amostradas NÃO usam essa poda: podem alcançar r*sqrt(2).
        if not o.tip then
          local dy = py + 0.5 - cy
          local squared = r * r - dy * dy
          if squared < 0 then
            rowStart = ax1 + 1
          else
            local reach = math.sqrt(squared)
            rowStart = math.max(ax0, math.ceil(cx - reach - 0.5))
            rowEnd = math.min(ax1, math.floor(cx + reach - 0.5))
          end
        end
        for px = rowStart, rowEnd do
          local dx, dy = px + 0.5 - cx, py + 0.5 - cy
          local f = coverage(dx, dy)
          if paper then f = Texture.paperCoverage(paper,f,px,py) end
          if f > 0 and (not o.selection or Selection.contains(o.selection,px,py))
            and (not o.alphaLock or
            (existing and select(4,existing:getPixel(px-ox,py-oy)) > 0)) then
            if not tile then
              Hist.touch(h,layer,key)
              tile=Doc.getTile(layer,tx,ty,true)
              if ink then
                accum=ink[key]
                if not accum then accum={}; ink[key]=accum end
              end
            end
            local sa = f * flow * o.alpha
            local lx, ly = px - ox, py - oy
            local dr, dg, db, da = tile:getPixel(lx, ly)
            if accum then
              -- A tinta acumula em um buffer por pixel. A opacidade do traço
              -- é um teto; repetir carimbos não escurece além dele.
              local index = ly * T + lx + 1
              local a = accum[index]
              if not a then
                a = {coverage = 0, maxAlpha = 0, r = dr, g = dg, b = db, a = da}
                accum[index] = a
              end
              local oldCoverage = a.coverage
              local newCoverage = oldCoverage + (1 - oldCoverage) * f * flow
              local increment = newCoverage - oldCoverage
              if newCoverage > 0 and not o.eraser then
                a.paintR = ((a.paintR or 0)*oldCoverage + c[1]*increment)/newCoverage
                a.paintG = ((a.paintG or 0)*oldCoverage + c[2]*increment)/newCoverage
                a.paintB = ((a.paintB or 0)*oldCoverage + c[3]*increment)/newCoverage
              end
              a.coverage = newCoverage
              a.maxAlpha = math.max(a.maxAlpha, o.alpha)
              sa = newCoverage * a.maxAlpha
              dr, dg, db, da = a.r, a.g, a.b, a.a
            end
            if o.eraser then
              tile:setPixel(lx, ly, dr, dg, db, da * (1 - sa))
            else
              local cr,cg,cb=c[1],c[2],c[3]
              if accum then
                local painted=accum[ly * T + lx + 1]
                cr,cg,cb=painted.paintR,painted.paintG,painted.paintB
              end
              if o.alphaLock then
                -- Alpha Lock altera somente RGB de pixels já existentes.
                tile:setPixel(lx,ly, cr*sa+dr*(1-sa),
                  cg*sa+dg*(1-sa),cb*sa+db*(1-sa),da)
              else
                local outA = sa + da * (1 - sa)
                if outA > 0 then
                  tile:setPixel(lx, ly,
                    (cr * sa + dr * da * (1 - sa)) / outA,
                    (cg * sa + dg * da * (1 - sa)) / outA,
                    (cb * sa + db * da * (1 - sa)) / outA,
                    outA)
                end
              end
            end
          end
        end
      end
      if tile then Doc.markDirty(layer, key) end
      end -- não cria tile para borracha sobre transparência
    end
  end
end

---------------------------------------------------------------- Pintura direta na máscara
-- A mesma geometria/pressão/textura do pincel raster é aplicada à cobertura
-- em escala de cinza. O alfa do ImageData da máscara permanece 1.
-- O modo eraser equivale a pintar preto; maskValue 1 revela, 0 oculta.
-- Mantém snapshots/revisões separados dos pixels da camada.
local function dabMask(doc, layer, h, cx, cy, o)
  local mask = layer.mask
  local r = o.size / 2
  if r <= 0 then return end
  local coverage, extent = shapeFor(o, r)
  local x0, y0, x1, y1 = bounds(doc, cx, cy, extent, o.selection)
  if not x0 then return end
  local value = o.eraser and 0 or (o.maskValue == nil and 1 or o.maskValue)
  local flow = o.flow or 1
  local paper = o.paper
  local ink = o._ink
  for ty = math.floor(y0 / T), math.floor(y1 / T) do
    for tx = math.floor(x0 / T), math.floor(x1 / T) do
      local tile, key = Mask.getTile(mask, tx, ty, false)
      local ox, oy = tx * T, ty * T
      local ax0, ay0 = math.max(x0, ox), math.max(y0, oy)
      local ax1, ay1 = math.min(x1, ox + T - 1), math.min(y1, oy + T - 1)
      local changed = false
      for py = ay0, ay1 do
        local rowStart, rowEnd = ax0, ax1
        if not o.tip then
          local dy = py + 0.5 - cy
          local squared = r * r - dy * dy
          if squared < 0 then
            rowStart = ax1 + 1
          else
            local reach = math.sqrt(squared)
            rowStart = math.max(ax0, math.ceil(cx - reach - 0.5))
            rowEnd = math.min(ax1, math.floor(cx + reach - 0.5))
          end
        end
        for px = rowStart, rowEnd do
          local dx, dy = px + 0.5 - cx, py + 0.5 - cy
          local strength = coverage(dx, dy)
          if paper then strength = Texture.paperCoverage(paper, strength, px, py) end
          local sa = strength * flow * o.alpha
          if sa > 0 and (not o.selection or Selection.contains(o.selection,px,py)) then
            local lx, ly = px - ox, py - oy
            local old = tile and select(1, tile:getPixel(lx, ly)) or mask.default
            local base = old
            if ink then
              local accum = ink[key]
              if not accum then accum = {}; ink[key] = accum end
              local i = ly * T + lx + 1
              local a = accum[i]
              if not a then
                a = {coverage = 0, maxAlpha = 0, base = old}
                accum[i] = a
              end
              a.coverage = a.coverage + (1 - a.coverage) * strength * flow
              a.maxAlpha = math.max(a.maxAlpha, o.alpha)
              sa = a.coverage * a.maxAlpha
              base = a.base
            end
            local nextValue = base + (value - base) * sa
            if math.abs(nextValue - old) > 1e-12 then
              if not changed then Hist.touchMask(h, mask, key); changed = true end
              if not tile then tile = Mask.getTile(mask, tx, ty, true) end
              tile:setPixel(lx, ly, nextValue, nextValue, nextValue, 1)
            end
          end
        end
      end
      if changed then Mask.markDirty(mask, key) end
    end
  end
end

---------------------------------------------------------------- LuaJIT + FFI

local function toByte(v)
  local b = math.floor(v * 255 + 0.5)
  if b < 0 then return 0 end
  if b > 255 then return 255 end
  return b
end

local function dabFFI(doc, layer, h, cx, cy, o)
  local r = o.size / 2
  if r <= 0 then return end
  local coverage, extent = shapeFor(o, r)
  local x0, y0, x1, y1 = bounds(doc, cx, cy, extent, o.selection)
  if not x0 then return end

  local color = o.eraser and o.color or Mixer.pick(doc,layer,cx,cy,o.color,o.mix)
  local c1, c2, c3 = color[1], color[2], color[3]
  local paper = o.paper
  local alpha = o.alpha * (o.flow or 1)
  local eraser = o.eraser

  for ty = math.floor(y0 / T), math.floor(y1 / T) do
    for tx = math.floor(x0 / T), math.floor(x1 / T) do
      local existing, key = Doc.getTile(layer, tx, ty, false)
      if not (eraser and not existing) then
      local tile, ptr

      local ox, oy = tx * T, ty * T
      local ax0, ay0 = math.max(x0, ox), math.max(y0, oy)
      local ax1, ay1 = math.min(x1, ox + T - 1), math.min(y1, oy + T - 1)

      for py = ay0, ay1 do
        local rowStart, rowEnd = ax0, ax1
        -- Pontas calculadas são sempre contidas no círculo de raio r,
        -- mesmo após achatamento/rotação. Poupa sqrt e amostragens fora dele.
        -- Pontas amostradas NÃO usam essa poda: podem alcançar r*sqrt(2).
        if not o.tip then
          local dy = py + 0.5 - cy
          local squared = r * r - dy * dy
          if squared < 0 then
            rowStart = ax1 + 1
          else
            local reach = math.sqrt(squared)
            rowStart = math.max(ax0, math.ceil(cx - reach - 0.5))
            rowEnd = math.min(ax1, math.floor(cx + reach - 0.5))
          end
        end
        for px = rowStart, rowEnd do
          local dx, dy = px + 0.5 - cx, py + 0.5 - cy
          local f = coverage(dx, dy)
          if paper then f = Texture.paperCoverage(paper,f,px,py) end
          if f > 0 and (not o.selection or Selection.contains(o.selection,px,py)) then
            if not tile then
              Hist.touch(h,layer,key)
              tile=Doc.getTile(layer,tx,ty,true)
              -- Referência local mantém o ImageData vivo enquanto o ponteiro existe.
              ptr=ffi.cast("uint8_t*",tile:getFFIPointer())
            end
            local sa = f * alpha
            local i = (((py - oy) * T) + (px - ox)) * 4
            local dr, dg, db = ptr[i] / 255, ptr[i + 1] / 255, ptr[i + 2] / 255
            local da = ptr[i + 3] / 255
            if eraser then
              ptr[i + 3] = toByte(da * (1 - sa))
            else
              local outA = sa + da * (1 - sa)
              if outA > 0 then
                ptr[i] = toByte((c1 * sa + dr * da * (1 - sa)) / outA)
                ptr[i + 1] = toByte((c2 * sa + dg * da * (1 - sa)) / outA)
                ptr[i + 2] = toByte((c3 * sa + db * da * (1 - sa)) / outA)
                ptr[i + 3] = toByte(outA)
              end
            end
          end
        end
      end
      if tile then Doc.markDirty(layer, key) end
      end -- borracha ignora tile que ainda não existe
    end
  end
end

---------------------------------------------------------------- seleção e fallback

B.impl = "lua"
local useFFI = HAS_JIT

local function dabDispatch(doc, layer, h, cx, cy, o)
  if o.alphaLock and o.target ~= "mask" then
    -- FFI não altera alfa em modo de bloqueio até haver teste de paridade.
    B.impl='lua-alpha-lock'
    if not o.eraser then return dabLua(doc,layer,h,cx,cy,o) end
    return
  end
  -- O buffer de fluxo preserva pixels anteriores e a cobertura acumulada.
  -- Por segurança usa Lua puro até haver paridade FFI/Lua comprovada.
  if o.target == "mask" then
    B.impl = "lua-mask"
    return dabMask(doc, layer, h, cx, cy, o)
  end
  if useFFI and not o._ink and not o._wetPaintEnabled then
    local ok, err = pcall(dabFFI, doc, layer, h, cx, cy, o)
    if ok then
      B.impl = "ffi"
      return
    end
    -- Falha no caminho rápido: volta para Lua puro e não tenta mais.
    useFFI = false
    B.impl = "lua"
    B.lastError = err
  end
  B.impl = "lua"
  dabLua(doc, layer, h, cx, cy, o)
end

-- Mantém as opções do chamador inalteradas. O controle da caneta usa uma
-- interpolação linear entre um valor mínimo e o tamanho/opacidade configurados.
local function withPressure(o, pressure)
  if pressure == nil then return o end
  assert(type(pressure) == "number" and pressure == pressure
    and pressure >= 0 and pressure <= 1, "pressão inválida: esperado 0..1")
  if not o.pressureSize and not o.pressureOpacity then return o end
  local result = {}
  for k, v in pairs(o) do result[k] = v end
  if o.pressureSize then
    local adjusted = Curve.value(o.pressureSizeCurve or o.pressureCurve, pressure)
    local minimum = o.pressureMinSize
    if minimum == nil then minimum = 0.15 end
    assert(type(minimum) == "number" and minimum >= 0 and minimum <= 1, "pressão mínima de tamanho inválida")
    result.size = o.size * (minimum + (1 - minimum) * adjusted)
  end
  if o.pressureOpacity then
    local adjusted = Curve.value(o.pressureOpacityCurve or o.pressureCurve, pressure)
    local minimum = o.pressureMinOpacity
    if minimum == nil then minimum = 0 end
    assert(type(minimum) == "number" and minimum >= 0 and minimum <= 1, "pressão mínima de opacidade inválida")
    result.alpha = o.alpha * (minimum + (1 - minimum) * adjusted)
  end
  return result
end

-- Carimbo único, que pode ter dinâmica de pressão e cópias por simetria.
-- Sem esses parâmetros, conserva exatamente o carimbo original.
function B.dab(doc, layer, h, x, y, o)
  Hist.assertUnlocked(h)
  if o.target ~= nil then
    assert(o.target == "mask", "destino de pincel desconhecido")
    assert(type(doc) == "table" and h == doc.history and h.stroke ~= nil,
      "pintura de máscara exige gesto no histórico do documento")
    local owned = false
    for _, L in ipairs(doc.layers) do if L == layer then owned = true; break end end
    if not owned and o._groupMaskId then
      local group=doc.groups and doc.groups[o._groupMaskId]
      owned=group and group.mask and group.mask==layer.mask
    end
    assert(owned and layer.mask ~= nil, "máscara não vinculada ao documento")
    assert(o._maskTarget == nil or o._maskTarget == layer.mask,
      "máscara foi substituída durante o gesto")
    assert(o.mix == nil and o.wetPaint == nil,
      "mistura de pigmentos não é suportada ao pintar máscara")
    local v = o.maskValue
    assert(v == nil or (type(v) == "number" and v == v and v >= 0
      and v <= 1 and v ~= math.huge), "maskValue deve estar entre 0 e 1")
  end
  for _, field in ipairs(TILT_FIELDS) do
    local v = o[field]
    if v ~= nil then
      assert(type(v) == "number" and v == v and v >= -1 and v <= 1,
        "inclinação inválida")
    end
  end
  if o.tiltScale ~= nil then
    assert(type(o.tiltScale) == "number" and o.tiltScale == o.tiltScale
      and o.tiltScale >= 0 and o.tiltScale <= 1, "escala tilt inválida")
  end
  if o.angle ~= nil then
    assert(type(o.angle) == "number" and o.angle == o.angle
      and o.angle > -math.huge and o.angle < math.huge, "ângulo inválido")
  end
  if o.flow ~= nil then
    assert(type(o.flow) == "number" and o.flow == o.flow
      and o.flow >= 0 and o.flow <= 1, "fluxo inválido")
  end
  local wetConfig
  if o.wetPaint then
    assert(not o.eraser and o.mix==nil,
      'tinta úmida não pode ser combinada com borracha ou mix')
    wetConfig=Mixer.prepareWet(o.wetPaint)
  end
  if o.flow == 0 or o.alpha == 0 then return end
  -- Tip.prepare copia a tabela do usuário; não modificar opções externas.
  local dynamic = withPressure(o, o.pressure)
  if not dynamic._brushPrepared and
      (dynamic.tip or dynamic.dualBrush or dynamic.paper or dynamic.mix) then
    local prepared = {}
    for k, v in pairs(dynamic) do prepared[k] = v end
    if prepared.tip then prepared.tip = Tip.prepare(prepared.tip) end
    if prepared.dualBrush then prepared.dualBrush=Texture.prepareDual(prepared.dualBrush) end
    if prepared.paper then prepared.paper=Texture.preparePaper(prepared.paper) end
    if prepared.mix then prepared.mix=Mixer.prepare(prepared.mix) end
    dynamic = prepared
  end
  local sx, sy = scatterPosition(x, y, dynamic)
  if wetConfig then
    -- Não altera a tabela passada pelo chamador; em Stroke, o reservatório
    -- pertence à transação e dura até finish/cancel.
    local state=dynamic._wetState or Mixer.newWetState(dynamic.color)
    local pigment,amount=Mixer.wetDab(doc,layer,sx,sy,wetConfig,state,dynamic.selection)
    if not pigment or amount==0 then return end
    if dynamic==o then
      local changed={}
      for k,v in pairs(dynamic) do changed[k]=v end
      dynamic=changed
    end
    dynamic.color=pigment
    dynamic.flow=(dynamic.flow or 1)*amount
    dynamic.mix=nil
    dynamic._wetPaintEnabled=true
  end
  if o.symmetry then
    for _, point in ipairs(Symmetry.points(doc, sx, sy, o.symmetry)) do
      dabDispatch(doc, layer, h, point[1], point[2], dynamic)
    end
  else
    dabDispatch(doc, layer, h, sx, sy, dynamic)
  end
end

-- Linha interpolada. Opcionalmente interpola a pressão ao longo do traço.
-- spacing é percentual do diâmetro nominal, mantendo o desenho estável
-- com alterações de pressão, e não depende da frequência dos eventos de toque.
function B.line(doc, layer, h, x0, y0, x1, y1, o)
  Hist.assertUnlocked(h)
  local dx, dy = x1 - x0, y1 - y0
  local dist = math.sqrt(dx * dx + dy * dy)
  assert(dist < math.huge and dist == dist, "segmento de pincel inválido")
  local fraction = o.spacing or 0.15
  assert(type(fraction) == "number" and fraction > 0 and fraction <= 2,
    "espaçamento inválido: esperado (0, 2]")
  local spacing = math.max(1, o.size * fraction)
  local steps = math.max(1, math.floor(dist / spacing))
  assert(steps <= 100000, "segmento longo demais; divida em trechos menores")
  -- Curvas por pontos são compiladas uma vez por segmento para não recalcular
  -- tangentes a cada carimbo. Nenhuma opção do chamador é modificada.
  do -- compilação única por linha, mantendo a configuração do chamador imutável
    local prepared = {}
    for k, v in pairs(o) do prepared[k] = v end
    if prepared.tip then prepared.tip = Tip.prepare(prepared.tip) end
    if prepared.dualBrush then prepared.dualBrush=Texture.prepareDual(prepared.dualBrush) end
    if prepared.paper then prepared.paper=Texture.preparePaper(prepared.paper) end
    if prepared.mix then prepared.mix=Mixer.prepare(prepared.mix) end
    if prepared.wetPaint then
      assert(not prepared.eraser and not prepared.mix,
        'tinta úmida não pode ser combinada com borracha ou mix')
      prepared.wetPaint=Mixer.prepareWet(prepared.wetPaint)
      prepared._wetState=Mixer.newWetState(prepared.color)
      prepared._ink={}
    end
    for _, key in ipairs({"pressureCurve", "pressureSizeCurve", "pressureOpacityCurve"}) do
      if prepared[key] ~= nil and getmetatable(prepared[key]) ~= Curve then
        prepared[key] = Curve.new(prepared[key])
      end
    end
    prepared._brushPrepared = true
    prepared._shapeCache = {built = 0, reused = 0}
    o = prepared
  end
  local p0 = o.pressureStart or o.pressure
  local p1 = o.pressureEnd or o.pressure
  if p0 ~= nil or p1 ~= nil then
    p0, p1 = p0 or 1, p1 or 1
  end
  for i = 1, steps do
    local t = i / steps
    if p0 ~= nil or (o.scatter or 0) > 0 then
      local dynamic = {}
      for k, v in pairs(o) do dynamic[k] = v end
      if p0 ~= nil then dynamic.pressure = p0 + (p1 - p0) * t end
      if (o.scatter or 0) > 0 then dynamic.dabIndex = (o.dabIndex or 0) + i - 1 end
      B.dab(doc, layer, h, x0 + dx * t, y0 + dy * t, dynamic)
    else
      B.dab(doc, layer, h, x0 + dx * t, y0 + dy * t, o)
    end
  end
end

-- Para testes: força o caminho escolhido (true = FFI se disponível).
function B.setFFI(enabled)
  useFFI = enabled and HAS_JIT or false
  B.impl = useFFI and "ffi" or "lua"
end

return B
