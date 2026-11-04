-- Teste do motor com ImageData REAL do LÖVE 11.5, sem mocks.
-- Executado pelo runner: PAINT_LUA_BRIDGE_E2E=1 love .
local Model=require("src.model")
local Viewport=require("src.viewport")
local Preferences=require("src.editor_preferences")
local Bridge=require("app.paint_bridge")
local History=require("core.history")

local model=Model.new()
model:open_gallery()
model:open_new_canvas()
model:create_canvas(64,64)
model:set_color(224,32,48)
model:set_brush_size(12)
local view=Viewport.new()
local preferences=Preferences.new()
local bridge=Bridge.new()
local doc=assert(bridge:sync(model))
assert(doc.w==64 and doc.h==64 and #doc.layers==1)

-- Centro exato do canvas logico desenhado em 1024x768.
local left=preferences.tool_position=="left" and 62 or 0
local right=preferences.tool_position=="right" and 75 or 34
local cx=left+(1024-left-right)/2
local cy=62+(768-160)/2
assert(bridge:press(model,view,preferences,1,1024,768,cx,cy,100),
  "pincel nao iniciou: "..tostring(bridge.status))
bridge:finish(false)
local tile=assert(doc.layers[1].tiles["0,0"],"pincel nao criou tile")
local r,g,b,a=tile:getPixel(32,32)
assert(a>0 and r>g and r>b, "cor real da pincelada incorreta")

History.undo(doc)
local undone=doc.layers[1].tiles["0,0"]
assert(not undone or select(4,undone:getPixel(32,32))==0,
  "undo nao restaurou a transparencia")
History.redo(doc)
local redone=assert(doc.layers[1].tiles["0,0"])
assert(select(4,redone:getPixel(32,32))>0,"redo nao restaurou o pixel")

bridge.filename="ci-paint-lua-e2e.npnt"
local ok,err=bridge:save()
assert(ok,"falha ao salvar NPNT: "..tostring(err))
assert(bridge:load(model),"falha ao reabrir NPNT: "..tostring(bridge.status))
local reopened=assert(bridge.doc.layers[1].tiles["0,0"])
assert(select(4,reopened:getPixel(32,32))>0,"pixel nao persistiu no NPNT")
love.filesystem.remove(bridge.filename)

-- Integração v0.22: balde cooperativo, conta-gotas e Alpha Lock com pixels reais.
model:open_gallery()
model:open_new_canvas()
model:create_canvas(64,64)
local nextDoc=assert(bridge:sync(model))
assert(#nextDoc.layers==1 and #nextDoc.history.undo==0)
model:set_tool("bucket")
model:set_color(10,60,200)
assert(bridge:press(model,view,preferences,1,1024,768,cx,cy,100),
  "balde nao iniciou")
local loops=0
while bridge.job and loops<300 do bridge:update();loops=loops+1 end
assert(bridge.job==nil and loops<300,"balde nao concluiu")
local filled=assert(nextDoc.layers[1].tiles["0,0"])
local br,bg,bb,ba=filled:getPixel(32,32)
assert(ba>0 and bb>br and bb>bg,"balde nao gravou a cor")
assert(bridge:historyStep(model,false),"balde nao foi desfeito")
local u=nextDoc.layers[1].tiles["0,0"]
assert(not u or select(4,u:getPixel(32,32))==0,"undo do balde falhou")
assert(bridge:historyStep(model,true),"balde nao foi refeito")

model:set_tool("eyedropper")
model:set_color(0,0,0)
assert(bridge:press(model,view,preferences,1,1024,768,cx,cy,100),
  "conta-gotas nao coletou cor")
assert(model.color[3]>model.color[1],"cor do conta-gotas incorreta")

model:add_layer()
bridge:sync(model)
model:toggle_layer_alpha_lock(model.active_layer_id)
model:set_tool("brush")
model:set_color(230,20,40)
assert(bridge:press(model,view,preferences,1,1024,768,cx,cy,100),
  "pincel alpha-lock nao iniciou")
bridge:finish(false)
assert(next(nextDoc.layers[2].tiles)==nil,
  "Alpha Lock criou pixels onde a camada estava transparente")
model:toggle_layer_clipping(model.active_layer_id)
bridge:sync(model)
assert(nextDoc.layers[2].clipped,"Clipping nao foi transferido da UI ao motor")
print("PASS: LÖVE real v0.22: balde, conta-gotas, Alpha Lock e Clipping")
print("PASS: Ibis-Lua + motor real do LOVE: pincel, undo, redo, NPNT")
