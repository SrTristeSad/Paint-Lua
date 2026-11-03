-- Paint-Lua: adaptador de aplicação para o núcleo; nenhuma lógica de rasterização na UI.
local Doc = require('core.doc')
local Stroke = require('core.stroke')
local Layers = require('core.layers')
local History = require('core.history')
local Render = require('core.render')
local Project = require('core.project')
local Layout = require('ui.layout')
local BonoBridge = require('integrations.bono')

local Editor = {}
Editor.__index = Editor

local function clamp(x, a, b) return math.min(b, math.max(a, x)) end
local function nowMs() return (love.timer and love.timer.getTime() or os.clock()) * 1000 end
local function modifierDown()
  return love.keyboard and (love.keyboard.isDown('lctrl', 'rctrl', 'lgui', 'rgui')) or false
end
local palette = {
  {0.13, 0.16, 0.21}, {0.95, 0.95, 0.95}, {0.89, 0.29, 0.37},
  {0.98, 0.62, 0.24}, {0.98, 0.80, 0.35}, {0.26, 0.72, 0.52},
  {0.21, 0.64, 0.88}, {0.44, 0.42, 0.85}, {0.77, 0.38, 0.75},
  {0.47, 0.31, 0.25}, {0.51, 0.55, 0.62}, {0.02, 0.02, 0.02}
}

function Editor.new(opts)
  opts = opts or {}
  local self = setmetatable({
    doc = Doc.new(opts.width or 1024, opts.height or 768, opts.name or 'Sem título'),
    color = {0.13, 0.16, 0.21},
    brushSize = 14, opacity = 1, hardness = 0.82,
    tool = 'brush', zoom = 0.8, originX = 0, originY = 0,
    viewport = nil, stroke = nil, panning = false, panX = 0, panY = 0,
    status = 'Pronto', filename = 'meu-desenho.npnt',
    bridge = BonoBridge.new(), initialized = false,
    palette = palette,
  }, Editor)
  return self
end

function Editor:resize(w, h)
  local previous = self.viewport
  self.viewport = Layout.canvas(w, h)
  if not self.initialized then
    self:recenter()
    self.initialized = true
  elseif previous then
    -- Preserve a posição aparente do desenho ao redimensionar.
    self.originX = self.originX + (self.viewport.x + self.viewport.w/2 - previous.x - previous.w/2)
    self.originY = self.originY + (self.viewport.y + self.viewport.h/2 - previous.y - previous.h/2)
  end
end

function Editor:recenter()
  if not self.viewport then return end
  local v = self.viewport
  local z = math.min(v.w / self.doc.w, v.h / self.doc.h, 1)
  self.zoom = clamp(z * 0.92, 0.1, 4)
  self.originX = v.x + (v.w - self.doc.w * self.zoom) / 2
  self.originY = v.y + (v.h - self.doc.h * self.zoom) / 2
end

function Editor:inside(x,y)
  local v = self.viewport
  return v and x >= v.x and y >= v.y and x < v.x + v.w and y < v.y + v.h
end

function Editor:canvasCoords(x,y)
  return (x - self.originX) / self.zoom, (y - self.originY) / self.zoom
end

function Editor:beginStroke(x, y)
  if self.stroke then return end
  local dx, dy = self:canvasCoords(x, y)
  if dx < 0 or dy < 0 or dx >= self.doc.w or dy >= self.doc.h then return end
  local opts = {
    size = self.brushSize, alpha = self.opacity, hardness = self.hardness,
    color = {self.color[1], self.color[2], self.color[3]},
    eraser = self.tool == 'eraser',
    selection = self.doc.selection,
    pressureSize = false,
    smoothing = {mode = 'exponential', amount = 0.35, catchUpOnEnd = true}
  }
  local ok, value = pcall(Stroke.new, self.doc, self.doc.layers[self.doc.sel], self.doc.history, opts)
  if not ok then self.status = 'Erro ao iniciar pincel: ' .. tostring(value); return end
  self.stroke = value
  self:pushStroke(x, y)
end

