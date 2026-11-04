-- Presets transcribed from a published Windows screenshot; build number unknown.
-- NOT certified as values for ibisPaint Windows 14.1.4.
-- Page DPI changes are simulations of pixel dimensions, not print processing.
local Presets={}
local definitions={
    {id="sd_speed",name="SD (Speed)",width=1024,height=768},
    {id="sd_square",name="1 : 1 (SD)",width=1280,height=1280},
    {id="sd_3_4",name="3 : 4 (SD)",width=1024,height=768},
    {id="sd_9_16",name="9 : 16 (SD)",width=1280,height=720},
    {id="twitter_header",name="Twitter Header",width=1500,height=500},
    {id="chat_stamp",name="Chat Stamp",width=370,height=320},
    {id="vertical",name="Vertical",width=690,height=4096},
    {id="manga",name="Manga Manuscript",width=2576,height=3648},
    {id="postcard",name="Postcard (JP)",width=1748,height=1181,dpi=300},
    {id="a4",name="A4",width=1754,height=1240,dpi=150},
    {id="a5",name="A5",width=1240,height=874,dpi=150},
    {id="b4",name="B4",width=2085,height=1476,dpi=150},
    {id="b5",name="B5",width=1476,height=1039,dpi=150}
}
local function copy(entry)
    local result={}
    for k,v in pairs(entry) do result[k]=v end
    return result
end
function Presets.list()
    local out={}
    for i,p in ipairs(definitions) do out[i]=copy(p) end
    return out
end
function Presets.get(id)
    for _,p in ipairs(definitions) do
        if p.id==id then return copy(p) end
    end
    return nil
end
function Presets.at(index)
    local p=definitions[index]
    return p and copy(p) or nil
end
function Presets.count()
    return #definitions
end
function Presets.dpi_options()
    return {150,300,600}
end
function Presets.pixels(preset,dpi)
    assert(type(preset)=="table" and type(preset.width)=="number"
        and type(preset.height)=="number","Modelo inválido")
    if not preset.dpi then
        assert(dpi==nil,"Este modelo não contém configuração de DPI")
        return preset.width,preset.height
    end
    dpi=dpi or preset.dpi
    assert(dpi==150 or dpi==300 or dpi==600,"DPI inválido")
    local factor=dpi/preset.dpi
    return math.floor(preset.width*factor+0.5),
        math.floor(preset.height*factor+0.5)
end
function Presets.next_dpi(preset,current)
    assert(preset and preset.dpi,"O modelo não possui DPI")
    local opts=Presets.dpi_options()
    current=current or preset.dpi
    for i,n in ipairs(opts) do
        if n==current then return opts[i%#opts+1] end
    end
    error("DPI inválido")
end
return Presets
