-- Simulated ibisPaint color-picker state. No artwork pixels are modified.
-- v14.0 introduced multiple editable palettes; this is a local UI model only.
local ColorState={}
ColorState.__index=ColorState

local defaults={
    {0,0,0},{255,255,255},{235,48,48},{252,147,33},
    {249,229,49},{34,171,65},{16,182,222},{33,88,209},
    {109,55,184},{245,80,177},{140,140,140},{181,107,55}
}
local function valid_channel(x)
    return type(x)=="number" and x==math.floor(x) and x>=0 and x<=255
end
local function copy_color(c)
    return {c[1],c[2],c[3]}
end
local function require_color(c)
    assert(type(c)=="table" and valid_channel(c[1]) and valid_channel(c[2])
        and valid_channel(c[3]),"RGB inválido")
end
local function identical(a,b)
    return a[1]==b[1] and a[2]==b[2] and a[3]==b[3]
end
local function clamp(x,lo,hi)
    return math.max(lo,math.min(hi,x))
end
local function valid_name(name)
    return type(name)=="string" and #name>0 and #name<=64
        and not name:match("^%s*$")
end
local function hsv_to_rgb(h,s,v)
    -- H is 0-360, saturation and brightness are percentages.
    h=(h%360)/60
    s=s/100
    v=v/100
    local i=math.floor(h)
    local f=h-i
    local p=v*(1-s)
    local q=v*(1-f*s)
    local t=v*(1-(1-f)*s)
    local rgb
    if i==0 then rgb={v,t,p}
    elseif i==1 then rgb={q,v,p}
    elseif i==2 then rgb={p,v,t}
    elseif i==3 then rgb={p,q,v}
    elseif i==4 then rgb={t,p,v}
    else rgb={v,p,q} end
    return {math.floor(rgb[1]*255+0.5),
        math.floor(rgb[2]*255+0.5),
        math.floor(rgb[3]*255+0.5)}
end
local function rgb_to_hsv(rgb)
    local r,g,b=rgb[1]/255,rgb[2]/255,rgb[3]/255
    local hi=math.max(r,g,b)
    local lo=math.min(r,g,b)
    local delta=hi-lo
    local h=0
    if delta>0 then
        if hi==r then h=((g-b)/delta)%6
        elseif hi==g then h=(b-r)/delta+2
        else h=(r-g)/delta+4 end
        h=(h*60)%360
    end
    return h,hi==0 and 0 or delta/hi*100,hi*100
end

function ColorState.new()
    local initial={}
    for _,c in ipairs(defaults) do initial[#initial+1]=copy_color(c) end
    return setmetatable({
        current={0,0,0},
        previous={0,0,0},
        opacity=100,
        rgb_mode=false,
        palette_mode=false,
        palettes={{name="Basic",colors=initial}},
        active_palette=1,
        history={},
        next_palette_id=2
    },ColorState)
end

function ColorState:open_window()
    self.previous=copy_color(self.current)
end

function ColorState:set_rgb(r,g,b)
    local color={r,g,b}
    require_color(color)
    if not identical(color,self.current) then
        local unique={copy_color(color)}
        for _,old in ipairs(self.history) do
            if not identical(color,old) and #unique<100 then
                unique[#unique+1]=copy_color(old)
            end
        end
        self.history=unique
    end
    self.current=copy_color(color)
end
function ColorState:set_rgb_channel(index,value)
    assert(index==1 or index==2 or index==3,"Canal RGB inválido")
    assert(valid_channel(value),"Canal RGB inválido")
    local c=copy_color(self.current)
    c[index]=value
    self:set_rgb(c[1],c[2],c[3])
end
function ColorState:hex()
    return string.format("#%02X%02X%02X",
        self.current[1],self.current[2],self.current[3])
end
function ColorState:set_hex(code)
    assert(type(code)=="string","Código HEX inválido")
    local hex=code:gsub("^#","")
    assert(#hex==6 and hex:match("^[%x]+$"),"Código HEX inválido")
    self:set_rgb(tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),
        tonumber(hex:sub(5,6),16))
end
function ColorState:hsb()
    return rgb_to_hsv(self.current)
end
function ColorState:set_hsb(h,s,b)
    assert(type(h)=="number" and type(s)=="number" and type(b)=="number"
        and h==h and s==s and b==b
        and h>=0 and h<=360 and s>=0 and s<=100 and b>=0 and b<=100,
        "HSB inválido")
    local rgb=hsv_to_rgb(h,s,b)
    self:set_rgb(rgb[1],rgb[2],rgb[3])
end
function ColorState:set_opacity(n)
    assert(type(n)=="number" and n==n and n>=0 and n<=100,
        "Opacidade inválida")
    self.opacity=math.floor(n+0.5)
end
function ColorState:toggle_rgb_mode()
    self.rgb_mode=not self.rgb_mode
    return self.rgb_mode
end
function ColorState:toggle_palette_mode()
    self.palette_mode=not self.palette_mode
    return self.palette_mode
end
function ColorState:palettes_list()
    local result={}
    for i,p in ipairs(self.palettes) do
        result[i]={index=i,name=p.name,count=#p.colors}
    end
    return result
end
function ColorState:create_palette(name)
    assert(valid_name(name),"Nome da paleta inválido")
    assert(#self.palettes<32,"Limite de paletas demonstrativas")
    local id=#self.palettes+1
    self.palettes[id]={name=name,colors={}}
    self.active_palette=id
    return id
end
function ColorState:rename_palette(id,name)
    assert(valid_name(name),"Nome da paleta inválido")
    assert(self.palettes[id],"Paleta inexistente")
    self.palettes[id].name=name
end
function ColorState:choose_palette(id)
    assert(type(id)=="number" and id==math.floor(id)
        and self.palettes[id],"Paleta inexistente")
    self.active_palette=id
end
function ColorState:colors()
    local out={}
    for i,c in ipairs(self.palettes[self.active_palette].colors) do
        out[i]=copy_color(c)
    end
    return out
end
function ColorState:add_current()
    local colors=self.palettes[self.active_palette].colors
    assert(#colors<120,"Paleta cheia")
    colors[#colors+1]=copy_color(self.current)
    return #colors
end
function ColorState:select_color(index)
    local c=self.palettes[self.active_palette].colors[index]
    assert(c,"Cor inexistente")
    self:set_rgb(c[1],c[2],c[3])
end
function ColorState:move_color(from_index,to_index)
    local colors=self.palettes[self.active_palette].colors
    assert(type(from_index)=="number" and from_index==math.floor(from_index)
        and type(to_index)=="number" and to_index==math.floor(to_index)
        and from_index>=1 and from_index<=#colors
        and to_index>=1 and to_index<=#colors,"Posição inválida")
    local item=table.remove(colors,from_index)
    table.insert(colors,to_index,item)
end
function ColorState:history_list()
    local out={}
    for i,c in ipairs(self.history) do out[i]=copy_color(c) end
    return out
end
return ColorState
