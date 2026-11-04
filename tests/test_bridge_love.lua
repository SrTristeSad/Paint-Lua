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

-- v0.25: máscaras de camada/grupo e pintura do grupo em ImageData real.
local Doc=require('core.doc')
local maskedModel=Model.new()
maskedModel:open_gallery();maskedModel:open_new_canvas();maskedModel:create_canvas(64,64)
local maskedBridge=Bridge.new()
local maskedDoc=assert(maskedBridge:sync(maskedModel))
local mLayer=maskedDoc.layers[1]
local mTile=Doc.getTile(mLayer,0,0,true)
mTile:setPixel(32,32,0.9,0.2,0.1,1)
Doc.markDirty(mLayer,'0,0')
local Composite=require('core.composite')
local function compositeAlpha()
  return select(4,Composite.flattenRegion(maskedDoc,32,32,1,1):getPixel(0,0))
end
assert(compositeAlpha()>0.9)
assert(maskedBridge:layerMaskAction(maskedModel,'add'))
assert(maskedBridge:editMask(maskedModel,'layer'))
maskedModel:set_tool('eraser')
maskedModel:set_brush_size(12)
assert(maskedBridge:press(maskedModel,view,preferences,1,1024,768,cx,cy,100))
maskedBridge:finish(false)
assert(compositeAlpha()<0.01,'máscara da camada não escondeu o pixel')
assert(select(4,mTile:getPixel(32,32))==1,'máscara apagou imagem original')
assert(maskedBridge:historyStep(maskedModel,false) and compositeAlpha()>0.9,
  'undo da máscara de camada')
assert(maskedBridge:historyStep(maskedModel,true) and compositeAlpha()<0.01,
  'redo da máscara de camada')
assert(maskedBridge:layerMaskAction(maskedModel,'inverted'))
assert(compositeAlpha()>0.9,'inversão de máscara não funcionou')
assert(maskedBridge:editPixels())
maskedModel:add_layer();maskedBridge:sync(maskedModel)
assert(maskedBridge:createGroup(maskedModel,true))
assert(require('core.groups').validate(maskedDoc))
local mg=assert(maskedBridge:activeGroup(maskedModel))
assert(maskedBridge:groupAction(maskedModel,'addMask'))
assert(mg.mask and maskedBridge:editMask(maskedModel,'group'))
assert(maskedBridge:press(maskedModel,view,preferences,1,1024,768,cx,cy,100))
maskedBridge:finish(false)
assert(compositeAlpha()<0.01,'máscara do grupo não escondeu a composição')
assert(maskedBridge:historyStep(maskedModel,false) and compositeAlpha()>0.9,
  'undo máscara de grupo')
assert(maskedBridge:historyStep(maskedModel,true) and compositeAlpha()<0.01,
  'redo máscara de grupo')
maskedBridge.filename='ci-paint-lua-v025.npnt'
assert(maskedBridge:save(),'não salvou documento com grupos e máscaras')
assert(maskedBridge:load(maskedModel),'não reabriu documento com grupos e máscaras')
local opened=maskedBridge.doc
local gid=opened.layers[1].groupId
assert(gid and opened.groups[gid] and opened.groups[gid].mask,
  'NPNT5 não preservou máscara de grupo')
assert(opened.layers[1].mask and opened.layers[1].mask.inverted,
  'NPNT5 não preservou máscara invertida de camada')
love.filesystem.remove(maskedBridge.filename)
print('PASS: LÖVE real v0.25: máscaras de camada/grupo, pintura, undo/redo e NPNT5')

