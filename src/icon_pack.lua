-- Paint Lua icon adapter. Source art: Lucide (ISC / MIT for Feather-derived).
-- See assets/icons/LICENSE-LUCIDE.txt and docs/ICONES.md.
-- SVG originals are stored in assets/icons/svg; LOVE uses pre-rendered PNGs.
local IconPack = {}
local assets = {
    brush = "paintbrush", pen = "pencil", eraser = "eraser",
    transform = "move", magic_wand = "wand-sparkles",
    special_pen = "pen-tool", lasso = "lasso",
    filter = "sliders-horizontal", smudge = "hand", blur = "droplets",
    bucket = "paint-bucket", vector = "spline", text = "type",
    frame_divider = "panels-top-left", eyedropper = "pipette",
    canvas = "image", color = "palette", layer = "layers",
    back = "chevron-left", undo = "undo-2", redo = "redo-2",
    plus = "plus", minus = "minus", fullscreen = "maximize",
    view = "list-filter", settings = "settings-2",
    selection = "square-dashed", stabilizer = "activity",
    shape = "shapes", ruler = "ruler", material = "images",
    globe = "globe", more = "ellipsis", play = "play",
    down = "arrow-down-to-line", merge_down = "arrow-down-to-line",
    check = "check", eye = "eye", search = "search",
    arrow_right = "arrow-right", chevron_down = "chevron-down",
}
local images = {}
local prepared = false
function IconPack.asset_for(name) return assets[name] end
function IconPack.names()
    local result={}
    for name in pairs(assets) do result[#result+1]=name end
    table.sort(result)
    return result
end
function IconPack.load()
    if prepared then return true end
    if not (love and love.graphics and love.graphics.newImage) then return false end
    local unique={}
    for _,asset in pairs(assets) do unique[asset]=true end
    for asset in pairs(unique) do
        local path="assets/icons/png/"..asset..".png"
        local ok,img=pcall(love.graphics.newImage,path)
        assert(ok and img and img.setFilter and img.getWidth,
            "Pacote Lucide ausente ou inválido: "..path)
        img:setFilter("linear","linear")
        images[asset]=img
    end
    prepared=true
    return true
end
function IconPack.draw(name,cx,cy,radius,tint,alpha)
    if type(name)~="string" or not assets[name] then
        error("Ícone não cadastrado: "..tostring(name),2)
    end
    assert(type(radius)=="number" and radius>0,"Raio do ícone inválido")
    if not prepared and not IconPack.load() then return end
    local img=images[assets[name]]
    local size=radius*2
    tint=tint or {1,1,1}
    love.graphics.setColor(tint[1],tint[2],tint[3],alpha or 1)
    love.graphics.draw(img,cx-size/2,cy-size/2,0,
        size/img:getWidth(),size/img:getHeight())
end
return IconPack
