-- v0.39: falha de geometria/combinação ao soltar não perde um gesto.
-- O limite de 2 milhões de pixels é uma recusa recuperável, não um commit.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Selection=require('core.selection')

  local function editor(w,h)
    local model=Model.new()
    model:open_gallery()
    model:open_new_canvas()
    model:create_canvas(w,h)
    local bridge=Bridge.new()
    local doc=assert(bridge:sync(model))
    bridge.point=function() return 12,12 end
    return model,bridge,doc
  end

  -- A combinação de uma seleção integral não pode materializar mais de
  -- 256 tiles. Preservar inclusive a pilha de redo já existente.
  local model,bridge,doc=editor(4096,4096)
  local full=assert(Selection.rect(doc,0,0,4095,4095))
  local small=assert(Selection.rect(doc,100,100,103,103))
  check('combinação recusada: seleção integral registrada',
    bridge:applySelection(full))
  check('combinação recusada: segunda seleção cria undo',
    bridge:applySelection(small))
  check('combinação recusada: undo recupera seleção integral e redo',
    bridge:historyStep(model,false) and doc.selection==full
      and #doc.history.undo==1 and #doc.history.redo==1)
  model:set_tool('selection_rect')
  bridge:setSelectionMode('subtract')
  check('combinação recusada: arraste subtrair inicia normalmente',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100))
  local drag=bridge.selectionDrag
  drag.x,drag.y=25,25
  local undoBefore,redoBefore=#doc.history.undo,#doc.history.redo
  local ok,result=pcall(bridge.finishSelection,bridge,model)
  check('combinação recusada: não causa exceção nem descarta gesto',
    ok and result==false and bridge.selectionDrag==drag
      and drag.mode=='subtract' and drag.x==25 and drag.y==25)
  check('combinação recusada: limite real informado ao usuário',
    bridge.status:find('Combinação excede',1,true)~=nil)
  check('combinação recusada: seleção e duas pilhas não mudam',
    doc.selection==full and #doc.history.undo==undoBefore
      and #doc.history.redo==redoBefore)
  check('combinação recusada: repetição não produz snapshot',
    not bridge:finishSelection(model) and bridge.selectionDrag==drag
      and #doc.history.undo==undoBefore and #doc.history.redo==redoBefore)
  -- A UI usa Escape para cancelar um arraste que continua pendente.
  bridge.selectionDrag=nil
  bridge:setSelectionMode('replace')
  check('combinação recusada: outro gesto pode começar após cancelar',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100))
  bridge.selectionDrag.x,bridge.selectionDrag.y=20,20
  check('combinação recusada: retângulo substituto confirma normalmente',
    bridge:finishSelection(model) and bridge.selectionDrag==nil
      and Selection.contains(doc.selection,15,15)
      and not Selection.contains(doc.selection,200,200)
      and #doc.history.undo==undoBefore+1 and #doc.history.redo==0)
  check('combinação recusada: undo posterior ainda restaura seleção integral',
    bridge:historyStep(model,false) and doc.selection==full)

  -- Erros na geometria do arraste devem ser tratados como falha recuperável.
  model,bridge,doc=editor(64,64)
  model:set_tool('selection_rect')
  check('geometria recusada: inicia retângulo',
    bridge:beginSelection(model,nil,nil,1,800,600,100,100))
  drag=bridge.selectionDrag
  drag.x=math.huge
  ok,result=pcall(bridge.finishSelection,bridge,model)
  check('geometria recusada: retângulo inválido não causa crash',
    ok and result==false and bridge.selectionDrag==drag
      and bridge.status:find('Retângulo inválido',1,true)~=nil)
  check('geometria recusada: sem alteração de seleção/histórico',
    doc.selection==nil and #doc.history.undo==0)
  drag.x,drag.y=18,18
  check('geometria recusada: corrigir retângulo permite confirmar',
    bridge:finishSelection(model) and bridge.selectionDrag==nil
      and Selection.contains(doc.selection,15,15)
      and #doc.history.undo==1)
  local prior=doc.selection
  model:set_tool('lasso')
  check('laço inválido: inicia gesto',
    bridge:beginSelection(model,nil,nil,1,800,600,100,100))
  drag=bridge.selectionDrag
  drag.points={{12,12},{math.huge,12},{25,25},{12,25}}
  ok,result=pcall(bridge.finishSelection,bridge,model)
  check('laço inválido: pontos incorretos não descartam gesto',
    ok and result==false and bridge.selectionDrag==drag
      and bridge.status:find('Laço inválido',1,true)~=nil)
  check('laço inválido: seleção anterior permanece com histórico',
    doc.selection==prior and #doc.history.undo==1)
  drag.points={{12,12},{25,12},{25,25},{12,25}}
  check('laço inválido: corrigir pontos permite confirmar',
    bridge:finishSelection(model) and bridge.selectionDrag==nil
      and doc.selection~=prior and #doc.history.undo==2)
  check('laço inválido: undo restaura seleção original',
    bridge:historyStep(model,false) and doc.selection==prior)

  -- Um arraste sem área continua sendo consumido como antes.
  model:set_tool('lasso')
  check('seleção vazia: gesto degenerado pode começar',
    bridge:beginSelection(model,nil,nil,1,800,600,100,100))
  drag=bridge.selectionDrag
  check('seleção vazia: não deixa gesto pendente nem gera undo',
    not bridge:finishSelection(model) and bridge.selectionDrag==nil
      and #doc.history.undo==1 and #doc.history.redo==1)
end
