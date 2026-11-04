package.path="./?.lua;./?/init.lua;"..package.path
local Layout=require("src.editor_layout")
for _,size in ipairs({{914,686},{1024,768},{1365,768},{1600,900}}) do
    local W,H=size[1],size[2]
    for _,position in ipairs({"left","right","popup"}) do
        local l=Layout.compute(W,H,position,15)
        assert(l.dock.x>=0 and l.dock.x+l.dock.w<=W)
        assert(l.top.x>=0 and l.top.x+l.top.w<=W)
        assert(l.sliders.left_x>=0)
        assert(l.sliders.right_x+l.sliders.w<=W)
        assert(l.sliders.left_x+l.sliders.w<=l.sliders.right_x)
        assert(l.sliders.y+l.sliders.h<l.dock.y)
        assert(l.rail.button_y+15*l.rail.each<l.sliders.y+6)
        if position=="left" then assert(l.rail.x==0)
        elseif position=="right" then assert(l.rail.x==W-59)
        else assert(l.rail.x==nil) end
    end
end
print("PASS: dock, sliders, barra superior e lateral")
