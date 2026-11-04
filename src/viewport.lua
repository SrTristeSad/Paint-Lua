-- Transformações de VISUALIZAÇÃO apenas; não processa pixels nem imagens.
-- Gestos documentados: zoom pelo scroll; Shift+scroll gira; Space+arrastar move.
local Viewport = {}
Viewport.__index = Viewport

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function Viewport.new()
    return setmetatable({
        zoom = 1, rotation = 0, pan_x = 0, pan_y = 0,
        is_panning = false, drag_x = 0, drag_y = 0
    }, Viewport)
end

function Viewport:reset()
    self.zoom = 1
    self.rotation = 0
    self.pan_x = 0
    self.pan_y = 0
    self.is_panning = false
end

function Viewport:zoom_at(steps, x, y, center_x, center_y)
    assert(type(steps)=="number" and steps==steps, "Passo de zoom inválido")
    local old = self.zoom
    local next_zoom = clamp(old * math.pow(1.15, steps), 0.10, 12)
    if next_zoom == old then return old end
    local ratio = next_zoom / old
    self.pan_x = self.pan_x + (1-ratio) * (x-center_x-self.pan_x)
    self.pan_y = self.pan_y + (1-ratio) * (y-center_y-self.pan_y)
    self.zoom = next_zoom
    return next_zoom
end

function Viewport:rotate_wheel(steps)
    self.rotation = (self.rotation + steps*math.pi/36) % (math.pi*2)
    return self.rotation
end

function Viewport:begin_pan(x,y)
    self.is_panning=true
    self.drag_x=x
    self.drag_y=y
end

function Viewport:pan_to(x,y)
    if not self.is_panning then return false end
    self.pan_x=self.pan_x + x-self.drag_x
    self.pan_y=self.pan_y + y-self.drag_y
    self.drag_x=x
    self.drag_y=y
    return true
end

function Viewport:end_pan()
    self.is_panning=false
end

return Viewport
