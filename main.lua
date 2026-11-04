-- Paint-Lua: interface de Ibis-Lua + nucleo proprio de pintura (LÖVE 11.5).
-- O Ibis-Lua permanece versionado como submodulo independente.
package.path = package.path
  .. ""
require("app.ibis_main")

-- Teste opt-in da integracao real; nao altera a inicializacao comum.
if os.getenv("PAINT_LUA_BRIDGE_E2E")=="1" then
  local originalLoad=love.load
  function love.load(...)
    originalLoad(...)
    require("tests.test_bridge_love")
    love.event.quit(0)
  end
end
