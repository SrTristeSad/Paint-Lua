-- Paint-Lua: interface de Ibis-Lua + nucleo proprio de pintura (LÖVE 11.5).
-- O Ibis-Lua permanece versionado como submodulo independente.
package.path = package.path
  .. ";vendor/Ibis-Lua/?.lua;vendor/Ibis-Lua/?/init.lua"
require("app.ibis_main")
