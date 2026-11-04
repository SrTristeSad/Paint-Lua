package.path="./?.lua;./?/init.lua;" .. package.path
local ViewState=require("src.view_state")
local s=ViewState.new()
assert(not s.grid and not s.reference and not s.manga)
assert(s.interpolation=="smooth" and s.grid1==64 and s.grid2==256)
assert(s:toggle_grid() and not s:toggle_grid())
assert(s:toggle_reference() and not s:toggle_reference())
assert(s:toggle_manga() and not s:toggle_manga())
assert(s:toggle_interpolation()=="pixelated")
assert(s:toggle_interpolation()=="smooth")
assert(s:toggle_wheel_direction() and not s:toggle_wheel_direction())
s:set_interval("grid1",32)
s:set_interval("grid2",128)
s:set_origin(-21,300)
assert(s.grid1==32 and s.grid2==128 and s.offset_x==-21 and s.offset_y==300)
for _,fn in ipairs({
    function() s:set_interval("foo",32) end,
    function() s:set_interval("grid1",0) end,
    function() s:set_interval("grid2",9000) end,
    function() s:set_interval("grid1",12.2) end,
    function() s:set_origin(1.4,3) end,
    function() s:set_origin(20000,0) end,
}) do assert(not pcall(fn)) end
s:reset_grid()
assert(s.grid1==64 and s.grid2==256 and s.offset_x==0 and s.offset_y==0)
s:toggle_grid()
s:toggle_reference()
s:toggle_manga()
s:toggle_interpolation()
s:toggle_wheel_direction()
s:set_interpolation("pixelated")
assert(s.interpolation=="pixelated")
s:set_interpolation("smooth")
assert(not pcall(function() s:set_interpolation("cubic") end))
local before=s:grid_color("grid1")
local after=s:cycle_grid_color("grid1")
assert(after==2 and before~=s:grid_color("grid1"))
assert(s:cycle_grid_color("grid2")==3)
assert(not pcall(function() s:cycle_grid_color("grid3") end))
assert(not pcall(function() s:grid_color("grid3") end))
s:reset()
assert(not s.grid and not s.reference and not s.manga and not s.invert_wheel)
assert(s.interpolation=="smooth" and s.grid1==64)
print("PASS: View Menu (grade, referência, manga, interpolação, limites e reset)")
