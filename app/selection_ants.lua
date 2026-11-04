-- Paint-Lua v0.38: bordas animadas de seleção (marching ants).
-- O shader colore somente a linha que o motor já desenharia. O padrão
-- é calculado em pixels da tela, mantendo o passo ao mudar o zoom.
-- Não desenha nenhuma geometria nova, nem modifica máscaras ou RGBA.
local Ants={}

Ants.DASH_PX=5
Ants.CYCLE_PX=Ants.DASH_PX*2
Ants.SPEED_PX_S=24

Ants.shaderSource=[[
extern number dashPhase;

vec4 effect(vec4 color, Image texture, vec2 texCoord, vec2 screenCoord)
{
    // Projeção oblíqua estável na tela: evita a maioria dos casos em que
    // uma borda rotacionada ficaria com a faixa inteira da mesma cor.
    number distancePx=screenCoord.x*0.9238795325+
        screenCoord.y*0.3826834324+dashPhase;
    number band=mod(floor(distancePx/5.0),2.0);
    number light=mix(0.08,0.98,band);
    return vec4(light,light,light,color.a);
}
]]

-- Retorna um deslocamento limitado ao período: evita perder precisão na GPU
-- após horas com o editor aberto. Argumento opcional para testes determinísticos.
function Ants.phase(seconds)
    if type(seconds)~='number' or seconds~=seconds
        or seconds<=-math.huge or seconds>=math.huge then return 0 end
    return (seconds*Ants.SPEED_PX_S)%Ants.CYCLE_PX
end

-- Guarda o shader em state; não recompila por quadro ou por seleção.
-- Em sistemas sem shaders (ou mocks), mantém um contorno estático legível.
-- O shader anterior é restaurado mesmo se a rotina de desenho falhar.
function Ants.render(graphics,state,seconds,draw)
    assert(type(graphics)=='table' and type(state)=='table'
        and type(draw)=='function','render de seleção inválido')
    local enabled=false
    local previous=nil
    if graphics.newShader and graphics.getShader and graphics.setShader
        and not state.unavailable then
        if not state.shader then
            local ok,shader=pcall(graphics.newShader,Ants.shaderSource)
            if ok and shader then state.shader=shader
            else
                state.unavailable=true
                state.error=tostring(shader)
            end
        end
        if state.shader then
            local phase=Ants.phase(seconds)
            local ok,err=pcall(state.shader.send,state.shader,'dashPhase',phase)
            if ok then
                previous=graphics.getShader()
                local applied,reason=pcall(graphics.setShader,state.shader)
                if applied then
                    state.lastPhase=phase
                    enabled=true
                else
                    state.unavailable=true
                    state.error=tostring(reason)
                end
            else
                state.unavailable=true
                state.error=tostring(err)
            end
        end
    end
    local ok,err=pcall(draw,enabled)
    if enabled then graphics.setShader(previous) end
    if not ok then error(err,0) end
    return enabled
end

function Ants.release(state)
    if not state then return end
    if state.shader and state.shader.release then state.shader:release() end
    state.shader=nil
    state.lastPhase=nil
    state.unavailable=nil
    state.error=nil
end

return Ants