-- v0.26: thumbs RGBA/máscara em ImageData real + GPU, drag lógico e NPNT5.
local Thumb=require('core.thumbnail')
local previewModel=Model.new()
previewModel:open_gallery();previewModel:open_new_canvas();previewModel:create_canvas(80,40)
local previewBridge=Bridge.new()
local previewDoc=previewBridge:sync(previewModel)
local src=previewDoc.layers[1]
local pix=Doc.getTile(src,0,0,true)
pix:setPixel(11,13,0.83,0.17,0.09,1)
Doc.markDirty(src,'0,0')
local image=assert(previewBridge:thumbnail(previewModel,previewModel.active_layer_id,'layer',40,40))
assert(image:getWidth()==40 and image:getHeight()==40,'thumb GPU não tem 40x40')
assert(previewBridge.thumbRenders==1,'thumb não gerada exatamente uma vez')
assert(previewBridge:thumbnail(previewModel,previewModel.active_layer_id,'layer',40,40)==image)
assert(previewBridge.thumbRenders==1,'redraw recomputou miniatura sem alteração')
local img=Thumb.render(previewDoc,src,'layer',40,40)
assert(select(4,img:getPixel(5,16))>0.9,'thumb da camada não contém pixel real')
pix:setPixel(11,13,0.04,0.8,0.6,1)
Doc.markDirty(src,'0,0')
assert(previewBridge:thumbnail(previewModel,previewModel.active_layer_id,'layer',40,40)==image)
assert(previewBridge.thumbRenders==2,'mudança de pixels não invalidou thumb')
assert(previewBridge:layerMaskAction(previewModel,'add'))
local maskThumb=assert(previewBridge:thumbnail(previewModel,previewModel.active_layer_id,'mask',19,19))
assert(maskThumb:getWidth()==19,'miniatura de máscara não foi criada')
local previous=previewBridge.thumbRenders
Layers=require('core.layers')
Layers.setMaskPixel(previewDoc,1,11,13,0)
previewBridge:thumbnail(previewModel,previewModel.active_layer_id,'mask',19,19)
assert(previewBridge.thumbRenders==previous+1,'pintura da máscara não invalidou thumb')
previewModel:add_layer();previewBridge:sync(previewModel)
previewModel:add_layer();previewBridge:sync(previewModel)
local movingId=previewModel.layers[1].id
assert(previewBridge:reorderLayer(previewModel,movingId,previewModel.layers[3].id))
assert(previewModel.layers[3].id==movingId and previewDoc.layers[3]==src,
  'UI mudou identidade dos pixels ao mover camada')
assert(previewBridge:historyStep(previewModel,false), 'undo reordenar camada real')
assert(previewBridge:historyStep(previewModel,true), 'redo reordenar camada real')
previewBridge.filename='ci-paint-lua-v026.npnt'
assert(previewBridge:save(),'não salvou ordem de camadas')
assert(previewBridge:load(previewModel),'não reabriu ordem de camadas')
assert(previewBridge.doc.layers[3].name==src.name,'NPNT5 alterou ordem das camadas')
love.filesystem.remove(previewBridge.filename)
print('PASS: LÖVE real v0.26: thumbnails GPU, máscaras, reorder, undo/redo, NPNT5')

-- v0.29: importar PNG real (LÖVE decoder), adicionar camada, rollback e NPNT5.
local pngModel=Model.new()
pngModel:open_gallery();pngModel:open_new_canvas();pngModel:create_canvas(64,64)
local pngBridge=Bridge.new()
local pngDoc=assert(pngBridge:sync(pngModel))
local baseLayer=pngDoc.layers[1]
local sourcePNG=love.image.newImageData(4,4)
sourcePNG:setPixel(1,2,0.2,0.6,0.9,0.5)
sourcePNG:setPixel(3,3,0.9,0.4,0.1,1)
local pngBytes=sourcePNG:encode('png'):getString()
assert(pngBridge:importPNGBytes(pngModel,pngBytes,'referencia.png'),
  'prévia PNG real falhou: '..tostring(pngBridge.status))
assert(#pngDoc.layers==1 and #pngDoc.history.undo==0,
  'prévia PNG não deve alterar a pintura nem o histórico')
assert(pngBridge:applyPNGImport(pngModel),'aplicar PNG real falhou')
assert(#pngDoc.layers==2 and pngDoc.layers[1]==baseLayer and pngDoc.sel==2,
  'importação substituiu uma camada existente')
