-- Mesclagem de referência CPU (canais sRGB normalizados 0..1).
-- Equações separáveis W3C/PDF, com variantes add/subtract comuns em editores.
-- Formulação source-over e alfa pertencem ao core.composite.
local min, max, sqrt = math.min, math.max, math.sqrt
local B = {}
local function clamp(x) return max(0, min(1, x)) end
local function dodge(b, s)
  if s >= 1 then return 1 end
  return min(1, b / (1 - s))
end
local function burn(b, s)
  if s <= 0 then return 0 end
  return 1 - min(1, (1 - b) / s)
end
local function soft(b, s)
  if s <= 0.5 then return b - (1 - 2 * s) * b * (1 - b) end
  local d = b <= 0.25 and ((16 * b - 12) * b + 4) * b or sqrt(b)
  return b + (2 * s - 1) * (d - b)
end
B.modes = {
  normal = function(_, s) return s end,
  multiply = function(b, s) return b * s end,
  screen = function(b, s) return b + s - b * s end,
  darken = min,
  lighten = max,
  overlay = function(b, s) return b <= 0.5 and 2*b*s or 1 - 2*(1-b)*(1-s) end,
  hardlight = function(b, s) return s <= 0.5 and 2*b*s or 1 - 2*(1-b)*(1-s) end,
  softlight = soft,
  difference = function(b, s) return math.abs(b-s) end,
  exclusion = function(b, s) return b+s-2*b*s end,
  add = function(b, s) return min(1, b+s) end,
  subtract = function(b, s) return max(0, b-s) end,
  color_dodge = dodge,
  color_burn = burn,
}
B.legacy = {normal=true, multiply=true, screen=true, darken=true, lighten=true}
function B.isValid(mode) return B.modes[mode] ~= nil end
function B.channel(mode, backdrop, source)
  local f = assert(B.modes[mode], 'modo de mesclagem inválido')
  return clamp(f(clamp(backdrop), clamp(source)))
end
return B
