-- Ponte opcional para Bono-Lua. A implementação atual suporta apenas WorldClock:
-- o runtime de armaturas / renderizador LÖVE ainda não está no Bono-Lua.
local Bridge = {}
Bridge.__index = Bridge
function Bridge.new()
  local self = setmetatable({clock = nil, state = 'indisponível'}, Bridge)
  -- A dependência é submódulo; sem ela o editor segue funcional.
  local ok, WorldClock = pcall(require,'dragonbones.animation.WorldClock')
  if ok and type(WorldClock)=='table' and type(WorldClock.new)=='function' then
    self.clock = WorldClock.new(0)
    self.state = 'relógio disponível; renderizador pendente'
  end
  return self
end
function Bridge:add(animatable)
  if not self.clock then return nil,'Bono-Lua não instalado' end
  if type(animatable)~='table' or type(animatable.advanceTime)~='function' then
    return nil,'animatable inválido'
  end
  self.clock:add(animatable)
  return true
end
function Bridge:update(dt)
  if self.clock then
    -- Delta medido pelo LÖVE; não tenta acessar APIs de armadura ainda ausentes.
    self.clock:advanceTime(math.max(0, math.min(dt or 0, 0.25)))
  end
end
return Bridge