local imported=pngDoc.layers[2]
local tilePNG=assert(imported.tiles['0,0'])
local ir,ig,ib,ia=tilePNG:getPixel(31,32)
assert(math.abs(ir-0.2)<0.008 and math.abs(ig-0.6)<0.008 and
  math.abs(ib-0.9)<0.008 and math.abs(ia-0.5)<0.008,
  'decodificação PNG não preservou RGBA corretamente')
assert(pngBridge:historyStep(pngModel,false) and #pngDoc.layers==1,
  'Ctrl+Z não retirou a imagem importada')
assert(pngBridge:historyStep(pngModel,true) and #pngDoc.layers==2,
  'Ctrl+Y não recuperou a imagem importada')
local undoCount=#pngDoc.history.undo
assert(not pngBridge:importPNGBytes(pngModel,'dados corrompidos','erro.png'))
assert(#pngDoc.layers==2 and #pngDoc.history.undo==undoCount,
  'arquivo inválido alterou a obra ou histórico')
assert(love.filesystem.createDirectory('imports'))
assert(love.filesystem.write('imports/ci-referencia.png',pngBytes))
assert(pngBridge:importPNGFromFolder(pngModel,'ci-referencia.png'),
  'prévia pela pasta imports falhou')
assert(#pngDoc.layers==2,'prévia da pasta alterou camadas')
assert(pngBridge:applyPNGImport(pngModel),'aplicar PNG da pasta falhou')
assert(#pngDoc.layers==3 and pngDoc.layers[3].name=='PNG: ci-referencia',
  'pasta imports não gerou nova camada')
assert(not pngBridge:importPNGFromFolder(pngModel,'../segredo.png'),
  'importador aceitou caminho inseguro')
love.filesystem.remove('imports/ci-referencia.png')
pngBridge.filename='ci-paint-lua-v029.npnt'
assert(pngBridge:save(),'NPNT não salvou camadas importadas')
assert(pngBridge:load(pngModel),'NPNT não reabriu camadas importadas')
assert(#pngBridge.doc.layers==3 and
  math.abs(select(4,pngBridge.doc.layers[2].tiles['0,0']:getPixel(31,32))-0.5)<0.008,
  'pixels PNG não sobreviveram ao NPNT')
love.filesystem.remove(pngBridge.filename)
print('PASS: LÖVE v0.29: PNG real, pasta imports, RGBA, undo/redo e NPNT5')

-- v0.30: PNG com prévia temporária, redimensionamento, cancelamento e NPNT5.
local placementModel=Model.new()
placementModel:open_gallery();placementModel:open_new_canvas();placementModel:create_canvas(64,64)
local placementBridge=Bridge.new()
local placementDoc=assert(placementBridge:sync(placementModel))
local historyBefore=#placementDoc.history.undo
assert(placementBridge:importPNGBytes(placementModel,pngBytes,'posicao.png'))
assert(placementBridge.pngPreview and #placementDoc.layers==1 and
  #placementDoc.history.undo==historyBefore,'prévia não pode modificar a imagem')
assert(placementBridge:adjustPNGImport(5,2,1.5))
assert(placementBridge.pngPreview.dx==5 and placementBridge.pngPreview.scaleX==1.5)
assert(placementBridge:cancelPNGImport())
assert(not placementBridge.pngPreview and #placementDoc.layers==1 and
  #placementDoc.history.undo==historyBefore,'cancelar a prévia alterou o desenho')
assert(placementBridge:importPNGBytes(placementModel,pngBytes,'posicao.png'))
assert(placementBridge:adjustPNGImport(5,2,1.5))
assert(placementBridge:applyPNGImport(placementModel),'aplicar o PNG redimensionado')
assert(#placementDoc.layers==2 and #placementDoc.history.undo==historyBefore+1,
  'importação transformada não foi uma ação')
local placed=placementDoc.layers[2]
local output=assert(placed.tiles['0,0'])
assert(select(4,output:getPixel(31,32))==0,
  'PNG redimensionado deveria mudar de posição')
assert(select(4,output:getPixel(36,34))>0,
  'PNG transformado não apareceu no destino esperado')
assert(placementBridge:historyStep(placementModel,false) and #placementDoc.layers==1)
assert(placementBridge:historyStep(placementModel,true) and #placementDoc.layers==2)
placementBridge.filename='ci-paint-lua-v030.npnt'
assert(placementBridge:save())
assert(placementBridge:load(placementModel))
assert(#placementBridge.doc.layers==2)
love.filesystem.remove(placementBridge.filename)
print('PASS: LÖVE v0.30: prévia PNG, zoom, mover, cancelar, undo e NPNT5')

-- v0.31: filtro alterável com prévia na GPU e PNG RGBA real do decodificador.
local smoothModel=Model.new()
smoothModel:open_gallery();smoothModel:open_new_canvas();smoothModel:create_canvas(64,64)
local smoothBridge=Bridge.new()
local smoothDoc=assert(smoothBridge:sync(smoothModel))
local bar=love.image.newImageData(2,1)
bar:setPixel(0,0,1,0,0,1)
bar:setPixel(1,0,0,0,1,1)
local barBytes=bar:encode('png'):getString()
assert(smoothBridge:importPNGBytes(smoothModel,barBytes,'degrade.png'))
assert(smoothBridge.pngPreview.interpolation=='smooth',
  'filtro suave deveria ser o padrão da UI')
assert(smoothBridge:adjustPNGImport(0,0,2))
local session=smoothBridge.pngPreview
local undoBefore=#smoothDoc.history.undo
assert(#smoothDoc.layers==1 and undoBefore==0,'filtro não deve alterar a obra na prévia')
assert(smoothBridge:setPNGInterpolation('pixelated'))
assert(session.interpolation=='pixelated')
assert(smoothBridge:setPNGInterpolation('smooth'))
local drawOK,drawErr=pcall(smoothBridge.drawPNGImport,smoothBridge,0,0)
assert(drawOK,'prévia GPU real falhou: '..tostring(drawErr))
assert(session.previewFilter=='linear','prévia GPU não aplicou linear')
assert(smoothBridge:setPNGInterpolation('pixelated'))
smoothBridge:drawPNGImport(0,0)
assert(session.previewFilter=='nearest','filtro GPU não alternou para nearest')
assert(smoothBridge:setPNGInterpolation('smooth'))
assert(smoothBridge:applyPNGImport(smoothModel))
assert(#smoothDoc.layers==2 and #smoothDoc.history.undo==undoBefore+1)
local tile=assert(smoothDoc.layers[2].tiles['0,0'])
local r,g,b,a=tile:getPixel(31,31)
assert(math.abs(r-0.75)<0.008 and math.abs(g)<0.008 and
  math.abs(b-0.25)<0.008 and math.abs(a-1)<0.008,
  'PNG bilinear com ImageData real não interpolou as cores')
assert(smoothBridge:historyStep(smoothModel,false) and #smoothDoc.layers==1)
assert(smoothBridge:historyStep(smoothModel,true) and #smoothDoc.layers==2)
smoothBridge.filename='ci-paint-lua-v031.npnt'
assert(smoothBridge:save(),'não salvou PNG interpolado')
assert(smoothBridge:load(smoothModel),'não reabriu PNG interpolado')
local reopened=assert(smoothBridge.doc.layers[2].tiles['0,0'])
local rr,_,bb,aa=reopened:getPixel(31,31)
assert(math.abs(rr-0.75)<0.008 and math.abs(bb-0.25)<0.008 and
  math.abs(aa-1)<0.008,'NPNT5 não preservou pixel suave')
love.filesystem.remove(smoothBridge.filename)
print('PASS: LÖVE v0.31: PNG bilinear RGBA, filtro GPU, histórico e NPNT5')

-- v0.32: máscara de cobertura da importação rotacionada no ImageData real.
local AAImport=require('src.png_import')
local aaDoc=Doc.new(24,24,'rotação com antialias')
local aaSource=love.image.newImageData(3,3)
for y=0,2 do for x=0,2 do aaSource:setPixel(x,y,1,0.1,0.05,1) end end
local aaSession=AAImport.preview(aaDoc,aaSource,'aa.png')
AAImport.setInterpolation(aaSession,'smooth')
AAImport.adjust(aaSession,0,0,1,math.pi/4)
local aaLayer=assert(AAImport.insert(aaDoc,aaSource,'aa.png',aaSession))
local aaTile=assert(aaLayer.tiles['0,0'])
local partial,opaque=false,false
for y=0,23 do for x=0,23 do
  local r,g,b,a=aaTile:getPixel(x,y)
  if a>0 and a<0.99 then partial=true end
  if a>0.99 then opaque=true end
  if a>0 then assert(r>g and g>b,'cor corrompida após antialias da rotação') end
end end
assert(partial and opaque,'giro suave não produziu pixels com cobertura parcial')
assert(#aaDoc.history.undo==1,'rotação PNG inseriu ações extras no histórico')
require('core.history').undo(aaDoc)
assert(#aaDoc.layers==2,'undo da importação rotacionada não removeu camada')
print('PASS: LÖVE real v0.32: bordas inclinadas AA, transparência e histórico')

-- v0.33: transformar seleção com bilinear/AA no ImageData real.
local SmoothTransform=require('core.transform')
local smoothSelect=require('core.selection')
local selectionModel=Model.new()
selectionModel:open_gallery();selectionModel:open_new_canvas();selectionModel:create_canvas(64,64)
local selectionBridge=Bridge.new()
local selDoc=assert(selectionBridge:sync(selectionModel))
local selLayer=selDoc.layers[selDoc.sel]
local selTile,selKey=Doc.getTile(selLayer,0,0,true)
selTile:setPixel(30,30,1,0,0,1)
selTile:setPixel(31,30,0,0,1,1)
Doc.markDirty(selLayer,selKey)
selDoc.selection=smoothSelect.rect(selDoc,30,30,31,30)
selectionModel:set_tool('transform')
assert(selectionBridge:startTransform(selectionModel))
assert(selectionBridge.transform.interpolation=='smooth')
assert(selectionBridge:adjustTransform(0,0,2))
assert(selectionBridge:setTransformInterpolation('pixelated'))
assert(pcall(selectionBridge.drawSelection,selectionBridge,0,0,1))
assert(selectionBridge.transform.previewFilter=='nearest','GPU do transform deveria estar pixelada')
assert(selectionBridge:setTransformInterpolation('smooth'))
assert(pcall(selectionBridge.drawSelection,selectionBridge,0,0,1))
assert(selectionBridge.transform.previewFilter=='linear','GPU do transform deveria estar suave')
assert(selectionBridge:applyTransform(selectionModel))
local red,_,blue,alpha=selTile:getPixel(30,30)
assert(red>0.70 and red<0.80 and blue>0.20 and blue<0.30 and alpha>0.99,
  'transformar Suave falhou com ImageData real')
assert(#selDoc.history.undo==1,'transformação suave gerou histórico extra')
assert(selectionBridge:historyStep(selectionModel,false),'desfazer suave falhou')
assert(selectionBridge:historyStep(selectionModel,true),'refazer suave falhou')
selectionBridge.filename='ci-paint-lua-v033.npnt'
assert(selectionBridge:save(),'não salvou seleção transformada com AA')
assert(selectionBridge:load(selectionModel),'não reabriu seleção transformada')
local persisted=assert(selectionBridge.doc.layers[1].tiles['0,0'])
local rr,_,bb,aa=persisted:getPixel(30,30)
assert(rr>0.70 and rr<0.80 and bb>0.20 and bb<0.30 and aa>0.99,
  'NPNT5 não preservou pixels da transformação suave')
love.filesystem.remove(selectionBridge.filename)
print('PASS: LÖVE real v0.33: suavização de seleção, filtro GPU, undo/redo, NPNT5')
