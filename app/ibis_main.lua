-- Ibis-Lua. Windows reference-based UI reconstruction, not the official application.
-- Layout evidence: Windows gallery/new canvas (Uptodown), Windows tool editor
-- (Microsoft Store, independent Windows screenshots), official tool manual.
-- Interface própria baseada no Ibis-Lua, ligada ao motor Paint-Lua v0.25.
local PaintBridge = require("app.paint_bridge")
local Model = require("src.model")
local Viewport = require("src.viewport")
local ViewState = require("src.view_state")
local CanvasPresets = require("src.canvas_presets")
local Gallery = require("src.gallery")
local GalleryStorage = require("src.gallery_storage")
local PNGExport = require("src.png_export")
local BrushCatalog = require("src.brush_catalog")
local EditorPreferences = require("src.editor_preferences")
local ColorState = require("src.color_state")
local Theme = require("src.ui_theme")
local IconPack = require("src.icon_pack")
local EditorLayout = require("src.editor_layout")
local utf8 = require("utf8")
local state = Model.new()
local paint = PaintBridge.new()
local view = Viewport.new()
local visual = ViewState.new()
local gallery = Gallery.new()
local preferences=EditorPreferences.new()
local colors=ColorState.new()
local color_e2e=os.getenv("PAINT_LUA_COLOR_E2E")=="1"
local color_e2e_stage=0
local color_float=false
local color_position=nil
local color_size=nil
local color_dialog=nil
local color_input=""
local color_input_replace=true
local color_drag=nil
local color_resize=nil
local color_slider_drag=nil
local color_wheel_drag=nil
local color_palette_page=0
local color_swatch_drag=nil
local settings_e2e=os.getenv("PAINT_LUA_SETTINGS_E2E")=="1"
local settings_e2e_stage=0
local gallery_selecting=false
local gallery_dialog=nil
local gallery_input=""
local gallery_input_replace=true
local active_artwork_id=nil
-- Cache LRU de prévias; geração de arquivos antigos ocorre de forma incremental.
local gallery_thumb_cache={}
local gallery_thumb_pending={}
local gallery_thumb_queue={}
local gallery_thumb_clock=0
local MAX_GALLERY_IMAGES=40
local controls = {}
local font = {}
local scale, W, H = 1, 1024, 768
local panel, gallery_menu = nil, nil
local gallery_scroll, gallery_item_scroll, preset_selected = 0, 0, 0
local drag_dimension = nil
local current_width, current_height = "1000", "1000"
local focus, opacity, size_zoom = nil, 100, 100
local input_replace = true
local layer_press = nil
-- Lista com rolagem e drag-and-drop; IDs (não índices) sobrevivem à reordenação.
local layer_scroll, layer_row_drag, layer_row_targets = 0, nil, {}
local layer_position, layer_size, drag_layer, drag_layer_resize, drag_opacity = nil, nil, nil, nil, nil
local layer_blend_open = false
local layer_advanced_tab = 'group'
local selected_brush, palette_index = 1, 1
local brush_scroll=0
local brush_search_active=false
local brush_search=""
local brush_drag=nil
local brush_tab="Basic"
local toast, toast_until = nil, 0
local smoke = os.getenv("PAINT_LUA_SMOKE") == "1"
local e2e = os.getenv("PAINT_LUA_E2E") == "1"
local e2e_stage = 0
local layer_e2e = os.getenv('PAINT_LUA_LAYER_E2E') == '1'
local layer_e2e_stage = 0
local gallery_e2e = os.getenv("PAINT_LUA_GALLERY_E2E") == "1"
local gallery_e2e_stage = 0
local gallery_persist_e2e=os.getenv('PAINT_LUA_GALLERY_PERSIST_E2E')
local gallery_persist_stage=0
-- Autotestes/capturas não devem criar dados persistentes por acidente.
local persistence_enabled=not (smoke or e2e or layer_e2e or
    settings_e2e or gallery_e2e or color_e2e or
    os.getenv('PAINT_LUA_BRIDGE_E2E')=='1' or
    os.getenv('PAINT_LUA_GALLERY_STORAGE_E2E')=='1')
local smoke_screen = os.getenv("PAINT_LUA_SCREEN") or "title"
local capture_requested, capture_done, capture_pending, capture_error = false, false, false, nil
local C = Theme.colors
local tools = {
    {"Transformar","transform"},{"Varinha Mágica","magic_wand"},{"Laço","lasso"},
    {"Filtro","filter"},{"Pincel","brush"},{"Borracha","eraser"},
    {"Borrar","smudge"},{"Desfoque","blur"},{"Caneta Especial","special_pen"},
    {"Lata de Tinta","bucket"},{"Vetor","vector"},{"Texto","text"},
    {"Divisor de quadros","frame_divider"},{"Conta-gotas","eyedropper"},
    {"Tela","canvas"}
}
local presets = CanvasPresets.list()
local active_dpi=nil

local palette = {
    {0,0,0},{255,255,255},{235,48,48},{252,147,33},
    {249,229,49},{34,171,65},{16,182,222},{33,88,209},
    {109,55,184},{245,80,177},{140,140,140},{181,107,55}
}

local function rgba(rgb,alpha)
    love.graphics.setColor(rgb[1],rgb[2],rgb[3],alpha or 1)
end
local function rectangle(x,y,w,h,col,alpha,round)
    rgba(col,alpha)
    love.graphics.rectangle("fill",x,y,w,h,round or 0,round or 0)
end
local function stroke(x,y,w,h,col,alpha)
    rgba(col,alpha)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line",x,y,w,h)
end
local function soft_shadow(x,y,w,h,round,intensity)
    local alpha=intensity or 1
    rectangle(x+1,y+9,w,h,C.deep,0.025*alpha,round+3)
    rectangle(x+1,y+5,w,h,C.deep,0.044*alpha,round+2)
    rectangle(x,y+2,w,h,C.deep,0.061*alpha,round+1)
end
local function vertical_gradient(x,y,w,h,top,bottom,steps)
    steps=steps or 40
    for i=0,steps-1 do
        local t=i/(steps-1)
        rectangle(x,y+h*i/steps,w,h/steps+1,Theme.mix(top,bottom,t))
    end
end
local function inset_border(x,y,w,h,round,alpha)
    rgba(C.card_border,alpha or 0.55)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line",x+0.5,y+0.5,w-1,h-1,round,round)
end
local function line(x1,y1,x2,y2,width,col,alpha)
    rgba(col or C.white,alpha)
    love.graphics.setLineWidth(width or 1.5)
    love.graphics.line(x1,y1,x2,y2)
end
local function label(s,x,y,w,typ,align,col)
    love.graphics.setFont(font[typ or "normal"])
    rgba(col or C.white)
    love.graphics.printf(tostring(s),x,y,w,align or "left")
