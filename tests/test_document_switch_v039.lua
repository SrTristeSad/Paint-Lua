-- v0.39: ao trocar de obra, cancelar gestos e liberar referências antigas.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Doc=require('core.doc')
  local Selection=require('core.selection')
  local Project=require('core.project')
  local Fill=require('core.fill')
  local Job=require('core.job')

  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(64,64)
  local bridge=Bridge.new()
  local previous=assert(bridge:sync(model))
  local previousLayer=previous.layers[previous.sel]
  local previousEntry=bridge.uiByLayer[previousLayer]
  local excluded=assert(Selection.rect(previous,5,5,9,9))
  previous.selection=assert(Selection.invert(previous,excluded))
  local oldSelection=previous.selection
  bridge.selectionOutline={selection=oldSelection,
    job=Selection.startOutline(oldSelection)}
  check('troca: cache incremental segura seleção da obra antiga',
    bridge.selectionOutline.selection==oldSelection and
    bridge.selectionOutline.job.selection==oldSelection)
  check('troca: mapa de camadas referencia obra anterior',
    previousEntry~=nil and bridge.byId[previousEntry.id]==previousLayer)
  check('troca: modo de combinação anterior é subtração',
    bridge:setSelectionMode('subtract') and bridge.selectionMode=='subtract')

  -- Usar o mesmo job cooperativo do motor de pintura; por ser uma
  -- operação da ponte, attachDocument deve cancelá-lo com rollback.
  local fill=Fill.newJob(previous,previousLayer,20,20,{1,0,0,1},
    0,oldSelection,{yieldEvery=2})
  bridge.job=fill
  bridge.jobKind='fill'
  local partial=false
  for i=1,150 do
    if fill.done then break end
    Job.step(fill,0)
    if next(previousLayer.tiles) then partial=true;break end
  end
  check('troca: balde ainda ativo possui pixels provisórios',
    partial and not fill.done and previous.history._fillLock~=nil)
  local previousUndo=#previous.history.undo

  -- Reabrir arquivo NPNT real, em vez de trocar por um objeto fictício.
  local destination=Doc.new(24,24,'Nova pintura')
  destination.selection=assert(Selection.rect(destination,2,2,4,4))
  local loaded=assert(Project.decode(Project.encode(destination)))
  local loadedSelection=loaded.selection
  check('troca: seleção do novo arquivo foi decodificada',
    Selection.contains(loadedSelection,3,3) and
    not Selection.contains(loadedSelection,12,12))
  check('troca: anexar projeto da galeria conclui mudança',
    bridge:attachDocument(model,loaded,42))
  check('troca: projeto aberto substitui ponte e dimensões do modelo',
    bridge.doc==loaded and bridge.modelDocument==model.document and
    model.document.width==24 and model.document.height==24)
  check('troca: arquivo e ID passam a pertencer à nova obra',
    bridge.artworkId==42 and bridge.filename=='gallery/works/42.npnt')
  check('troca: balde antigo é cancelado e seu histórico liberado',
    fill.cancelled and bridge.job==nil and
    previous.history._fillLock==nil and previous.history.stroke==nil)
  check('troca: pixels provisórios da obra antiga foram revertidos',
    next(previousLayer.tiles)==nil and #previous.history.undo==previousUndo)
  check('troca: a nova obra não herda pixels ou undo do balde',
    next(loaded.layers[loaded.sel].tiles)==nil and
    #loaded.history.undo==0 and #loaded.history.redo==0)
  check('troca: ponte libera referências das camadas antigas',
    bridge.uiByLayer[previousLayer]==nil and
    bridge.byId[previousEntry.id]~=previousLayer)
  check('troca: mapa contém só camadas do novo documento',
    bridge.uiByLayer[loaded.layers[1]]~=nil and
    bridge.uiByLayer[loaded.layers[2]]~=nil)
  check('troca: contorno incremental anterior foi descartado',
    bridge.selectionOutline==nil)
  check('troca: primeira seleção da obra abre em modo substituir',
    bridge.selectionMode=='replace' and
    bridge.jobSelectionMode==nil)
  check('troca: seleção NPNT da obra recém-aberta foi preservada',
    loaded.selection==loadedSelection and
    Selection.contains(loaded.selection,3,3))

  -- O primeiro gesto na segunda obra deve substituir sua seleção,
  -- não tentar aplicar a subtração que estava ativa na obra antiga.
  model:set_tool('selection_rect')
  bridge.point=function() return 8,8 end
  check('troca: primeira ferramenta retangular pode começar',
    bridge:beginSelection(model,nil,nil,1,1024,768,10,10) and
    bridge.selectionDrag and bridge.selectionDrag.mode=='replace')
  bridge.selectionDrag.x,bridge.selectionDrag.y=12,12
  check('troca: primeiro gesto substitui, sem herdar modo anterior',
    bridge:finishSelection(model) and
    Selection.contains(loaded.selection,10,10) and
    not Selection.contains(loaded.selection,3,3) and
    #loaded.history.undo==1)
  check('troca: undo na obra nova recupera sua própria seleção',
    bridge:historyStep(model,false) and
    loaded.selection==loadedSelection)
  check('troca: redo não acessa a pintura anterior',
    bridge:historyStep(model,true) and
    Selection.contains(loaded.selection,10,10) and
    next(loaded.layers[loaded.sel].tiles)==nil)

  local secondLayer=loaded.layers[loaded.sel]
  bridge.selectionOutline={selection=loaded.selection}
  bridge:setSelectionMode('intersect')
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(16,16)
  local fresh=assert(bridge:sync(model))
  check('troca: criar tela nova troca objeto e limpa seleção',
    fresh~=loaded and fresh.w==16 and fresh.h==16 and
    fresh.selection==nil)
  check('troca: nova tela não conserva referências antigas',
    bridge.uiByLayer[secondLayer]==nil and
    bridge.selectionOutline==nil and bridge.selectionMode=='replace')
  check('troca: nova tela inicializa histórico sem ações herdadas',
    #fresh.history.undo==0 and #fresh.history.redo==0)
end
