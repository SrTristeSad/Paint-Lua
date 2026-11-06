-- v0.39: trocar de documento não pode abandonar trabalho iniciado fora da ponte.
-- Jobs que pertencem ao Bridge continuam cancelados com rollback normalmente.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Doc=require('core.doc')
  local Selection=require('core.selection')
  local Fill=require('core.fill')
  local Job=require('core.job')
  local History=require('core.history')

  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(48,48)
  local bridge=Bridge.new()
  local original=assert(bridge:sync(model))
  local originalModel=model.document
  local layer=original.layers[original.sel]
  local firstEntry=bridge.uiByLayer[layer]
  local selected=assert(Selection.rect(original,1,1,5,5))
  check('troca externa: seleção anterior registrada',
    bridge:applySelection(selected) and #original.history.undo==1)
  local undoBefore=#original.history.undo

  local external=Fill.newJob(original,layer,20,20,{1,0,0,1},0,nil,
    {yieldEvery=2})
  check('troca externa: job do motor não é controlado pela ponte',
    external and bridge.job==nil and original.history._fillLock~=nil)
  local target=Doc.new(20,20,'Destino')
  local ok=bridge:attachDocument(model,target,89)
  check('troca externa: anexo recusado antes da primeira fatia',
    ok==false and bridge.doc==original and model.document==originalModel
      and original.history._fillLock~=nil and not external.cancelled)
  check('troca externa: ID, mapa e seleção não são alterados',
    bridge.artworkId==nil and bridge.uiByLayer[layer]==firstEntry
      and original.selection==selected and #original.history.undo==undoBefore)
  local partial=false
  for _=1,400 do
    if external.done then break end
    Job.step(external,0)
    if original.history.stroke and next(layer.tiles) then
      partial=true
      break
    end
  end
  check('troca externa: balde mantém pixels provisórios e transação',
    partial and not external.done and original.history._fillLock~=nil
      and original.history.stroke~=nil)
  ok=bridge:attachDocument(model,target,89)
  check('troca externa: anexo recusado também após pixels parciais',
    ok==false and bridge.doc==original and model.document==originalModel
      and not external.cancelled and original.history.stroke~=nil)

  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(16,16)
  local changedModel=model.document
  check('troca externa: a UI solicitou documento novo',
    changedModel~=originalModel and model.screen=='editor')
  check('troca externa: sync não abandona fill externo em nova tela',
    bridge:sync(model)==nil and bridge.doc==original
      and bridge.modelDocument==originalModel and
      bridge.uiByLayer[layer]==firstEntry)
  check('troca externa: pixels, locks e histórico seguem recuperáveis',
    original.history._fillLock~=nil and original.history.stroke~=nil
      and next(layer.tiles)~=nil and not external.cancelled
      and original.selection==selected and
      #original.history.undo==undoBefore)
  check('troca externa: mensagem indica necessidade de encerrar operação',
    bridge.status:find('operação externa',1,true)~=nil)
  check('troca externa: cancelamento pelo dono reverte a transação',
    Job.cancel(external) and original.history._fillLock==nil
      and original.history.stroke==nil and next(layer.tiles)==nil
      and #original.history.undo==undoBefore)
  local fresh=bridge:sync(model)
  check('troca externa: trocar após cancelar funciona normalmente',
    fresh and fresh~=original and fresh.w==16 and fresh.h==16
      and bridge.modelDocument==changedModel)
  check('troca externa: obra nova não herda referências nem seleção antiga',
    bridge.uiByLayer[layer]==nil and fresh.selection==nil
      and #fresh.history.undo==0 and #fresh.history.redo==0)

  -- Uma History.begin externa não usa _fillLock: impedir a troca
  -- tanto via anexo quanto via sync de um novo canvas.
  History.begin(fresh.history)
  local redoBefore=#fresh.history.redo
  local another=Doc.new(12,12,'Outra obra')
  check('troca externa: pincelada direta detém History.stroke',
    fresh.history.stroke~=nil and fresh.history._fillLock==nil)
  check('troca externa: anexo bloqueia History.stroke não pertencente à ponte',
    bridge:attachDocument(model,another,95)==false
      and bridge.doc==fresh and model.document==changedModel
      and fresh.history.stroke~=nil)
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(10,10)
  check('troca externa: sync bloqueia pincelada direta pendente',
    bridge:sync(model)==nil and bridge.doc==fresh
      and fresh.history.stroke~=nil and
      #fresh.history.redo==redoBefore)
  check('troca externa: rollback externo permite sincronizar nova obra',
    History.rollback(fresh.history) and bridge:sync(model)~=nil
      and bridge.doc~=fresh and bridge.doc.w==10 and
      bridge.doc.h==10)

  -- Jobs controlados pela ponte podem ser cancelados pelo próprio Bridge,
  -- mantendo o comportamento histórico da troca de obras.
  local ownedDoc=bridge.doc
  local ownedLayer=ownedDoc.layers[ownedDoc.sel]
  local owned=Fill.newJob(ownedDoc,ownedLayer,6,6,{0,1,0,1},0,nil,
    {yieldEvery=2})
  bridge.job=owned
  bridge.jobKind='fill'
  local ownedPartial=false
  for _=1,400 do
    if owned.done then break end
    Job.step(owned,0)
    if next(ownedLayer.tiles) then ownedPartial=true;break end
  end
  check('troca externa: preenchimento da ponte está ativo',
    ownedPartial and ownedDoc.history._fillLock~=nil
      and bridge.job==owned)
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(8,8)
  local latest=bridge:sync(model)
  check('troca externa: sync continua cancelando job que pertence à ponte',
    latest and latest~=ownedDoc and latest.w==8
      and owned.cancelled and bridge.job==nil
      and ownedDoc.history._fillLock==nil and
      ownedDoc.history.stroke==nil)
  check('troca externa: rollback do job próprio preserva pixels anteriores',
    next(ownedLayer.tiles)==nil and #ownedDoc.history.undo==0)
end
