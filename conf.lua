function love.conf(t)
  t.identity = 'paint-lua'
  t.version = '11.5'
  t.window.title = 'Paint-Lua — Editor de Pintura'
  t.window.width = 1280
  t.window.height = 800
  t.window.resizable = true
  t.window.minwidth = 860
  t.window.minheight = 560
  t.modules.physics = false
end
