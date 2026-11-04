package.path="./?.lua;./?/init.lua;" .. package.path
local P=require("src.canvas_presets")
assert(P.count()==13)
local list=P.list()
assert(#list==13)
local a4=P.get("a4")
assert(a4.dpi==150)
local w,h=P.pixels(a4)
assert(w==1754 and h==1240)
assert(P.next_dpi(a4,150)==300)
assert(P.next_dpi(a4,300)==600)
assert(P.next_dpi(a4,600)==150)
local scaled_w,scaled_h=P.pixels(a4,300)
assert(scaled_w==3508 and scaled_h==2480)
local p=P.at(1)
assert(p.width==1024 and p.height==768)
assert(P.at(13).id=="b5")
local generic=P.get("sd_speed")
assert(P.pixels(generic)==1024)
local normal_w,normal_h=P.pixels(generic)
assert(normal_w==1024 and normal_h==768)
assert(P.get("not_a_preset")==nil and P.at(19)==nil)
-- Make sure outside code cannot mutate shared entries.
list[1].width=3
a4.width=9
assert(P.at(1).width==1024 and P.get("a4").width==1754)
for _,fn in ipairs({
    function() P.pixels(generic,300) end,
    function() P.pixels(a4,72) end,
    function() P.next_dpi(generic) end,
    function() P.next_dpi(P.get("a5"),75) end,
}) do assert(not pcall(fn)) end
print("PASS: presets Windows (valores de referência, DPI, cópia defensiva)")
