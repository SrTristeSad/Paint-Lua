-- Ponta amostrada em tons de cinza, independente do LÖVE.
-- Inspirada na ideia de GrayTile do PhotoCraft, crates/paint/src/tile.rs.
-- data é um array unidimensional (linha a linha) de cobertura entre 0 e 1.
local Tip = {}
Tip.__index = Tip
Tip.MAX_SIDE = 512

local function finite(x)
  return type(x) == "number" and x == x and x > -math.huge and x < math.huge
end

function Tip.new(width, height, data)
  assert(finite(width) and width == math.floor(width) and width >= 1 and width <= Tip.MAX_SIDE,
    "largura da ponta inválida")
  assert(finite(height) and height == math.floor(height) and height >= 1 and height <= Tip.MAX_SIDE,
    "altura da ponta inválida")
  assert(type(data) == "table" and #data == width * height, "dados da ponta incompletos")
  local samples = {}
  for i = 1, width * height do
    assert(finite(data[i]) and data[i] >= 0 and data[i] <= 1,
      "cobertura da ponta deve estar entre 0 e 1")
    samples[i] = data[i]
  end
  return setmetatable({width = width, height = height, data = samples}, Tip)
end

-- Aceita {width=..,height=..,data={...}} ou Tip.new(...).
function Tip.prepare(spec)
  if spec == nil then return nil end
  assert(type(spec) == "table", "ponta inválida")
  if getmetatable(spec) == Tip then return spec end
  return Tip.new(spec.width, spec.height, spec.data)
end

-- Amostragem bilinear; fora do quadrado não deposita tinta.
function Tip.sample(tip, u, v)
  if u < 0 or u > 1 or v < 0 or v > 1 then return 0 end
  local x, y = u * (tip.width - 1), v * (tip.height - 1)
  local x0, y0 = math.floor(x), math.floor(y)
  local x1, y1 = math.min(x0 + 1, tip.width - 1), math.min(y0 + 1, tip.height - 1)
  local fx, fy = x - x0, y - y0
  local a = tip.data[y0 * tip.width + x0 + 1]
  local b = tip.data[y0 * tip.width + x1 + 1]
  local c = tip.data[y1 * tip.width + x0 + 1]
  local d = tip.data[y1 * tip.width + x1 + 1]
  return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
end

-- Amostra uma textura repetível em coordenadas de texel. A interpolação
-- cruza a borda normalmente (incluindo coordenadas negativas).
function Tip.sampleRepeat(tip, x, y)
  local x0,y0=math.floor(x),math.floor(y)
  local fx,fy=x-x0,y-y0
  local function at(ix,iy)
    return tip.data[(iy % tip.height)*tip.width+(ix % tip.width)+1]
  end
  local a,b=at(x0,y0),at(x0+1,y0)
  local c,d=at(x0,y0+1),at(x0+1,y0+1)
  return (a*(1-fx)+b*fx)*(1-fy)+(c*(1-fx)+d*fx)*fy
end

return Tip
