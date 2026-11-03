-- Primeira casca LÖVE 11.5: renderização somente de UI; pixels ficam no core.
local Layout = require('ui.layout')
local Render = require('core.render')
local Draw = {}
local function color(r,g,b,a) love.graphics.setColor(r,g,b,a or 1) end
local function rect(mode,x,y,w,h,r) love.graphics.rectangle(mode,x,y,w,h,r or 0,r or 0) end
local function label(s,x,y) love.graphics.print(s,x,y) end
local function button(text,x,y,w,h,active)
  color(active and 0.17 or 0.14, active and 0.40 or 0.17, active and 0.57 or 0.23)
  rect('fill',x,y,w,h,6)
  color(0.94,0.96,0.98); label(text,x+10,y+8)
end
function Draw.draw(editor)
  local w,h=love.graphics.getDimensions()
  local v=editor.viewport or Layout.canvas(w,h)
  color(0.10,0.12,0.16); rect('fill',0,0,w,h)
  color(0.14,0.17,0.22); rect('fill',0,0,w,Layout.TOP)
  button('Salvar',16,12,85,32)
  button('Abrir',108,12,85,32)
  button('Centralizar',200,12,100,32)
  color(0.84,0.89,0.94)
  label('Paint-Lua  |  v0.21',315,20)
  color(0.13,0.15,0.19); rect('fill',0,Layout.TOP,Layout.LEFT,h-Layout.TOP-Layout.BOTTOM)
  button('P',10,Layout.TOP+12,56,56,editor.tool=='brush')
  button('E',10,Layout.TOP+78,56,56,editor.tool=='eraser')
  color(0.67,0.73,0.82); label('['..editor.brushSize..']',11,Layout.TOP+155)
  -- Área e página: scissor impede que a imagem encubra a interface.
  love.graphics.setScissor(v.x,v.y,v.w,v.h)
  color(0.22,0.24,0.28); rect('fill',v.x,v.y,v.w,v.h)
  color(0.89,0.89,0.89); rect('fill',editor.originX-2,editor.originY-2,
    editor.doc.w*editor.zoom+4,editor.doc.h*editor.zoom+4)
  color(1,1,1); rect('fill',editor.originX,editor.originY,editor.doc.w*editor.zoom,editor.doc.h*editor.zoom)
  Render.refresh(editor.doc,editor.originX,editor.originY,editor.zoom,v)
  Render.draw(editor.doc,editor.originX,editor.originY,editor.zoom,v)
  love.graphics.setScissor()
  love.graphics.setBlendMode('alpha')
  -- Painel de camadas
  local rx=w-Layout.RIGHT
  color(0.13,0.15,0.19); rect('fill',rx,Layout.TOP,Layout.RIGHT,h-Layout.TOP)
  color(0.92,0.93,0.97); label('CAMADAS',rx+16,Layout.TOP+17)
  button('+ Nova camada',rx+12,Layout.TOP+48,245,36)
  for i,layer in ipairs(editor.doc.layers) do
    local yy=Layout.TOP+94+(i-1)*Layout.LAYER_HEIGHT
    if yy > h-170 then break end
    color(i==editor.doc.sel and 0.20 or 0.15,
      i==editor.doc.sel and 0.37 or 0.18,
      i==editor.doc.sel and 0.51 or 0.23)
    rect('fill',rx+12,yy,245,Layout.LAYER_HEIGHT-4,5)
    color(0.95,0.95,0.98)
    label((layer.visible and '◉ ' or '○ ')..layer.name,rx+20,yy+12)
  end
  color(0.83,0.87,0.92); label('CORES',rx+16,h-170)
  for i,c in ipairs(editor.palette) do
    local col=(i-1)%6; local row=math.floor((i-1)/6)
    local sx,sy=rx+16+col*40,h-145+row*42
    color(c[1],c[2],c[3]); rect('fill',sx,sy,32,32,3)
    if c == editor.color then
      color(1,1,1); rect('line',sx-2,sy-2,36,36,4)
    end
  end
  color(0.09,0.11,0.14); rect('fill',0,h-Layout.BOTTOM,w,Layout.BOTTOM)
  color(0.79,0.83,0.88)
  label(editor.status:sub(1,100),12,h-22)
  love.graphics.printf(string.format('%d×%d  |  %d camadas  |  %.0f%%',
    editor.doc.w,editor.doc.h,#editor.doc.layers,editor.zoom*100),0,h-22,w-15,'right')
  color(1,1,1)
end
return Draw
