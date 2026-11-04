-- Visual-only examples derived from publicly shown Windows brush lists.
-- Not a full brush database or real stroke engine; version 14.1.4 unverified.
local BrushCatalog={}
local entries={
    {id="dip_soft",label="Dip Pen (Soft)",size=3,kind="pen"},
    {id="dip_hard",label="Dip Pen (Hard)",size=3,kind="pen"},
    {id="dip_bleed",label="Dip Pen (Bleed)",size=3,kind="bleed"},
    {id="felt_soft",label="Felt Tip Pen (Soft)",size=6,kind="marker"},
    {id="felt_hard",label="Felt Tip Pen (Hard)",size=6,kind="marker"},
    {id="felt_fade",label="Felt Tip Pen (Fade)",size=8,kind="fade"},
    {id="air_normal",label="Airbrush (Normal)",size=8,kind="air"},
    {id="air_triangle",label="Airbrush (Triangle)",size=8,kind="air"},
    {id="air_trapezoid_20",label="Airbrush (Trapezoid 20%)",size=8,kind="air"},
    {id="air_trapezoid_40",label="Airbrush (Trapezoid 40%)",size=8,kind="air"},
    {id="pencil_2",label="Pencil (#2)",size=4,kind="pencil"},
    {id="watercolor_opaque",label="Watercolor (Opaque)",size=15,kind="watercolor"}
}
local function clone(t)
    if not t then return nil end
    local out={}
    for k,v in pairs(t) do out[k]=v end
    return out
end
function BrushCatalog.count() return #entries end
function BrushCatalog.get(index)
    assert(type(index)=="number" and index==math.floor(index),"Invalid brush index")
    return clone(entries[index])
end
function BrushCatalog.search(query)
    assert(type(query)=="string","Search text must be a string")
    local match={}
    query=query:lower()
    for index,brush in ipairs(entries) do
        if query=="" or brush.label:lower():find(query,1,true) then
            match[#match+1]={index=index,brush=clone(brush)}
        end
    end
    return match
end
return BrushCatalog
