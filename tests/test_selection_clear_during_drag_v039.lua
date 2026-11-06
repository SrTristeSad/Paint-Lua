-- Regressão v0.39: desmarcar não cancela o gesto antes da proteção central.
-- Atalho e painel compartilham o contrato de não alterar histórico no arraste.
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
  local second=assert(Selection.rect(doc,20,20,24,24))
  check('Ctrl+D: seleção inicial entra no histórico',
    bridge:applySelection(original) and #doc.history.undo==1)
  check('Ctrl+D: seleção seguinte entra no histórico',
    bridge:applySelection(second) and #doc.history.undo==2)
  check('Ctrl+D: desfazer cria redo anterior ao novo arraste',
    bridge:historyStep(model,false) and doc.selection==original
      and #doc.history.undo==1 and #doc.history.redo==1)

  model:set_tool('selection_rect')
  bridge.point=function() return 12,12 end
  check('Ctrl+D: gesto retangular começa com histórico de redo',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100))
  local drag=bridge.selectionDrag
  local function intact()
    return doc.selection==original and bridge.selectionDrag==drag
      and #doc.history.undo==1 and #doc.history.redo==1
  end
  check('Ctrl+D: ação de desmarcar recusa sem descartar gesto',
    bridge:clearSelection()==false and intact())
  check('Ctrl+D: recusa tem mensagem de operação pendente',
    bridge.status:find('operação atual',1,true)~=nil and intact())

  -- O mesmo método é chamado pelo atalho Ctrl+D: a ponte deve consumir
  -- a tecla mas não desfazer o arraste em andamento.
  local oldKeyboard=love.keyboard
  love.keyboard={isDown=function(...)
    for i=1,select('#',...) do
      if select(i,...)=='lctrl' then return true end
    end
    return false
  end}
  check('Ctrl+D: atalho é consumido sem remover seleção original',
    bridge:key(model,'d') and intact())
  love.keyboard=oldKeyboard
  check('Ctrl+D: gesto mantém as coordenadas e modo originais',
    drag.mode=='replace' and drag.startX==12 and drag.startY==12
    and drag.x==12 and drag.y==12 and intact())
  drag.x,drag.y=15,15
  check('Ctrl+D: gesto ainda conclui depois da recusa',
    bridge:finishSelection(model) and bridge.selectionDrag==nil
      and Selection.contains(doc.selection,13,13)
      and not Selection.contains(doc.selection,5,5))
  local committed=doc.selection
  check('Ctrl+D: confirmação grava somente um snapshot e limpa redo',
    #doc.history.undo==2 and #doc.history.redo==0)
  check('Ctrl+D: desmarcar após confirmar realmente limpa seleção',
    bridge:clearSelection() and doc.selection==nil
      and #doc.history.undo==3)
  check('Ctrl+D: primeiro undo restaura seleção confirmada',
    bridge:historyStep(model,false) and doc.selection==committed)
  check('Ctrl+D: segundo undo recupera seleção original',
    bridge:historyStep(model,false) and doc.selection==original)
  check('Ctrl+D: primeiro redo restaura gesto confirmado',
    bridge:historyStep(model,true) and doc.selection==committed)
  check('Ctrl+D: segundo redo recupera a ausência de seleção',
    bridge:historyStep(model,true) and doc.selection==nil)

  check('Ctrl+D: iniciar novo gesto funciona sem seleção prévia',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100))
  local emptyDrag=bridge.selectionDrag
  local undoCount,redoCount=#doc.history.undo,#doc.history.redo
  check('Ctrl+D: desmarcar não encerra gesto mesmo sem seleção prévia',
    not bridge:clearSelection() and bridge.selectionDrag==emptyDrag
      and doc.selection==nil and #doc.history.undo==undoCount
      and #doc.history.redo==redoCount)
  -- Escape é o cancelamento explícito documentado pela UI.
  bridge.selectionDrag=nil
  check('Ctrl+D: cancelar explicitamente deixa histórico intocado',
    doc.selection==nil and #doc.history.undo==undoCount
      and #doc.history.redo==redoCount)
  check('Ctrl+D: sem seleção nem gesto, desmarcar continua no-op',
    not bridge:clearSelection() and #doc.history.undo==undoCount)
  check('Ctrl+D: voltar a selecionar após cancelamento funciona',
    bridge:applySelection(original) and doc.selection==original
      and #doc.history.undo==undoCount+1)

  -- Mesmo sem gesto da interface, um Fill.newJob externo ainda está
  -- escrevendo tiles de forma cooperativa: inverter/combinar devem
  -- recusar ANTES de rasterizar ou criar máscaras temporárias.
  local job=Fill.newJob(doc,doc.layers[doc.sel],5,5,
    {0.7,0.2,0.1,1},0,nil,{yieldEvery=2})
  check('Ctrl+D: lock de balde externo ativo sem bridge.job',
    doc.history._fillLock~=nil and bridge.job==nil)
  local originalInvert=Selection.invert
  local invertCalls=0
  Selection.invert=function(...)
    invertCalls=invertCalls+1
    return originalInvert(...)
  end
  local okInvert,inverted=pcall(bridge.invertSelection,bridge,model)
  Selection.invert=originalInvert
  check('Ctrl+D: inversão recusa lock antes de calcular máscara',
    okInvert and inverted==false and invertCalls==0
      and doc.selection==original)
  local originalCombine=Selection.combine
  local combineCalls=0
  Selection.combine=function(...)
    combineCalls=combineCalls+1
    return originalCombine(...)
  end
  local okCombine,combined=pcall(bridge.combineSelection,bridge,second,'add')
  Selection.combine=originalCombine
  check('Ctrl+D: combinação recusa lock antes de calcular união',
    okCombine and combined==false and combineCalls==0
      and doc.selection==original)
  check('Ctrl+D: lock externo também recusa desmarcar',
    not bridge:clearSelection() and doc.selection==original
      and #doc.history.undo==undoCount+1)
  check('Ctrl+D: cancelar balde libera histórico e reverte pixels',
    Job.cancel(job) and doc.history._fillLock==nil and
    doc.history.stroke==nil and
    next(doc.layers[doc.sel].tiles)==nil)
  check('Ctrl+D: operações voltam a funcionar após rollback',
    bridge:invertSelection(model) and
    not Selection.contains(doc.selection,5,5) and
    Selection.contains(doc.selection,20,20)
      and #doc.history.undo==undoCount+2)
  check('Ctrl+D: undo da inversão restaura seleção sem alterar pixels',
    bridge:historyStep(model,false) and doc.selection==original
      and next(doc.layers[doc.sel].tiles)==nil)
end