end
local function hit(x,y,w,h,fn,key)
    controls[#controls+1] = {x=x,y=y,w=w,h=h,fn=fn,key=key}
end
local function pointer()
    local x,y = love.mouse.getPosition()
    return x/scale,y/scale
end
local function over(x,y,w,h)
    local mx,my=pointer()
    return mx>=x and mx<=x+w and my>=y and my<=y+h
end
local function notice(s)
    toast=s
    toast_until=love.timer.getTime()+3.5
end
local function persist_gallery()
    if not persistence_enabled then return true end
    local ok,err=GalleryStorage.save(gallery)
    if not ok then notice('Galeria: falha ao salvar índice: '..tostring(err)) end
    return ok,err
end
local function forget_gallery_thumbnail(id)
    local entry=gallery_thumb_cache[id]
    if entry and entry.image and entry.image.release then entry.image:release() end
    gallery_thumb_cache[id]=nil
    gallery_thumb_pending[id]=nil
end
local function gallery_thumbnail(id)
    if not persistence_enabled then return nil end
    gallery_thumb_clock=gallery_thumb_clock+1
    local cached=gallery_thumb_cache[id]
    if cached then cached.t=gallery_thumb_clock;return cached.image end
    if not gallery_thumb_pending[id] then
        gallery_thumb_pending[id]=true
        gallery_thumb_queue[#gallery_thumb_queue+1]=id
    end
    return nil
end
local function build_next_gallery_thumbnail()
    if not persistence_enabled or state.screen~='gallery' then return end
    while #gallery_thumb_queue>0 do
        local id=table.remove(gallery_thumb_queue,1)
        if gallery_thumb_pending[id] then
            gallery_thumb_pending[id]=nil
            local bytes=GalleryStorage.ensureThumbnail(id)
            local function decode_preview(raw)
                if not raw then return nil end
                local ok,result=pcall(function()
                    return love.graphics.newImage(love.filesystem.newFileData(raw,'preview.png'))
                end)
                if ok then result:setFilter('linear','linear');return result end
                return nil
            end
            local image=decode_preview(bytes)
            if bytes and not image then
                -- Um PNG pode ter assinatura válida e dados internos corrompidos.
                -- Reconstruir a prévia derivada; nunca substituir a pintura NPNT.
                image=decode_preview(GalleryStorage.ensureThumbnail(id,true))
            end
            gallery_thumb_clock=gallery_thumb_clock+1
            gallery_thumb_cache[id]={image=image,t=gallery_thumb_clock}
            local n=0
            local oldest,oldTime
            for key,entry in pairs(gallery_thumb_cache) do
                n=n+1
                if not oldTime or entry.t<oldTime then
                    oldest,oldTime=key,entry.t
                end
            end
            if n>MAX_GALLERY_IMAGES and oldest~=id then
                forget_gallery_thumbnail(oldest)
            end
            break -- No máximo uma composição/decodificação por quadro.
        end
    end
end
local function save_current_artwork()
    if not persistence_enabled or not active_artwork_id then return true end
    paint:sync(state)
    local ok,err=paint:save()
    if not ok then
        notice('Falha ao salvar a obra: '..tostring(err))
        return nil,err
    end
    forget_gallery_thumbnail(active_artwork_id)
    return persist_gallery()
end
local function back_to_gallery()
    if not save_current_artwork() then return end
    state:open_gallery()
    panel=nil
end
local function open_gallery_artwork(item)
    if not persistence_enabled then
        state:reopen_canvas(item.width,item.height)
        active_artwork_id=item.id
        view:reset()
        return
    end
    local doc,warning=GalleryStorage.loadArtwork(item.id)
    if not doc then
        notice('Não foi possível abrir '..item.name..': '..tostring(warning))
        return
    end
    paint:attachDocument(state,doc,item.id)
    active_artwork_id=item.id
    view:reset()
    panel=nil
    if warning then notice(warning) end
end
local function save_preferences()
    -- Screenshot and interaction tests start with deterministic defaults.
    if smoke or e2e or settings_e2e or gallery_e2e then return end
    local ok,reason=love.filesystem.write(
        "editor-preferences.txt",preferences:encode())
    if not ok then notice("Settings could not be saved: "..tostring(reason)) end
end
local function current()
    return state.screen=="editor"
end
local picker_hue=0
local function set_panel(name)
    if panel==name then panel=nil else panel=name end
    if name=="color" and panel=="color" then
        colors:open_window()
        local h=colors:hsb()
        picker_hue=(h%360)/360
    elseif panel~="color" then
        color_dialog=nil
    end
    if name=="brush" or name=="layer" or name=="color" then
        state.active_panel=panel==name and name or nil
    else
        state.active_panel=nil
    end
end
local function hsv_rgb(h,s,v)
    h=(h%1)*6
    local i=math.floor(h)
    local f=h-i
    local p=v*(1-s)
    local q=v*(1-f*s)
    local t=v*(1-(1-f)*s)
    if i==0 then return {v,t,p}
    elseif i==1 then return {q,v,p}
    elseif i==2 then return {p,v,t}
    elseif i==3 then return {p,q,v}
    elseif i==4 then return {t,p,v}
    else return {v,p,q} end
end
local function draw_hue_wheel(cx,cy,r)
    local steps=72
    for i=0,steps-1 do
        local a=-math.pi/2+i*2*math.pi/steps
        local b=-math.pi/2+(i+1)*2*math.pi/steps
        rgba(hsv_rgb(i/steps,1,1))
        love.graphics.polygon("fill",
            cx+math.cos(a)*r,cy+math.sin(a)*r,
            cx+math.cos(b)*r,cy+math.sin(b)*r,
            cx+math.cos(b)*(r-17),cy+math.sin(b)*(r-17),
            cx+math.cos(a)*(r-17),cy+math.sin(a)*(r-17))
    end
    local N=24
    local radius=r-23
    for i=0,N-1 do
        for j=0,N-1 do
            local u=(i+0.5)/N
            local v=(j+0.5)/N
            rgba(hsv_rgb(picker_hue,u,1-v))
            local function q(uu,vv)
                return cx+(uu-vv)*radius,cy+(uu+vv-1)*radius
            end
            local x1,y1=q(i/N,j/N)
            local x2,y2=q((i+1)/N,j/N)
            local x3,y3=q((i+1)/N,(j+1)/N)
            local x4,y4=q(i/N,(j+1)/N)
            love.graphics.polygon("fill",x1,y1,x2,y2,x3,y3,x4,y4)
        end
    end
    rgba(C.white)
    love.graphics.setLineWidth(1.4)
    love.graphics.polygon("line",cx,cy-radius,cx+radius,cy,cx,cy+radius,cx-radius,cy)
    local t=picker_hue*2*math.pi-math.pi/2
    love.graphics.circle("line",cx+math.cos(t)*(r-8),cy+math.sin(t)*(r-8),6)
end

local function outline_circle(x,y,r,alpha)
    rgba(C.white,alpha or 0.8)
    love.graphics.setLineWidth(1.6)
    love.graphics.circle("line",x,y,r)
end

-- Shared Lucide icon pack, with editable SVG sources and offline PNGs.
local glyph_color=nil
local function glyph(name,cx,cy,r)
    IconPack.draw(name,cx,cy,r,glyph_color or C.white,0.96)
end

local function icon_button(x,y,w,h,name,fn,active,disabled)
    local hovered=over(x,y,w,h) and not disabled
    local round=Theme.radius.button
    if active then
        rectangle(x,y,w,h,C.accent,0.93,round)
        inset_border(x,y,w,h,round,0.30)
    elseif hovered then
        rectangle(x,y,w,h,C.white,0.16,round)
        inset_border(x,y,w,h,round,0.20)
    end
    glyph(name,x+w/2,y+h/2,math.min(w,h)*0.32)
    if fn and not disabled then hit(x,y,w,h,fn,name) end
end
local function plain_button(x,y,w,h,name,fn,accent,key)
    local round=Theme.radius.button
    local hovered=over(x,y,w,h)
    if accent then soft_shadow(x,y,w,h,round,0.70) end
    rectangle(x,y,w,h,
        accent and (hovered and C.accent_light or C.accent) or
        (hovered and C.hover or C.dark),1,round)
    if not accent then inset_border(x,y,w,h,round,0.15) end
    label(name,x,y+(h-17)/2,w,"normal","center",
        accent and C.deep or C.white)
    hit(x,y,w,h,fn,key or name)
end
local function title_screen()
    -- Independent Paint Lua visual identity; this is not the ibisPaint logo.
    local hero_h=H*0.675
    vertical_gradient(0,0,W,hero_h,
        {0.160,0.240,0.365},C.deep,64)
    rectangle(0,hero_h,W,H-hero_h,C.ranking)
    rectangle(0,hero_h,W,3,C.accent,0.91)
    rgba(C.white,0.035)
    love.graphics.circle("fill",W*0.13,hero_h*0.25,145)
    love.graphics.circle("fill",W*0.91,hero_h*0.83,210)
    rgba(C.accent,0.17)
    love.graphics.circle("line",W*0.91,hero_h*0.83,145)
    love.graphics.circle("line",W*0.91,hero_h*0.83,161)
    label("SEU ESTÚDIO CRIATIVO",0,hero_h*0.145,W,
        "small","center",C.accent_light)
    local cx=W/2
    love.graphics.setFont(font.logo)
    local w1,w2=font.logo:getWidth("Paint "),font.logo:getWidth("Lua")
    local lx=cx-(w1+w2)/2
    local ly=hero_h*0.215
    rgba(C.white);love.graphics.print("Paint ",lx,ly)
    rgba(C.accent);love.graphics.print("Lua",lx+w1,ly)
    rgba(C.accent)
    love.graphics.circle("fill",lx+w1+w2+10,ly+13,5)
    label("INTERFACE DEMONSTRATIVA · LÖVE 11.5",0,ly+81,W,
        "tiny","center",C.soft)
    local card_w=math.min(238,(W-70)/2)
    local card_h=132
    local card_y=hero_h*0.565
    local function action_card(x,icon,title,subtitle,fn)
        local hovered=over(x,card_y,card_w,card_h)
        local round=Theme.radius.card
        soft_shadow(x,card_y,card_w,card_h,round,hovered and 1.35 or 1)
        rectangle(x,card_y,card_w,card_h,
            hovered and C.hover or C.panel_head,0.98,round)
        inset_border(x,card_y,card_w,card_h,round,0.20)
        rectangle(x+16,card_y+15,47,47,
            hovered and C.accent or C.top_button,0.99,12)
        glyph(icon,x+39.5,card_y+38,15)
        label(title,x+17,card_y+76,card_w-34,"normal","left",C.white)
        label(subtitle,x+17,card_y+100,card_w-34,"small","left",C.soft)
        glyph_color=hovered and C.accent_light or C.accent
        glyph("arrow_right",x+card_w-23,card_y+29,12)
        glyph_color=nil
        hit(x,card_y,card_w,card_h,fn,icon)
    end
    local gutter=16
    local left=cx-card_w-gutter/2
    action_card(left,"brush","A Minha Galeria","Criar e organizar telas",
        function() state:open_gallery() end)
    action_card(cx+gutter/2,"globe","Galeria Online","Visitar a comunidade",
        function() love.system.openURL("https://ibispaint.com/") end)
    label("CLASSIFICAÇÃO DIÁRIA",0,hero_h+26,W,
        "header","center",C.white)
    line(W*0.17,hero_h+61,W*0.83,hero_h+61,1,C.white,0.16)
    label("A classificação online não é carregada nesta demonstração.",
        0,hero_h+92,W,"small","center",C.soft)
    label("Paint Lua  ·  Protótipo visual independente",0,H-29,W,
        "tiny","center",C.soft)
end

-- Gallery layout inspired by a published Windows image and the official
-- artwork-folder tutorial. Exact version-14.1.4 geometry is not certified.
local function gallery_open_dialog(mode,id)
    gallery_dialog={mode=mode,id=id}
    gallery_input=mode=="rename" and gallery:get(id).name or "New Folder"
    gallery_input_replace=true
    gallery_menu=nil
end

local function gallery_header()
    rectangle(0,0,W,54,C.topbar)
    rectangle(0,52,W,2,C.accent,0.68)
    local folder=gallery:folder(gallery.current_folder)
    local title=folder.id==0 and "A Minha Galeria" or folder.name
    label(title,114,15,math.max(100,W-513),"header","left",C.white)
    if W>800 then
        label(string.format("%d obra(s)",gallery:total_artworks()),
            115,37,math.max(100,W-513),"tiny","left",C.soft)
    end
    glyph_color=C.accent
    glyph("back",18,24,12)
    glyph_color=nil
    label("Voltar",30,16,80,"normal","left",C.accent)
    hit(8,6,96,42,function()
        if not gallery:back() then
            state.screen="title"
            gallery_selecting=false
        end
        gallery_item_scroll=0
        gallery_menu=nil
        gallery:clear_selection()
        persist_gallery()
    end,"back")
    local actions={
        {"plus",function() gallery_menu=gallery_menu=="new" and nil or "new" end},
        {"settings",function() gallery_menu=gallery_menu=="cloud" and nil or "cloud" end},
        {"play",function() notice("Time-lapse indisponível sem o motor de obras.") end},
        {"down",function()
            local picked,count=nil,0
            for id,selected in pairs(gallery.selected) do
                if selected then
                    count=count+1
                    local item=gallery:get(id)
                    if item.type=='artwork' then picked=id end
                end
            end
            if count~=1 or not picked then
                notice('Selecione uma única obra para exportar PNG')
                return
            end
            local doc,err=GalleryStorage.loadArtwork(picked)
            if not doc then notice('Não foi possível abrir a obra: '..tostring(err));return end
            local path,why=PNGExport.save(doc,picked)
            if path then notice('PNG em '..love.filesystem.getSaveDirectory()..'/'..path)
            else notice('PNG: '..tostring(why)) end
        end},
        {"more",function() gallery_menu=gallery_menu=="more" and nil or "more" end}
    }
    local start=W-392
    glyph_color=C.accent
    for i,a in ipairs(actions) do
        icon_button(start+(i-1)*42,7,39,40,a[1],a[2])
    end
    glyph_color=nil
    label(gallery_selecting and "Concluído" or "Selecionar",
        W-152,17,92,"small","center",C.accent)
    hit(W-156,7,100,40,function()
        gallery_selecting=not gallery_selecting
        if not gallery_selecting then
            gallery:clear_selection();gallery_menu=nil
        end
    end,"gallery_select")
    label("Editar",W-52,17,50,"small","center",
        gallery.current_folder~=0 and C.accent or {0.5,0.5,0.5})
    hit(W-56,7,50,40,function()
        if gallery.current_folder~=0 then
            gallery_open_dialog("rename",gallery.current_folder)
        else
            notice("Selecione uma obra ou abra uma pasta para editar.")
        end
    end,"gallery_edit")
end

local function gallery_item(tile,item)
    local x,y,w,h=tile.x,tile.y,tile.w,tile.h
    local hovered=over(x,y,w,h) and not gallery_menu
    soft_shadow(x,y,w,h,Theme.radius.card,hovered and 1.2 or 0.90)
    rectangle(x,y,w,h,hovered and C.white or C.tile,1,Theme.radius.card)
    inset_border(x,y,w,h,Theme.radius.card,hovered and 0.85 or 0.58)
    rectangle(x+12,y+10,w-24,2,C.accent,hovered and 0.78 or 0.22,2)
    if item.type=="folder" then
        rectangle(x+25,y+53,w-50,h-99,C.accent_tint,1,10)
        rectangle(x+40,y+44,w*0.40,21,C.accent_light,0.92,6)
        rectangle(x+35,y+62,w-70,h-120,C.white,1,6)
        stroke(x+35,y+62,w-70,h-120,C.card_border,0.8)
        rectangle(x+49,y+76,w-98,4,C.card_border,0.6,2)
        rectangle(x+49,y+91,w-116,4,C.card_border,0.6,2)
        label("PASTA",x+19,y+22,w-38,"tiny","left",C.muted)
    else
        local avail_w,avail_h=w-52,h-68
        local ratio=item.width/item.height
        local cw,ch=math.min(avail_w,avail_h*ratio),math.min(avail_h,avail_w/ratio)
        local px,py=x+(w-cw)/2,y+27+(avail_h-ch)/2
        rectangle(px+2,py+4,cw,ch,C.deep,0.08,4)
        rectangle(px,py,cw,ch,C.white,1,4)
        local artworkImage=gallery_thumbnail(item.id)
        if artworkImage then
            local size=math.min(avail_w,avail_h)
            rgba(C.white)
            love.graphics.draw(artworkImage,x+w/2-size/2,
                y+27+avail_h/2-size/2,0,
                size/artworkImage:getWidth(),size/artworkImage:getHeight())
        else
            label('Sem prévia',px+2,py+ch/2-6,cw-4,'tiny','center',C.muted)
        end
        stroke(px,py,cw,ch,C.card_border,0.95)
        label(string.format("%d × %d",item.width,item.height),
            x+10,y+h-24,w-20,"tiny","center",C.muted)
        label("TELA",x+17,y+18,w-34,"tiny","left",C.muted)
    end
    local name=item.name
    if #name>22 then name=name:sub(1,20).."…" end
    label(name,x-8,y+h+7,w+16,"small","center",C.ink)
    if gallery.selected[item.id] then
        rectangle(x,y,w,h,C.accent,0.13,Theme.radius.card)
        stroke(x+1,y+1,w-2,h-2,C.accent,0.85)
        rectangle(x+w-34,y+9,24,24,C.accent,0.95,12)
        glyph("check",x+w-22,y+21,11)
    end
    local id=item.id
    local visible_top=math.max(y,83)
    local visible_bottom=math.min(y+h,H-58)
    if visible_bottom>visible_top then
        hit(x,visible_top,w,visible_bottom-visible_top,function()
            if gallery_selecting then
                gallery:select(id)
            elseif item.type=="folder" then
                gallery:enter(id)
                gallery_item_scroll=0
                persist_gallery()
            else
                open_gallery_artwork(item)
            end
            gallery_menu=nil
        end,item.type.."_"..id)
    end
end

local function gallery_screen()
    rectangle(0,0,W,H,C.paper)
    gallery_header()
    rectangle(0,54,W,29,{0.924,0.936,0.951})
    label("Sincronização da Nuvem",16,61,198,"small","left",C.muted)
    rectangle(220,59,38,19,{0.77,0.80,0.84},1,10)
    rgba(C.white);love.graphics.circle("fill",229,68,7.5)
    label("PAINT LUA  /  ESTÚDIO",W-196,61,184,"tiny","right",C.muted)
    hit(214,51,48,30,function() gallery_menu="cloud" end,"cloud")
    local items=gallery:items()
    if #items==0 then
        local cx=W/2
        local cy=H*0.43
        local center_w=math.min(410,W-56)
        soft_shadow(cx-center_w/2,cy-82,center_w,242,18,0.65)
        rectangle(cx-center_w/2,cy-82,center_w,242,C.white,0.97,18)
        inset_border(cx-center_w/2,cy-82,center_w,242,18,0.80)
        rectangle(cx-41,cy-56,83,92,C.accent_tint,1,10)
        rectangle(cx-24,cy-40,83,92,C.light,1,9)
        stroke(cx-24,cy-40,83,92,C.card_border,0.85)
        line(cx-7,cy-15,cx+40,cy-15,3,C.card_border)
        line(cx-7,cy-2,cx+30,cy-2,3,C.card_border)
        label(gallery.current_folder==0 and "Sua galeria está pronta"
             or "Esta pasta está vazia",cx-center_w/2+14,cy+69,
             center_w-28,"header","center",C.ink)
        label("Crie uma tela para começar seu próximo projeto.",
             cx-center_w/2+14,cy+99,center_w-28,"small","center",C.muted)
        local bw=math.min(220,center_w-45)
        plain_button(cx-bw/2,cy+123,bw,34,"+  Nova tela",function()
            gallery_menu="new"
        end,true,"gallery_empty_new")
    else
        local tile_w=200
        local gap=28
        local left=15
        local count=math.max(1,math.floor((W-left*2+gap)/(tile_w+gap)))
        local total_rows=math.ceil(#items/count)
        local maximum=math.max(0,total_rows*228-(H-58-109))
        gallery_item_scroll=math.max(0,math.min(maximum,gallery_item_scroll))
        love.graphics.setScissor(0,83*scale,W*scale,(H-141)*scale)
        for i,item in ipairs(items) do
            local row=math.floor((i-1)/count)
            local col=(i-1)%count
            local tile={
                x=left+col*(tile_w+gap),
                y=109+row*228-gallery_item_scroll,w=tile_w,h=200
            }
            if tile.y+tile.h>83 and tile.y<H-58 then
                gallery_item(tile,item)
            end
        end
        love.graphics.setScissor()
        if maximum>0 then
            local track_y=97
            local track_h=H-163
            local thumb_h=math.max(22,track_h*track_h/(track_h+maximum))
            local progress=gallery_item_scroll/maximum
            rectangle(W-13,track_y,5,track_h,{0.83,0.83,0.83})
            rectangle(W-13,track_y+progress*(track_h-thumb_h),5,
                thumb_h,{0.53,0.53,0.53})
        end
    end
    if gallery_selecting then
        rectangle(0,H-49,W,49,C.dark)
        label(tostring(#gallery:selection()).." selected",15,H-32,210,
            "small","left",C.white)
        plain_button(W-181,H-43,168,36,"Move",function()
            if #gallery:selection()>0 then gallery_menu="move"
            else notice("Select an artwork or folder first.") end
        end,true)
    end

    if gallery_menu=="new" and state.modal~="new_canvas" then
        local x=math.max(66,W-326)
        rectangle(x,49,256,130,C.dark,0.98,3)
        label("New",x+11,60,230,"small","left",C.white)
        plain_button(x+9,81,238,38,"Canvas",function()
            state:open_new_canvas();gallery_menu=nil
        end)
        hit(x+9,81,238,38,function()
            state:open_new_canvas();gallery_menu=nil
        end,"new_canvas")
        plain_button(x+9,125,238,38,"Folder (Pro)",function()
            gallery_open_dialog("create")
        end)
        hit(x+9,125,238,38,function()
            gallery_open_dialog("create")
        end,"new_folder")
    elseif gallery_menu=="move" and state.modal~="new_canvas" then
        local folders=gallery:folders()
        local n=math.min(#folders,10)
        local menu_w=292
        local x=W-menu_w-11
        local y=82
        rectangle(x,y,menu_w,45+n*34,C.dark,0.99,3)
        hit(x,y,menu_w,45+n*34,function() end,"move_surface")
        label("Move to folder",x+12,y+10,menu_w-25,"normal","left",C.white)
        for i=1,n do
            local folder=folders[i]
            local yy=y+42+(i-1)*34
            local fid=folder.id
            rectangle(x+9,yy,menu_w-18,32,
                over(x+9,yy,menu_w-18,32) and C.blue or C.bar,0.72,2)
            label(folder.name,x+19,yy+9,menu_w-40,"small","left",C.white)
            hit(x+9,yy,menu_w-18,32,function()
                local ok,result=pcall(function()
                    return gallery:move_selection(fid)
                end)
                if not ok then notice("Move not permitted: folder hierarchy.")
                else
                    gallery_menu=nil;gallery_selecting=false
                    persist_gallery()
                    notice(result.." item(s) moved.")
                end
            end,"move_to_"..fid)
        end
    elseif gallery_menu and state.modal~="new_canvas" then
        local x=W-245
        rectangle(x,49,238,138,C.dark,0.95,3)
        local text_map={
            cloud="Cloud synchronization requires an account.",
            more="My Gallery (demonstration only)"
        }
        label(text_map[gallery_menu] or "",x+10,66,218,
            "small","center",C.white)
        plain_button(x+22,124,190,33,"Close",function()
            gallery_menu=nil
        end)
    end

    if gallery_dialog then
        rectangle(0,0,W,H,C.deep,0.56)
        hit(0,0,W,H,function() end,"folder_scrim")
        local ww=math.min(W-52,408)
        local xx=(W-ww)/2
        local yy=H/2-119
        rectangle(xx,yy,ww,238,C.light,1,8)
        label(gallery_dialog.mode=="rename" and "Rename Folder" or "New Folder",
            xx+18,yy+20,ww-36,"header","center",C.ink)
        label("Folder name",xx+26,yy+74,ww-52,"small","left",C.ink)
        rectangle(xx+26,yy+97,ww-52,41,C.white,1,3)
        stroke(xx+26,yy+97,ww-52,41,C.blue)
        label(gallery_input,xx+36,yy+108,ww-72,"normal","left",C.ink)
        hit(xx+26,yy+97,ww-52,41,function()
            gallery_input_replace=true
        end,"folder_name")
        plain_button(xx+26,yy+171,(ww-63)/2,39,"Cancel",function()
            gallery_dialog=nil
        end)
        plain_button(xx+37+(ww-63)/2,yy+171,(ww-63)/2,39,"OK",function()
            local valid=gallery_input~="" and #gallery_input<=100
                and not gallery_input:match("^%s*$")
            if not valid then notice("Enter a valid folder name.");return end
            if gallery_dialog.mode=="rename" then
                gallery:rename(gallery_dialog.id,gallery_input)
            else
                gallery:add_folder(gallery_input)
            end
            gallery_dialog=nil
            persist_gallery()
        end,true)
        hit(xx+37+(ww-63)/2,yy+171,(ww-63)/2,39,function()
            local valid=gallery_input~="" and #gallery_input<=100
                and not gallery_input:match("^%s*$")
            if valid then
                if gallery_dialog.mode=="rename" then
                    gallery:rename(gallery_dialog.id,gallery_input)
                else gallery:add_folder(gallery_input) end
                gallery_dialog=nil
                gallery_item_scroll=0
                persist_gallery()
            else notice("Enter a valid folder name.") end
        end,"folder_confirm")
    end
    if state.modal=="new_canvas" then draw_new_canvas() end
end

local function finish_new_canvas(wi,he)
    state:create_canvas(wi,he)
    active_artwork_id=gallery:add_artwork(
        wi,he,"Untitled "..tostring(gallery:total_artworks()+1))
    if persistence_enabled then
        paint:sync(state)
        paint:setArtwork(active_artwork_id)
        local ok,err=paint:save()
        if not ok then notice('Obra criada, mas não salva: '..tostring(err))
        else
            forget_gallery_thumbnail(active_artwork_id)
            persist_gallery()
        end
    end
    view:reset()
    panel=nil;gallery_menu=nil;focus=nil
    gallery_selecting=false
end

-- This side-aligned full-height panel follows the WINDOWS screenshot,
-- replacing the ungrounded central modal used in prior commits.
function draw_new_canvas()
    local pw=math.min(1050,math.max(440,W*0.69))
    local px=W-pw-4
    rectangle(px-3,47,pw+7,H-48,C.deep,0.98,2)
    rectangle(px,50,pw,H-54,C.light)
    rectangle(px,50,pw,28,C.dark)
    label("New Canvas",px,55,pw,"small","center",C.white)
    -- Bloqueio da tela sob o painel: o cabeçalho da galeria não recebe cliques.
    hit(0,0,W,H,function() end,"canvas_panel_capture")
    hit(0,48,px-3,H-48,function()
        state:cancel_new_canvas();focus=nil
    end,"outside_canvas_panel")
    -- Content area is clipped, independently scrolled by the mouse wheel.
    local top=80
    love.graphics.setScissor(px*scale,top*scale,pw*scale,(H-top-42)*scale)
    local yy=top-gallery_scroll
    local function row(n,y,extra,fn)
        local ry=y
        rectangle(px+2,ry,pw-5,extra or 29,{0.88,0.88,0.88})
        line(px+2,ry+extra-1,px+pw-3,ry+extra-1,1,{0.73,0.73,0.73})
        label(n,px+31,ry+6,pw-170,"small","left",C.ink)
        if fn and ry>=top and ry < H-70 then
            hit(px+2,ry,pw-5,extra or 29,fn,"preset")
        end
    end
    row("Import Picture",yy,35,function()
        notice("Importar imagem exige o motor de obras, excluído nesta fase.")
    end)
    label("W",px+15,yy+43,18,"small","left",C.ink)
    label("H",px+15,yy+70,18,"small","left",C.ink)
    for i,f in ipairs({{key="width",value=current_width},{key="height",value=current_height}}) do
        local y=yy+42+(i-1)*28
        local key=f.key
        local function update_dimension(value)
            local n=math.max(1,math.min(16384,math.floor(value+0.5)))
            if key=="width" then current_width=tostring(n)
            else current_height=tostring(n) end
            preset_selected=0
            active_dpi=nil
            focus=nil
            input_replace=true
        end
        rectangle(px+39,y,pw*0.25,24,C.white)
        stroke(px+39,y,pw*0.25,24,focus==key and C.blue or C.soft)
        label(f.value,px+43,y+3,pw*0.25-8,"small","center",C.ink)
        hit(px+39,y,pw*0.25,24,function() focus=key;input_replace=true end,"input_"..key)
        local sx=px+pw*0.35
        local track_w=pw*0.51
        line(sx,y+12,sx+track_w,y+12,4,{0.68,0.68,0.68})
        local value=tonumber(f.value) or 1
        local fill=math.max(0,math.min(1,(value-1)/8191))
        rectangle(sx,y+10,track_w*fill,4,C.blue)
        rgba(C.white)
        love.graphics.circle("fill",sx+track_w*fill,y+12,7)
        rgba(C.deep)
        love.graphics.circle("fill",sx-15,y+12,10)
        love.graphics.circle("fill",sx+track_w+15,y+12,10)
        line(sx-19,y+12,sx-11,y+12,1.7,C.white)
        line(sx+track_w+11,y+12,sx+track_w+19,y+12,1.7,C.white)
        line(sx+track_w+15,y+8,sx+track_w+15,y+16,1.7,C.white)
        hit(sx-26,y,21,24,function() update_dimension(value-1) end,"decrease_"..key)
        hit(sx,y,track_w,24,function()
            local mx=pointer()
            update_dimension(1+math.max(0,math.min(1,(mx-sx)/track_w))*8191)
            drag_dimension={key=key,sx=sx,width=track_w}
        end,"slider_"..key)
        hit(sx+track_w+5,y,23,24,function() update_dimension(value+1) end,"increase_"..key)
    end
    label("Speed ↔ Quality",px,yy+108,pw,"small","center",{0.30,0.30,0.30})
    yy=yy+128
    local row_h=math.min(39,math.max(25,(H-250)/#presets))
    for i,p in ipairs(presets) do
        local row_y=yy+(i-1)*row_h
        if row_y+row_h>=top and row_y<=H-42 then
            local selected=preset_selected==i
            rectangle(px+4,row_y,pw-8,row_h-1,
                selected and {0.77,0.83,0.87} or C.light)
            local ar=p.width/p.height
            local thumb_w=math.min(24,math.max(4,19*ar))
            local thumb_h=math.min(22,math.max(4,19/ar))
            stroke(px+8+(24-thumb_w)/2,
                row_y+(row_h-thumb_h)/2,thumb_w,thumb_h,{0.43,0.43,0.43})
            label(p.name,px+39,row_y+(row_h-16)/2,pw-(p.dpi and 245 or 165),
                "small","left",C.ink)
            local shown_w,shown_h=CanvasPresets.pixels(
                p,preset_selected==i and active_dpi or nil)
            label(tostring(shown_w).." x "..tostring(shown_h),
                px+pw-123,row_y+(row_h-16)/2,109,"small","right",C.ink)
            line(px+4,row_y+row_h-1,px+pw-4,row_y+row_h-1,
                1,{0.72,0.72,0.72})
            hit(px+4,row_y,pw-8,row_h,function()
                preset_selected=i
                active_dpi=p.dpi
                local wi,he=CanvasPresets.pixels(p,active_dpi)
                current_width=tostring(wi)
                current_height=tostring(he)
                focus=nil;input_replace=true
            end,"preset_"..i)
            if p.dpi then
                local dpi=preset_selected==i and active_dpi or p.dpi
                local dpi_x=px+pw-210
                rectangle(dpi_x,row_y+4,81,row_h-9,C.white,0.96,2)
                stroke(dpi_x,row_y+4,81,row_h-9,C.soft)
                label(tostring(dpi).." dpi",dpi_x+3,
                    row_y+(row_h-15)/2,75,"tiny","center",C.ink)
                hit(dpi_x,row_y+4,81,row_h-9,function()
                    if preset_selected~=i then
                        preset_selected=i
                        active_dpi=p.dpi
                    end
                    active_dpi=CanvasPresets.next_dpi(p,active_dpi)
                    local wi,he=CanvasPresets.pixels(p,active_dpi)
                    current_width=tostring(wi)
                    current_height=tostring(he)
                    focus=nil;input_replace=true
                end,"dpi_"..p.id)
            end
        end
    end
    love.graphics.setScissor()
    rectangle(px,H-42,pw,38,C.dark)
    label(current_width.." x "..current_height.." px",
        px+12,H-32,pw-154,"small","left",C.white)
    plain_button(px+pw-136,H-38,127,30,"OK",function()
        local ww,hh=tonumber(current_width),tonumber(current_height)
        if not ww or not hh or ww<1 or hh<1 or ww>16384 or hh>16384
        or ww~=math.floor(ww) or hh~=math.floor(hh) then
            notice("Informe dimensões inteiras de 1 a 16384 pixels.")
            return
        end
        finish_new_canvas(ww,hh)
    end,true)
end

local function draw_editor_toolbar()
    -- Compact central dock, with exactly eight stable hitbox identifiers.
    local layout=EditorLayout.compute(W,H,preferences.tool_position,#tools)
    local dock=layout.dock
    rectangle(0,H-66,W,66,C.topbar)
    rectangle(0,H-66,W,1,C.card_border,0.22)
    soft_shadow(dock.x,dock.y+4,dock.w,54,15,0.45)
    rectangle(dock.x,dock.y+4,dock.w,54,C.rail,1,14)
    inset_border(dock.x,dock.y+4,dock.w,54,14,0.17)
    local entries={
        {"transform",function() set_panel("tools") end},
        {"settings",function() set_panel("brush") end},
        {"color",function() set_panel("color") end},
        {"merge_down",function()
            notice("Mesclar para baixo ainda não é simulado.")
        end},
        {"undo",function()
            paint:historyStep(state,false)
            if preferences.show_undo_message then notice(paint.status) end
        end},
        {"redo",function()
            paint:historyStep(state,true)
            if preferences.show_undo_message then notice(paint.status) end
        end},
        {"layer",function() set_panel("layer") end},
        {"back",function() set_panel("back") end}
    }
    for i,e in ipairs(entries) do
        local key=e[1]
        local x=dock.button_x+(i-1)*dock.button_pitch
        local y=dock.button_y
        local cx=x+dock.button_size/2
        local cy=y+dock.button_size/2
        local active=(key=="transform" and panel=="tools")
            or (key=="layer" and panel=="layer")
            or (key=="settings" and panel=="brush")
            or (key=="color" and panel=="color")
            or (key=="back" and panel=="back")
        local hovered=over(x,y,dock.button_size,dock.button_size)
        if active then
            rectangle(x+1,y+1,46,46,C.accent,0.18,10)
            rectangle(x+8,y+44,32,2,C.accent,0.94,1)
        elseif hovered then
            rectangle(x+1,y+1,46,46,C.white,0.095,10)
        end
        if key=="settings" then
            glyph_color=active and C.accent_light or C.white
            glyph("brush",cx,cy-6,12)
            glyph_color=nil
            label(string.format("%g",state.brush_size),x+2,y+31,44,
                "tiny","center",C.soft)
        elseif key=="color" then
            local c=state.color or {0,0,0}
            local factor=(c[1] or 0)>1 and 255 or 1
            rectangle(cx-13,cy-13,26,26,
                {(c[1] or 0)/factor,(c[2] or 0)/factor,
                (c[3] or 0)/factor},1,6)
            stroke(cx-13,cy-13,26,26,C.white,0.82)
        else
            glyph_color=active and C.accent_light or C.white
            glyph(key,cx,cy,14)
            glyph_color=nil
        end
        if key=="layer" then
            local count=#(state.layers or {})
            rectangle(cx+8,cy-19,18,15,C.accent,0.99,5)
            label(tostring(count),cx+8,cy-17,18,"tiny","center",C.deep)
        end
        hit(x,y,dock.button_size,dock.button_size,e[2],key)
        if i==3 or i==6 then
            line(x+54,y+11,x+54,y+38,1,C.card_border,0.18)
        end
    end
    if dock.x>205 then
        local selected_name="Ferramenta"
        for _,tool in ipairs(tools) do
            if tool[2]==state.active_tool then selected_name=tool[1];break end
        end
        rectangle(26,H-36,6,6,C.accent,1,3)
        label(selected_name,40,H-43,math.max(110,dock.x-59),
            "small","left",C.soft)
    end
    if W-dock.x-dock.w>110 then
        label("SIMULAÇÃO",dock.x+dock.w+13,H-41,
            math.max(65,W-dock.x-dock.w-20),"tiny","center",C.soft)
    end
end

local function draw_size_controls()
    -- Compact floating controls no longer stretch across the canvas.
    local layout=EditorLayout.compute(W,H,preferences.tool_position,#tools)
    local l=layout.sliders
    local function small_button(cx,cy,plus,fn)
        local x,y=cx-11,cy-11
        rectangle(x,y,22,22,
            over(x,y,22,22) and C.hover or C.top_button,0.96,6)
        glyph(plus and "plus" or "minus",cx,cy,7)
        if fn then hit(x,y,22,22,fn) end
    end
    local function track(x,fraction,on_value,key)
        local y=l.y+21
        local tw=129
        local fr=math.max(0,math.min(1,fraction))
        rectangle(x,y-2,tw,4,C.soft,0.33,2)
        rectangle(x,y-2,tw*fr,4,C.accent,0.95,2)
        rgba(C.white)
        love.graphics.circle("fill",x+tw*fr,y,6.5)
        rgba(C.deep,0.32)
        love.graphics.setLineWidth(1)
        love.graphics.circle("line",x+tw*fr,y,6.5)
        hit(x,y-12,tw,24,function()
            local mx=pointer()
            on_value(math.max(0,math.min(1,(mx-x)/tw)))
        end,key)
    end
    local function panel_box(x,icon_name,value,minus,plus,fraction,on_value,key)
        soft_shadow(x,l.y,l.w,l.h,12,0.48)
        rectangle(x,l.y,l.w,l.h,C.panel_head,0.98,12)
        inset_border(x,l.y,l.w,l.h,12,0.25)
        glyph_color=C.accent_light
        glyph(icon_name,x+21,l.y+22,11)
        glyph_color=nil
        label(value,x+40,l.y+14,57,"small","left",C.white)
        small_button(x+108,l.y+22,false,minus)
        track(x+132,fraction,on_value,key)
        small_button(x+282,l.y+22,true,plus)
    end
    panel_box(l.left_x,"brush",string.format("%g px",state.brush_size),
        function()
            state:set_brush_size(math.max(0.1,state.brush_size-0.5))
        end,
        function()
            state:set_brush_size(math.min(100,state.brush_size+0.5))
        end,
        math.min(state.brush_size/100,1),function(fr)
            state:set_brush_size(math.max(0.1,math.floor(fr*1000+0.5)/10))
        end,"brush_slider")
    panel_box(l.right_x,"blur",tostring(opacity).."%",
        function() opacity=math.max(0,opacity-5) end,
        function() opacity=math.min(100,opacity+5) end,
        opacity/100,function(fr)
            opacity=math.floor(fr*100+0.5)
        end,"opacity_slider")
end

local function draw_view_guides(dw,dh,canvas_scale)
    if visual.grid then
        local function grid_pass(interval,shade,alpha)
            -- Evitar milhares de linhas invisíveis em zooms muito baixos.
            if interval*canvas_scale<6 then return end
            rgba(shade,alpha)
            love.graphics.setLineWidth(math.max(0.2,0.85/canvas_scale))
            local begin_x=visual.offset_x%interval
            local begin_y=visual.offset_y%interval
            local x=begin_x
            while x<dw do
                love.graphics.line(x-dw/2,-dh/2,x-dw/2,dh/2)
                x=x+interval
            end
            local y=begin_y
            while y<dh do
                love.graphics.line(-dw/2,y-dh/2,dw/2,y-dh/2)
                y=y+interval
            end
        end
        grid_pass(visual.grid2,visual:grid_color("grid2"),0.22)
        grid_pass(visual.grid1,visual:grid_color("grid1"),0.48)
    end
    if visual.manga then
        rgba({0.94,0.25,0.29},0.55)
        love.graphics.setLineWidth(math.max(0.2,1.2/canvas_scale))
        love.graphics.rectangle("line",-dw*0.47,-dh*0.47,dw*0.94,dh*0.94)
        love.graphics.rectangle("line",-dw*0.40,-dh*0.40,dw*0.80,dh*0.80)
    end
end
local function draw_reference_window()
    local pw=210
    local x,y=W-pw-14,53
    local h=178
    rectangle(x,y,pw,h,C.deep,0.94,3)
    rectangle(x,y,pw,30,C.bar,0.98,3)
    label("Reference Window",x+7,y+8,pw-48,"small","left",C.white)
    icon_button(x+pw-31,y+2,27,26,"check",function()
        visual:toggle_reference()
    end)
    rectangle(x+13,y+40,pw-26,111,C.light,0.97)
    local dw,dh=state.document.width,state.document.height
    local factor=math.min((pw-54)/dw,93/dh)
    rectangle(x+pw/2-dw*factor/2,y+49+(93-dh*factor)/2,
        dw*factor,dh*factor,C.white)
    label("Prévia simplificada do canvas",x+5,y+156,pw-10,"tiny","center",C.white)
end

local function editor_screen()
    rectangle(0,0,W,H,C.background)
    -- Low-contrast workspace guides keep the canvas in focus.
    for gx=0,W,72 do
        line(gx,35,gx,H-67,1,C.workspace_grid,0.045)
    end
    for gy=35,H-67,72 do
        line(0,gy,W,gy,1,C.workspace_grid,0.045)
    end
    rectangle(0,0,W,35,C.topbar,1)
    rectangle(0,34,W,1,C.card_border,0.18)
    local header_left=preferences.tool_position=="left" and 73 or 20
    label("PAINT LUA",header_left,10,107,"small","left",C.white)
    local maskMode=paint:maskEditMode(state)
    if maskMode then
        label(maskMode=='layer' and 'PINTANDO MÁSCARA DA CAMADA'
            or 'PINTANDO MÁSCARA DO GRUPO',header_left+445,10,
            math.max(110,W-header_left-540),'tiny','left',C.accent_light)
    end
    rectangle(header_left+101,12,1,13,C.card_border,0.3)
    label(string.format("Documento  ·  %d × %d px",
        state.document.width,state.document.height),
        header_left+117,10,300,"small","left",C.soft)
    local space_left=preferences.tool_position=="left" and 62 or 0
    local space_right=preferences.tool_position=="right" and 75 or 34
    local aw=W-space_left-space_right
    local ah=H-160
    local dw,dh=state.document.width,state.document.height
    local canvas_scale=math.min(aw/dw,ah/dh,1.1)
    local cx=space_left+aw/2
    local cy=62+ah/2
    local actual_scale=canvas_scale*view.zoom
    love.graphics.push()
    love.graphics.translate(cx+view.pan_x,cy+view.pan_y)
    love.graphics.rotate(view.rotation)
    love.graphics.scale(actual_scale)
    local shadow=5/actual_scale
    rectangle(-dw/2-shadow*2,-dh/2-shadow*2,
        dw+shadow*4,dh+shadow*4,C.deep,0.042)
    rectangle(-dw/2-shadow,-dh/2-shadow,
        dw+shadow*2,dh+shadow*2,C.deep,0.13)
    if state.background_mode=="white" then
        rectangle(-dw/2,-dh/2,dw,dh,C.white)
    else
        local count=14
        local rows=math.max(2,math.floor(count*dh/dw+0.5))
        local tw,th=dw/count,dh/rows
        for i=0,count-1 do for j=0,rows-1 do
            local dark=state.background_mode=="transparent_dark"
            local level=(i+j)%2==0 and (dark and 0.25 or 0.78)
                or (dark and 0.38 or 0.94)
            rectangle(-dw/2+i*tw,-dh/2+j*th,tw+0.1,th+0.1,
                {level,level,level})
        end end
    end
    -- Pixeis reais do motor, dentro da mesma transformacao do canvas da UI.
    paint:sync(state)
    paint:draw(-dw/2,-dh/2)
    draw_view_guides(dw,dh,actual_scale)
    paint:drawSelection(-dw/2,-dh/2,actual_scale)
    rgba(C.deep,0.22)
    love.graphics.setLineWidth(1/math.max(0.05,actual_scale))
    love.graphics.rectangle("line",-dw/2,-dh/2,dw,dh)
    love.graphics.pop()
    -- Compact top-right action cluster instead of oversized round buttons.
    local ui=EditorLayout.compute(W,H,preferences.tool_position,#tools)
    local quick=ui.top
    soft_shadow(quick.x,quick.y,quick.w,quick.h,13,0.35)
    rectangle(quick.x,quick.y,quick.w,quick.h,C.panel_head,0.96,12)
    inset_border(quick.x,quick.y,quick.w,quick.h,12,0.17)
    local tops={"view","selection","stabilizer","shape","ruler","material"}
    local quick_names={
        view="Visualização",selection="Seleção",stabilizer="Estabilizador",
        shape="Formas",ruler="Régua",material="Materiais"
    }
    local hovered_tooltip=nil
    for i,name in ipairs(tops) do
        local x=quick.button_x+(i-1)*(quick.button_w+quick.button_gap)
        local y=quick.y+4
        local selected=panel==name
        if selected then
            rectangle(x,y,quick.button_w,36,C.accent,0.26,9)
        elseif over(x,y,quick.button_w,36) then
            rectangle(x,y,quick.button_w,36,C.white,0.12,9)
        end
        glyph_color=selected and C.accent_light or C.white
        glyph(name,x+quick.button_w/2,y+18,11.5)
        glyph_color=nil
        hit(x,y,quick.button_w,36,function() set_panel(name) end,name)
        if over(x,y,quick.button_w,36) then
            hovered_tooltip={text=quick_names[name],x=x,y=quick.y+49,
                left=false}
        end
    end
    -- Icon-only rail, with tool names in hover hints when enabled.
    local rail=ui.rail
    if rail.x then
        soft_shadow(rail.x,rail.y,rail.w,rail.h,10,0.35)
        rectangle(rail.x,rail.y,rail.w,rail.h,C.rail,1,10)
        line(rail.x+(rail.x==0 and 58 or 0),rail.y+12,
             rail.x+(rail.x==0 and 58 or 0),rail.y+rail.h-10,
             1,C.card_border,0.13)
        for i,entry in ipairs(tools) do
            local y=rail.button_y+(i-1)*rail.each
            local h=rail.each
            local selected=state.active_tool==entry[2]
            local hovered=over(rail.x+2,y,rail.w-4,h)
            if selected then
                rectangle(rail.x+6,y+1,rail.w-12,h-2,C.accent,0.20,9)
                rectangle(rail.x+3,y+h*0.23,3,h*0.54,
                    C.accent,0.98,2)
            elseif hovered then
                rectangle(rail.x+6,y+1,rail.w-12,h-2,C.white,0.10,9)
            end
            glyph_color=selected and C.accent_light or C.white
            glyph(entry[2],rail.x+rail.w/2,y+h/2,12)
            glyph_color=nil
            local key=entry[2]
            hit(rail.x+2,y,rail.w-4,h,function()
                if paint.transform and key~='transform' then
                    notice('Confirme ou cancele a transformação antes de mudar de ferramenta')
                    return
                end
                state:set_tool(key)
                if key=='transform' then
                    paint:startTransform(state)
                    notice(paint.status)
                end
                if key=="brush" or key=="eraser" then set_panel("brush")
                elseif key=="text" then set_panel("text")
                else panel=nil;state.active_panel=nil end
            end,key)
            if hovered and preferences.show_tool_labels then
                hovered_tooltip={text=entry[1],x=rail.x,y=y+h/2,
                    left=rail.x>W/2}
            end
            if i==4 or i==10 then
                line(rail.x+16,y+h-1,rail.x+rail.w-16,y+h-1,
                    1,C.card_border,0.20)
            end
        end
    end
    if visual.reference then draw_reference_window() end
    -- Controles flutuantes da prévia. O original permanece intacto até Aplicar.
    if paint.transform then
        local bw=85
        local gap=5
        local ox=math.max(72,(W-(bw+gap)*6)/2)
        local oy=H-158
        rectangle(ox-7,oy-7,(bw+gap)*6+9,43,C.deep,0.96,6)
        local buttons={
            {'-15°',function() paint:adjustTransform(0,0,1,-math.pi/12) end},
            {'+15°',function() paint:adjustTransform(0,0,1,math.pi/12) end},
            {'- Zoom',function() paint:adjustTransform(0,0,1/1.1) end},
            {'+ Zoom',function() paint:adjustTransform(0,0,1.1) end},
            {'Cancelar',function() paint:cancelTransform() end},
            {'Aplicar',function() paint:applyTransform(state) end},
        }
        for i,item in ipairs(buttons) do
            local bx=ox+(i-1)*(bw+gap)
            rectangle(bx,oy,bw,30,i==6 and C.blue or C.panel_head,0.95,4)
            label(item[1],bx+1,oy+8,bw-2,'small','center',C.white)
            hit(bx,oy,bw,30,function() item[2]();notice(paint.status) end,
                'transform_action_'..i)
        end
    end
    draw_size_controls()
    draw_editor_toolbar()
    if panel then
        draw_editor_panel()
    elseif hovered_tooltip then
        local t=hovered_tooltip
        local tw=math.min(205,math.max(105,
            font.small:getWidth(t.text)+28))
        local tx=t.left and (t.x-tw-10) or
            (t.x+(t.x<70 and 69 or 0))
        tx=math.max(8,math.min(W-tw-8,tx))
        local ty=t.y
        if t.x<70 or t.left then ty=ty-15 end
        ty=math.max(37,math.min(H-110,ty))
        soft_shadow(tx,ty,tw,30,8,0.45)
        rectangle(tx,ty,tw,30,C.panel_head,0.99,8)
        inset_border(tx,ty,tw,30,8,0.28)
        label(t.text,tx+12,ty+7,tw-24,"small","left",C.white)
    end
end

-- Procedural vector strokes, for brush-library thumbnails only.
-- They do not write to the canvas or create artwork pixels.
local function draw_brush_sample(x,y,width,amplitude,kind,large)
    local graphics=love.graphics
    -- Sample points overlap at display scale; discrete dots previously
    -- produced a visually incorrect dotted "pen" in the Windows list.
    local steps=math.max(60,math.floor(width*(large and 1.20 or 1.05)))
    local base=large and 6 or 2.4
    for step=0,steps do
        local t=step/steps
        local px=x+width*t
        local py=y-amplitude*0.35*math.sin(t*math.pi*1.8)
            +amplitude*0.10*math.sin(t*math.pi*4)
        local taper=math.max(0.12,math.sin(t*math.pi)^0.7)
        local radius=base*taper
        if kind=="air" or kind=="watercolor" then
            for ring=3,1,-1 do
                graphics.setColor(0.1,0.1,0.1,
                    kind=="watercolor" and 0.075 or 0.047)
                graphics.circle("fill",px,py,radius*(ring+1.3))
            end
        elseif kind=="pencil" then
            graphics.setColor(0.12,0.12,0.12,0.30)
            graphics.circle("fill",px,py,radius*0.9)
        elseif kind=="bleed" then
            graphics.setColor(0.08,0.08,0.08,0.45)
            graphics.circle("fill",px,py,radius*1.6)
        elseif kind=="fade" then
            graphics.setColor(0.05,0.05,0.05,0.65*(1-t))
            graphics.circle("fill",px,py,radius*2)
        else
            graphics.setColor(0.06,0.06,0.06,0.94)
            graphics.circle("fill",px,py,
                kind=="marker" and radius*1.5 or radius)
        end
    end
end

local function draw_panel_box(x,y,w,h,title)
    rectangle(x-1,y-1,w+2,h+2,C.deep,0.80,3)
    rectangle(x,y,w,h,{0.31,0.31,0.31},0.89,3)
    rectangle(x,y,w,36,{0.38,0.38,0.38},0.96)
    label(title,x+9,y+8,w-53,"small","left",C.white)
    hit(x,y,w,h,function() end,"panel_surface")
    icon_button(x+w-37,y+2,35,32,"check",function()
        panel=nil;state.active_panel=nil
    end)
end
function draw_editor_panel()
    local name=panel
    local x,y,w,h
    if name=="tools" then
        w,h=preferences:panel_size(W,H)
        if preferences.tool_position=="popup" then
            x=(W-w)/2
        elseif preferences.tool_position=="right" then
            x=W-w-66
        else
            x=65
        end
        y=math.max(7,math.min(58,H-h-80))
    elseif name=="settings" then
        w=math.min(438,W-90)
        h=math.min(476,H-145)
        x=W-w-22
        y=55
    elseif name=="brush" then
        -- Store Windows screenshot: light preset list, charcoal parameter side.
        x=math.min(185,math.max(66,W*0.16))
        y=55
        w=math.min(565,W-x-34)
        h=math.min(H-107,660)
    elseif name=="color" then
        w=math.min(color_size and color_size.w or 520,W-96)
        h=math.min(color_size and color_size.h or 635,H-119)
        w=math.max(370,w)
        h=math.max(490,h)
        x=color_float and (color_position and color_position.x or
            math.min(310,W-w-22)) or 65
        y=color_float and (color_position and color_position.y or 60) or 55
        x=math.max(4,math.min(W-w-3,x))
        y=math.max(2,math.min(H-h-54,y))
    elseif name=="tools" then
        x=65;y=92;w=math.min(505,W-140);h=math.min(570,H-185)
    elseif name=="view" then
        w=math.min(350,W-90);h=342
        x=W-w-20;y=50
    elseif name=="grid_settings" then
        w=math.min(370,W-90);h=440
        x=W-w-20;y=50
    elseif name=="layer_advanced" then
        w=math.min(460,W-90);h=math.min(410,H-110)
        x=W-w-22;y=math.max(48,math.min(65,H-h-55))
    elseif name=="layer" then
        w=math.max(310,math.min(layer_size and layer_size.w or 408,W-110))
        h=math.max(360,math.min(layer_size and layer_size.h or 468,H-125))
        x=layer_position and layer_position.x or W-w-18
        y=layer_position and layer_position.y or H-h-91
        x=math.max(63,math.min(W-w-5,x))
        y=math.max(3,math.min(H-h-54,y))
    else
        w=math.min(320,W-90);h=math.min(330,H-160)
        x=W-w-22;y=58
    end
    local titles={brush="Brush",tools="Tool Select",color="Color",layer="Layer",
        layer_advanced="Grupos e máscaras",
        back="Back",view="View Menu",grid_settings="Grid Settings",
        settings="Settings",selection="Selection Area",
        stabilizer="Stabilizer",shape="Shape",ruler="Ruler",material="Material",
        text="Text"}
    draw_panel_box(x,y,w,h,titles[name] or name)
    if name=="selection" then
        local options={
            {"Retângulo", "selection_rect"},
            {"Laço livre", "lasso"},
            {"Varinha mágica", "magic_wand"},
        }
        for i,item in ipairs(options) do
            local yy=y+48+(i-1)*45
            local selected=state.active_tool==item[2]
            rectangle(x+15,yy,w-30,36,
                selected and C.accent or C.panel_head,selected and 0.80 or 0.9,7)
            label(item[1],x+28,yy+9,w-56,"small","left",C.white)
            local tool=item[2]
            hit(x+15,yy,w-30,36,function()
                state:set_tool(tool)
                panel=nil;state.active_panel=nil
                notice(item[1]..": arraste sobre a tela")
            end,"selection_tool_"..tool)
        end
        local function action(yy,text,fn,key)
            rectangle(x+15,yy,w-30,36,C.deep,0.84,7)
            label(text,x+28,yy+9,w-56,"small","left",C.white)
            hit(x+15,yy,w-30,36,function()
                fn()
                notice(paint.status)
                panel=nil;state.active_panel=nil
            end,key)
        end
        action(y+197,"Selecionar tudo",function() paint:selectAll(state) end,
            "selection_all")
        action(y+240,"Desmarcar",function() paint:clearSelection() end,
            "selection_clear")
        label("Ctrl+A: tudo   Ctrl+D: desmarcar",x+12,y+292,w-24,
            "tiny","center",C.soft)
    elseif name=="view" then
        local bx=x+12
        local function option(yy,title,enabled,action,key)
            rectangle(bx,yy,w-24,34,C.white,over(bx,yy,w-24,34) and 0.13 or 0.04,2)
            label(title,bx+10,yy+9,w-95,"small","left",C.white)
            local xx=bx+w-79
            rectangle(xx,yy+6,42,23,
                enabled and C.blue or {0.60,0.60,0.60},1,11)
            rgba(C.white)
            love.graphics.circle("fill",enabled and xx+31 or xx+11,yy+17,9)
            hit(bx,yy,w-24,34,action,key)
        end
        option(y+47,"Reference Window",visual.reference,
            function() visual:toggle_reference() end,"view_reference")
        option(y+85,"Grid",visual.grid,
            function() visual:toggle_grid() end,"view_grid")
        option(y+165,"Manga Manuscript",visual.manga,
            function() visual:toggle_manga() end,"view_manga")
        local function section_row(yy,text,callback,key)
            rectangle(bx+12,yy,w-49,32,C.deep,over(bx+12,yy,w-49,32) and 0.94 or 0.75,16)
            label(text,bx+18,yy+9,w-61,"small","center",C.white)
            hit(bx+12,yy,w-49,32,callback,key)
        end
        section_row(y+123,"Grid Settings",function() set_panel("grid_settings") end,
            "view_grid_settings")
        section_row(y+203,"Manga Manuscript Settings",function()
            notice("Geometria das opções de manuscrito ainda não verificada no Windows.")
        end,"view_manga_settings")
        label("Display when zooming",bx+9,y+245,w-44,"small","left",C.white)
        local bw=(w-48)/2
        local xx=bx+12
        rectangle(xx,y+267,bw,35,
            visual.interpolation=="smooth" and C.blue or C.deep,0.84,2)
        rectangle(xx+bw,y+267,bw,35,
            visual.interpolation=="pixelated" and C.blue or C.deep,0.84,2)
        label("Smooth",xx,y+277,bw,"small","center",C.white)
        label("Pixelated",xx+bw,y+277,bw,"small","center",C.white)
        hit(xx,y+267,bw,35,function()
            visual:set_interpolation("smooth")
        end,"view_smooth")
        hit(xx+bw,y+267,bw,35,function()
            visual:set_interpolation("pixelated")
        end,"view_pixelated")
    elseif name=="grid_settings" then
        local bx=x+13
        local function interval_row(yy,title,value,key,step)
            label(title,bx,yy,w-26,"small","left",C.white)
            local by=yy+19
            rectangle(bx,by,w-26,37,C.white,0.09,2)
            label(tostring(value).." px",bx+57,by+11,w-150,"small","center",C.white)
            local dec=function()
                visual:set_interval(key,math.max(1,visual[key]-step))
            end
            local inc=function()
                visual:set_interval(key,math.min(8192,visual[key]+step))
            end
            plain_button(bx+3,by+3,35,31,"-",dec)
            plain_button(x+w-59,by+3,35,31,"+",inc)
            hit(x+w-59,by+3,35,31,inc,"increase_"..key)
        end
        interval_row(y+76,"Grid 1 Interval",visual.grid1,"grid1",8)
        interval_row(y+145,"Grid 2 Interval",visual.grid2,"grid2",8)
        local function color_row(yy,title,key)
            label(title,bx,yy+8,w-115,"small","left",C.white)
            local xx=x+w-75
            rectangle(xx,yy+3,53,27,visual:grid_color(key),1,2)
            stroke(xx,yy+3,53,27,C.white,0.5)
            hit(xx-2,yy,58,34,function()
                visual:cycle_grid_color(key)
            end,"grid_color_"..key)
        end
        color_row(y+214,"Grid 1 Color","grid1")
        color_row(y+248,"Grid 2 Color","grid2")
        label("Position X",bx,y+288,(w-24)/2,"small","left",C.white)
        label("Position Y",bx+(w-24)/2,y+288,(w-24)/2,"small","left",C.white)
        local bw=(w-42)/4
        plain_button(bx,y+310,bw,28,"-",function()
            visual:set_origin(visual.offset_x-8,visual.offset_y)
        end)
        plain_button(bx+bw,y+310,bw,28,
            tostring(visual.offset_x),function()
                visual:set_origin(0,visual.offset_y)
            end)
        plain_button(bx+2*bw+9,y+310,bw,28,"-",function()
            visual:set_origin(visual.offset_x,visual.offset_y-8)
        end)
        plain_button(bx+3*bw+9,y+310,bw,28,
            tostring(visual.offset_y),function()
                visual:set_origin(visual.offset_x,0)
            end)
        local toggle_x=x+w-90
        label("Show Grid",bx,y+49,w-110,"small","left",C.white)
        rectangle(toggle_x,y+46,60,23,
            visual.grid and C.blue or {0.5,0.5,0.5},1,11)
        rgba(C.white)
        love.graphics.circle("fill",
            visual.grid and toggle_x+46 or toggle_x+12,y+57,9)
        hit(toggle_x,y+43,62,29,function() visual:toggle_grid() end,
            "settings_grid_toggle")
        plain_button(bx,y+367,w-26,33,
            "Reset Grid",function() visual:reset_grid() end)
    elseif name=="layer_advanced" then
        paint:sync(state)
        local group=paint:activeGroup(state)
        local active=state:active_layer()
        local layer=paint.doc.layers[paint.doc.sel]
        local mode=paint:maskEditMode(state)
        label('Camada: '..active.name,x+13,y+45,w-75,'small','left',C.white)
        local advancedThumbKind=layer_advanced_tab=='group_mask' and 'group_mask'
            or layer_advanced_tab=='layer_mask' and 'mask' or 'layer'
        local advancedThumb=paint:thumbnail(state,active.id,advancedThumbKind,36,36)
        if advancedThumb then
            rectangle(x+w-51,y+43,36,36,C.white,0.45,2)
            rgba(C.white)
            love.graphics.draw(advancedThumb,x+w-51,y+43)
        end
        label('Grupo: '..(group and (group.name..'  ('..group.opacity..'%)') or 'nenhum'),
            x+13,y+65,w-26,'small','left',C.soft)
        local margin,gap=13,7
        local full=w-margin*2
        local half=(full-gap)/2
        local third=(full-gap*2)/3
        local function action(xx,yy,ww,txt,enabled,fn,key)
            rectangle(xx,yy,ww,32,enabled and C.blue or C.panel_head,0.94,5)
            label(txt,xx+3,yy+8,ww-6,'small','center',C.white)
            hit(xx,yy,ww,32,function()
                local ok,err=pcall(fn)
                notice(ok and paint.status or ('Erro: '..tostring(err)))
            end,key)
        end
        local tabs={{'Grupos','group'},{'Máscara camada','layer_mask'},
            {'Máscara grupo','group_mask'}}
        for i,entry in ipairs(tabs) do
            local xx=x+margin+(i-1)*(third+gap)
            rectangle(xx,y+95,third,33,
                layer_advanced_tab==entry[2] and C.blue or C.deep,0.9,5)
            label(entry[1],xx+2,y+105,third-4,'tiny','center',C.white)
            local tab=entry[2]
            hit(xx,y+95,third,33,function() layer_advanced_tab=tab end,
                'advanced_tab_'..tab)
        end
        local function pair(row,a,b)
            local yy=y+146+(row-1)*48
            action(x+margin,yy,half,a[1],a[2],a[3],a[4])
            action(x+margin+half+gap,yy,half,b[1],b[2],b[3],b[4])
        end
        if layer_advanced_tab=='group' then
            pair(1,{'Grupo 1 camada',false,function()
                paint:createGroup(state,false) end,'group_single'},
                {'Grupo 2 camadas',false,function()
                paint:createGroup(state,true) end,'group_pair'})
            pair(2,{'Desagrupar',false,function()
                paint:ungroup(state) end,'group_ungroup'},
                {'Visível',group and group.visible,function()
                paint:groupAction(state,'visible') end,'group_visible'})
            pair(3,{'Opacidade -',false,function()
                paint:groupAction(state,'opacityMinus') end,'group_opacity_minus'},
                {'Opacidade +',false,function()
                paint:groupAction(state,'opacityPlus') end,'group_opacity_plus'})
            pair(4,{'Subir grupo',false,function()
                paint:moveGroup(state,1) end,'group_move_up'},
                {'Descer grupo',false,function()
                paint:moveGroup(state,-1) end,'group_move_down'})
            label('Movimento inclui todas as camadas e subgrupos.',
                x+margin,y+337,full,'tiny','left',C.soft)
        elseif layer_advanced_tab=='layer_mask' then
            pair(1,{'Adicionar',false,function()
                paint:layerMaskAction(state,'add') end,'layer_mask_add'},
                {'Remover',false,function()
                paint:layerMaskAction(state,'remove') end,'layer_mask_remove'})
            pair(2,{'Ativar',layer.mask and layer.mask.enabled,function()
                paint:layerMaskAction(state,'enabled') end,'layer_mask_enabled'},
                {'Inverter',layer.mask and layer.mask.inverted,function()
                paint:layerMaskAction(state,'inverted') end,'layer_mask_inverted'})
            pair(3,{'Editar máscara',mode=='layer',function()
                paint:editMask(state,'layer') end,'layer_mask_paint'},
                {'Pintar pixels',not mode,function()
                paint:editPixels() end,'layer_paint_pixels'})
            label('A máscara da camada não apaga pixels originais.',
                x+margin,y+301,full,'tiny','left',C.soft)
        else
            pair(1,{'Adicionar',false,function()
                paint:groupAction(state,'addMask') end,'group_mask_add'},
                {'Remover',false,function()
                paint:groupAction(state,'removeMask') end,'group_mask_remove'})
            pair(2,{'Ativar',group and group.mask and group.mask.enabled,function()
                paint:groupAction(state,'maskEnabled') end,'group_mask_enabled'},
                {'Inverter',group and group.mask and group.mask.inverted,function()
                paint:groupAction(state,'maskInverted') end,'group_mask_inverted'})
            pair(3,{'Editar máscara',mode=='group',function()
                paint:editMask(state,'group') end,'group_mask_paint'},
                {'Pintar pixels',not mode,function()
                paint:editPixels() end,'group_paint_pixels'})
            label('A máscara do grupo atua no resultado de seus filhos.',
                x+margin,y+301,full,'tiny','left',C.soft)
        end
        label('Pincel revela; borracha esconde. Feche o painel para pintar.',
            x+margin,y+h-24,full,'tiny','left',C.soft)
    elseif name=="layer" then
        hit(x+3,y+2,w-48,32,function()
            local mx,my=pointer()
            drag_layer={dx=mx-x,dy=my-y}
        end,"layer_drag")
        local bx=x+10
        rectangle(bx,y+43,w-126,37,C.light,0.20,2)
        label("Grupos / Máscaras  >",bx+13,y+54,w-145,"small","left",C.white)
        hit(bx,y+43,w-126,37,function() set_panel('layer_advanced') end,'layer_advanced')
        local function moveButton(xx,text,dir,key)
            rectangle(xx,y+45,30,32,C.panel_head,0.97,5)
            label(text,xx,y+53,30,'small','center',C.white)
            hit(xx,y+45,30,32,function()
                paint:moveLayer(state,dir)
                notice(paint.status)
            end,key)
        end
        moveButton(x+w-107,'↑',1,'layer_move_up')
        moveButton(x+w-73,'↓',-1,'layer_move_down')
        local max_rows=math.max(1,math.floor((h-269)/52))
        layer_scroll=math.max(0,math.min(layer_scroll,math.max(0,#state.layers-max_rows)))
        layer_row_targets={}
        for slot=1,math.min(#state.layers-layer_scroll,max_rows) do
            local index=#state.layers-slot+1-layer_scroll
            local layer=state.layers[index]
            local yy=y+85+(slot-1)*52
            local active=layer.id==state.active_layer_id
            rectangle(bx,yy,w-53,50,
                active and C.blue or C.light,active and 0.72 or 0.15,2)
            -- Miniatura real da camada ativa, centrada e preservando proporção.
            -- O quadriculado é APENAS o fundo da transparência.
            for i=0,3 do for j=0,3 do
                local v=(i+j)%2==0 and 0.87 or 0.65
                rectangle(bx+4+i*10,yy+5+j*10,10,10,{v,v,v})
            end end
            local thumb=paint:thumbnail(state,layer.id,'layer',40,40)
            if thumb then
                rgba(C.white)
                love.graphics.draw(thumb,bx+4,yy+5)
            end
            stroke(bx+4,yy+5,40,40,C.soft,0.7)
            layer_row_targets[#layer_row_targets+1]={id=layer.id,x=bx,y=yy,w=w-98,h=50}
            if layer_row_drag and layer_row_drag.moved and
                layer_row_drag.targetId==layer.id and
                layer_row_drag.id~=layer.id then
                stroke(bx+2,yy+1,w-102,48,C.accent,1)
            end
            label(tostring(index),bx+48,yy+4,30,"small","center",C.white)
            local docLayer=paint.doc and paint.byId[layer.id]
            local gr=docLayer and docLayer.groupId and paint.doc.groups[docLayer.groupId]
            local title=(gr and '[G] ' or '')..layer.name
            label(title,bx+79,yy+4,w-185,"tiny","left",C.white)
            if docLayer and docLayer.mask then
                local maskThumb=paint:thumbnail(state,layer.id,'mask',19,19)
                if maskThumb then
                    rectangle(bx+50,yy+27,19,19,C.deep,1,1)
                    rgba(C.white)
                    love.graphics.draw(maskThumb,bx+50,yy+27)
                    stroke(bx+50,yy+27,19,19,C.soft,0.8)
                end
            end
            label(tostring(layer.opacity).."%   "..layer.blending,
                bx+79,yy+24,w-172,"small","left",C.white)
            local id=layer.id
            hit(bx,yy,w-98,50,function()
                state:select_layer(id)
                local mx,my=pointer()
                layer_row_drag={id=id,startX=mx,startY=my,moved=false,targetId=nil}
            end,"select_layer")
            glyph("eye",x+w-29,yy+25,12)
            hit(x+w-48,yy+3,41,44,function()
                layer_press={id=id,started=love.timer.getTime()}
            end,"visibility")
            if not layer.visible then
                rectangle(bx,yy,w-53,50,C.deep,0.34)
            end
        end
        icon_button(x+w-39,y+44,31,31,"plus",function()
            state:add_layer()
        end)
        hit(x+w-39,y+44,31,31,function() state:add_layer() end,
            "layer_add")
        local active=state:active_layer()
        local foot=y+h-174
        line(x+8,foot-8,x+w-8,foot-8,1,C.soft,0.3)
        label("Opacity",x+13,foot,w-40,"small","left",C.white)
        label(active.opacity.."%",x+w-53,foot,45,"small","right",C.white)
        local slider_x=x+94
        local slider_w=w-157
        rectangle(slider_x,foot+12,slider_w,4,C.soft,0.58)
        rectangle(slider_x,foot+12,slider_w*active.opacity/100,4,C.blue)
        rgba(C.white)
        love.graphics.circle("fill",slider_x+slider_w*active.opacity/100,foot+14,7)
        hit(slider_x,foot+2,slider_w,27,function()
            local mx=pointer()
            state:set_layer_opacity(active.id,
                math.floor(math.max(0,math.min(1,(mx-slider_x)/slider_w))*100+0.5))
            drag_opacity={id=active.id,x=slider_x,w=slider_w}
        end,"layer_opacity")
        local bw=(w-29)/2
        local function toggle(xx,name,enabled,fn,key)
            rectangle(xx,foot+37,bw,30,enabled and C.blue or C.deep,0.92,2)
            label(name,xx+1,foot+45,bw-2,"small","center",C.white)
            hit(xx,foot+37,bw,30,fn,key)
        end
        toggle(x+10,"Clipping",active.clipping,function()
            state:toggle_layer_clipping(active.id)
        end,"layer_clipping")
        toggle(x+19+bw,"Alpha Lock",active.alpha_lock,function()
            state:toggle_layer_alpha_lock(active.id)
        end,"layer_alpha_lock")
        rectangle(x+10,foot+72,w-20,30,C.deep,0.86,2)
        label("Blending Mode   "..active.blending.."   ▾",
            x+19,foot+80,w-38,"small","left",C.white)
        hit(x+10,foot+72,w-20,30,function()
            layer_blend_open=not layer_blend_open
        end,"layer_blend")
        label("Background",x+10,foot+109,w-20,"small","left",C.white)
        local backgrounds={
            {"White","white"},{"Light","transparent_light"},
            {"Dark","transparent_dark"}
        }
        for i,option in ipairs(backgrounds) do
            local ww=(w-24)/3
            local xx=x+9+(i-1)*ww
            local enabled=state.background_mode==option[2]
            rectangle(xx,foot+128,ww-3,31,
                enabled and C.blue or C.deep,enabled and 0.96 or 0.79,2)
            label(option[1],xx+1,foot+136,ww-5,"small","center",C.white)
            local mode=option[2]
            hit(xx,foot+128,ww-3,31,function()
                state:set_background(mode)
            end,"background_"..mode)
        end
        -- Floating Layer Window grip: size-adjustment is documented for PCs.
        line(x+w-17,y+h-5,x+w-5,y+h-17,1.2,C.white)
        line(x+w-11,y+h-5,x+w-5,y+h-11,1.2,C.white)
        hit(x+w-24,y+h-24,24,24,function()
            local mx,my=pointer()
            drag_layer_resize={start_x=mx,start_y=my,w=w,h=h}
        end,"layer_resize")
        if layer_blend_open then
            local opts={"Normal","Multiply","Screen","Overlay","Darken","Lighten",
                "Color Burn","Color Dodge","Soft Light"}
            local popup_x=x+w-210
            local popup_y=y+35
            rectangle(popup_x,popup_y,201,#opts*27+6,C.deep,0.99,2)
            hit(popup_x,popup_y,201,#opts*27+6,function() end,"blend_surface")
            for i,mode in ipairs(opts) do
                local yy=popup_y+3+(i-1)*27
                if active.blending==mode then
                    rectangle(popup_x+2,yy,197,26,C.blue,0.80,2)
                end
                label(mode,popup_x+11,yy+7,174,"small","left",C.white)
                hit(popup_x+3,yy,195,26,function()
                    state:set_layer_blending(state.active_layer_id,mode)
                    layer_blend_open=false
                end,"blend_"..mode)
            end
        end
    elseif name=="brush" then
        local gx=love.graphics
        local margin=8
        local inner_x=x+margin
        local inner_y=y+39
        local inner_w=w-margin*2
        local inner_h=h-46
        local left_w=math.floor(inner_w*0.53)
        local right_x=inner_x+left_w
        local right_w=inner_w-left_w
        rectangle(inner_x,inner_y,left_w,inner_h,C.white,1)
        rectangle(right_x,inner_y,right_w,inner_h,{0.19,0.19,0.19},0.97)
        -- Separate rows and a three-tab header follow the desktop screenshot.
        local top_height=34
        local tab_gap=left_w/3
        local tabs={"Basic","Custom","Online"}
        for i,name in ipairs(tabs) do
            local xx=inner_x+(i-1)*tab_gap
            rectangle(xx,inner_y,tab_gap,top_height,
                brush_tab==name and C.white or {0.64,0.64,0.64})
            if brush_tab==name then
                rectangle(xx,inner_y+top_height-3,tab_gap,3,C.blue)
            end
            label(name,xx+2,inner_y+9,tab_gap-4,"small","center",C.ink)
            local chosen=name
            hit(xx,inner_y,tab_gap,top_height,function()
                brush_tab=chosen
                brush_search=""
                brush_search_active=false
                brush_scroll=0
            end,"brush_tab_"..name)
        end
        local list_y=inner_y+top_height+1
        local search_h=brush_search_active and 33 or 24
        rectangle(inner_x,list_y,left_w,search_h,{0.94,0.94,0.94})
        if brush_search_active then
            rectangle(inner_x+8,list_y+5,left_w-43,24,C.white)
            stroke(inner_x+8,list_y+5,left_w-43,24,C.blue)
            label(brush_search~="" and brush_search or "Search brushes",
                inner_x+15,list_y+11,left_w-57,"small","left",
                brush_search~="" and C.ink or {0.60,0.60,0.60})
        else
            label("Brush Library",inner_x+9,list_y+5,left_w-52,
                "small","left",C.ink)
        end
        -- Magnifier drawn with LÖVE line work; not a captured proprietary icon.
        local mag_x=inner_x+left_w-19
        local mag_y=list_y+search_h/2-2
        rgba(C.ink)
        gx.setLineWidth(1.8)
        gx.circle("line",mag_x-2,mag_y-2,5)
        gx.line(mag_x+2,mag_y+2,mag_x+7,mag_y+7)
        hit(inner_x+left_w-40,list_y,40,search_h,function()
            brush_search_active=not brush_search_active
            brush_search=""
            brush_scroll=0
        end,"brush_search_toggle")
        local entries=BrushCatalog.search(brush_search)
        local row_h=43
        local list_top=list_y+search_h
        local list_h=math.max(32,inner_y+inner_h-list_top-2)
        local max_scroll=math.max(0,#entries*row_h-list_h)
        brush_scroll=math.max(0,math.min(max_scroll,brush_scroll))
        gx.setScissor(inner_x*scale,list_top*scale,
            left_w*scale,list_h*scale)
        if brush_tab~="Basic" then
            label(brush_tab.." brushes are not included in this simulation.",
                inner_x+12,list_top+40,left_w-24,"small","center",
                {0.48,0.48,0.48})
        elseif #entries==0 then
            label("No matching brushes",inner_x+10,list_top+36,
                left_w-20,"small","center",{0.43,0.43,0.43})
        else
            for i,item in ipairs(entries) do
                local brush=item.brush
                local yy=list_top+(i-1)*row_h-brush_scroll
                if yy+row_h>list_top and yy<list_top+list_h then
                    local selected=selected_brush==item.index
                    rectangle(inner_x,yy,left_w,row_h-1,
                        selected and {0.77,0.85,0.92} or C.white)
                    line(inner_x,yy+row_h-1,inner_x+left_w,
                        yy+row_h-1,1,{0.82,0.82,0.82})
                    rectangle(inner_x+7,yy+5,17,17,C.white,1,9)
                    stroke(inner_x+7,yy+5,17,17,
                        selected and C.blue or {0.65,0.65,0.65})
                    line(inner_x+12,yy+13,inner_x+19,yy+13,1.2,C.ink)
                    line(inner_x+15,yy+10,inner_x+15,yy+16,1.2,C.ink)
                    label(brush.label,inner_x+29,yy+3,left_w-83,
                        "tiny","left",C.ink)
                    label(tostring(brush.size)..".0",inner_x+left_w-42,
                        yy+6,36,"tiny","right",{0.39,0.39,0.39})
                    -- Deterministic synthetic sample strokes, no canvas engine.
                    draw_brush_sample(inner_x+36,yy+30,left_w-80,
                        7,brush.kind,false)
                    local index=item.index
                    local hit_y=math.max(yy,list_top)
                    local hit_bottom=math.min(yy+row_h,list_top+list_h)
                    if hit_bottom>hit_y then
                        hit(inner_x,hit_y,left_w,hit_bottom-hit_y,function()
                            selected_brush=index
                            local chosen=BrushCatalog.get(index)
                            state:set_brush_size(chosen.size)
                        end,"brush_preset_"..index)
                    end
                end
            end
        end
        gx.setScissor()
        if max_scroll>0 and brush_tab=="Basic" then
            local track_x=inner_x+left_w-4
            local thumb_h=math.max(22,list_h*list_h/(list_h+max_scroll))
            local thumb_y=list_top+(list_h-thumb_h)*brush_scroll/max_scroll
            rectangle(track_x,list_top,3,list_h,{0.82,0.82,0.82})
            rectangle(track_x,thumb_y,3,thumb_h,{0.52,0.52,0.52})
        end
        -- Dark properties area, including stroke preview and active brush data.
        local active=BrushCatalog.get(selected_brush)
        local rx=right_x+10
        local rw=right_w-20
        rectangle(right_x,inner_y,right_w,top_height,{0.27,0.27,0.27})
        label(active.label,right_x+6,inner_y+9,right_w-12,
            "small","center",C.white)
        local sample_y=inner_y+43
        local sample_h=92
        rectangle(rx,sample_y,rw,sample_h,{0.91,0.91,0.91},1,2)
        for row=0,5 do for col=0,10 do
            if (row+col)%2==0 then
                rectangle(rx+col*rw/11,sample_y+row*sample_h/6,
                    rw/11+0.1,sample_h/6+0.1,{0.95,0.95,0.95})
            end
        end end
        draw_brush_sample(rx+17,sample_y+sample_h*0.54,rw-34,34,
            active.kind,true)
        rectangle(rx,sample_y+sample_h+2,rw,25,{0.25,0.25,0.25})
        label("Brush properties",rx+5,sample_y+sample_h+9,
            rw-10,"small","center",C.white)
        local control_y=sample_y+sample_h+42
        local function value_slider(yoff,title,value,suffix,kind)
            local yy=control_y+yoff
            label(title,rx+4,yy,rw-8,"small","left",C.white)
            label(tostring(value)..suffix,rx+5,yy+22,
                rw-10,"small","right",C.white)
            local track_y=yy+43
            local px=rx+11
            local pw=rw-22
            local fraction=kind=="size" and math.min(1,value/100)
                or value/100
            rectangle(px,track_y,pw,4,{0.62,0.62,0.62},0.68,2)
            rectangle(px,track_y,pw*fraction,4,C.blue,1,2)
            rgba(C.white)
            gx.circle("fill",px+pw*fraction,track_y+2,7)
            local function update_mouse()
                local mx=pointer()
                local f=math.max(0,math.min(1,(mx-px)/pw))
                if kind=="size" then
                    state:set_brush_size(math.max(0.1,math.floor(f*1000+0.5)/10))
                else opacity=math.floor(f*100+0.5) end
            end
            hit(px,track_y-10,pw,25,function()
                update_mouse()
                brush_drag={kind=kind,x=px,w=pw}
            end,"brush_"..kind.."_slider")
        end
        value_slider(0,"Thickness",math.floor(state.brush_size*10+0.5)/10,
            " px","size")
        value_slider(79,"Opacity",opacity,"%","opacity")
        local by=control_y+174
        rectangle(rx,by,rw,32,{0.34,0.34,0.34},0.96,3)
        label("Reset",rx+8,by+8,rw-16,"small","center",C.white)
        hit(rx,by,rw,32,function()
            local selected=BrushCatalog.get(selected_brush)
            state:set_brush_size(selected.size)
            opacity=100
        end,"brush_reset")
        -- Show what the selected brush looks like without claiming to paint.
        label("Amostra visual — pincel real no canvas",
            rx,inner_y+inner_h-32,rw,"tiny","center",C.soft)
    elseif name=="color" then
        local function apply_color()
            state:set_color(colors.current[1],colors.current[2],colors.current[3])
            local hue=colors:hsb()
            picker_hue=(hue%360)/360
            palette_index=0
        end
        local function from_pointer(mx,my,wheel_x,wheel_y,radius)
            local dx,dy=mx-wheel_x,my-wheel_y
            local distance=math.sqrt(dx*dx+dy*dy)
            local h,s,b=colors:hsb()
            if distance>=radius-23 then
                local a
                if math.atan2 then a=math.atan2(dy,dx)
                elseif dx~=0 then
                    a=math.atan(dy/dx)
                    if dx<0 then a=a+math.pi end
                else a=dy>=0 and math.pi/2 or -math.pi/2 end
                h=(((a+math.pi/2)/(2*math.pi))%1)*360
            else
                local radius_inner=radius-23
                local u=(dx+dy)/(2*radius_inner)+0.5
                local v=(dy-dx)/(2*radius_inner)+0.5
                s=math.max(0,math.min(1,u))*100
                b=(1-math.max(0,math.min(1,v)))*100
            end
            colors:set_hsb(h,s,b)
            apply_color()
        end
        -- Header controls (a floating Color Window was introduced in v14).
        hit(x+5,y+2,w-176,31,function()
            if color_float then
                local mx,my=pointer()
                color_drag={dx=mx-x,dy=my-y}
            end
        end,"color_move_bar")
        rectangle(x+w-172,y+4,127,28,
            color_float and C.blue or C.deep,0.93,2)
        label(color_float and "Dock Color" or "Floating Window",
            x+w-170,y+12,123,"tiny","center",C.white)
        hit(x+w-172,y+4,127,28,function()
            color_float=not color_float
            color_position=nil
        end,"color_float_toggle")
        -- Current / previous colors are explicit in the official Color window.
        local current=colors.current
        local prev=colors.previous
        rectangle(x+16,y+47,68,43,
            {current[1]/255,current[2]/255,current[3]/255},1,3)
        stroke(x+16,y+47,68,43,C.white,0.68)
        rectangle(x+91,y+47,68,43,{prev[1]/255,prev[2]/255,prev[3]/255},1,3)
        stroke(x+91,y+47,68,43,C.white,0.68)
        label("Current",x+16,y+92,68,"tiny","center",C.white)
        label("Previous",x+91,y+92,68,"tiny","center",C.white)
        hit(x+91,y+47,68,43,function()
            colors:set_rgb(prev[1],prev[2],prev[3]);apply_color()
        end,"color_previous")
        rectangle(x+183,y+51,w-200,34,C.deep,0.92,3)
        label(colors:hex(),x+192,y+61,w-218,"normal","center",C.white)
        hit(x+183,y+51,w-200,34,function()
            color_dialog="hex"
            color_input=colors:hex()
            color_input_replace=true
        end,"color_hex")
        -- Toggle HSB/Palette and HSB/RGB separately.
        local tab_y=y+119
        local half=(w-32)/2
        for i,item in ipairs({
            {"HSB",false},{"Palette",true}
        }) do
            local xx=x+16+(i-1)*half
            local selected=colors.palette_mode==item[2]
            rectangle(xx,tab_y,half-3,33,
                selected and C.blue or C.deep,0.89,2)
            label(item[1],xx+4,tab_y+9,half-11,
                "small","center",C.white)
            local desired=item[2]
            hit(xx,tab_y,half-3,33,function()
                colors.palette_mode=desired
            end,"color_mode_"..item[1]:lower())
        end
        if not colors.palette_mode then
            local wheel_x=x+127
            local wheel_y=y+265
            local radius=104
            draw_hue_wheel(wheel_x,wheel_y,radius)
            local _,saturation,brightness=colors:hsb()
            local diamond_r=radius-23
            local u=saturation/100
            local v=1-brightness/100
            local pick_x=wheel_x+(u-v)*diamond_r
            local pick_y=wheel_y+(u+v-1)*diamond_r
            rgba(C.deep)
            love.graphics.setLineWidth(3)
            love.graphics.circle("line",pick_x,pick_y,7)
            rgba(C.white)
            love.graphics.setLineWidth(1.8)
            love.graphics.circle("line",pick_x,pick_y,7)
            hit(wheel_x-radius,wheel_y-radius,radius*2,radius*2,function()
                local mx,my=pointer()
                from_pointer(mx,my,wheel_x,wheel_y,radius)
                color_wheel_drag={
                    x=wheel_x,y=wheel_y,r=radius,
                    action=from_pointer,apply=apply_color
                }
            end,"color_wheel")
            local sx=x+264
            local track_w=math.max(60,w-306)
            local hue,saturation,brightness=colors:hsb()
            local channels=colors.rgb_mode and {
                {"R",current[1],255},{"G",current[2],255},
                {"B",current[3],255},{"Opacity",colors.opacity,100}
            } or {
                {"H",math.floor(hue+0.5),360},
                {"S",math.floor(saturation+0.5),100},
                {"B",math.floor(brightness+0.5),100},
                {"Opacity",colors.opacity,100}
            }
            for index,entry in ipairs(channels) do
                local yy=y+169+(index-1)*69
                label(entry[1],sx,yy,track_w*0.55,"small","left",C.white)
                label(tostring(entry[2])..(index==4 and "%" or ""),
                    sx+track_w*0.53,yy,track_w*0.47,
                    "small","right",C.white)
                rectangle(sx,yy+27,track_w,5,C.soft,0.62,2)
                local frac=entry[2]/entry[3]
                rectangle(sx,yy+27,track_w*frac,5,C.blue,1,2)
                rgba(C.white)
                love.graphics.circle("fill",sx+track_w*frac,yy+29,7)
                local mode=colors.rgb_mode and "RGB" or "HSB"
                local number=index
                local function set_fraction(fr)
                    fr=math.max(0,math.min(1,fr))
                    if number==4 then colors:set_opacity(fr*100)
                    elseif mode=="RGB" then
                        colors:set_rgb_channel(number,math.floor(fr*255+0.5))
                        apply_color()
                    else
                        local hue,sat,bright=colors:hsb()
                        if number==1 then hue=fr*360
                        elseif number==2 then sat=fr*100
                        else bright=fr*100 end
                        colors:set_hsb(hue,sat,bright)
                        apply_color()
                    end
                end
                hit(sx,yy+15,track_w,31,function()
                    local mx=pointer()
                    set_fraction((mx-sx)/track_w)
                    color_slider_drag={x=sx,w=track_w,change=set_fraction}
                end,"color_slider_"..(colors.rgb_mode and
                    ({"r","g","b","opacity"})[index] or
                    ({"h","s","b","opacity"})[index]))
            end
            rectangle(sx,y+448,track_w,32,C.deep,0.86,3)
            label(colors.rgb_mode and "RGB → HSB" or "HSB → RGB",
                sx+3,y+456,track_w-6,"small","center",C.white)
            hit(sx,y+448,track_w,32,function()
                colors:toggle_rgb_mode()
            end,"color_rgb_toggle")
            label("Color preview only — no painting engine",
                x+12,y+h-56,w-24,"tiny","center",C.soft)
        else
            local active=colors.palettes[colors.active_palette]
            label("Color Palettes",x+20,y+167,w-40,"small","left",C.white)
            local pal_x=x+17
            local pal_list=colors:palettes_list()
            local max_page=math.max(0,math.floor((#pal_list-1)/3))
            color_palette_page=math.max(0,
                math.min(max_page,color_palette_page))
            local tab_w=math.max(50,math.min(132,(w-113)/3))
            for j=1,3 do
                local i=color_palette_page*3+j
                local item=pal_list[i]
                if item then
                    local px=pal_x+(j-1)*(tab_w+2)
                    rectangle(px,y+190,tab_w,30,
                        colors.active_palette==i and C.blue or C.deep,
                        0.91,3)
                    label(item.name,px+3,y+200,tab_w-6,"small","center",C.white)
                    local id=i
                    hit(px,y+190,tab_w,30,function()
                        colors:choose_palette(id)
                    end,"color_palette_"..i)
                end
            end
            local prev_x=x+w-70
            local next_x=x+w-37
            rectangle(prev_x,y+191,30,27,C.deep,
                color_palette_page>0 and 0.94 or 0.46,2)
            rectangle(next_x,y+191,30,27,C.deep,
                color_palette_page<max_page and 0.94 or 0.46,2)
            label("<",prev_x,y+197,30,"small","center",C.white)
            label(">",next_x,y+197,30,"small","center",C.white)
            if color_palette_page>0 then
                hit(prev_x,y+191,30,27,function()
                    color_palette_page=color_palette_page-1
                end,"color_palette_prev")
            end
            if color_palette_page<max_page then
                hit(next_x,y+191,30,27,function()
                    color_palette_page=color_palette_page+1
                end,"color_palette_next")
            end
            local current_name=active.name
            label(current_name.." ("..#active.colors..")",
                x+17,y+233,w-34,"normal","left",C.white)
            local menu_y=y+259
            local bw=(w-43)/3
            for i,item in ipairs({
                {"New",function()
                    color_dialog="new_palette"
                    color_input="New Palette"
                    color_input_replace=true
                end,"color_new_palette"},
                {"Rename",function()
                    color_dialog="rename_palette"
                    color_input=active.name
                    color_input_replace=true
                end,"color_rename_palette"},
                {"+ Color",function()
                    colors:add_current()
                end,"color_add_swatch"}
            }) do
                local px=x+17+(i-1)*(bw+4)
                rectangle(px,menu_y,bw,36,C.deep,0.94,2)
                label(item[1],px+2,menu_y+11,bw-4,
                    "small","center",C.white)
                hit(px,menu_y,bw,36,item[2],item[3])
            end
            local swatches=colors:colors()
            local swatch_size=32
            local swatch_gap=6
            local columns=math.max(1,math.floor((w-42)/(swatch_size+swatch_gap)))
            local max_slots=math.max(1,math.floor((h-415)/40)*columns)
            for i=1,math.min(#swatches,max_slots) do
                local col=(i-1)%columns
                local row=math.floor((i-1)/columns)
                local px=x+17+col*(swatch_size+swatch_gap)
                local py=y+310+row*40
                local c=swatches[i]
                rectangle(px,py,swatch_size,swatch_size,
                    {c[1]/255,c[2]/255,c[3]/255},1,2)
                stroke(px,py,swatch_size,swatch_size,C.white,0.42)
                local id=i
                hit(px,py,swatch_size,swatch_size,function()
                    colors:select_color(id);apply_color()
                    color_swatch_drag={
                        from=id,initial_x=px+swatch_size/2,
                        initial_y=py+swatch_size/2,
                        grid_x=x+17,grid_y=y+310,
                        step=swatch_size+swatch_gap,
                        columns=columns
                    }
                end,"color_swatch_"..i)
            end
            local recent=colors:history_list()
            local foot=y+h-100
            label("Color History — selected colors",
                x+16,foot,w-32,"small","left",C.white)
            for i=1,math.min(#recent,11) do
                local c=recent[i]
                local xx=x+16+(i-1)*37
                rectangle(xx,foot+25,30,30,
                    {c[1]/255,c[2]/255,c[3]/255},1,2)
                stroke(xx,foot+25,30,30,C.white,0.31)
                hit(xx,foot+25,30,30,function()
                    colors:set_rgb(c[1],c[2],c[3]);apply_color()
                end,"color_history_"..i)
            end
        end
        -- Floating size control, analogous to the official Windows/Mac widget.
        if color_float then
            line(x+w-18,y+h-5,x+w-5,y+h-18,1.6,C.white)
            line(x+w-11,y+h-5,x+w-5,y+h-11,1.6,C.white)
            hit(x+w-24,y+h-24,24,24,function()
                local mx,my=pointer()
                color_resize={mx=mx,my=my,w=w,h=h}
            end,"color_resize")
        end
        if color_dialog then
            local pw=math.min(365,w-35)
            local ph=213
            local px=x+(w-pw)/2
            local py=y+(h-ph)/2
            rectangle(x,y,w,h,C.deep,0.54)
            hit(x,y,w,h,function() end,"color_dialog_shield")
            rectangle(px,py,pw,ph,C.light,1,7)
            label(color_dialog=="hex" and "Hex Color Code" or
                (color_dialog=="new_palette" and "Create New Palette" or
                    "Rename Palette"),
                px+15,py+23,pw-30,"normal","center",C.ink)
            rectangle(px+24,py+87,pw-48,41,C.white,1,3)
            stroke(px+24,py+87,pw-48,41,C.blue)
            label(color_input,px+33,py+100,pw-66,"normal","left",C.ink)
            hit(px+24,py+87,pw-48,41,function()
                color_input_replace=true
            end,"color_dialog_input")
            local bw=(pw-63)/2
            plain_button(px+24,py+157,bw,36,"Cancel",function()
                color_dialog=nil
            end)
            local function confirm()
                local ok,err=pcall(function()
                    if color_dialog=="hex" then
                        colors:set_hex(color_input)
                        apply_color()
                    elseif color_dialog=="new_palette" then
                        local id=colors:create_palette(color_input)
                        color_palette_page=math.floor((id-1)/3)
                    else colors:rename_palette(colors.active_palette,color_input) end
                end)
                if ok then color_dialog=nil
                else notice("Invalid color or palette name.") end
            end
            plain_button(px+39+bw,py+157,bw,36,"OK",confirm)
            hit(px+39+bw,py+157,bw,36,confirm,"color_dialog_confirm")
        end
    elseif name=="tools" then
        local cols=preferences:effective_tool_columns()
        local rows=math.ceil(#tools/cols)
        local gap=5
        local inset=10
        local cell_w=(w-2*inset-gap*(cols-1))/cols
        local row_h=(h-51)/rows
        for i,item in ipairs(tools) do
            local row_index=math.floor((i-1)/cols)
            local column=(i-1)%cols
            local xx=x+inset+column*(cell_w+gap)
            local yy=y+42+row_index*row_h
            local cell_h=row_h-3
            local selected=item[2]==state.active_tool
            rectangle(xx,yy,cell_w,cell_h,
                selected and C.blue or C.deep,
                selected and 0.87 or 0.67,3)
            if cols==1 then
                glyph(item[2],xx+25,yy+cell_h/2,math.min(17,cell_h*0.37))
                if preferences.show_tool_labels then
                    label(item[1],xx+48,yy+(cell_h-13)/2,
                        cell_w-55,"small","left",C.white)
                end
            else
                glyph(item[2],xx+cell_w/2,
                    yy+(preferences.show_tool_labels and cell_h*0.38
                        or cell_h*0.5),
                    math.min(18,cell_h*0.27))
                if preferences.show_tool_labels then
                    label(item[1],xx+2,yy+cell_h*0.69,
                        cell_w-4,"tiny","center",C.white)
                end
            end
            local key=item[2]
            hit(xx,yy,cell_w,cell_h,function()
                if paint.transform and key~='transform' then
                    notice('Confirme ou cancele a transformação')
                    return
                end
                state:set_tool(key)
                panel=nil;state.active_panel=nil
                if key=='transform' then
                    paint:startTransform(state)
                    notice(paint.status)
                end
            end,"tool_choice_"..key)
        end
    elseif name=="back" then
        label("Back",x+20,y+69,w-40,"normal","center",C.white)
        plain_button(x+20,y+127,w-40,42,"Back to My Gallery",back_to_gallery,true)
        plain_button(x+20,y+191,w-40,42,"Settings",function()
            set_panel("settings")
        end)
        plain_button(x+20,y+250,w-40,42,"Exportar PNG",function()
            local path,err=paint:exportPNG(state)
            if path then
                notice('PNG em '..love.filesystem.getSaveDirectory()..'/'..path)
            else notice('PNG: '..tostring(err)) end
        end,false,'editor_export_png')
        hit(x+20,y+191,w-40,42,function()
            set_panel("settings")
        end,"back_settings")
    elseif name=="settings" then
        local bx=x+15
        local bw=w-30
        label("User Interface",bx,y+46,bw,"normal","left",C.white)
        line(bx,y+78,x+w-15,y+78,1,C.soft,0.37)
        label("Tool Select Position",bx,y+91,bw,"small","left",C.white)
        local choices={
            {"Left","left"},{"Right","right"},{"Popup","popup"}
        }
        local sw=(bw-8)/3
        for i,choice in ipairs(choices) do
            local xx=bx+(i-1)*(sw+4)
            local current=preferences.tool_position==choice[2]
            rectangle(xx,y+114,sw,37,current and C.blue or C.deep,
                current and 0.94 or 0.75,3)
            label(choice[1],xx+2,y+126,sw-4,"small","center",C.white)
            local selected=choice[2]
            hit(xx,y+114,sw,37,function()
                preferences:set_tool_position(selected)
                save_preferences()
            end,"pref_position_"..selected)
        end
        label("Number of Columns in Tool Select Popup",
            bx,y+165,bw,"small","left",
            preferences.tool_position=="popup" and C.white or C.soft)
        for cols=1,3 do
            local xx=bx+(cols-1)*(sw+4)
            local active=preferences.popup_columns==cols
            local available=preferences.tool_position=="popup"
            rectangle(xx,y+189,sw,34,available and
                (active and C.blue or C.deep) or C.bar,
                available and 0.90 or 0.48,3)
            label(tostring(cols),xx+2,y+199,sw-4,"small","center",
                available and C.white or C.soft)
            local value=cols
            if available then hit(xx,y+189,sw,34,function()
                preferences:set_popup_columns(value)
                save_preferences()
            end,"pref_columns_"..value) end
        end
        local function pref_toggle(yy,title,enabled,fn,key)
            rectangle(bx,yy,bw,42,C.white,0.065,3)
            label(title,bx+11,yy+13,bw-88,"small","left",C.white)
            local tx=bx+bw-72
            rectangle(tx,yy+9,54,25,
                enabled and C.blue or {0.49,0.49,0.49},1,12)
            rgba(C.white)
            love.graphics.circle("fill",tx+(enabled and 40 or 13),yy+21,9)
            hit(bx,yy,bw,42,fn,key)
        end
        pref_toggle(y+237,"Show Label in Tool Select",
            preferences.show_tool_labels,
            function()
                preferences:toggle_tool_labels()
                save_preferences()
            end,"pref_show_labels")
        pref_toggle(y+285,"Invert Direction of Mouse Wheel",
            preferences.invert_wheel,
            function()
                preferences:toggle_invert_wheel()
                save_preferences()
            end,"pref_invert_wheel")
        pref_toggle(y+333,"Show Message on Undo",
            preferences.show_undo_message,
            function()
                preferences:toggle_undo_messages()
                save_preferences()
            end,"pref_undo_messages")
        label("Additional settings are not yet reconstructed.",
            bx,y+400,bw,"tiny","center",C.soft)
    elseif name=="text" then
        label("Text tool selected.",x+15,y+99,w-30,"normal","center",C.white)
        label("Editing artwork is outside the UI-only scope.",x+12,y+145,w-24,"small","center",C.soft)
    else
        label((titles[name] or name).." settings",x+20,y+90,w-40,"normal","center",C.white)
        label("Insufficient verified Windows 14.1.4 references",x+20,y+139,w-40,"small","center",C.soft)
        label("No unverified controls have been added.",x+20,y+168,w-40,"small","center",C.soft)
    end
end

local function queue_capture()
    if capture_pending then return end
    capture_pending=true
    love.graphics.captureScreenshot(function(image)
        local ok,encoded=pcall(function() return image:encode("png") end)
        if not ok then capture_error=tostring(encoded)
        else
            local saved,err=love.filesystem.write("ci-smoke.png",encoded)
            if not saved then capture_error=tostring(err) end
        end
        capture_pending=false
        capture_done=true
    end)
end

function love.load()
    font.tiny=love.graphics.newFont(10)
    font.small=love.graphics.newFont(12)
    font.normal=love.graphics.newFont(16)
    font.header=love.graphics.newFont(19)
    font.logo=love.graphics.newFont(65)
    font.icon=love.graphics.newFont(14)
    font.big_icon=love.graphics.newFont(26)
    IconPack.load()
    if persistence_enabled then
        local loaded,warning,fresh=GalleryStorage.load()
        gallery=loaded
        if fresh then
            local migrated,reason=GalleryStorage.importLegacy(gallery)
            if migrated then notice('Obra antiga importada para a galeria')
            elseif reason then notice('Importação antiga: '..tostring(reason)) end
        end
        if warning then notice(warning) end
    end
    if not (smoke or e2e or settings_e2e or gallery_e2e) then
        local content=love.filesystem.read("editor-preferences.txt")
        if content then
            local ok,restored=pcall(EditorPreferences.decode,content)
            if ok then preferences=restored
            else notice("Invalid saved settings; using defaults.") end
        end
    end
    if (e2e or settings_e2e or color_e2e)
        and os.getenv("PAINT_LUA_E2E_RES") then
        local w,h=os.getenv("PAINT_LUA_E2E_RES"):match("^(%d+)x(%d+)$")
        assert(w and h,"PAINT_LUA_E2E_RES deve ser largura x altura")
        local ok=love.window.setMode(tonumber(w),tonumber(h),{resizable=true})
        assert(ok,"Não foi possível configurar resolução de teste")
    end
    if smoke then
        if smoke_screen=="gallery" then state:open_gallery()
        elseif smoke_screen=="gallery_new" then
            state:open_gallery();gallery_menu="new"
        elseif smoke_screen=="gallery_folders" then
            state:open_gallery()
            gallery:add_folder("Projects")
            gallery:add_folder("Archive")
            gallery:add_artwork(1024,768,"Untitled 1")
        elseif smoke_screen=="gallery_many" then
            state:open_gallery()
            gallery:add_folder("Projects")
            for i=1,24 do
                gallery:add_artwork(640+i*10,800+i*5,"Study "..i)
            end
            gallery_item_scroll=240
        elseif smoke_screen=="gallery_inside" then
            state:open_gallery()
            local fid=gallery:add_folder("Projects")
            gallery:enter(fid)
            gallery:add_artwork(900,600,"Study")
        elseif smoke_screen=="gallery_selection" then
            state:open_gallery()
            gallery:add_folder("Projects")
            local id=gallery:add_artwork(900,600,"Study")
            gallery_selecting=true
            gallery:select(id)
        elseif smoke_screen=="new_canvas" then state:open_gallery();state:open_new_canvas()
        elseif smoke_screen=="new_canvas_dpi" then
            state:open_gallery();state:open_new_canvas()
            preset_selected=10;active_dpi=300
            local wi,he=CanvasPresets.pixels(presets[10],active_dpi)
            current_width=tostring(wi);current_height=tostring(he)
        elseif smoke_screen=="color_palette"
            or smoke_screen=="color_hex"
            or smoke_screen=="color_floating"
            or smoke_screen=="color_rgb" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1800,2400)
            set_panel("color")
            colors:set_hex("#337BCC")
            state:set_color(51,123,204)
            local current_hue=colors:hsb()
            picker_hue=(current_hue%360)/360
            if smoke_screen=="color_palette" then
                colors.palette_mode=true
                colors:create_palette("Character")
                colors:add_current()
                colors:set_hex("#FF8D53")
                colors:add_current()
                state:set_color(255,141,83)
                local current_hue=colors:hsb()
                picker_hue=(current_hue%360)/360
            elseif smoke_screen=="color_hex" then
                color_dialog="hex"
                color_input="#337BCC"
                color_input_replace=true
            elseif smoke_screen=="color_floating" then
                color_float=true
                color_position={x=310,y=70}
                color_size={w=480,h=575}
            elseif smoke_screen=="color_rgb" then
                colors.rgb_mode=true
            end
        elseif smoke_screen=="brush_search" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1800,2400)
            selected_brush=7;state:set_brush_size(8)
            panel="brush";brush_search_active=true;brush_search="Airbrush"
        elseif smoke_screen=="editor_settings"
            or smoke_screen=="tool_popup_1"
            or smoke_screen=="tool_popup_2"
            or smoke_screen=="tool_popup_3"
            or smoke_screen=="tool_right"
            or smoke_screen=="tool_labels_off" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1800,2400)
            if smoke_screen=="editor_settings" then
                set_panel("settings")
            elseif smoke_screen=="tool_right" then
                preferences:set_tool_position("right")
            else
                preferences:set_tool_position("popup")
                if smoke_screen=="tool_popup_1" then
                    preferences:set_popup_columns(1)
                elseif smoke_screen=="tool_popup_2" then
                    preferences:set_popup_columns(2)
                else preferences:set_popup_columns(3) end
                if smoke_screen=="tool_labels_off" then
                    preferences:toggle_tool_labels()
                end
                set_panel("tools")
            end
        elseif smoke_screen=="editor_square" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1000,1000)
        elseif smoke_screen=="editor" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1800,2400)
        elseif smoke_screen=="layer_advanced" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1280,960)
            state:add_layer()
            paint:sync(state)
            assert(paint:createGroup(state,true))
            assert(paint:groupAction(state,'addMask'))
            assert(paint:layerMaskAction(state,'add'))
            layer_advanced_tab='group_mask'
            set_panel('layer_advanced')
        elseif smoke_screen=="layer" or smoke_screen=="color" or smoke_screen=="brush" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1800,2400)
            set_panel(smoke_screen)
        elseif smoke_screen=="zoom" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1800,2400)
            view:zoom_at(2,512,384,512,384)
            view:rotate_wheel(3)
            view:begin_pan(500,360);view:pan_to(540,380);view:end_pan()
        elseif smoke_screen=="solo" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1800,2400)
            state:add_layer();state:toggle_layer_solo(1)
            set_panel("layer")
        elseif smoke_screen=="layer_floating" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1800,2400)
            state:add_layer()
            layer_size={w=340,h=390}
            layer_position={x=128,y=86}
            set_panel("layer")
        elseif smoke_screen=="layer_properties" or smoke_screen=="layer_blend"
            or smoke_screen=="transparent" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1800,2400)
            state:add_layer()
            state:set_layer_opacity(2,63)
            state:toggle_layer_clipping(2)
            state:toggle_layer_alpha_lock(2)
            state:set_layer_blending(2,"Multiply")
            state:set_background("transparent_dark")
            if smoke_screen~="transparent" then
                set_panel("layer")
                layer_blend_open=smoke_screen=="layer_blend"
            end
        elseif smoke_screen=="view" or smoke_screen=="grid_settings"
            or smoke_screen=="grid" or smoke_screen=="reference" then
            state:open_gallery();state:open_new_canvas();state:create_canvas(1800,2400)
            visual.grid=true
            if smoke_screen=="reference" then visual.reference=true
            elseif smoke_screen=="view" then panel="view"
            elseif smoke_screen=="grid_settings" then panel="grid_settings" end
        end
        capture_requested=true
    end
    if layer_e2e then
        state:open_gallery();state:open_new_canvas();state:create_canvas(96,64)
        state:add_layer();state:add_layer()
        paint:sync(state)
        set_panel('layer')
    end
end

function love.draw()
    local real_w,real_h=love.graphics.getDimensions()
    scale=math.max(0.70,math.min(1.4,real_h/768))
    W=real_w/scale;H=real_h/scale
    love.graphics.push()
    love.graphics.scale(scale)
    controls={}
    if state.screen=="title" then title_screen()
    elseif state.screen=="gallery" then gallery_screen()
    elseif current() then editor_screen()
    end
    if toast and love.timer.getTime()<toast_until then
        local tw=math.min(W*0.7,520)
        rectangle((W-tw)/2,H-116,tw,31,C.deep,0.91,4)
        label(toast,(W-tw)/2+8,H-108,tw-16,"small","center",C.white)
    end
    love.graphics.pop()
    if capture_requested then capture_requested=false;queue_capture() end
end

function love.mousepressed(rx,ry,button)
    if button~=1 then return end
    layer_press=nil
    layer_row_drag=nil
    local x,y=rx/scale,ry/scale
    for i=#controls,1,-1 do
        local b=controls[i]
        if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then
            b.fn()
            return
        end
    end
    if state.screen=="editor" and not panel
        and not love.keyboard.isDown("space")
        and paint:beginTransformDrag(state,view,preferences,scale,W,H,rx,ry) then
        return
    end
    if state.screen=="editor" and not panel
        and not love.keyboard.isDown("space")
        and paint:beginSelection(state,view,preferences,scale,W,H,rx,ry) then
        if state.active_tool=="magic_wand" then notice(paint.status) end
        return
    end
    if state.screen=="editor" and not panel
        and not love.keyboard.isDown("space")
        and paint:press(state,view,preferences,scale,W,H,rx,ry,opacity) then
        if state.active_tool=="eyedropper" then
            local c=state.color
            colors:set_rgb(c[1],c[2],c[3])
        elseif state.active_tool=="bucket" then
            notice(paint.status)
        end
        return
    end
    if state.screen=="editor" and not panel and love.keyboard.isDown("space") then
        view:begin_pan(x,y)
    elseif panel then panel=nil;state.active_panel=nil;layer_blend_open=false end
end
function love.mousemoved(rx,ry,dx,dy)
    if color_drag and panel=="color" and color_float then
        color_position={
            x=rx/scale-color_drag.dx,
            y=ry/scale-color_drag.dy
        }
    end
    if color_resize and panel=="color" and color_float then
        color_size={
            w=math.max(370,math.min(W-96,
                color_resize.w+rx/scale-color_resize.mx)),
            h=math.max(490,math.min(H-119,
                color_resize.h+ry/scale-color_resize.my))
        }
    end
    if color_slider_drag and panel=="color" then
        local d=color_slider_drag
        d.change((rx/scale-d.x)/d.w)
    end
    if color_wheel_drag and panel=="color" then
        local d=color_wheel_drag
        d.action(rx/scale,ry/scale,d.x,d.y,d.r)
    end
    if brush_drag and panel=="brush" then
        local fraction=math.max(0,math.min(1,
            (rx/scale-brush_drag.x)/brush_drag.w))
        if brush_drag.kind=="size" then
            state:set_brush_size(math.max(0.1,
                math.floor(fraction*1000+0.5)/10))
        else opacity=math.floor(fraction*100+0.5) end
    end
    if layer_row_drag and panel=='layer' then
        local d=layer_row_drag
        local xx,yy=rx/scale,ry/scale
        if (xx-d.startX)^2+(yy-d.startY)^2>=8*8 then d.moved=true end
        if d.moved then
            d.targetId=nil
            for _,rect in ipairs(layer_row_targets) do
                if xx>=rect.x and xx<=rect.x+rect.w
                    and yy>=rect.y and yy<=rect.y+rect.h then
                    d.targetId=rect.id
                    break
                end
            end
        end
    end
    if drag_layer and panel=="layer" then
        layer_position={x=rx/scale-drag_layer.dx,y=ry/scale-drag_layer.dy}
    end
    if drag_layer_resize and panel=="layer" then
        local g=drag_layer_resize
        layer_size={
            w=math.max(310,math.min(W-110,g.w+rx/scale-g.start_x)),
            h=math.max(360,math.min(H-125,g.h+ry/scale-g.start_y))
        }
    end
    if drag_opacity and panel=="layer" then
        local p=drag_opacity
        state:set_layer_opacity(p.id,math.floor(
            math.max(0,math.min(1,(rx/scale-p.x)/p.w))*100+0.5))
    end
    if drag_dimension and state.modal=="new_canvas" then
        local value=math.floor(1+math.max(0,math.min(1,
            (rx/scale-drag_dimension.sx)/drag_dimension.width))*8191+0.5)
        if drag_dimension.key=="width" then current_width=tostring(value)
        else current_height=tostring(value) end
    end
    if view.is_panning then
        if love.keyboard.isDown("space") then view:pan_to(rx/scale,ry/scale)
        else view:end_pan() end
    end
    if paint.transformDrag then
        paint:moveTransform(state,view,preferences,scale,W,H,rx,ry)
    end
    if paint.selectionDrag then
        paint:moveSelection(state,view,preferences,scale,W,H,rx,ry)
    end
    if paint.stroke then paint:move(state,view,preferences,scale,W,H,rx,ry) end
end
function love.mousereleased(rx,ry,button)
    if button~=1 then return end
    if layer_row_drag then
        local drag=layer_row_drag
        layer_row_drag=nil
        if drag.moved and drag.targetId and drag.targetId~=drag.id
            and state.screen=='editor' and panel=='layer' then
            paint:reorderLayer(state,drag.id,drag.targetId)
            notice(paint.status)
        end
    end
    paint:finishTransformDrag()
    paint:finish(false)
    if paint.selectionDrag then
        paint:finishSelection(state,view,preferences,scale,W,H,rx,ry)
        notice(paint.status)
    end
    if color_swatch_drag and panel=="color" and colors.palette_mode then
        local d=color_swatch_drag
        local xx,yy=rx/scale,ry/scale
        local dx=xx-d.initial_x
        local dy=yy-d.initial_y
        if dx*dx+dy*dy>=12*12 then
            local col=math.floor((xx-d.grid_x)/d.step)
            local row=math.floor((yy-d.grid_y)/40)
            local target=row*d.columns+col+1
            if col>=0 and col<d.columns and row>=0
                and target>=1 and target<=#colors:colors() then
                colors:move_color(d.from,target)
            end
        end
    end
    color_swatch_drag=nil
    drag_dimension=nil
    color_drag=nil
    color_resize=nil
    color_slider_drag=nil
    color_wheel_drag=nil
    brush_drag=nil
    drag_layer=nil
    drag_layer_resize=nil
    drag_opacity=nil
    view:end_pan()
    if layer_press then
        if state.screen=="editor" and panel=="layer" then
            if love.timer.getTime()-layer_press.started>=0.55 then
                state:toggle_layer_solo(layer_press.id)
            else
                state:toggle_layer_visibility(layer_press.id)
            end
        end
        layer_press=nil
    end
end
function love.wheelmoved(dx,dy)
    if state.screen=="gallery" and state.modal=="new_canvas" then
        local row_h=math.min(39,math.max(25,(H-250)/#presets))
        local last=80+128+#presets*row_h
        gallery_scroll=math.max(0,math.min(
            math.max(0,last-(H-42)+6),gallery_scroll-dy*28))
    elseif state.screen=='editor' and panel=='layer' then
        local hh=layer_size and layer_size.h or 468
        local visible=math.max(1,math.floor((hh-269)/52))
        layer_scroll=math.max(0,math.min(math.max(0,#state.layers-visible),
            layer_scroll-math.floor(dy*1.5+(dy>=0 and 0.5 or -0.5))))
    elseif state.screen=="editor" and panel=="brush" then
        local entries=brush_tab=="Basic" and BrushCatalog.search(brush_search) or {}
        local bw=math.min(565,W-math.min(185,math.max(66,W*0.16))-34)
        local bh=math.min(H-107,660)
        local rows_h=math.max(32,bh-46-34-1-
            (brush_search_active and 33 or 24)-2)
        local maximum=math.max(0,#entries*43-rows_h)
        brush_scroll=math.max(0,math.min(maximum,brush_scroll-dy*39))
    elseif state.screen=="gallery" and not gallery_dialog and not gallery_menu then
        local items=gallery:items()
        local columns=math.max(1,math.floor((W-30+28)/(200+28)))
        local rows=math.ceil(#items/columns)
        local maximum=math.max(0,rows*228-(H-58-109))
        gallery_item_scroll=math.max(0,math.min(maximum,
            gallery_item_scroll-dy*72))
    elseif state.screen=="editor" and not panel then
        if love.keyboard.isDown("lshift","rshift") then
            view:rotate_wheel(dy)
        else
            local x,y=pointer()
            local left=preferences.tool_position=="left" and 62 or 0
            local right=preferences.tool_position=="right" and 75 or 34
            local cx=left+(W-left-right)/2
            local cy=28+(H-111)/2
            view:zoom_at(preferences:wheel_steps(dy),x,y,cx,cy)
        end
    end
end
function love.textinput(t)
    if state.screen=="editor" and panel=="color" and color_dialog then
        local limit=color_dialog=="hex" and 7 or 64
        local content=color_input_replace and t or color_input..t
        if #content<=limit then
            color_input=content
            color_input_replace=false
        end
        return
    end
    if state.screen=="editor" and panel=="brush" and brush_search_active then
        if #brush_search+#t<=64 then
            brush_search=brush_search..t
            brush_scroll=0
        end
        return
    end
    if gallery_dialog and state.screen=="gallery" then
        if t~="" and #gallery_input+#t<=100 then
            gallery_input=gallery_input_replace and t or gallery_input..t
            gallery_input_replace=false
        end
        return
    end
    if state.screen~="gallery" or state.modal~="new_canvas" or not focus then return end
    if not t:match("^%d+$") then return end
    if focus=="width" then
        current_width=(input_replace and t or current_width..t):sub(-5)
    elseif focus=="height" then
        current_height=(input_replace and t or current_height..t):sub(-5)
    end
    preset_selected=0
    active_dpi=nil
    input_replace=false
end
function love.keypressed(key)
    if key=="f12" then capture_requested=true;return end
    if paint:transformKey(state,key) then notice(paint.status);return end
    if key=="escape" and paint.job then
        paint:cancelJob()
        notice(paint.status)
        return
    end
    if key=="escape" and paint.selectionDrag then
        paint.selectionDrag=nil
        notice("Seleção cancelada")
        return
    end
    if paint:key(state,key) then
        if key=='s' and persistence_enabled and paint.status:match('^Salvo:') then
            persist_gallery()
        end
        notice(paint.status)
        return
    end
    if state.screen=="editor" and panel=="color" and color_dialog then
        if key=="escape" then color_dialog=nil
        elseif key=="backspace" then
            if color_input_replace then color_input=""
            else
                local index=utf8.offset(color_input,-1)
                color_input=index and color_input:sub(1,index-1) or ""
            end
            color_input_replace=false
        elseif key=="return" or key=="kpenter" then
            local ok=pcall(function()
                if color_dialog=="hex" then
                    colors:set_hex(color_input)
                    state:set_color(colors.current[1],
                        colors.current[2],colors.current[3])
                    local h=colors:hsb()
                    picker_hue=(h%360)/360
                elseif color_dialog=="new_palette" then
                    local id=colors:create_palette(color_input)
                    color_palette_page=math.floor((id-1)/3)
                else
                    colors:rename_palette(colors.active_palette,color_input)
                end
            end)
            if ok then color_dialog=nil
            else notice("Invalid color or palette name.") end
        end
        return
    end
    if state.screen=="editor" and panel=="brush" and brush_search_active then
        if key=="backspace" then
            local index=utf8.offset(brush_search,-1)
            brush_search=index and brush_search:sub(1,index-1) or ""
            brush_scroll=0
            return
        elseif key=="escape" then
            brush_search_active=false
            brush_search=""
            brush_scroll=0
            return
        end
    end
    if gallery_dialog and state.screen=="gallery" then
        if key=="escape" then gallery_dialog=nil
        elseif key=="backspace" then
            if gallery_input_replace then gallery_input=""
            else
                local index=utf8.offset(gallery_input,-1)
                gallery_input=index and gallery_input:sub(1,index-1) or ""
            end
            gallery_input_replace=false
        elseif key=="return" or key=="kpenter" then
            if gallery_input=="" or #gallery_input>100 or gallery_input:match("^%s*$") then
                notice("Enter a valid folder name.")
            else
                if gallery_dialog.mode=="rename" then
                    gallery:rename(gallery_dialog.id,gallery_input)
                else gallery:add_folder(gallery_input) end
                gallery_dialog=nil
                persist_gallery()
            end
        end
        return
    end
    if state.modal=="new_canvas" then
        if key=="escape" then state:cancel_new_canvas();focus=nil;return end
        if key=="backspace" then
            if focus=="width" then current_width=input_replace and "" or current_width:sub(1,-2)
            elseif focus=="height" then current_height=input_replace and "" or current_height:sub(1,-2) end
            input_replace=false
            return
        end
        if key=="tab" then
            focus=focus=="width" and "height" or "width"
            input_replace=true
            return
        end
        if key=="return" or key=="kpenter" then
            local ww,hh=tonumber(current_width),tonumber(current_height)
            if ww and hh and ww>=1 and hh>=1 and ww<=16384 and hh<=16384
            and ww==math.floor(ww) and hh==math.floor(hh) then
                finish_new_canvas(ww,hh)
            else notice("Dimensões inválidas") end
            return
        end
    end
    if key=="escape" then
        if state.screen=="editor" and not panel and paint.doc
            and paint.doc.selection then
            paint:clearSelection()
            notice(paint.status)
            return
        end
        view:end_pan()
        if layer_blend_open then layer_blend_open=false
        elseif panel then panel=nil;state.active_panel=nil
        elseif state.screen=="editor" then set_panel("back")
        elseif state.screen=="gallery" then
            if gallery_menu then gallery_menu=nil
            elseif gallery_selecting then
                gallery_selecting=false;gallery:clear_selection()
            elseif not gallery:back() then state.screen="title"
            else gallery_item_scroll=0 end
        else love.event.quit() end
    elseif state.screen=="editor" then
        if key=="b" then state:set_tool("brush")
        elseif key=="e" then state:set_tool("eraser")
        elseif key=="l" then set_panel("layer")
        elseif key=="c" then set_panel("color")
        elseif key=="[" then state:set_brush_size(math.max(0.1,state.brush_size-1))
        elseif key=="]" then state:set_brush_size(math.min(1000,state.brush_size+1))
        end
    end
end
local function click_control(key)
    local b
    for i=#controls,1,-1 do
        if controls[i].key==key then b=controls[i];break end
    end
    assert(b,"UI e2e: controle indisponível: "..key)
    local x=(b.x+b.w/2)*scale
    local y=(b.y+b.h/2)*scale
    -- Mouse callbacks that use love.mouse.getPosition must see this cursor.
    love.mouse.setPosition(x,y)
    love.mousepressed(x,y,1)
    love.mousereleased(x,y,1)
end

local function gallery_e2e_update()
    if gallery_e2e_stage==0 then
        click_control("brush")
        assert(state.screen=="gallery")
        gallery_e2e_stage=1
    elseif gallery_e2e_stage==1 then
        -- Screenshot inspection revealed overlapping header hitboxes.
        local header={"plus","settings","play","material","more",
            "gallery_select","gallery_edit"}
        local slots={}
        for _,name in ipairs(header) do
            for _,control in ipairs(controls) do
                if control.key==name then
                    slots[#slots+1]=control;break
                end
            end
        end
        assert(#slots==#header,"UI e2e: missing Gallery header control")
        for i=1,#slots do for j=i+1,#slots do
            local x1,y1=slots[i],slots[j]
            assert(x1.x+x1.w<=y1.x or y1.x+y1.w<=x1.x,
                "UI e2e: overlapping Gallery header hitboxes")
        end end
        click_control("plus")
        assert(gallery_menu=="new")
        gallery_e2e_stage=2
    elseif gallery_e2e_stage==2 then
        click_control("new_folder")
        assert(gallery_dialog and gallery_dialog.mode=="create")
        gallery_e2e_stage=3
    elseif gallery_e2e_stage==3 then
        for character in ("Projects"):gmatch(".") do love.textinput(character) end
        click_control("folder_confirm")
        assert(not gallery_dialog and #gallery:items()==1)
        assert(gallery:get(1).name=="Projects")
        gallery_e2e_stage=4
    elseif gallery_e2e_stage==4 then
        click_control("folder_1")
        assert(gallery.current_folder==1)
        gallery_e2e_stage=5
    elseif gallery_e2e_stage==5 then
        click_control("plus")
        gallery_e2e_stage=6
    elseif gallery_e2e_stage==6 then
        click_control("new_canvas")
        assert(state.modal=="new_canvas")
        gallery_e2e_stage=7
    elseif gallery_e2e_stage==7 then
        click_control("OK")
        assert(state.screen=="editor" and gallery:total_artworks()==1)
        assert(gallery:get(2).parent==1)
        gallery_e2e_stage=8
    elseif gallery_e2e_stage==8 then
        click_control("back")
        assert(panel=="back")
        gallery_e2e_stage=9
    elseif gallery_e2e_stage==9 then
        click_control("Back to My Gallery")
        assert(state.screen=="gallery" and gallery.current_folder==1)
        gallery_e2e_stage=10
    elseif gallery_e2e_stage==10 then
        click_control("gallery_select")
        assert(gallery_selecting)
        gallery_e2e_stage=11
    elseif gallery_e2e_stage==11 then
        click_control("artwork_2")
        assert(#gallery:selection()==1)
        gallery_e2e_stage=12
    elseif gallery_e2e_stage==12 then
        click_control("Move")
        assert(gallery_menu=="move")
        gallery_e2e_stage=13
    elseif gallery_e2e_stage==13 then
        click_control("move_to_0")
        assert(gallery:get(2).parent==0 and not gallery_selecting)
        gallery_e2e_stage=14
    elseif gallery_e2e_stage==14 then
        click_control("back")
        assert(gallery.current_folder==0)
        gallery_e2e_stage=15
    elseif gallery_e2e_stage==15 then
        click_control("artwork_2")
        assert(state.screen=="editor" and state.document.width==1000)
        gallery_e2e_stage=16
    elseif gallery_e2e_stage==16 then
        click_control("back")
        gallery_e2e_stage=17
    elseif gallery_e2e_stage==17 then
        click_control("Back to My Gallery")
        assert(state.screen=="gallery")
        gallery_e2e_stage=18
    elseif gallery_e2e_stage==18 then
        click_control("folder_1")
        assert(gallery.current_folder==1)
        gallery_e2e_stage=19
    elseif gallery_e2e_stage==19 then
        click_control("gallery_edit")
        assert(gallery_dialog and gallery_dialog.mode=="rename")
        gallery_e2e_stage=20
    elseif gallery_e2e_stage==20 then
        for character in ("Ideas"):gmatch(".") do love.textinput(character) end
        click_control("folder_confirm")
        assert(gallery:get(1).name=="Ideas" and gallery_dialog==nil)
        gallery_e2e_stage=21
    elseif gallery_e2e_stage==21 then
        click_control("back")
        assert(gallery.current_folder==0)
        for i=1,24 do
            gallery:add_artwork(900,600,"Scroll test "..i)
        end
        gallery_e2e_stage=22
    elseif gallery_e2e_stage==22 then
        love.wheelmoved(0,-6)
        assert(gallery_item_scroll>0,
            "UI e2e: gallery list did not scroll")
        gallery_e2e_stage=23
    elseif gallery_e2e_stage==23 then
        local key=nil
        for i=#controls,1,-1 do
            if controls[i].key and controls[i].key:match("^artwork_%d+$") then
                key=controls[i].key
                break
            end
        end
        assert(key,"UI e2e: no visible thumbnail after scroll")
        click_control(key)
        assert(state.screen=="editor",
            "UI e2e: scrolled thumbnail is not clickable")
        gallery_e2e_stage=24
    else
        print("PASS: My Gallery E2E (folders, move, rename, scroll and reopen)")
        love.event.quit(0)
    end
end

local function settings_e2e_update()
    if settings_e2e_stage==0 then
        click_control("brush")
        assert(state.screen=="gallery")
    elseif settings_e2e_stage==1 then
        click_control("plus")
        assert(gallery_menu=="new")
    elseif settings_e2e_stage==2 then
        click_control("new_canvas")
        assert(state.modal=="new_canvas")
    elseif settings_e2e_stage==3 then
        click_control("OK")
        assert(state.screen=="editor")
        assert(preferences:rail_x(W)==0)
    elseif settings_e2e_stage==4 then
        click_control("back")
        assert(panel=="back")
    elseif settings_e2e_stage==5 then
        click_control("back_settings")
        assert(panel=="settings")
    elseif settings_e2e_stage==6 then
        click_control("pref_position_popup")
        assert(preferences.tool_position=="popup")
    elseif settings_e2e_stage==7 then
        click_control("pref_columns_1")
        assert(preferences.popup_columns==1)
    elseif settings_e2e_stage==8 then
        click_control("pref_show_labels")
        click_control("pref_invert_wheel")
        assert(not preferences.show_tool_labels and preferences.invert_wheel)
    elseif settings_e2e_stage==9 then
        click_control("check")
        assert(panel==nil)
    elseif settings_e2e_stage==10 then
        click_control("transform")
        assert(panel=="tools")
    elseif settings_e2e_stage==11 then
        local n=0
        for _,b in ipairs(controls) do
            if b.key and b.key:match("^tool_choice_") then n=n+1 end
        end
        assert(n==15,"UI e2e: expected all 15 tools in 1-column popup")
        click_control("tool_choice_bucket")
        assert(state.active_tool=="bucket" and not panel)
    elseif settings_e2e_stage==12 then
        love.wheelmoved(0,1)
        assert(view.zoom<1,"UI e2e: inverted mouse wheel failed")
    elseif settings_e2e_stage==13 then
        click_control("back")
    elseif settings_e2e_stage==14 then
        click_control("back_settings")
        assert(panel=="settings")
    elseif settings_e2e_stage==15 then
        click_control("pref_position_right")
        assert(preferences.tool_position=="right")
    elseif settings_e2e_stage==16 then
        local found=false
        for _,b in ipairs(controls) do
            if b.key=="bucket" and b.x>W-65 then found=true end
        end
        assert(found,"UI e2e: right-side tool rail not rendered")
        click_control("pref_show_labels")
        assert(preferences.show_tool_labels)
    elseif settings_e2e_stage==17 then
        click_control("pref_position_popup")
        assert(preferences.tool_position=="popup")
    elseif settings_e2e_stage==18 then
        click_control("pref_columns_3")
        assert(preferences.popup_columns==3)
    elseif settings_e2e_stage==19 then
        click_control("check")
        assert(panel==nil)
    elseif settings_e2e_stage==20 then
        click_control("transform")
        assert(panel=="tools")
        local pw,ph=preferences:panel_size(W,H)
        assert(pw<450 and ph<500,"UI e2e: 3-column popup incorrect size")
    elseif settings_e2e_stage==21 then
        click_control("tool_choice_text")
        assert(state.active_tool=="text" and panel==nil)
    else
        print("PASS: Settings E2E (rail Left/Right/Popup, columns, labels, inverted zoom)")
        love.event.quit(0)
    end
    settings_e2e_stage=settings_e2e_stage+1
end

local function color_e2e_update()
    if color_e2e_stage==0 then
        click_control("brush")
        assert(state.screen=="gallery")
    elseif color_e2e_stage==1 then
        click_control("plus")
        assert(gallery_menu=="new")
    elseif color_e2e_stage==2 then
        click_control("new_canvas")
        assert(state.modal=="new_canvas")
    elseif color_e2e_stage==3 then
        click_control("OK")
        assert(state.screen=="editor")
    elseif color_e2e_stage==4 then
        click_control("color")
        assert(panel=="color" and colors:hex()=="#000000")
    elseif color_e2e_stage==5 then
        click_control("color_hex")
        assert(color_dialog=="hex")
    elseif color_e2e_stage==6 then
        for ch in ("#33AA55"):gmatch(".") do love.textinput(ch) end
        click_control("color_dialog_confirm")
        assert(colors:hex()=="#33AA55"
            and state.color[1]==51 and state.color[2]==170)
    elseif color_e2e_stage==7 then
        click_control("color_rgb_toggle")
        assert(colors.rgb_mode)
    elseif color_e2e_stage==8 then
        click_control("color_slider_r")
        assert(colors.current[1]>=120 and colors.current[1]<=135,
            "Color UI e2e: RGB slider not applied")
    elseif color_e2e_stage==9 then
        click_control("color_mode_palette")
        assert(colors.palette_mode)
    elseif color_e2e_stage==10 then
        click_control("color_new_palette")
        assert(color_dialog=="new_palette")
    elseif color_e2e_stage==11 then
        for ch in ("Character"):gmatch(".") do love.textinput(ch) end
        click_control("color_dialog_confirm")
        assert(#colors:palettes_list()==2 and
            colors:palettes_list()[2].name=="Character")
    elseif color_e2e_stage==12 then
        click_control("color_add_swatch")
        assert(#colors:colors()==1)
    elseif color_e2e_stage==13 then
        click_control("color_hex")
        assert(color_dialog=="hex")
    elseif color_e2e_stage==14 then
        for ch in ("#FF0000"):gmatch(".") do love.textinput(ch) end
        click_control("color_dialog_confirm")
        assert(colors:hex()=="#FF0000")
    elseif color_e2e_stage==15 then
        click_control("color_add_swatch")
        assert(#colors:colors()==2 and colors:colors()[2][1]==255)
    elseif color_e2e_stage==16 then
        local from,to
        for _,control in ipairs(controls) do
            if control.key=="color_swatch_1" then from=control
            elseif control.key=="color_swatch_2" then to=control end
        end
        assert(from and to,"Color E2E: swatch move hitboxes missing")
        local mx=(from.x+from.w/2)*scale
        local my=(from.y+from.h/2)*scale
        local tx=(to.x+to.w/2)*scale
        local ty=(to.y+to.h/2)*scale
        love.mouse.setPosition(mx,my)
        love.mousepressed(mx,my,1)
        love.mousemoved(tx,ty,tx-mx,ty-my)
        love.mousereleased(tx,ty,1)
        assert(colors:colors()[1][1]==255
            and colors:colors()[2][1]~=255,
            "Color E2E: swatch drag failed to reorder")
    elseif color_e2e_stage==17 then
        click_control("color_rename_palette")
        assert(color_dialog=="rename_palette")
    elseif color_e2e_stage==18 then
        for ch in ("Warm tones"):gmatch(".") do love.textinput(ch) end
        click_control("color_dialog_confirm")
        assert(colors:palettes_list()[2].name=="Warm tones")
    elseif color_e2e_stage==19 then
        click_control("color_new_palette")
    elseif color_e2e_stage==20 then
        for ch in ("Sketch"):gmatch(".") do love.textinput(ch) end
        click_control("color_dialog_confirm")
        assert(colors.active_palette==3)
    elseif color_e2e_stage==21 then
        click_control("color_new_palette")
    elseif color_e2e_stage==22 then
        for ch in ("Highlights"):gmatch(".") do love.textinput(ch) end
        click_control("color_dialog_confirm")
        assert(colors.active_palette==4 and color_palette_page==1)
    elseif color_e2e_stage==23 then
        click_control("color_palette_prev")
        assert(color_palette_page==0)
    elseif color_e2e_stage==24 then
        click_control("color_palette_next")
        assert(color_palette_page==1)
    elseif color_e2e_stage==25 then
        click_control("color_float_toggle")
        assert(color_float)
    elseif color_e2e_stage==26 then
        local b
        for _,c in ipairs(controls) do
            if c.key=="color_move_bar" then b=c;break end
        end
        assert(b,"Color window drag hitbox missing")
        local mx=(b.x+b.w/2)*scale
        local my=(b.y+b.h/2)*scale
        love.mouse.setPosition(mx,my)
        love.mousepressed(mx,my,1)
        love.mousemoved(mx+22*scale,my+14*scale,22*scale,14*scale)
        love.mousereleased(mx+22*scale,my+14*scale,1)
        assert(color_position and color_position.x>290,
            "Color window not moved")
    elseif color_e2e_stage==27 then
        local b
        for _,c in ipairs(controls) do
            if c.key=="color_resize" then b=c;break end
        end
        assert(b,"Color resize grip hitbox missing")
        local mx=(b.x+b.w/2)*scale
        local my=(b.y+b.h/2)*scale
        love.mouse.setPosition(mx,my)
        love.mousepressed(mx,my,1)
        love.mousemoved(mx-25*scale,my-22*scale,-25*scale,-22*scale)
        love.mousereleased(mx-25*scale,my-22*scale,1)
        assert(color_size and color_size.w<520 and color_size.h<635,
            "Color window not resized")
    elseif color_e2e_stage==28 then
        click_control("check")
        assert(panel==nil)
    else
        print("PASS: Color E2E (HEX, RGB, swatch reorder, palette pages, floating UI)")
        love.event.quit(0)
    end
    color_e2e_stage=color_e2e_stage+1
end

function love.focus(focused)
    if not focused then
        paint:finish(true)
        paint:finishTransformDrag()
    end
end
-- Teste da interface real em dois processos: gravar, reiniciar e reabrir.
-- O CI chama uma vez com 'create' e depois com 'check'.
local function gallery_persist_update()
    if gallery_persist_e2e=='create' then
        if gallery_persist_stage==0 then
            assert(gallery:total_artworks()==0,'CI precisa de galeria vazia')
            click_control('brush')
        elseif gallery_persist_stage==1 then
            click_control('plus')
        elseif gallery_persist_stage==2 then
            click_control('new_folder')
        elseif gallery_persist_stage==3 then
            for character in ('Projetos'):gmatch('.') do love.textinput(character) end
            click_control('folder_confirm')
            assert(gallery:get(1).name=='Projetos','pasta não criada')
        elseif gallery_persist_stage==4 then
            click_control('folder_1')
        elseif gallery_persist_stage==5 then
            click_control('plus')
        elseif gallery_persist_stage==6 then
            click_control('new_canvas')
        elseif gallery_persist_stage==7 then
            click_control('OK')
            assert(state.screen=='editor' and active_artwork_id==2,
                'arquivo de obra não foi criado')
        elseif gallery_persist_stage==8 then
            state:set_brush_size(15)
            state:set_color(210,30,55)
            local left=preferences.tool_position=='left' and 62 or 0
            local right=preferences.tool_position=='right' and 75 or 34
            local x=(left+(W-left-right)/2)*scale
            local y=(62+(H-160)/2)*scale
            love.mouse.setPosition(x,y)
            love.mousepressed(x,y,1)
            love.mousereleased(x,y,1)
            local doc=paint.doc
            assert(doc and next(doc.layers[doc.sel].tiles),'pixels não foram pintados')
        elseif gallery_persist_stage==9 then
            click_control('back')
        elseif gallery_persist_stage==10 then
            click_control('Back to My Gallery')
            assert(state.screen=='gallery','não voltou à galeria')
        else
            local loaded=GalleryStorage.load()
            assert(loaded:get(1).type=='folder' and loaded:get(2).type=='artwork',
                'catálogo não persistiu')
            local doc=assert(GalleryStorage.loadArtwork(2),'NPNT da obra ausente')
            assert(next(doc.layers[doc.sel].tiles),'pixel não salvo no NPNT')
            local bytes=assert(GalleryStorage.thumbnailBytes(2),'prévia PNG ausente')
            local png=love.image.newImageData(love.filesystem.newFileData(bytes,'preview.png'))
            assert(png:getWidth()==160 and png:getHeight()==160,'prévia inválida')
            print('PASS: galeria persistente E2E: pintura, autosave e miniatura')
            love.event.quit(0)
            return
        end
    else
        if gallery_persist_stage==0 then
            assert(gallery:get(1).name=='Projetos' and gallery:get(2).parent==1,
                'galeria não foi restaurada após reiniciar LÖVE')
            click_control('brush')
        elseif gallery_persist_stage==1 then
            click_control('artwork_2')
            assert(state.screen=='editor' and active_artwork_id==2,
                'artwork não abriu depois de reiniciar')
        elseif gallery_persist_stage==2 then
            local layer=paint.doc.layers[paint.doc.sel]
            assert(next(layer.tiles),'obra perdeu seus pixels após reinício')
            click_control('back')
        elseif gallery_persist_stage==3 then
            click_control('editor_export_png')
            assert(love.filesystem.getInfo('exports/obra-2.png'),
                'botão de exportação não produziu PNG')
            print('PASS: galeria persistente E2E: reabertura e exportação PNG pelo botão')
            love.event.quit(0)
            return
        end
    end
    gallery_persist_stage=gallery_persist_stage+1
end

function love.update()
    build_next_gallery_thumbnail()
    if gallery_persist_e2e and #controls>0 then
        gallery_persist_update()
        return
    end
    local result=paint:update()
    if result then notice(result) end
    if smoke and capture_done then
        if capture_error then error("Screenshot: "..capture_error) end
        love.event.quit(0)
    end
    -- Each stage runs after a draw; hitboxes represent the visible UI.
    if color_e2e and #controls>0 then
        color_e2e_update()
        return
    end
    if settings_e2e and #controls>0 then
        settings_e2e_update()
        return
    end
    if gallery_e2e and #controls>0 then
        gallery_e2e_update()
        return
    end
    if layer_e2e and #controls>0 then
        if layer_e2e_stage==0 then
            -- Arraste pela interface visível, sem chamar Layers.move diretamente.
            local rows={}
            for _,ctrl in ipairs(controls) do
                if ctrl.key=='select_layer' then rows[#rows+1]=ctrl end
            end
            table.sort(rows,function(a,b) return a.y<b.y end)
            assert(#rows==3,'UI v0.26: três linhas de camada esperadas')
            local src,dst=rows[1],rows[3]
            local x=(src.x+src.w/2)*scale
            local y=(src.y+src.h/2)*scale
            local tx=(dst.x+dst.w/2)*scale
            local ty=(dst.y+dst.h/2)*scale
            local activeId=state.layers[3].id
            love.mouse.setPosition(x,y)
            love.mousepressed(x,y,1)
            love.mouse.setPosition(tx,ty)
            love.mousemoved(tx,ty,tx-x,ty-y)
            love.mousereleased(tx,ty,1)
            assert(state.layers[1].id==activeId,
                'UI v0.26: drag-and-drop não alterou ordem real')
            assert(#paint.doc.history.undo==1,'UI v0.26: drag deve gerar um undo')
            layer_e2e_stage=1
        elseif layer_e2e_stage==1 then
            local activeId=state.active_layer_id
            click_control('layer_move_up')
            assert(state.layers[2].id==activeId,
                'UI v0.26: botão de subir camada não moveu')
            layer_e2e_stage=2
        elseif layer_e2e_stage==2 then
            state:add_layer()
            love.wheelmoved(0,-1)
            assert(layer_scroll>0,'UI v0.26: rolagem não mudou a lista')
            assert(#state.layers==4,'UI v0.26: adicionar camada falhou')
            layer_e2e_stage=3
        else
            print('PASS: UI LÖVE v0.26: drag/drop, setas e scroll de camadas')
            love.event.quit(0)
        end
        return
    end
    if not e2e or #controls==0 then return end
    if e2e_stage==0 then
        assert(state.screen=="title")
        click_control("brush") -- My Gallery
        assert(state.screen=="gallery")
        e2e_stage=1
    elseif e2e_stage==1 then
        click_control("plus")
        assert(gallery_menu=="new")
        e2e_stage=1.5
    elseif e2e_stage==1.5 then
        click_control("new_canvas")
        assert(state.modal=="new_canvas")
        e2e_stage=2
    elseif e2e_stage==2 then
        click_control("increase_width")
        assert(current_width=="1001","UI e2e: incremento inicial da largura falhou")
        click_control("preset_10")
        assert(current_width=="1754" and current_height=="1240",
            "UI e2e: preset A4 não aplicado")
        click_control("dpi_a4")
        assert(current_width=="3508" and current_height=="2480",
            "UI e2e: DPI A4 não mudou dimensões")
        click_control("input_width")
        for ch in ("900"):gmatch(".") do love.textinput(ch) end
        click_control("input_height")
        for ch in ("600"):gmatch(".") do love.textinput(ch) end
        click_control("OK")
        assert(state.screen=="editor" and state.document.width==900
            and state.document.height==600,"UI e2e: nova tela com dimensões erradas")
        e2e_stage=3
    elseif e2e_stage==3 then
        click_control("layer")
        assert(panel=="layer","UI e2e: painel de camadas não abriu")
        e2e_stage=4
    elseif e2e_stage==4 then
        click_control("visibility")
        assert(not state.layers[1].visible,"UI e2e: visibilidade não alterou")
        love.keypressed("escape")
        assert(panel==nil,"UI e2e: painel não fechou")
        love.wheelmoved(0,1)
        assert(view.zoom>1,"UI e2e: zoom por roda não respondeu")
        e2e_stage=5
    elseif e2e_stage==5 then
        click_control("view")
        assert(panel=="view","UI e2e: View Menu não abriu")
        e2e_stage=6
    elseif e2e_stage==6 then
        click_control("view_grid")
        assert(visual.grid,"UI e2e: grade não ativou")
        click_control("view_reference")
        assert(visual.reference,"UI e2e: janela de referência não ativou")
        click_control("view_pixelated")
        assert(visual.interpolation=="pixelated",
            "UI e2e: interpolação não alternou")
        click_control("view_grid_settings")
        assert(panel=="grid_settings","UI e2e: Grid Settings não abriu")
        e2e_stage=7
    elseif e2e_stage==7 then
        click_control("increase_grid1")
        assert(visual.grid1==72,"UI e2e: intervalo da grade não foi alterado")
        click_control("Reset Grid")
        assert(visual.grid1==64 and visual.grid2==256,
            "UI e2e: Reset Grid não restaurou os intervalos")
        e2e_stage=8
    elseif e2e_stage==8 then
        love.keypressed("escape")
        click_control("layer")
        assert(panel=="layer","UI e2e: retorno ao painel Layer falhou")
        e2e_stage=9
    elseif e2e_stage==9 then
        click_control("layer_add")
        assert(#state.layers==2,"UI e2e: Add Layer falhou")
        e2e_stage=10
    elseif e2e_stage==10 then
        click_control("layer_clipping")
        click_control("layer_alpha_lock")
        assert(state:active_layer().clipping and state:active_layer().alpha_lock,
            "UI e2e: clipping ou alpha lock falhou")
        click_control("layer_opacity")
        assert(state:active_layer().opacity<100,
            "UI e2e: controle de opacidade falhou")
        click_control("layer_blend")
        assert(layer_blend_open,"UI e2e: lista de blending não abriu")
        e2e_stage=11
    elseif e2e_stage==11 then
        click_control("blend_Multiply")
        assert(state:active_layer().blending=="Multiply",
            "UI e2e: modo Multiply não selecionado")
        assert(not layer_blend_open)
        e2e_stage=12
    elseif e2e_stage==12 then
        click_control("background_transparent_dark")
        assert(state.background_mode=="transparent_dark",
            "UI e2e: transparência de fundo não alterada")
        e2e_stage=13
    elseif e2e_stage==13 then
        -- Drive actual mouse movement through the floating-window grip.
        local resize
        for i=#controls,1,-1 do
            if controls[i].key=="layer_resize" then
                resize=controls[i];break
            end
        end
        assert(resize,"UI e2e: resize grip missing")
        local mx=(resize.x+resize.w/2)*scale
        local my=(resize.y+resize.h/2)*scale
        love.mouse.setPosition(mx,my)
        love.mousepressed(mx,my,1)
        love.mousemoved(mx-40*scale,my-30*scale,-40*scale,-30*scale)
        love.mousereleased(mx-40*scale,my-30*scale,1)
        assert(layer_size and layer_size.w<408 and layer_size.h<468,
            "UI e2e: resize da janela Layer falhou")
        e2e_stage=14
    elseif e2e_stage==14 then
        love.keypressed("escape")
        click_control("settings")
        assert(panel=="brush","UI e2e: painel Brush não abriu")
        e2e_stage=15
    elseif e2e_stage==15 then
        click_control("brush_search_toggle")
        assert(brush_search_active and brush_search=="")
        e2e_stage=16
    elseif e2e_stage==16 then
        for letter in ("Air"):gmatch(".") do love.textinput(letter) end
        assert(#BrushCatalog.search(brush_search)==4)
        e2e_stage=17
    elseif e2e_stage==17 then
        click_control("brush_preset_9")
        assert(selected_brush==9 and state.brush_size==8)
        e2e_stage=18
    elseif e2e_stage==18 then
        click_control("brush_size_slider")
        click_control("brush_opacity_slider")
        assert(state.brush_size>10 and opacity<100)
        click_control("brush_reset")
        assert(state.brush_size==8 and opacity==100)
        e2e_stage=19
    elseif e2e_stage==19 then
        love.keypressed('escape')
        e2e_stage=20
    elseif e2e_stage==20 then
        click_control('layer')
        assert(panel=='layer','não reabriu Layer para teste avançado')
        e2e_stage=21
    elseif e2e_stage==21 then
        click_control('layer_advanced')
        assert(panel=='layer_advanced','painel Grupos e Máscaras não abriu')
        e2e_stage=22
    elseif e2e_stage==22 then
        click_control('group_pair')
        assert(paint.doc.layers[2].groupId~=nil,'Group Pair não alterou o motor')
        e2e_stage=23
    elseif e2e_stage==23 then
        click_control('advanced_tab_layer_mask')
        assert(layer_advanced_tab=='layer_mask','aba Máscara camada não abriu')
        e2e_stage=24
    elseif e2e_stage==24 then
        click_control('layer_mask_add')
        assert(paint.doc.layers[2].mask,'botão Add Mask não criou máscara real')
        e2e_stage=25
    elseif e2e_stage==25 then
        click_control('layer_mask_paint')
        assert(paint:maskEditMode(state)=='layer','Editar máscara não ativou pincel')
        e2e_stage=26
    elseif e2e_stage==26 then
        click_control('advanced_tab_group_mask')
        e2e_stage=27
    elseif e2e_stage==27 then
        click_control('group_mask_add')
        local g=paint:activeGroup(state)
        assert(g and g.mask,'botão Group Mask não criou máscara real')
        e2e_stage=28
    elseif e2e_stage==28 then
        click_control('group_mask_paint')
        assert(paint:maskEditMode(state)=='group','Editar máscara grupo não ativou')
        e2e_stage=29
    else
        print("PASS: UI LÖVE E2E (gallery, layers, selection, masks/groups and brush)")
        love.event.quit(0)
    end
end

-- Não sair silenciosamente com alterações não gravadas.
function love.quit()
    if persistence_enabled and state.screen=='editor' and active_artwork_id then
        if not save_current_artwork() then return true end
    end
    return false
end
