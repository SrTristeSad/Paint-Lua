-- Integração: o bloqueio do balde cooperativo deve alcançar a ponte do editor.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Selection=require('core.selection')
  local Fill=require('core.fill')
  local Job=require('core.job')
  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(64,64)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  local original=assert(Selection.rect(doc,4,4,7,7))
  local full=assert(Selection.rect(doc,0,0,63,63))
  doc.selection=original
  local history=doc.history
  local function intact()
    return doc.selection==original and #history.undo==0 and #history.redo==0
  end

  -- O job pertence ao motor e não consta em bridge.job: isto também deve
  -- ser seguro, sem gerar a assertiva de History.recordStructure.
  local job=Fill.newJob(doc,doc.layers[doc.sel],5,5,
    {0.3,0.6,0.9,1},0,nil,{yieldEvery=2})
  check('balde externo: histórico bloqueado antes da primeira fatia',
    history._fillLock~=nil and bridge.job==nil and intact())
  local okAll,changedAll=pcall(bridge.selectAll,bridge,model)
  check('balde externo: Ctrl+A retorna false, sem exceção nem histórico',
    okAll and changedAll==false and intact())
  local okApply,changedApply=pcall(bridge.applySelection,bridge,full)
  check('balde externo: seleção direta não altera documento',
    okApply and changedApply==false and intact())
  local okClear,changedClear=pcall(bridge.clearSelection,bridge)
  check('balde externo: Desmarcar não libera a pintura',
    okClear and changedClear==false and intact())
  local okInv,changedInv=pcall(bridge.invertSelection,bridge,model)
  check('balde externo: Inverter é recusado sem falhar',
    okInv and changedInv==false and intact())
  local okComb,changedComb=pcall(bridge.combineSelection,bridge,full,'add')
  check('balde externo: Combinar é recusado sem falhar',
    okComb and changedComb==false and intact())
  check('balde externo: propriedades estruturais são bloqueadas',
    bridge:canEditStructure(model)==nil and intact())

  local oldName=doc.layers[doc.sel].name
  model.layers[1].name='Camada editada durante balde'
  local okSync,delayed=pcall(bridge.sync,bridge,model)
  check('balde externo: sincronização adia nome de camada sem exceção',
    okSync and delayed==nil and doc.layers[1].name==oldName and intact())
  check('balde externo: alterar camada pendente preserva o lock',
    history._fillLock~=nil and not job.done and bridge.doc==doc)

  -- Processa uma parte do balde para testar a combinação de lock e stroke.
  local partially=false
  for i=1,400 do
    if job.done then break end
    Job.step(job,0)
    if history.stroke and select(4,Fill.pixel(doc.layers[doc.sel],5,5))==1 then
      partially=true;break
    end
  end
  check('balde externo: execução parcial deixa a pincelada transacional',
    partially and not job.done and history.stroke~=nil)
  local okPart,resPart=pcall(bridge.applySelection,bridge,full)
  check('balde externo: pixels parciais não permitem alterar seleção',
    okPart and resPart==false and intact())
  local okPartSync,resSync=pcall(bridge.sync,bridge,model)
  check('balde externo: mudanças de camada continuam adiadas durante pintura',
    okPartSync and resSync==nil and doc.layers[1].name==oldName and intact())
  local cancelled=Job.cancel(job)
  check('balde externo: cancelar desfaz os pixels e desbloqueia histórico',
    cancelled and history._fillLock==nil and history.stroke==nil
    and next(doc.layers[doc.sel].tiles)==nil and intact())

  local restored=bridge:sync(model)
  check('balde externo: propriedade adiada aplica após cancelar',
    restored==doc and doc.layers[1].name=='Camada editada durante balde'
    and #history.undo==1 and doc.selection==original)
  check('balde externo: Ctrl+A retoma e registra um único undo',
    bridge:selectAll(model) and doc.selection~=original
    and Selection.contains(doc.selection,63,63) and #history.undo==2)
  check('balde externo: undo de Ctrl+A recupera seleção anterior',
    bridge:historyStep(model,false) and doc.selection==original
    and Selection.contains(doc.selection,5,5))
  check('balde externo: redo de Ctrl+A recupera seleção total',
    bridge:historyStep(model,true)
    and Selection.contains(doc.selection,63,63))
  check('balde externo: documento final sem pixels artificiais',
    next(doc.layers[doc.sel].tiles)==nil and history._fillLock==nil)
end
