-- Entrada do LÖVE 11.5. O motor de pintura permanece em core/.
package.path = package.path .. ';vendor/Bono-Lua/?.lua;vendor/Bono-Lua/?/init.lua'
local Editor = require('app.editor')
local app
function love.load()
  app=Editor.new()
  local w,h=love.graphics.getDimensions()
  app:resize(w,h)
end
function love.resize(w,h) if app then app:resize(w,h) end end
function love.update(dt) if app then app:update(dt) end end
function love.draw() if app then app:draw() end end
function love.mousepressed(x,y,button) if app then app:click(x,y,button) end end
function love.mousemoved(x,y,dx,dy) if app then app:mouseMoved(x,y,dx,dy) end end
function love.mousereleased(x,y,button)
  if app then
    if button==1 then app:endStroke(false); app.panning=false
    elseif button==3 then app.panning=false end
  end
end
function love.wheelmoved(x,y) if app then app:wheel(x,y) end end
function love.keypressed(key) if app then app:keypressed(key) end end
function love.focus(focused) if app and not focused then app:endStroke(true); app.panning=false end end
