-- Auditoria de concorrência de seleções no editor v0.39.
-- Regressão: Ctrl+A podia criar histórico durante arraste ou prévia de PNG.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Selection=require('core.selection')
  local History=require('core.history')
  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(64,64)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  local first=assert(Selection.rect(doc,4,4,7,7))
  doc.selection=first
  local function unchanged()
    return doc.selection==first and #doc.history.undo==0
      and #doc.history.redo==0
  end
  local all=assert(Selection.rect(doc,0,0,63,63))
  local other=assert(Selection.rect(doc,12,12,15,15))

  -- Arraste ainda não confirmado. A UI poderá continuar o gesto depois.
  local drag={kind='selection_rect',mode='replace',
    startX=12,startY=12,x=15,y=15}
  bridge.selectionDrag=drag
  check('seleção em arraste: Ctrl+A recusado sem histórico',
    not bridge:selectAll(model) and unchanged())
  check('seleção em arraste: API central bloqueia substituição',
    not bridge:applySelection(other) and unchanged())
  check('seleção em arraste: inversão bloqueada',
    not bridge:invertSelection(model) and unchanged())
  check('seleção em arraste: combinação bloqueada',
    not bridge:combineSelection(other,'add') and unchanged())
  check('seleção em arraste: gesto não foi cancelado pela ação recusada',
    bridge.selectionDrag==drag and bridge.status:find('operação atual',1,true)~=nil)
  check('seleção em arraste: soltar mouse conclui uma operação',
    bridge:finishSelection(model) and doc.selection~=first
      and Selection.contains(doc.selection,13,13)
      and not Selection.contains(doc.selection,5,5)
      and #doc.history.undo==1 and bridge.selectionDrag==nil)
  check('seleção em arraste: undo restaura região original',
    bridge:historyStep(model,false) and doc.selection==first
      and Selection.contains(doc.selection,5,5))
  check('seleção em arraste: redo recupera seleção confirmada',
    bridge:historyStep(model,true)
      and Selection.contains(doc.selection,13,13))
  -- Reiniciar histórico e seleção somente para os próximos cenários.
  doc.selection=first
  doc.history.undo={}
  doc.history.redo={}

  -- A prévia não pode ser desincronizada por outro atalho.
  local preview={}
  bridge.pngPreview=preview
  check('prévia PNG: Ctrl+A não interfere na obra',
    not bridge:selectAll(model) and unchanged())
  check('prévia PNG: desmarcar é recusado sem snapshot',
    not bridge:clearSelection() and unchanged())
  check('prévia PNG: API central não substitui seleção',
    not bridge:applySelection(all) and unchanged())
  check('prévia PNG: inversão continua recusada',
    not bridge:invertSelection(model) and unchanged())
  check('prévia PNG: contexto da importação é mantido',
    bridge.pngPreview==preview and unchanged())
  bridge.pngPreview=nil

  -- History.stroke também é usado pelo motor, sem Bridge.stroke.
  History.begin(doc.history)
  check('pincelada no histórico: Ctrl+A recusado',
    not bridge:selectAll(model) and unchanged())
  check('pincelada no histórico: desmarcar recusado',
    not bridge:clearSelection() and unchanged())
  check('pincelada no histórico: API central bloqueada',
    not bridge:applySelection(other) and unchanged())
  check('pincelada no histórico: continua reversível e ativa',
    doc.history.stroke~=nil and History.rollback(doc.history) and unchanged())

  -- A proteção é limitada ao estado transitório. Após concluir o gesto,
  -- não pode bloquear seleções legítimas, nem criar entradas extras.
  check('após concluir operação: Ctrl+A volta a funcionar',
    bridge:selectAll(model) and Selection.contains(doc.selection,63,63)
      and #doc.history.undo==1)
  check('após concluir operação: desmarcar volta a funcionar',
    bridge:clearSelection() and doc.selection==nil
      and #doc.history.undo==2)
  check('após concluir operação: undo de desmarcar restaura tudo',
    bridge:historyStep(model,false) and doc.selection~=nil
      and Selection.contains(doc.selection,63,63))
  check('após concluir operação: redo restaura ausência de seleção',
    bridge:historyStep(model,true) and doc.selection==nil)
end
