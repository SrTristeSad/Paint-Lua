-- Dupla ponta e textura de papel (máscaras de cobertura 0..1).
-- Implementação própria e reduzida, inspirada em PhotoCraft paint::brush/render.
-- Geometria do papel usa coordenadas ABSOLUTAS do documento, sem emendas entre tiles.
local Tip = require('core.tip')
local Texture = {}
local Dual = {}; Dual.__index = Dual
local Paper = {}; Paper.__index = Paper
local MODES = {multiply=true, subtract=true, darken=true, overlay=true}
local function finite(v)
  return type(v)=='number' and v==v and v>-math.huge and v<math.huge
end
local function between(v,a,b) return finite(v) and v>=a and v<=b end
local function mode(v)
  v = v or 'multiply'
  assert(MODES[v], 'modo de textura inválido')
  return v
end
function Texture.prepareDual(spec)
  if spec==nil then return nil end
  assert(type(spec)=='table', 'pincel duplo inválido')
  if getmetatable(spec)==Dual then return spec end
  assert(spec.tip ~= nil, 'ponta secundária ausente')
  local scale = spec.scale or 1
  local angle = spec.angle or 0
  local depth = spec.depth == nil and 1 or spec.depth
  assert(between(scale,0.05,8), 'escala do pincel duplo inválida')
  assert(finite(angle), 'ângulo do pincel duplo inválido')
  assert(between(depth,0,1), 'profundidade do pincel duplo inválida')
  return setmetatable({tip=Tip.prepare(spec.tip), scale=scale, angle=angle,
    depth=depth, mode=mode(spec.mode)}, Dual)
end
function Texture.preparePaper(spec)
  if spec==nil then return nil end
  assert(type(spec)=='table', 'textura de papel inválida')
  if getmetatable(spec)==Paper then return spec end
  assert(spec.tip ~= nil, 'imagem de papel ausente')
  local scale = spec.scale or 1 -- tamanho em pixels de UM texel de papel
  local depth = spec.depth == nil and 1 or spec.depth
  local ox,oy = spec.offsetX or 0, spec.offsetY or 0
  assert(between(scale,0.25,512), 'escala de papel inválida')
  assert(between(depth,0,1), 'profundidade de papel inválida')
  assert(between(ox,-1e7,1e7) and between(oy,-1e7,1e7), 'posição de papel inválida')
  assert(spec.invert==nil or type(spec.invert)=='boolean', 'inversão de papel inválida')
  return setmetatable({tip=Tip.prepare(spec.tip), scale=scale, depth=depth,
    offsetX=ox,offsetY=oy,invert=spec.invert==true,mode=mode(spec.mode)}, Paper)
end
function Texture.combine(v,t,depth,method)
  if v<=0 or depth<=0 then return v end
  local result
  if method=='multiply' then result=v*t
  elseif method=='subtract' then result=math.max(0,v-(1-t))
  elseif method=='darken' then result=math.min(v,t)
  elseif method=='overlay' then
    result = v<0.5 and 2*v*t or (1-2*(1-v)*(1-t))
  else error('modo de textura inválido') end
  return math.max(0,math.min(1,v+(result-v)*depth))
end
-- Calcula a transformação da segunda ponta uma vez por carimbo,
-- não uma vez por pixel (importante no caminho Lua puro).
function Texture.dualSampler(dual,r)
  local size=math.max(dual.tip.width,dual.tip.height)
  local hw=r*dual.scale*dual.tip.width/size
  local hh=r*dual.scale*dual.tip.height/size
  local a=math.rad(dual.angle)
  local ca,sa=math.cos(a),math.sin(a)
  return function(dx,dy)
    local x,y=dx*ca+dy*sa,-dx*sa+dy*ca
    return Tip.sample(dual.tip,x/(2*hw)+0.5,y/(2*hh)+0.5)
  end
end
function Texture.dualCoverage(dual,base,r,dx,dy)
  if not dual or dual.depth==0 or base<=0 then return base end
  return Texture.combine(base,Texture.dualSampler(dual,r)(dx,dy),dual.depth,dual.mode)
end
function Texture.paperCoverage(paper,base,x,y)
  if not paper or paper.depth==0 or base<=0 then return base end
  local t=Tip.sampleRepeat(paper.tip,(x-paper.offsetX)/paper.scale,
    (y-paper.offsetY)/paper.scale)
  if paper.invert then t=1-t end
  return Texture.combine(base,t,paper.depth,paper.mode)
end
return Texture
