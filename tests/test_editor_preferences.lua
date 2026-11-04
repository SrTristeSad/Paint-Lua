package.path="./?.lua;./?/init.lua;"..package.path
local P=require("src.editor_preferences")
local p=P.new()
assert(p.tool_position=="left" and p.popup_columns==3)
assert(p.show_tool_labels and not p.invert_wheel)
assert(p:rail_x(1024)==0)
assert(p:effective_tool_columns()==1)
assert(not pcall(function() p:set_popup_columns(2) end))
p:set_tool_position("right")
assert(p:rail_x(1024)==965)
assert(p:effective_tool_columns()==1)
assert(p:wheel_steps(3)==3)
p:set_tool_position("popup")
assert(p:rail_x(1024)==nil)
for n=1,3 do
    p:set_popup_columns(n)
    assert(p.popup_columns==n and p:effective_tool_columns()==n)
    local width,height=p:panel_size(1024,768)
    assert(width>100 and width<1024 and height>90 and height<768)
end
assert(not pcall(function() p:set_popup_columns(0) end))
assert(not pcall(function() p:set_popup_columns(4) end))
assert(not pcall(function() p:set_popup_columns(2.5) end))
assert(not pcall(function() p:set_tool_position("above") end))
assert(not p:toggle_tool_labels())
assert(p:toggle_tool_labels())
assert(p:toggle_invert_wheel())
assert(p:wheel_steps(4)==-4)
assert(p:wheel_steps(-1)==1)
assert(not p:toggle_invert_wheel())
assert(not p:toggle_undo_messages())
assert(p:toggle_undo_messages())
p:set_tool_position("left")
assert(p:rail_x(1600)==0)
-- User preferences must be reversible and safe to restore from disk.
local saved=P.new()
saved:set_tool_position("popup")
saved:set_popup_columns(2)
saved:set_tool_position("right")
saved:toggle_tool_labels()
saved:toggle_invert_wheel()
saved:toggle_undo_messages()
local encoded=saved:encode()
local restored=P.decode(encoded)
assert(restored.tool_position=="right" and restored.popup_columns==2)
assert(not restored.show_tool_labels and restored.invert_wheel)
assert(not restored.show_undo_message and restored:encode()==encoded)
local default=P.new()
assert(P.decode(default:encode()).tool_position=="left")
for _,contents in ipairs({
    "", "garbage", "version=2\n",
    "version=1\ntool_position=unknown\npopup_columns=2\n",
    encoded.."tool_position=popup\n",
    encoded:gsub("popup_columns=2","popup_columns=999"),
    encoded:gsub("invert_wheel=1","invert_wheel=true"),
    encoded.."function=print\n",
}) do
    assert(not pcall(function() return P.decode(contents) end),
        "Invalid preferences file must be rejected")
end
assert(not pcall(function() P.decode(string.rep("a",5000)) end))
print("PASS: safe settings file round-trip and corrupt config validation")
print("PASS: editor UI preferences (positions, popup columns, labels and mouse wheel)")
