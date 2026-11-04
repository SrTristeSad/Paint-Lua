package.path="./?.lua;./?/init.lua;"..package.path
local B=require("src.brush_catalog")
assert(B.count()==12)
local all=B.search("")
assert(#all==12)
assert(all[1].brush.id=="dip_soft")
assert(B.get(1).label=="Dip Pen (Soft)")
assert(B.get(12).kind=="watercolor")
assert(B.get(13)==nil)
assert(#B.search("airbrush")==4)
assert(#B.search("felt tip")==3)
assert(#B.search("PEN")>=3)
assert(#B.search("unlisted")==0)
local isolated=B.get(1)
isolated.label="modified"
assert(B.get(1).label=="Dip Pen (Soft)")
all[1].brush.size=1234
assert(B.get(1).size==3)
assert(not pcall(function() B.get(1.25) end))
assert(not pcall(function() B.search(3) end))
for i=1,B.count() do
    local b=B.get(i)
    assert(type(b.label)=="string" and #b.label>0)
    assert(b.size>0 and b.size<=1000)
end
print("PASS: visual-only brush catalog and search state")
