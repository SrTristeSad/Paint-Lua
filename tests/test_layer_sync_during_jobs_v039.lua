-- v0.39: propriedades leves da UI não atravessam jobs cooperativos.
-- Opacidade mantém contrato sem snapshot por atualização; layer switch é adiado.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Fill=require('core.fill')
  local Job=require('core.job')

  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(64,64)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  model:add_layer()
  check('sync leve: cria camada adicional',bridge:sync(model)==doc
    and #doc.layers==2 and doc.sel==2)
  local first=doc.layers[1]
  local second=doc.layers[2]
  local secondId=model.active_layer_id
  local undoBefore,redoBefore=#doc.history.undo,#doc.history.redo
  local function untouched()
    return doc.sel==2 and first.opacity==100 and second.opacity==100
      and #doc.history.undo==undoBefore
      and #doc.history.redo==redoBefore
  end

  -- Trabalho criado pelo motor, sem bridge.job: antes mesmo de
  -- sua primeira fatia, a camada em uso deve permanecer estável.
  local fill=Fill.newJob(doc,second,5,5,{0.7,0.3,0.2,1},0,nil,
    {yieldEvery=2})
  check('sync leve: job externo segura token e não pertence à ponte',
    doc.history._fillLock~=nil and bridge.job==nil and untouched())
  model:set_layer_opacity(secondId,38)
  local ok,delayed=pcall(bridge.sync,bridge,model)
  check('sync leve: opacidade isolada é adiada antes do primeiro pixel',
    ok and delayed==nil and untouched())
  model:select_layer(model.layers[1].id)
  ok,delayed=pcall(bridge.sync,bridge,model)
  check('sync leve: troca de camada ativa é adiada durante balde',
    ok and delayed==nil and untouched())
  check('sync leve: referência do balde continua na camada original',
    doc.layers[2]==second and doc.history._fillLock~=nil)

  local hasPixels=false
  for i=1,400 do
    if fill.done then break end
    Job.step(fill,0)
    if doc.history.stroke and next(second.tiles) then
      hasPixels=true
      break
    end
  end
  check('sync leve: preenchimento parcial mantém lock transacional',
    hasPixels and not fill.done and doc.history.stroke~=nil)
  ok,delayed=pcall(bridge.sync,bridge,model)
  check('sync leve: opacidade e camada continuam adiadas com pixels temporários',
    ok and delayed==nil and untouched())
  check('sync leve: cancelar balde externo remove pixels parciais',
    Job.cancel(fill) and doc.history._fillLock==nil and
    doc.history.stroke==nil and next(second.tiles)==nil and untouched())

  -- A política existente é não inserir uma entrada de undo por
  -- frame de slider ou por troca da camada selecionada.
  check('sync leve: após rollback aplica opacidade e camada pendentes',
    bridge:sync(model)==doc and second.opacity==38 and doc.sel==1
    and next(second.tiles)==nil)
  check('sync leve: aplicação de propriedades leves não cria snapshot',
    #doc.history.undo==undoBefore and #doc.history.redo==redoBefore)
  check('sync leve: sincronizar repetidamente não altera histórico',
    bridge:sync(model)==doc and #doc.history.undo==undoBefore
    and #doc.history.redo==redoBefore)

  -- A varinha não possui _fillLock, mas usa uma camada de origem que
  -- não deve ser trocada ou ter suas propriedades atualizadas durante o job.
  bridge.point=function() return 8,8 end
  model:set_tool('magic_wand')
  check('sync leve: varinha inicia na camada vigente',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100)
    and bridge.job~=nil and bridge.jobKind=='wand')
  local wand=bridge.job
  model:set_layer_opacity(model.layers[1].id,62)
  ok,delayed=pcall(bridge.sync,bridge,model)
  check('sync leve: opacidade isolada é adiada durante varinha',
    ok and delayed==nil and first.opacity==100
    and bridge.job==wand and doc.sel==1)
  model:select_layer(secondId)
  ok,delayed=pcall(bridge.sync,bridge,model)
  check('sync leve: camada ativa é adiada durante varinha',
    ok and delayed==nil and first.opacity==100
    and bridge.job==wand and doc.sel==1)
  bridge:cancelJob()
  check('sync leve: cancelar varinha libera job sem alterar histórico',
    bridge.job==nil and #doc.history.undo==undoBefore
    and #doc.history.redo==redoBefore)
  check('sync leve: alterações pendentes aplicam após cancelar varinha',
    bridge:sync(model)==doc and doc.sel==2
    and first.opacity==62 and second.opacity==38)
  check('sync leve: duas operações leves não criam histórico extra',
    #doc.history.undo==undoBefore and #doc.history.redo==redoBefore)

  -- Alterações estruturais continuam a usar exatamente um snapshot.
  local oldName=second.name
  model:rename_layer(secondId,'Renomeada após balde')
  check('sync leve: renomear depois do lock cria único snapshot',
    bridge:sync(model)==doc and second.name=='Renomeada após balde'
    and #doc.history.undo==undoBefore+1)
  check('sync leve: undo da estrutura restaura nome sem alterar opacidades',
    bridge:historyStep(model,false) and second.name==oldName
    and first.opacity==62 and second.opacity==38)
  check('sync leve: redo preserva nome e opacidades pós-gesto',
    bridge:historyStep(model,true) and second.name=='Renomeada após balde'
    and first.opacity==62 and second.opacity==38)
end
