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

-- v0.23: seleção real nas coordenadas da UI e persistência NPNT5.
local Selection=require('core.selection')
local fresh=Model.new()
fresh:open_gallery()
fresh:open_new_canvas()
fresh:create_canvas(64,64)
local selectionBridge=Bridge.new()
local selDoc=assert(selectionBridge:sync(fresh))
local canvasScale=math.min((1024-left-right)/64,(768-160)/64,1.1)
local function pos(x,y)
  return cx+(x-32)*canvasScale,cy+(y-32)*canvasScale
end
fresh:set_tool('selection_rect')
local x1,y1=pos(25,25)
local x2,y2=pos(39,39)
assert(selectionBridge:beginSelection(fresh,view,preferences,1,1024,768,x1,y1),
  'início retangular não funcionou')
selectionBridge:moveSelection(fresh,view,preferences,1,1024,768,x2,y2)
assert(selectionBridge:finishSelection(fresh,view,preferences,1,1024,768,x2,y2),
  'fim retangular não funcionou')
assert(Selection.contains(selDoc.selection,32,32) and not Selection.contains(selDoc.selection,20,20),
  'retângulo não delimitou os pixels')
fresh:set_tool('brush')
fresh:set_color(230,20,40)
fresh:set_brush_size(18)
assert(selectionBridge:press(fresh,view,preferences,1,1024,768,cx,cy,100))
selectionBridge:finish(false)
local cTile=assert(selDoc.layers[1].tiles['0,0'])
assert(select(4,cTile:getPixel(32,32))>0,'pincel não escreveu dentro da seleção')
assert(select(4,cTile:getPixel(20,20))==0,'pincel ultrapassou seleção retangular')

fresh:set_tool('lasso')
local ax,ay=pos(22,22)
assert(selectionBridge:beginSelection(fresh,view,preferences,1,1024,768,ax,ay))
local bx,by=pos(43,22)
selectionBridge:moveSelection(fresh,view,preferences,1,1024,768,bx,by)
bx,by=pos(22,43)
selectionBridge:moveSelection(fresh,view,preferences,1,1024,768,bx,by)
assert(selectionBridge:finishSelection(fresh,view,preferences,1,1024,768,bx,by))
assert(selDoc.selection.kind=='polygon' and not Selection.contains(selDoc.selection,40,40),
  'laço não criou seleção poligonal exata')
selectionBridge.filename='ci-paint-lua-v023.npnt'
local ok23,err23=selectionBridge:save()
assert(ok23,'não salvou NPNT5: '..tostring(err23))
assert(selectionBridge:load(fresh),'não carregou NPNT5 com laço: '..selectionBridge.status)
assert(selectionBridge.doc.selection.kind=='polygon','NPNT5 não manteve laço')
assert(not Selection.contains(selectionBridge.doc.selection,40,40),
  'NPNT5 alterou forma do laço')

fresh:set_tool('magic_wand')
assert(selectionBridge:beginSelection(fresh,view,preferences,1,1024,768,cx,cy),
  'varinha não iniciou')
local count23=0
while selectionBridge.job and count23<300 do
  selectionBridge:update();count23=count23+1
end
assert(selectionBridge.job==nil and count23<300,'varinha não concluiu')
assert(selectionBridge.doc.selection.kind=='wand','varinha não retornou máscara raster')
assert(Selection.contains(selectionBridge.doc.selection,32,32),
  'varinha não selecionou pixel da camada')
assert(not Selection.contains(selectionBridge.doc.selection,20,20),
  'varinha selecionou transparência adjacente')
assert(selectionBridge:save(),'NPNT5 não salvou varinha')
assert(selectionBridge:load(fresh),'NPNT5 não reabriu varinha')
assert(selectionBridge.doc.selection.kind=='wand' and
  Selection.contains(selectionBridge.doc.selection,32,32),
  'máscara da varinha não persistiu no NPNT5')
love.filesystem.remove(selectionBridge.filename)
print('PASS: LÖVE real v0.23: retângulo, laço, varinha e NPNT5')

-- v0.24: seleção flutuante, prévia e transação de transformação no LÖVE real.
local transformDoc=selectionBridge.doc
local transformLayer=transformDoc.layers[transformDoc.sel]
local beforeTile=assert(transformLayer.tiles['0,0'])
local _,_,_,beforeAlpha=beforeTile:getPixel(32,32)
assert(beforeAlpha>0,'seleção de transformação deve conter pixels')
fresh:set_tool('transform')
assert(selectionBridge:startTransform(fresh),
  'não iniciou prévia de transformação: '..selectionBridge.status)
assert(selectionBridge.transform and selectionBridge.transform.active)
assert(not selectionBridge:save(),'salvar durante prévia deve ser bloqueado')
local beforeUndo=#transformDoc.history.undo
assert(selectionBridge:adjustTransform(8,0,1,0),'deslocamento de prévia falhou')
assert(select(4,beforeTile:getPixel(32,32))>0,
  'a prévia modificou pixels da camada antes da confirmação')
assert(#transformDoc.history.undo==beforeUndo,'prévia criou histórico prematuro')
assert(selectionBridge:applyTransform(fresh),'não aplicou a transformação')
assert(selectionBridge.transform==nil,'sessão não foi liberada após confirmar')
assert(#transformDoc.history.undo==beforeUndo+1,'transformação deve ser um gesto de undo')
assert(select(4,transformLayer.tiles['0,0']:getPixel(40,32))>0,
  'transformação não escreveu pixels no destino')
assert(selectionBridge:historyStep(fresh,false),'não desfez transformação')
assert(select(4,transformLayer.tiles['0,0']:getPixel(32,32))>0,
  'undo não restaurou pixels de origem')
assert(selectionBridge:historyStep(fresh,true),'não refez transformação')
assert(Selection.contains(transformDoc.selection,40,32),
  'redo não restaurou a seleção transformada')
selectionBridge.filename='ci-paint-lua-v024.npnt'
assert(selectionBridge:save(),'NPNT5 não salvou a seleção transformada')
assert(selectionBridge:load(fresh),'NPNT5 não reabriu a transformação')
assert(Selection.contains(selectionBridge.doc.selection,40,32),
  'NPNT5 não preservou máscara transformada')
assert(select(4,selectionBridge.doc.layers[selectionBridge.doc.sel].tiles['0,0']:getPixel(40,32))>0,
  'NPNT5 não preservou pixels transformados')
love.filesystem.remove(selectionBridge.filename)
print('PASS: LÖVE real v0.24: transformar, preview, undo/redo e NPNT5')