function Editor:pushStroke(x, y)
  if not self.stroke then return end
  local dx, dy = self:canvasCoords(x, y)
  local ok, err = pcall(self.stroke.push, self.stroke, dx, dy, 1, nowMs())
  if not ok then
    local stroke = self.stroke
    self.stroke = nil
    pcall(stroke.cancel, stroke)
    self.status = 'Traço cancelado: ' .. tostring(err)
  end
end

function Editor:endStroke(cancel)
  if not self.stroke then return end
  local stroke = self.stroke
  self.stroke = nil
  local ok, err = pcall(cancel and stroke.cancel or stroke.finish, stroke)
  if not ok then
    self.status = 'Erro ao encerrar traço: ' .. tostring(err)
    pcall(stroke.cancel, stroke)
  end
end

function Editor:save()
  if self.stroke then self:endStroke(false) end
  local ok, err = Project.save(self.doc, self.filename)
  self.status = ok and ('Salvo: ' .. self.filename .. ' (save directory do LÖVE)')
    or ('Falha ao salvar: ' .. tostring(err))
  return ok, err
end

function Editor:open()
  if self.stroke then self:endStroke(true) end
  local ok, loaded, err = pcall(Project.load, self.filename)
  if ok and loaded then
    Render.clearComposited(self.doc)
    self.doc = loaded
    self:recenter()
    self.status = 'Projeto aberto: ' .. self.filename
    return true
  end
  self.status = 'Falha ao abrir: ' .. tostring(ok and err or loaded)
  return nil, self.status
end

function Editor:click(x, y, button)
  if button == 2 then return end
  if button == 3 or (love.keyboard and love.keyboard.isDown('space')) then
    self.panning, self.panX, self.panY = true, x, y
    return
  end
  if button ~= 1 then return end
  local w, h = love.graphics.getDimensions()
  local action = Layout.hit(w, h, x, y, #self.doc.layers)
  if action then
    if action == 'add-layer' then
      local ok, err = pcall(Layers.add, self.doc)
      self.status = ok and 'Camada criada' or tostring(err)
    elseif action == 'brush' or action == 'eraser' then self.tool = action
    elseif action == 'save' then self:save()
    elseif action == 'open' then self:open()
    elseif action == 'recenter' then self:recenter()
    elseif action:match('^layer:') then
      local index = tonumber(action:match('^layer:(%d+)$'))
      if index then Layers.select(self.doc, index) end
    elseif action:match('^swatch:') then
      local index = tonumber(action:match('^swatch:(%d+)$'))
      if self.palette[index] then self.color = self.palette[index] end
    end
    return
  end
  if self:inside(x,y) then self:beginStroke(x,y) end
end

function Editor:mouseMoved(x,y,dx,dy)
  if self.panning then
    self.originX, self.originY = self.originX + dx, self.originY + dy
  elseif self.stroke then self:pushStroke(x, y) end
end

function Editor:wheel(_, amount)
  local mx, my = love.mouse.getPosition()
  if not self:inside(mx,my) then return end
  local cx, cy = self:canvasCoords(mx,my)
  local newZoom = clamp(self.zoom * (1.16 ^ amount), 0.05, 16)
  self.zoom = newZoom
  self.originX, self.originY = mx - cx * newZoom, my - cy * newZoom
end

function Editor:keypressed(key)
  local ctrl = modifierDown()
  if ctrl and key == 's' then self:save(); return end
  if ctrl and key == 'o' then self:open(); return end
  if ctrl and (key == 'z' or key == 'y') then
    if self.stroke then self:endStroke(false) end
    local f = key == 'y' and History.redo or History.undo
    local ok, err = pcall(f, self.doc)
    self.status = ok and (key == 'z' and 'Desfeito' or 'Refeito') or tostring(err)
    return
  end
  if key == 'escape' then self:endStroke(true); return end
  if key == 'b' then self.tool = 'brush'
  elseif key == 'e' then self.tool = 'eraser'
  elseif key == 'leftbracket' then self.brushSize = math.max(1, self.brushSize - 2)
  elseif key == 'rightbracket' then self.brushSize = math.min(5000, self.brushSize + 2)
  elseif key == 'f' then self:recenter() end
end

function Editor:update(dt)
  self.bridge:update(dt)
end

function Editor:draw()
  local Draw = require('ui.draw')
  Draw.draw(self)
end

return Editor
