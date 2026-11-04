-- Estado de interação SIMULADO e puro; não equivale ao layout ou à execução oficial.
-- Nenhum pixel da imagem ou da obra é processado.
local Model = {}
Model.__index = Model

local valid_tools = {
    transform = true, magic_wand = true, lasso = true, filter = true,
    brush = true, eraser = true, smudge = true, blur = true,
    special_pen = true, bucket = true, vector = true, text = true,
    frame_divider = true, eyedropper = true, canvas = true
}
local valid_panels = { brush = true, color = true, layer = true }
-- Only the selection state of these documented modes is reproduced;
-- no compositing or raster effect is performed.
local blend_modes = {
    Normal = true, Multiply = true, Screen = true, Overlay = true,
    Darken = true, Lighten = true, ["Color Burn"] = true,
    ["Color Dodge"] = true, ["Soft Light"] = true
}

local function require_screen(self, screen)
    assert(self.screen == screen, "Operação inválida fora da tela: " .. screen)
end

local function uint(value, max)
    return type(value) == "number"
       and value == math.floor(value)
       and value >= 1
       and value <= max
end

function Model.new()
    return setmetatable({
        screen = "title",
        modal = nil,
        document = nil,
        active_tool = nil,
        active_panel = nil,
        brush_size = 1,
        color = { 0, 0, 0 },
        layers = {},
        active_layer_id = nil,
        next_layer_id = 1,
        solo_layer_id = nil,
        solo_before = nil,
        background_mode = "white"
    }, Model)
end

function Model:open_gallery()
    assert(self.screen == "title" or self.screen == "editor")
    self.screen = "gallery"
    self.active_panel = nil
    self.modal = nil
end

function Model:open_new_canvas()
    require_screen(self, "gallery")
    self.modal = "new_canvas"
end

function Model:cancel_new_canvas()
    require_screen(self, "gallery")
    assert(self.modal == "new_canvas", "Não há diálogo aberto")
    self.modal = nil
end

function Model:add_layer()
    require_screen(self, "editor")
    if self.solo_layer_id then self:toggle_layer_solo(self.solo_layer_id) end
    local id = self.next_layer_id
    self.next_layer_id = id + 1
    self.layers[#self.layers + 1] = {
        id = id,
        name = "Camada demonstrativa " .. tostring(id),
        visible = true,
        opacity = 100,
        blending = "Normal",
        clipping = false,
        alpha_lock = false,
        locked = false
    }
    self.active_layer_id = id
    return id
end

local function initialise_canvas(self,width,height)
    assert(uint(width,16384) and uint(height,16384),"Dimensões inválidas")
    self.document={width=width,height=height,simulated=true}
    self.screen="editor"
    self.modal=nil
    self.active_tool="brush"
    self.active_panel=nil
    self.layers={}
    self.active_layer_id=nil
    self.next_layer_id=1
    self.solo_layer_id=nil
    self.solo_before=nil
    self.background_mode="white"
    self:add_layer()
end

function Model:create_canvas(width,height)
    require_screen(self,"gallery")
    assert(self.modal=="new_canvas","Abra o diálogo de nova tela")
    initialise_canvas(self,width,height)
end

function Model:reopen_canvas(width,height)
    require_screen(self,"gallery")
    assert(self.modal==nil,"Feche o diálogo antes de abrir uma obra")
    initialise_canvas(self,width,height)
end

function Model:set_tool(tool)
    require_screen(self, "editor")
    assert(valid_tools[tool], "Ferramenta não documentada no modelo")
    self.active_tool = tool
end

function Model:toggle_panel(panel)
    require_screen(self, "editor")
    assert(valid_panels[panel], "Painel não documentado no modelo")
    if self.active_panel == panel then
        self.active_panel = nil
    else
        self.active_panel = panel
    end
end

function Model:set_brush_size(size)
    require_screen(self, "editor")
    assert(type(size) == "number" and size == size and size >= 0.1 and size <= 1000,
        "Espessura inválida")
    self.brush_size = size
end

function Model:set_color(r, g, b)
    require_screen(self, "editor")
    for _, c in ipairs({ r, g, b }) do
        assert(type(c) == "number" and c == c and c >= 0 and c <= 255 and c == math.floor(c),
            "Canal de cor inválido")
    end
    self.color = { r, g, b }
end

-- Long press no controle de visibilidade alterna modo solo (14.1.0+).
-- O snapshot evita perder o estado de visibilidade anterior das camadas.
function Model:get_layer(id)
    require_screen(self, "editor")
    for _,layer in ipairs(self.layers) do
        if layer.id==id then return layer end
    end
    error("Camada inexistente")
end

function Model:active_layer()
    return self:get_layer(self.active_layer_id)
end

function Model:set_layer_opacity(id,opacity)
    local layer=self:get_layer(id)
    assert(type(opacity)=="number" and opacity==opacity
        and opacity>=0 and opacity<=100, "Opacidade inválida")
    layer.opacity=math.floor(opacity+0.5)
end

function Model:set_layer_blending(id,mode)
    local layer=self:get_layer(id)
    assert(blend_modes[mode], "Modo de mesclagem desconhecido")
    layer.blending=mode
end

function Model:toggle_layer_clipping(id)
    local layer=self:get_layer(id)
    layer.clipping=not layer.clipping
    return layer.clipping
end

function Model:toggle_layer_alpha_lock(id)
    local layer=self:get_layer(id)
    layer.alpha_lock=not layer.alpha_lock
    return layer.alpha_lock
end

function Model:toggle_layer_lock(id)
    local layer=self:get_layer(id)
    layer.locked=not layer.locked
    return layer.locked
end

function Model:rename_layer(id,name)
    local layer=self:get_layer(id)
    assert(type(name)=="string" and #name>=1 and #name<=80
        and not name:match("^%s*$"), "Nome de camada inválido")
    layer.name=name
end

function Model:set_background(mode)
    require_screen(self, "editor")
    assert(mode=="white" or mode=="transparent_light"
        or mode=="transparent_dark","Fundo inválido")
    self.background_mode=mode
end

-- A tela não tem pixels editáveis: mudanças abaixo afetam somente a
-- simulação de hierarquia e as propriedades do painel.
function Model:toggle_layer_solo(id)
    require_screen(self, "editor")
    local found=false
    for _,layer in ipairs(self.layers) do
        if layer.id==id then found=true; break end
    end
    assert(found, "Camada inexistente")
    if self.solo_layer_id==id then
        for _,layer in ipairs(self.layers) do
            layer.visible=self.solo_before[layer.id]
        end
        self.solo_layer_id=nil
        self.solo_before=nil
        return false
    end
    if not self.solo_before then
        self.solo_before={}
        for _,layer in ipairs(self.layers) do
            self.solo_before[layer.id]=layer.visible
        end
    end
    self.solo_layer_id=id
    for _,layer in ipairs(self.layers) do
        layer.visible=layer.id==id
    end
    return true
end

function Model:toggle_layer_visibility(id)
    require_screen(self, "editor")
    if self.solo_layer_id then self:toggle_layer_solo(self.solo_layer_id) end
    for _, layer in ipairs(self.layers) do
        if layer.id == id then
            layer.visible = not layer.visible
            return layer.visible
        end
    end
    error("Camada inexistente")
end

function Model:select_layer(id)
    require_screen(self, "editor")
    for _, layer in ipairs(self.layers) do
        if layer.id == id then self.active_layer_id = id; return end
    end
    error("Camada inexistente")
end

return Model
