-- Simetria geométrica para pincéis (sem acesso a pixels ou à interface).
-- Adaptado conceitualmente do modelo de eixos do PhotoCraft (MIT / Apache-2.0).
-- Modos: vertical, horizontal, diagonal, dual (dois eixos perpendiculares).
-- {mode='vertical', center={x, y}, angle=0} usa coordenadas de documento.
local S = {}

local function finite(v)
  return type(v) == "number" and v == v and v < math.huge and v > -math.huge
end

local function addUnique(out, x, y)
  for _, p in ipairs(out) do
    if math.abs(p[1] - x) < 1e-7 and math.abs(p[2] - y) < 1e-7 then return end
  end
  out[#out + 1] = {x, y}
end

local function reflect(x, y, cx, cy, angle)
  local ux, uy = math.cos(angle), math.sin(angle)
  local dx, dy = x - cx, y - cy
  local along = dx * ux + dy * uy
  return cx + 2 * along * ux - dx, cy + 2 * along * uy - dy
end

-- Devolve os pontos de um carimbo, incluindo o original, eliminando coincidências
-- sobre o(s) eixo(s) para não acumular tinta duplicada na linha central.
function S.points(doc, x, y, cfg)
  assert(finite(x) and finite(y), "posição de pincel inválida")
  local out = {{x, y}}
  if cfg == nil then return out end
  assert(type(cfg) == "table", "configuração de simetria inválida")
  local mode = cfg.mode
  assert(mode == "vertical" or mode == "horizontal" or mode == "dual" or mode == "diagonal", "modo de simetria inválido")
  local cx, cy = doc.w / 2, doc.h / 2
  if cfg.center then
    assert(type(cfg.center) == "table", "centro de simetria inválido")
    cx, cy = cfg.center[1], cfg.center[2]
  end
  assert(finite(cx) and finite(cy), "centro de simetria inválido")
  local angle = cfg.angle or 0
  assert(finite(angle), "ângulo de simetria inválido")
  local base = (mode == "vertical" or mode == "dual") and 90
    or (mode == "diagonal" and 45 or 0)
  local a = math.rad(base + angle)
  local rx, ry = reflect(x, y, cx, cy, a)
  addUnique(out, rx, ry)
  if mode == "dual" then
    local hx, hy = reflect(x, y, cx, cy, a + math.pi / 2)
    addUnique(out, hx, hy)
    addUnique(out, 2 * cx - x, 2 * cy - y)
  end
  return out
end

return S
