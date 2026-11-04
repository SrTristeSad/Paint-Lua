package.path="./?.lua;./?/init.lua;"..package.path
local Color=require("src.color_state")
local c=Color.new()
assert(c:hex()=="#000000")
assert(#c:colors()==12 and #c:palettes_list()==1)
assert(c.opacity==100 and not c.palette_mode and not c.rgb_mode)
c:set_rgb(27,84,162)
assert(c:hex()=="#1B54A2")
c:open_window()
assert(c.previous[1]==27 and c.previous[3]==162)
c:set_hex("ff0080")
assert(c:hex()=="#FF0080")
c:set_hex("#01abfF")
assert(c:hex()=="#01ABFF")
c:set_rgb_channel(2,22)
assert(c.current[2]==22)
c:set_hsb(0,100,100)
assert(c:hex()=="#FF0000")
local h,s,b=c:hsb()
assert(h<0.1 and s>99 and b>99)
c:set_hsb(120,100,100)
assert(c:hex()=="#00FF00")
c:set_hsb(240,100,100)
assert(c:hex()=="#0000FF")
c:set_opacity(33.5)
assert(c.opacity==34)
assert(c:toggle_palette_mode() and c:toggle_rgb_mode())
assert(not c:toggle_palette_mode() and not c:toggle_rgb_mode())
local id=c:create_palette("Character")
assert(id==2 and c.active_palette==2 and #c:colors()==0)
assert(c:add_current()==1)
c:set_hex("FFFFFF")
assert(c:add_current()==2)
c:move_color(2,1)
assert(c:colors()[1][1]==255)
c:select_color(2)
assert(c:hex()=="#0000FF")
c:rename_palette(2,"Skin colors")
assert(c:palettes_list()[2].name=="Skin colors")
c:choose_palette(1)
assert(#c:colors()==12)
local copy=c:colors()
copy[1][1]=255
assert(c:colors()[1][1]==0)
c:choose_palette(2)
local latest=c:history_list()
assert(#latest>0)
latest[1][1]=2
assert(c:history_list()[1][1]~=2)
for i=1,130 do c:set_rgb(i%256,(i+1)%256,(i+2)%256) end
assert(#c:history_list()==100)
for _,fn in ipairs({
    function() c:set_hex("#fff") end,
    function() c:set_hex("HAPPY!") end,
    function() c:set_rgb(-1,0,0) end,
    function() c:set_rgb(0,256,0) end,
    function() c:set_hsb(400,90,90) end,
    function() c:set_hsb(0,0/0,0) end,
    function() c:set_opacity(101) end,
    function() c:create_palette(" ") end,
    function() c:choose_palette(99) end,
    function() c:move_color(0,2) end,
    function() c:select_color(99) end,
    function() c:rename_palette(99,"x") end,
}) do assert(not pcall(fn)) end
print("PASS: Color window state (RGB, HSB, HEX, palettes, reorder, history)")
