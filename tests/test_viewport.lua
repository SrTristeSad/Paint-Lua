package.path = "./?.lua;./?/init.lua;" .. package.path
local Viewport=require("src.viewport")
local v=Viewport.new()
assert(v.zoom==1 and v.rotation==0 and v.pan_x==0)
assert(not v:pan_to(12,8))
v:begin_pan(10,10)
assert(v:pan_to(25,30))
assert(v.pan_x==15 and v.pan_y==20)
assert(v:pan_to(25,30))
assert(v.pan_x==15 and v.pan_y==20)
v:end_pan()
assert(not v:pan_to(30,40))
v:reset()
local z=v:zoom_at(1,130,140,100,100)
assert(z>1 and v.pan_x<0 and v.pan_y<0)
-- O ponto sob o cursor deve permanecer sob o cursor após mudar o zoom.
local x_before=130-100
local projected=100+v.pan_x + x_before*z
assert(math.abs(projected-130)<0.0001)
for i=1,100 do v:zoom_at(10,100,100,100,100) end
assert(v.zoom<=12)
for i=1,100 do v:zoom_at(-10,100,100,100,100) end
assert(v.zoom>=0.10)
v:rotate_wheel(4)
assert(math.abs(v.rotation-math.pi/9)<0.00001)
v:reset()
assert(v.zoom==1 and v.rotation==0 and v.pan_x==0 and v.pan_y==0)
print("PASS: viewport (zoom, ancoragem, rotação, pan e limites)")
