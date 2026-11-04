-- Curva de resposta (0..1 -> 0..1) para pressão de caneta.
-- Inspirada em crates/paint/src/curve.rs do PhotoCraft (MIT OU Apache-2.0).
-- Usa interpolação cúbica monótona (Fritsch-Carlson) sem extrapolação.
-- Exemplo: Curve.new({{0, 0}, {0.5, 0.2}, {1, 1}}):eval(0.5) == 0.2
local Curve = {}
Curve.__index = Curve
Curve.MAX_POINTS = 16

local function finite(x)
  return type(x) == "number" and x == x and x > -math.huge and x < math.huge
end
local function clamp(x)
  return math.min(1, math.max(0, x))
end

function Curve.new(points)
  assert(type(points) == "table", "curva de pressão deve ser uma lista de pontos")
  assert(#points <= 256, "curva de pressão tem pontos demais")
  local p = {}
  for i, pair in ipairs(points) do
    assert(type(pair) == "table" and finite(pair[1]) and finite(pair[2]),
      "ponto de curva inválido")
    p[#p + 1] = {clamp(pair[1]), clamp(pair[2]), i}
  end
  table.sort(p, function(a, b)
    if a[1] == b[1] then return a[3] < b[3] end
    return a[1] < b[1]
  end)
  local pts = {}
  for _, v in ipairs(p) do
    if #pts > 0 and math.abs(v[1] - pts[#pts][1]) < 1e-6 then
      pts[#pts][2] = v[2] -- entrada repetida: último valor prevalece
    else
      pts[#pts + 1] = {v[1], v[2]}
    end
  end
  if #pts < 2 then pts = {{0, 0}, {1, 1}} end
  while #pts > Curve.MAX_POINTS do table.remove(pts) end
  for i = 2, #pts do
    pts[i][2] = math.max(pts[i][2], pts[i - 1][2])
  end

  local n, slopes, tangent = #pts, {}, {}
  for i = 1, n - 1 do
    slopes[i] = (pts[i + 1][2] - pts[i][2]) / (pts[i + 1][1] - pts[i][1])
  end
  tangent[1], tangent[n] = slopes[1], slopes[n - 1]
  for i = 2, n - 1 do
    if slopes[i - 1] * slopes[i] <= 0 then
      tangent[i] = 0
    else
      tangent[i] = (slopes[i - 1] + slopes[i]) / 2
    end
  end
  for i = 1, n - 1 do
    local d = slopes[i]
    if d == 0 then
      tangent[i], tangent[i + 1] = 0, 0
    else
      local a, b = tangent[i] / d, tangent[i + 1] / d
      if a * a + b * b > 9 then
        local t = 3 / math.sqrt(a * a + b * b)
        tangent[i], tangent[i + 1] = t * a * d, t * b * d
      end
    end
  end
  return setmetatable({points = pts, tangents = tangent}, Curve)
end

function Curve:eval(x)
  assert(finite(x), "pressão para curva deve ser um número finito")
  x = clamp(x)
  local pts, ms = self.points, self.tangents
  if x <= pts[1][1] then return pts[1][2] end
  if x >= pts[#pts][1] then return pts[#pts][2] end
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    if x <= b[1] then
      local h = b[1] - a[1]
      local t = (x - a[1]) / h
      local t2, t3 = t * t, t * t * t
      local y = (2 * t3 - 3 * t2 + 1) * a[2]
        + (t3 - 2 * t2 + t) * h * ms[i]
        + (-2 * t3 + 3 * t2) * b[2]
        + (t3 - t2) * h * ms[i + 1]
      return math.max(a[2], math.min(b[2], y))
    end
  end
  return pts[#pts][2]
end

-- Aceita curva compilada ou lista de pontos. Omissa = resposta linear.
function Curve.value(spec, pressure)
  if spec == nil then return pressure end
  if getmetatable(spec) == Curve then return spec:eval(pressure) end
  return Curve.new(spec):eval(pressure)
end

return Curve
