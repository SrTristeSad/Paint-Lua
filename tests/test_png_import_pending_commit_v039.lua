-- v0.39: confirmar importação PNG não pode apagar edições pendentes do painel.
-- A importação e as propriedades da UI continuam sendo ações distintas de undo.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local PNGImport=require('src.png_import')

  local function editor()
    local model=Model.new()
    model:open_gallery()
    model:open_new_canvas()
    model:create_canvas(48,48)
    local bridge=Bridge.new()
    local doc=assert(bridge:sync(model))
    model:add_layer()
    assert(bridge:sync(model)==doc)
    return model,bridge,doc
  end
  local function preview(bridge,doc,name,alpha)
    local image=love.image.newImageData(2,2)
    if alpha~=false then image:setPixel(0,0,0.8,0.2,0.1,1) end
    local session=PNGImport.preview(doc,image,name)
    bridge.pngPreview=session
    return session
  end

  -- Sem mudanças pendentes, a importação mantém o PNG recém-inserido
  -- ativo e não grava snapshot extra para o painel.
  local model,bridge,doc=editor()
  local baseline=#doc.history.undo
  local session=preview(bridge,doc,'normal.png')
  check('PNG confirmar: prévia real inicia sem modificar camadas',
    session.active and #doc.layers==2 and #doc.history.undo==baseline)
  check('PNG confirmar: PNG normal confirmado',
    bridge:applyPNGImport(model) and #doc.layers==3 and
    doc.layers[3].name=='PNG: normal')
  local png=doc.layers[3]
  check('PNG confirmar: importação sem pendências deixa PNG ativo',
    doc.sel==3 and model.active_layer_id==model.layers[3].id and
    bridge.byId[model.active_layer_id]==png)
  check('PNG confirmar: PNG sem pendências grava somente um undo',
    #doc.history.undo==baseline+1 and #doc.history.redo==0 and
    not session.active and bridge.pngPreview==nil)
  check('PNG confirmar: desfazer importação remove a nova camada',
    bridge:historyStep(model,false) and #doc.layers==2 and
    #doc.history.redo==1)
  check('PNG confirmar: refazer importação restaura PNG ativo',
    bridge:historyStep(model,true) and #doc.layers==3 and
    doc.layers[3]==png and doc.sel==3)

  -- A prévia pode durar vários frames; alterações no painel são
  -- adiadas por sync. Confirmar não deve apagá-las com refreshModel.
  model,bridge,doc=editor()
  baseline=#doc.history.undo
  local first,second=doc.layers[1],doc.layers[2]
  local firstId,secondId=model.layers[1].id,model.layers[2].id
  local firstName=first.name
  local oldSecondOpacity=second.opacity
  session=preview(bridge,doc,'pendente.png')
  model:rename_layer(firstId,'Camada renomeada no painel')
  model:set_layer_opacity(secondId,46)
  model:set_layer_blending(secondId,'Multiply')
  model:toggle_layer_clipping(secondId)
  model:toggle_layer_visibility(firstId)
  model:select_layer(firstId)
  check('PNG confirmar: propriedades realmente ficaram pendentes',
    bridge:sync(model)==nil and first.name==firstName and
    second.opacity==oldSecondOpacity and doc.sel==2 and
    #doc.history.undo==baseline)
  check('PNG confirmar: sessão e seleção aguardam confirmação',
    bridge.pngPreview==session and session.active and
    model.active_layer_id==firstId)
  check('PNG confirmar: confirma sem descartar edição do painel',
    bridge:applyPNGImport(model) and
    #doc.layers==3 and not session.active)
  png=doc.layers[3]
  check('PNG confirmar: mantém nova camada com pixels reais',
    png.name=='PNG: pendente' and
    png.tiles['0,0']~=nil and
    select(4,png.tiles['0,0']:getPixel(23,23))>0)
  check('PNG confirmar: nome e visibilidade pendentes preservados',
    first.name=='Camada renomeada no painel' and first.visible==false
    and model.layers[1].name==first.name)
  check('PNG confirmar: opacidade, blend e recorte pendentes aplicados',
    second.opacity==46 and second.blend=='multiply'
    and second.clipped and model.layers[2].opacity==46)
  check('PNG confirmar: seleção intencional do painel é respeitada',
    doc.sel==1 and model.active_layer_id==firstId and
    bridge.byId[firstId]==first)
  check('PNG confirmar: importação e painel têm snapshots separados',
    #doc.history.undo==baseline+2 and #doc.history.redo==0)
  check('PNG confirmar: undo do painel mantém PNG no documento',
    bridge:historyStep(model,false) and #doc.layers==3
    and doc.layers[3]==png and doc.sel==3)
  check('PNG confirmar: primeiro undo restaura propriedades anteriores',
    first.name==firstName and first.visible==true and
    second.opacity==oldSecondOpacity and second.blend=='normal'
    and not second.clipped)
  check('PNG confirmar: segundo undo remove somente a importação',
    bridge:historyStep(model,false) and #doc.layers==2 and
    doc.layers[1]==first and doc.layers[2]==second)
  check('PNG confirmar: dois redo restauram operações na mesma ordem',
    bridge:historyStep(model,true) and #doc.layers==3 and
    bridge:historyStep(model,true) and
    #doc.layers==3 and doc.sel==1 and
    first.name=='Camada renomeada no painel' and second.opacity==46)

  -- Também preservar criação de camada pendente, em vez de perdê-la
  -- ao reconstruir a lista depois de anexar a camada do PNG.
  model,bridge,doc=editor()
  baseline=#doc.history.undo
  session=preview(bridge,doc,'mais-uma.png')
  local pendingId=model.next_layer_id
  model:add_layer()
  check('PNG confirmar: nova camada só existe no modelo durante prévia',
    model.active_layer_id==pendingId and #model.layers==3
    and #doc.layers==2 and bridge:sync(model)==nil)
  check('PNG confirmar: importa PNG e mantém camada nova pendente',
    bridge:applyPNGImport(model) and #doc.layers==4
    and #model.layers==4 and #doc.history.undo==baseline+2)
  png=doc.layers[4]
  check('PNG confirmar: IDs distintos e ordem preservada',
    doc.layers[3].name=='Camada demonstrativa '..pendingId and png.name=='PNG: mais-uma'
    and model.layers[3].id==pendingId and
    model.layers[4].id~=pendingId)
  check('PNG confirmar: seleção da camada criada é respeitada',
    doc.sel==3 and model.active_layer_id==pendingId)
  check('PNG confirmar: undo da adição mantém camada PNG',
    bridge:historyStep(model,false) and #doc.layers==3
    and doc.layers[3]==png and doc.sel==3)
  check('PNG confirmar: undo seguinte remove PNG sem alterar outras',
    bridge:historyStep(model,false) and #doc.layers==2)
  check('PNG confirmar: redo recompõe PNG e camada adicionada',
    bridge:historyStep(model,true) and
    bridge:historyStep(model,true) and #doc.layers==4 and doc.sel==3)

  -- Falha ao aplicar PNG não pode consumar alterações do painel:
  -- a prévia permanece ativa e só depois do cancelamento sync é liberado.
  model,bridge,doc=editor()
  baseline=#doc.history.undo
  local originalName=doc.layers[1].name
  session=preview(bridge,doc,'vazio.png',false)
  model:rename_layer(model.layers[1].id,'Nome após falha')
  check('PNG confirmar: transparência total provoca falha segura',
    not bridge:applyPNGImport(model) and
    #doc.layers==2 and #doc.history.undo==baseline)
  check('PNG confirmar: falha preserva sessão e alterações na UI',
    bridge.pngPreview==session and session.active
    and model.layers[1].name=='Nome após falha'
    and doc.layers[1].name==originalName)
  check('PNG confirmar: cancelar falha deixa pendência aplicável',
    bridge:cancelPNGImport() and bridge:sync(model)==doc
    and doc.layers[1].name=='Nome após falha'
    and #doc.history.undo==baseline+1)
end
