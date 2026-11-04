-- Mistura LOCAL de tinta com cores existentes, uma amostra por carimbo.
-- Não é o reservatório de tinta úmida completo do PhotoCraft: a v0.8 apenas
-- simula coleta de pigmento na camada ativa. A amostra antecede a escrita.
local Doc = require('core.doc')
local Selection = require('core.selection')
local Mixer = {}
local Mix = {}; Mix.__index=Mix
local function finite(v) return type(v)=='number' and v==v and v>-math.huge and v<math.huge end
function Mixer.prepare(spec)
  if spec==nil then return nil end
  assert(type(spec)=='table', 'mistura de cor inválida')
  if getmetatable(spec)==Mix then return spec end
  local strength=spec.strength==nil and 0.5 or spec.strength
  local radius=spec.radius or 0
  assert(finite(strength) and strength>=0 and strength<=1, 'força da mistura inválida')
  assert(finite(radius) and radius==math.floor(radius) and radius>=0 and radius<=8,
    'raio da mistura inválido')
  return setmetatable({strength=strength, radius=radius}, Mix)
end
function Mixer.pick(doc,layer,cx,cy,color,mix)
  if not mix or mix.strength==0 then return color end
  -- Média ponderada por alfa: transparência não se transforma em tinta preta.
  local x0,y0=math.floor(cx),math.floor(cy)
  local weight,rs,gs,bs=0,0,0,0
  local radius=mix.radius
  local count=0
  for y=y0-radius,y0+radius do
    for x=x0-radius,x0+radius do
      if x>=0 and x<doc.w and y>=0 and y<doc.h then
        count=count+1
        local tile=Doc.getTile(layer,math.floor(x/Doc.TILE),math.floor(y/Doc.TILE),false)
        if tile then
          local r,g,b,a=tile:getPixel(x%Doc.TILE,y%Doc.TILE)
          weight=weight+a
          rs,gs,bs=rs+r*a,gs+g*a,bs+b*a
        end
      end
    end
  end
  if weight==0 then return color end
  -- A mistura em uma região parcialmente transparente é proporcional à tinta coletada.
  local t=mix.strength*weight/count
  return {color[1]*(1-t)+rs/weight*t,
          color[2]*(1-t)+gs/weight*t,
          color[3]*(1-t)+bs/weight*t}
end

-- v0.9: modelo simples de pincel úmido inspirado no Mixer Brush do PhotoCraft.
-- A cor carregada e a cor recolhida são armazenadas por traço (não no documento).
-- Não é uma simulação física de fluidos: combina cores e massas normalizadas.
local WetConfig = {}; WetConfig.__index = WetConfig
local function valid01(v) return finite(v) and v>=0 and v<=1 end
local function rgb(color)
  return type(color)=='table' and valid01(color[1])
    and valid01(color[2]) and valid01(color[3])
end

function Mixer.prepareWet(spec)
  if spec == nil then return nil end
  assert(type(spec)=='table', 'configuração de tinta úmida inválida')
  if getmetatable(spec)==WetConfig then
    for _,k in ipairs({'wet','load','mix','flow'}) do
      assert(valid01(spec[k]),'tinta úmida: '..k..' deve estar entre 0 e 1')
    end
    assert(finite(spec.radius) and spec.radius==math.floor(spec.radius)
      and spec.radius>=0 and spec.radius<=8,'tinta úmida: raio de coleta inválido')
    return spec
  end
  -- wet: absorção; load: conservação da tinta; mix: razão entre tinta
  -- carregada e pigmento coletado; flow: transferência ao papel.
  local cfg={wet=spec.wet==nil and 0.5 or spec.wet,
    load=spec.load==nil and 0.5 or spec.load,
    mix=spec.mix==nil and 0.5 or spec.mix,
    flow=spec.flow==nil and 1 or spec.flow,
    radius=spec.radius==nil and 0 or spec.radius}
  for _,k in ipairs({'wet','load','mix','flow'}) do
    assert(valid01(cfg[k]), 'tinta úmida: '..k..' deve estar entre 0 e 1')
  end
  assert(finite(cfg.radius) and cfg.radius==math.floor(cfg.radius)
    and cfg.radius>=0 and cfg.radius<=8,
    'tinta úmida: raio de coleta inválido')
  for k in pairs(spec) do
    assert(cfg[k]~=nil, 'tinta úmida: opção desconhecida '..tostring(k))
  end
  return setmetatable(cfg,WetConfig)
