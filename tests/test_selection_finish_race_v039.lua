-- v0.39: preservar o gesto se o histórico bloquear na hora de soltar.
-- O bloqueio pode surgir após beginSelection por um job externo ao Bridge.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Selection=require('core.selection')
  local History=require('core.history')
  local Fill=require('core.fill')
  local Job=require('core.job')

  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(64,64)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  local original=assert(Selection.rect(doc,2,2,6,6))
  local other=assert(Selection.rect(doc,24,24,29,29))
  check('concluir bloqueado: primeira seleção entrou no histórico',
    bridge:applySelection(original) and #doc.history.undo==1)
  check('concluir bloqueado: segunda seleção entrou no histórico',
    bridge:applySelection(other) and #doc.history.undo==2)
  check('concluir bloqueado: undo prepara um redo legítimo',
    bridge:historyStep(model,false) and doc.selection==original
    and #doc.history.undo==1 and #doc.history.redo==1)

  model:set_tool('selection_rect')
  bridge.point=function() return 12,12 end
  check('concluir bloqueado: começa retângulo antes do balde',
    bridge:beginSelection(model,nil,nil,1,1024,768,120,120))
  local drag=bridge.selectionDrag
  drag.x,drag.y=18,18
  local function intact()
    return bridge.selectionDrag==drag and doc.selection==original
      and #doc.history.undo==1 and #doc.history.redo==1
  end

  local layer=doc.layers[doc.sel]
  local job=Fill.newJob(doc,layer,4,4,{0.8,0.2,0.1,1},0,nil,
    {yieldEvery=2})
  check('concluir bloqueado: balde externo chega após iniciar arraste',
    doc.history._fillLock~=nil and bridge.job==nil and intact())
  local ok,finished=pcall(bridge.finishSelection,bridge,model)
  check('concluir bloqueado: soltar durante lock recusa sem exceção',
    ok and finished==false and intact())
  check('concluir bloqueado: coordenadas do retângulo são preservadas',
    drag.startX==12 and drag.startY==12 and drag.x==18 and drag.y==18)
  check('concluir bloqueado: aviso explica que operação atual impede commit',
    bridge.status:find('Conclua a operação',1,true)~=nil and intact())

  local partial=false
  for i=1,400 do
    if job.done then break end
    Job.step(job,0)
    if doc.history.stroke and next(layer.tiles) then
      partial=true
      break
    end
  end
  check('concluir bloqueado: balde gerou pixels ainda provisórios',
    partial and not job.done and doc.history._fillLock~=nil)
  ok,finished=pcall(bridge.finishSelection,bridge,model)
  check('concluir bloqueado: lock com pixels também mantém arraste',
    ok and finished==false and intact()
    and doc.history.stroke~=nil and next(layer.tiles)~=nil)
  check('concluir bloqueado: cancelar balde remove pixels e lock',
    Job.cancel(job) and doc.history._fillLock==nil
    and doc.history.stroke==nil and next(layer.tiles)==nil)
  check('concluir bloqueado: retângulo retomado confirma sem refazer gesto',
    bridge:finishSelection(model) and bridge.selectionDrag==nil
    and doc.selection~=original
    and Selection.contains(doc.selection,15,15)
    and not Selection.contains(doc.selection,4,4))
  local committed=doc.selection
  check('concluir bloqueado: confirmação grava só um undo e limpa redo',
    #doc.history.undo==2 and #doc.history.redo==0)
  check('concluir bloqueado: undo restaura a seleção antiga',
    bridge:historyStep(model,false) and doc.selection==original)
  check('concluir bloqueado: redo retorna ao retângulo confirmado',
    bridge:historyStep(model,true) and doc.selection==committed)

  -- Um segundo tipo de concorrência pode abrir a transação de pincel
  -- diretamente em History, sem criar um job cooperativo.
  bridge:historyStep(model,false)
  local redoBefore=#doc.history.redo
  model:set_tool('lasso')
  bridge.point=function() return 10,10 end
  bridge:setSelectionMode('add')
  check('concluir bloqueado: começa laço para combinar com seleção antiga',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100))
  drag=bridge.selectionDrag
  local points={{10,10},{20,10},{20,20},{10,20}}
  drag.points=points
  local undoBefore=#doc.history.undo
  check('concluir bloqueado: modo e pontos do laço estão prontos',
    drag.mode=='add' and #drag.points==4 and doc.selection==original)
  History.begin(doc.history)
  check('concluir bloqueado: pincelada externa começa no meio do laço',
    doc.history.stroke~=nil and doc.history._fillLock==nil)
  ok,finished=pcall(bridge.finishSelection,bridge,model)
  check('concluir bloqueado: stroke externo mantém laço e redo',
    ok and finished==false and bridge.selectionDrag==drag
    and drag.points==points and doc.selection==original
    and #doc.history.undo==undoBefore and #doc.history.redo==redoBefore)
  check('concluir bloqueado: rollback externo permite confirmar laço',
    History.rollback(doc.history) and doc.history.stroke==nil)
  check('concluir bloqueado: laço confirmado aplica modo adicionar original',
    bridge:finishSelection(model) and bridge.selectionDrag==nil
    and Selection.contains(doc.selection,4,4)
    and Selection.contains(doc.selection,15,15)
    and not Selection.contains(doc.selection,40,40))
  local combined=doc.selection
  check('concluir bloqueado: confirmar laço registra um único snapshot',
    #doc.history.undo==undoBefore+1 and #doc.history.redo==0)
  check('concluir bloqueado: undo do laço retorna à seleção anterior',
    bridge:historyStep(model,false) and doc.selection==original)
  check('concluir bloqueado: redo do laço retorna à combinação',
    bridge:historyStep(model,true) and doc.selection==combined)

  -- Uma varinha pertencente à ponte é outro estado transitório.
  -- Mesmo que ela seja iniciada em código externo, não consumir o arraste.
  model:set_tool('selection_rect')
  bridge.point=function() return 31,31 end
  check('concluir bloqueado: inicia retângulo antes de outro job',
    bridge:beginSelection(model,nil,nil,1,1024,768,50,50))
  drag=bridge.selectionDrag
  drag.x,drag.y=35,35
  undoBefore=#doc.history.undo
  local concurrent=Job.new(function()
    coroutine.yield(0.25)
    return true
  end)
  bridge.job=concurrent
  bridge.jobKind='wand'
  ok,finished=pcall(bridge.finishSelection,bridge,model)
  check('concluir bloqueado: job da ponte não consome gesto',
    ok and finished==false and bridge.selectionDrag==drag
    and doc.selection==combined and #doc.history.undo==undoBefore)
  check('concluir bloqueado: cancelar o job conserva retângulo',
    bridge:cancelJob()==nil and concurrent.cancelled
    and bridge.selectionDrag==drag and bridge.job==nil)
  check('concluir bloqueado: confirmar retângulo após cancelar é reversível',
    bridge:finishSelection(model) and
    Selection.contains(doc.selection,33,33)
    and not Selection.contains(doc.selection,4,4)
    and #doc.history.undo==undoBefore+1)
  check('concluir bloqueado: undo final restaura combinação anterior',
    bridge:historyStep(model,false) and doc.selection==combined)

  -- Laço degenerado continua usando a política anterior: não gera
  -- seleção nem snapshot e não deixa um estado pendurado sem lock.
  model:set_tool('lasso')
  check('concluir bloqueado: laço inválido começa como gesto normal',
    bridge:beginSelection(model,nil,nil,1,1024,768,50,50))
  drag=bridge.selectionDrag
  undoBefore=#doc.history.undo
  check('concluir bloqueado: laço com menos de três pontos não confirma',
    not bridge:finishSelection(model) and
    bridge.selectionDrag==nil and #doc.history.undo==undoBefore)
end
