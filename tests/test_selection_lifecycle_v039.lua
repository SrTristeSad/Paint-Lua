-- Ciclo de vida de seleções: atalhos durante gesto e lock de balde externo.
-- A UI não deve descartar um arraste nem amostrar pixels temporários da pintura.
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
  local original=assert(Selection.rect(doc,2,2,6,6))
  local second=assert(Selection.rect(doc,20,20,24,24))
  check('ciclo: primeira seleção registrada',bridge:applySelection(original))
  check('ciclo: segunda seleção registrada',bridge:applySelection(second))
  check('ciclo: undo prepara histórico de redo',
    bridge:historyStep(model,false) and doc.selection==original
      and #doc.history.undo==1 and #doc.history.redo==1)

  -- Evita dependência de coordenadas de tela: verificamos a transação,
  -- não o cálculo de viewport já coberto pelos testes de interface.
  bridge.point=function() return 12,12 end
  model:set_tool('selection_rect')
  check('ciclo: retângulo inicia com histórico existente',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100))
  local pending=bridge.selectionDrag
  local function intact()
    return doc.selection==original and bridge.selectionDrag==pending
      and #doc.history.undo==1 and #doc.history.redo==1
  end
  local okUndo,undone=pcall(bridge.historyStep,bridge,model,false)
  check('ciclo: undo não descarta arraste nem aplica histórico anterior',
    okUndo and undone==false and intact())
  local okRedo,redone=pcall(bridge.historyStep,bridge,model,true)
  check('ciclo: redo não descarta arraste nem reaplica histórico',
    okRedo and redone==false and intact())
  check('ciclo: mensagem instrui finalizar gesto sem tocar seleção',
    bridge.status:find('arraste',1,true)~=nil and intact())
  pending.x,pending.y=14,14
  check('ciclo: confirmar arraste gera um único snapshot',
    bridge:finishSelection(model) and doc.selection~=original
      and Selection.contains(doc.selection,13,13)
      and not Selection.contains(doc.selection,3,3)
      and #doc.history.undo==2 and #doc.history.redo==0)
  local committed=doc.selection
  check('ciclo: undo após confirmar restaura seleção original',
    bridge:historyStep(model,false) and doc.selection==original)
  check('ciclo: redo após confirmar restaura nova seleção',
    bridge:historyStep(model,true) and doc.selection==committed)
  local undoCount,redoCount=#doc.history.undo,#doc.history.redo

  -- Um balde criado diretamente no motor não é Bridge.job. A seleção
  -- antiga precisa sobreviver e nenhuma varinha poderá ler pixels parciais.
  local layer=doc.layers[doc.sel]
  local job=Fill.newJob(doc,layer,5,5,{0.8,0.3,0.2,1},0,nil,
    {yieldEvery=2})
  local function stable()
    return doc.selection==committed and #doc.history.undo==undoCount
      and #doc.history.redo==redoCount
  end
  check('ciclo: preenchimento externo mantém lock fora de Bridge.job',
    doc.history._fillLock~=nil and bridge.job==nil and stable())
  model:set_tool('magic_wand')
  local okWand,wand=pcall(bridge.beginSelection,bridge,model,nil,nil,
    1,1024,768,100,100)
  check('ciclo: varinha não pode começar durante lock externo',
    okWand and wand==false and bridge.job==nil and stable())
  model:set_tool('selection_rect')
  local okRect,rect=pcall(bridge.beginSelection,bridge,model,nil,nil,
    1,1024,768,100,100)
  check('ciclo: novo retângulo não inicia durante preenchimento',
    okRect and rect==false and bridge.selectionDrag==nil and stable())
  check('ciclo: undo não entra no histórico de balde externo',
    not bridge:historyStep(model,false) and stable())
  check('ciclo: redo não entra no histórico de balde externo',
    not bridge:historyStep(model,true) and stable())

  local partially=false
  for i=1,400 do
    if job.done then break end
    Job.step(job,0)
    if doc.history.stroke and select(4,Fill.pixel(layer,5,5))==1 then
      partially=true;break
    end
  end
  check('ciclo: preenchimento cooperativo produziu pixels parciais',
    partially and doc.history._fillLock~=nil and not job.done)
  model:set_tool('magic_wand')
  check('ciclo: varinha segue bloqueada após pixels parciais',
    not bridge:beginSelection(model,nil,nil,1,1024,768,100,100)
      and bridge.job==nil and stable())
  check('ciclo: undo não cancela preenchimento parcial',
    not bridge:historyStep(model,false) and doc.history._fillLock~=nil
      and stable())
  check('ciclo: cancelar balde externo reverte pixels e lock',
    Job.cancel(job) and doc.history._fillLock==nil
      and doc.history.stroke==nil and next(layer.tiles)==nil and stable())

  check('ciclo: varinha pode iniciar após cancelar o balde',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100)
      and bridge.job~=nil and bridge.jobKind=='wand')
  bridge:cancelJob()
  check('ciclo: cancelar varinha preserva seleção e histórico',
    bridge.job==nil and stable())
  model:set_tool('selection_rect')
  check('ciclo: retângulo volta a iniciar após cancelar',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100)
      and bridge.selectionDrag~=nil and stable())
  bridge.selectionDrag.x,bridge.selectionDrag.y=16,16
  check('ciclo: confirmar seleção após desbloqueio continua reversível',
    bridge:finishSelection(model) and #doc.history.undo==undoCount+1
      and #doc.history.redo==0 and Selection.contains(doc.selection,15,15))
end