end

function Mixer.newWetState(color)
  assert(rgb(color),'tinta úmida: cor inválida')
  return {reservoir={color[1],color[2],color[3]}, amount=1,
    pickup=nil, pickupAmount=0}
end

function Mixer.loadWet(state,color)
  assert(type(state)=='table' and rgb(color),'carga de tinta inválida')
  state.reservoir={color[1],color[2],color[3]}
  state.amount=1
end

function Mixer.cleanWet(state)
  assert(type(state)=='table','estado de tinta inválido')
  state.reservoir=nil
  state.amount=0
  state.pickup=nil
  state.pickupAmount=0
end

-- Amostragem alfa-ponderada da camada ativa, antes de escrever o carimbo.
-- Cobertura (0..1) mede quanto da vizinhança contém pigmento opaco.
-- Se houver seleção, pigmentos de fora dela não contaminam o pincel.
function Mixer.sampleWet(doc,layer,cx,cy,radius,selection)
  local x0,y0=math.floor(cx), math.floor(cy)
  local weight,rs,gs,bs,count=0,0,0,0,0
  for y=y0-radius,y0+radius do
    for x=x0-radius,x0+radius do
      if x>=0 and y>=0 and x<doc.w and y<doc.h
        and (not selection or Selection.contains(selection,x,y)) then
        count=count+1
        local tile=Doc.getTile(layer,math.floor(x/Doc.TILE),math.floor(y/Doc.TILE),false)
        if tile then
          local r,g,b,a=tile:getPixel(x%Doc.TILE,y%Doc.TILE)
          weight=weight+a
          rs,gs,bs=rs+r*a,gs+g*a,bs+b*a
        end
      end
    end
  end
  if weight<=0 or count==0 then return nil,0 end
  return {rs/weight,gs/weight,bs/weight},math.min(1,weight/count)
end

-- Executar UMA VEZ por carimbo, antes de desenhar (inclusive com simetria).
-- Retorna cor RGB e multiplicador 0..1 para o fluxo definido pelo usuário.
-- A coleta usa apenas a camada ativa, não uma composição das camadas visíveis.
function Mixer.wetDab(doc,layer,cx,cy,settings,state,selection)
  local cfg=Mixer.prepareWet(settings)
  assert(type(state)=='table' and valid01(state.amount)
    and valid01(state.pickupAmount),'estado de tinta úmida inválido')
  local sample,coverage=Mixer.sampleWet(doc,layer,cx,cy,cfg.radius,selection)
  local pickupRate=cfg.wet*0.25*coverage
  -- O pigmento úmido recolhido permanece por alguns carimbos e se esgota
  -- gradualmente, inclusive quando o pincel passa por transparência.
  local oldMass=state.pickupAmount*0.88
  if sample and pickupRate>0 then
    if state.pickup and oldMass>0 then
      local k=pickupRate/(oldMass+pickupRate)
      state.pickup={state.pickup[1]*(1-k)+sample[1]*k,
                    state.pickup[2]*(1-k)+sample[2]*k,
                    state.pickup[3]*(1-k)+sample[3]*k}
    else
      state.pickup={sample[1],sample[2],sample[3]}
    end
    state.pickupAmount=math.min(1,oldMass+pickupRate)
  else
    state.pickupAmount=oldMass
    if oldMass<1e-8 then state.pickup=nil; state.pickupAmount=0 end
  end

  local pickupFactor=cfg.mix*cfg.wet
  local rWeight=(state.reservoir and state.amount or 0)*(1-pickupFactor)
  local pWeight=(state.pickup and state.pickupAmount or 0)*pickupFactor
  local total=rWeight+pWeight
  local color=nil
  if total>1e-9 then
    color={0,0,0}
    for i=1,3 do
      color[i]=((state.reservoir and state.reservoir[i] or 0)*rWeight
        +(state.pickup and state.pickup[i] or 0)*pWeight)/total
    end
  end
  -- Load=1 mantém a carga; Load=0 a esgota progressivamente.
  state.amount=state.amount*(0.8+0.2*cfg.load)
  if state.amount<1e-8 then state.amount=0 end
  return color, cfg.flow*math.min(1,total)
end

return Mixer
