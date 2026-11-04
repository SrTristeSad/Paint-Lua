-- v0.25: máscaras e grupos acessíveis pela ponte da interface Ibis-Lua.
-- Rodar dentro de tests/test_core.lua, que instala um ImageData mock.
return function(check)
  local Doc=require('core.doc')
  local Groups=require('core.groups')
  local Mask=require('core.mask')
  local Hist=require('core.history')
  local Composite=require('core.composite')
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Project=require('core.project')

  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(64,64)
  local bridge=Bridge.new()
  local doc=bridge:sync(model)
  local layer=doc.layers[1]
  local tile=Doc.getTile(layer,0,0,true)
  tile:setPixel(32,32,0.9,0.2,0.1,1)
  Doc.markDirty(layer,'0,0')
  local function alpha()
    return select(4,Composite.flattenRegion(doc,32,32,1,1):getPixel(0,0))
  end
  check('v0.25: camada sem máscara visível',alpha()>0.9)
  check('v0.25: UI adiciona máscara de camada',bridge:layerMaskAction(model,'add')
    and layer.mask~=nil and layer.mask.default==1)
  check('v0.25: adição de máscara participa do histórico',#doc.history.undo==1)
  check('v0.25: UI entra em modo máscara de camada',bridge:editMask(model,'layer')
    and bridge:maskEditMode(model)=='layer')
  local view={pan_x=0,pan_y=0,zoom=1,rotation=0}
  local prefs={tool_position='left'}
  local cx=62+(1024-62-34)/2
  local cy=62+(768-160)/2
  model:set_tool('eraser');model:set_brush_size(12)
  check('v0.25: borracha da máscara inicia sem apagar RGBA',
    bridge:press(model,view,prefs,1,1024,768,cx,cy,100))
  bridge:finish(false)
  check('v0.25: borracha da máscara oculta camada',alpha()<0.01)
  check('v0.25: pintar máscara preserva pixels originais',
    select(4,tile:getPixel(32,32))==1 and select(1,tile:getPixel(32,32))==0.9)
  check('v0.25: máscara possui tile próprio',
    layer.mask.tiles['0,0']~=nil and Mask.value(layer.mask,32,32)<0.01)
  check('v0.25: desfazer do gesto de máscara',bridge:historyStep(model,false)
    and alpha()>0.9)
  check('v0.25: refazer do gesto de máscara',bridge:historyStep(model,true)
    and alpha()<0.01)
  check('v0.25: desativar máscara restaura imagem',
    bridge:layerMaskAction(model,'enabled') and alpha()>0.9)
  check('v0.25: reativar máscara esconde imagem',
    bridge:layerMaskAction(model,'enabled') and alpha()<0.01)
  check('v0.25: inverter máscara alterna cobertura',
    bridge:layerMaskAction(model,'inverted') and alpha()>0.9)
  check('v0.25: voltar ao modo pixels',bridge:editPixels()
    and bridge:maskEditMode(model)==nil)
  check('v0.25: remover máscara restaura pixels',
    bridge:layerMaskAction(model,'remove') and layer.mask==nil and alpha()>0.9)
  check('v0.25: desfazer restaura máscara removida',
    bridge:historyStep(model,false) and layer.mask~=nil)
  check('v0.25: refazer remove máscara novamente',
    bridge:historyStep(model,true) and layer.mask==nil)

  model:add_layer();bridge:sync(model)
  local nextLayer=doc.layers[2]
  local t2=Doc.getTile(nextLayer,0,0,true)
  t2:setPixel(32,32,0.2,0.8,0.2,1)
  Doc.markDirty(nextLayer,'0,0')
  check('v0.25: grupo de duas camadas cria hierarquia real',
    bridge:createGroup(model,true) and doc.layers[1].groupId==doc.layers[2].groupId)
  local group=bridge:activeGroup(model)
  check('v0.25: grupo pode validar contiguidade',group~=nil and Groups.validate(doc))
  check('v0.25: ocultar grupo oculta os pixels',
    bridge:groupAction(model,'visible') and alpha()<0.01)
  check('v0.25: revelar grupo mantém a composição',
    bridge:groupAction(model,'visible') and alpha()>0.9)
  check('v0.25: opacidade do grupo é aplicada',
    bridge:groupAction(model,'opacityMinus') and math.abs(alpha()-0.9)<0.01)
  check('v0.25: restaurar opacidade do grupo',
    bridge:groupAction(model,'opacityPlus') and math.abs(alpha()-1)<0.01)
  check('v0.25: UI adiciona máscara ao grupo',
    bridge:groupAction(model,'addMask') and group.mask~=nil)
  check('v0.25: UI permite pintar máscara do grupo',
    bridge:editMask(model,'group') and bridge:maskEditMode(model)=='group')
  model:set_tool('eraser')
  check('v0.25: máscara do grupo inicia pincel',
    bridge:press(model,view,prefs,1,1024,768,cx,cy,100))
  bridge:finish(false)
  check('v0.25: máscara do grupo afeta composição, não fontes',
    alpha()<0.01 and select(4,t2:getPixel(32,32))==1)
  check('v0.25: desfazer pintura máscara do grupo',
    bridge:historyStep(model,false) and alpha()>0.9)
  check('v0.25: refazer pintura máscara do grupo',
    bridge:historyStep(model,true) and alpha()<0.01)
  check('v0.25: inverter máscara do grupo',
    bridge:groupAction(model,'maskInverted') and alpha()>0.9)
  check('v0.25: alternar máscara do grupo',
    bridge:groupAction(model,'maskEnabled') and alpha()>0.9)
  check('v0.25: retirar máscara do grupo',
    bridge:groupAction(model,'removeMask') and group.mask==nil)
  check('v0.25: editar máscara ausente é bloqueado',
    not bridge:editMask(model,'group') and bridge:maskEditMode(model)==nil)
  check('v0.25: documento de grupo salvo no NPNT',bridge:save())
  local saved=assert(Project.load(bridge.filename))
  check('v0.25: grupo preservado após reabrir',
    saved.layers[1].groupId~=nil and saved.groups[saved.layers[1].groupId]~=nil)
  check('v0.25: grupo pode ser desfeito pela UI',
    bridge:ungroup(model) and doc.layers[1].groupId==nil and doc.layers[2].groupId==nil)
  check('v0.25: undo da desagregação restaura grupo',
    bridge:historyStep(model,false) and doc.layers[2].groupId~=nil)
  check('v0.25: redo da desagregação remove grupo',
    bridge:historyStep(model,true) and doc.layers[2].groupId==nil)
  check('v0.25: criar grupo de camada isolada',
    bridge:createGroup(model,false) and doc.layers[2].groupId~=nil)
  model:add_layer()
  bridge:sync(model)
  check('v0.25: nova camada no fim herda grupo do topo',
    doc.layers[3].groupId==doc.layers[2].groupId and Groups.validate(doc))
  check('v0.25: remover último grupo pode ser desfeito',
    bridge:ungroup(model) and #doc.layers==3 and Groups.validate(doc))
  check('v0.25: undo restaura grupo com dois filhos',
    bridge:historyStep(model,false) and Groups.validate(doc)
      and doc.layers[2].groupId==doc.layers[3].groupId)
  check('v0.25: edição não cria entradas por frame',
    (function()local n=#doc.history.undo;bridge:sync(model);bridge:sync(model)
    return #doc.history.undo==n end)())
end
