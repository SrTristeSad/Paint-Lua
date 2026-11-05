-- v0.39: operações visuais não podem receber mutações indiretas de camada
-- via sync. Mudanças no modelo ficam pendentes até confirmar ou cancelar.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Selection=require('core.selection')
  local PNGImport=require('src.png_import')

  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(48,48)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  model:add_layer()
  check('prévia sync: camada de trabalho criada',bridge:sync(model)==doc
    and #doc.layers==2 and doc.sel==2)
  local first,second=doc.layers[1],doc.layers[2]
  local firstId,secondId=model.layers[1].id,model.layers[2].id
  local oldName=second.name
  doc.selection=assert(Selection.rect(doc,2,2,8,8))

  -- Transform.begin usa a camada atual. Trocar camada/nome/opacidade
  -- antes de confirmar poderia deformar o estado do histórico.
  local before=#doc.history.undo
  model:set_tool('transform')
  check('prévia sync: transformação real inicia na camada 2',
    bridge:startTransform(model) and bridge.transform.layer==second)
  local transform=bridge.transform
  model:set_layer_opacity(secondId,35)
  model:rename_layer(secondId,'Camada após transformação')
  model:select_layer(firstId)
  local ok,delayed=pcall(bridge.sync,bridge,model)
  check('prévia sync: mudança estrutural e leve é adiada',
    ok and delayed==nil and doc.sel==2 and second.name==oldName
    and second.opacity==100 and #doc.history.undo==before)
  check('prévia sync: sessão de transformação continua ativa',
    bridge.transform==transform and transform.active
    and transform.layer==second)
  check('prévia sync: comando estrutural respeita bloqueio',
    bridge:canEditStructure(model)==nil and bridge.transform==transform)
  check('prévia sync: aviso do bloqueio não vira documento ausente',
    bridge.status:find('prévia',1,true)~=nil)
  check('prévia sync: cancelar transformação não cria histórico',
    bridge:cancelTransform() and not transform.active
    and doc.sel==2 and #doc.history.undo==before)
  check('prévia sync: mudanças pendentes aplicam após cancelar transformação',
    bridge:sync(model)==doc and doc.sel==1
    and second.name=='Camada após transformação'
    and second.opacity==35 and #doc.history.undo==before+1)
  check('prévia sync: undo restaura nome/opacidade e camada anteriores',
    bridge:historyStep(model,false) and doc.sel==2 and
    second.name==oldName and second.opacity==100)
  check('prévia sync: redo recupera propriedades sem perder seleção',
    bridge:historyStep(model,true) and doc.sel==1 and
    second.name=='Camada após transformação' and second.opacity==35
    and Selection.contains(doc.selection,3,3))

  -- Importação PNG: a prévia mantém posição do desenho sobre o
  -- documento; alterações concorrentes não entram nele antes de cancelar.
  before=#doc.history.undo
  local src=love.image.newImageData(2,2)
  src:setPixel(0,0,0.8,0.1,0.2,1)
  local session=PNGImport.preview(doc,src,'camada.png')
  bridge.pngPreview=session
  bridge.pngModel=model
  local firstName=first.name
  model:rename_layer(firstId,'Renomeada após prévia PNG')
  model:set_layer_opacity(firstId,52)
  model:select_layer(secondId)
  ok,delayed=pcall(bridge.sync,bridge,model)
  check('prévia sync: importação PNG adia nome/opacidade/camada ativa',
    ok and delayed==nil and first.name==firstName
    and first.opacity==100 and doc.sel==1
    and #doc.history.undo==before)
  check('prévia sync: sessão PNG não é cancelada ao recusar sync',
    bridge.pngPreview==session and session.active)
  check('prévia sync: operações estruturais recusadas com motivo correto',
    bridge:canEditStructure(model)==nil and
    bridge.status:find('prévia',1,true)~=nil)
  check('prévia sync: cancelar PNG não modifica seleção ou histórico',
    bridge:cancelPNGImport() and not session.active
    and bridge.pngPreview==nil
    and Selection.contains(doc.selection,3,3)
    and #doc.history.undo==before)
  check('prévia sync: edição pendente é aplicada após cancelar PNG',
    bridge:sync(model)==doc and first.name=='Renomeada após prévia PNG'
    and first.opacity==52 and doc.sel==2
    and #doc.history.undo==before+1)
  check('prévia sync: undo e redo da edição posterior são isolados',
    bridge:historyStep(model,false) and first.name==firstName and
    bridge:historyStep(model,true) and
    first.name=='Renomeada após prévia PNG')

  -- Arraste de seleção: a nova região ainda não foi confirmada, então
  -- mudar camadas no mesmo quadro não pode redirecionar o gesto.
  model:set_tool('selection_rect')
  bridge.point=function() return 12,12 end
  before=#doc.history.undo
  local oldSelection=doc.selection
  local oldSecondName=second.name
  check('prévia sync: arraste de retângulo inicia com camada 2',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100))
  local drag=bridge.selectionDrag
  model:rename_layer(secondId,'Renomeada após arraste')
  model:set_layer_opacity(secondId,64)
  model:select_layer(firstId)
  ok,delayed=pcall(bridge.sync,bridge,model)
  check('prévia sync: arraste adia mudanças de camada',
    ok and delayed==nil and doc.sel==2
    and second.name==oldSecondName and second.opacity==35
    and doc.selection==oldSelection and
    #doc.history.undo==before)
  check('prévia sync: gesto não é descartado ao recusar alterações',
    bridge.selectionDrag==drag)
  drag.x,drag.y=16,16
  check('prévia sync: soltar confirma seleção na obra original',
    bridge:finishSelection(model) and
    bridge.selectionDrag==nil and doc.selection~=oldSelection
    and Selection.contains(doc.selection,14,14)
    and #doc.history.undo==before+1)
  local selected=doc.selection
  check('prévia sync: sincronizar mudança de camada após confirmação',
    bridge:sync(model)==doc and doc.sel==1
    and second.name=='Renomeada após arraste'
    and second.opacity==64 and #doc.history.undo==before+2)
  check('prévia sync: undo primeiro desfaz somente nome/camada',
    bridge:historyStep(model,false) and doc.sel==2
    and second.name==oldSecondName
    and doc.selection==selected)
  check('prévia sync: undo seguinte desfaz seleção confirmada',
    bridge:historyStep(model,false) and doc.selection==oldSelection
    and Selection.contains(doc.selection,3,3))
  check('prévia sync: redo restaura seleção e mudanças separadamente',
    bridge:historyStep(model,true) and doc.selection==selected
    and bridge:historyStep(model,true) and doc.sel==1
    and second.name=='Renomeada após arraste')
end
