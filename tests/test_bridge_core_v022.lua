-- Testa a integração sobre o mock de ImageData definido em test_core.lua.
return function(check)
  local Model=require('src.model')
  local View=require('src.viewport')
  local Pref=require('src.editor_preferences')
  local Bridge=require('app.paint_bridge')
  local Hist=require('core.history')
  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(64,64)
  local bridge=Bridge.new()
  local d=assert(bridge:sync(model))
  local pref=Pref.new()
  local view=View.new()
  local cx=(pref.tool_position=='left' and 62 or 0)
    +(1024-(pref.tool_position=='left' and 62 or 0)
       -(pref.tool_position=='right' and 75 or 34))/2
  local cy=62+(768-160)/2
  check('ponte: projeto inicial tem uma camada',#d.layers==1)
  check('ponte: início não gera histórico de estrutura',#d.history.undo==0)
  bridge:sync(model)
  check('ponte: frames sem alterações não geram undo',#d.history.undo==0)
  local id=model:add_layer()
  bridge:sync(model)
  check('ponte: adicionar camada grava uma única ação estrutural',
    #d.layers==2 and #d.history.undo==1)
  model:toggle_layer_visibility(id)
  bridge:sync(model)
  check('ponte: visibilidade atinge camada real e histórico',
    not d.layers[2].visible and #d.history.undo==2)
  bridge:sync(model)
  check('ponte: sincronização idempotente',#d.history.undo==2)
  model:set_layer_blending(id,'Multiply')
  bridge:sync(model)
  check('ponte: blending faz parte do motor',d.layers[2].blend=='multiply')
  model:toggle_layer_clipping(id)
  bridge:sync(model)
  check('ponte: clipping faz parte do motor',d.layers[2].clipped)
  model:set_layer_opacity(id,42)
  bridge:sync(model)
  check('ponte: slider de opacidade atinge motor',d.layers[2].opacity==42)
  check('ponte: slider não gera entrada de histórico por frame',#d.history.undo==4)
  -- A sincronização reversa impede que a UI reaplique a propriedade desfeita.
  local oldKeyboard=love.keyboard
  love.keyboard={isDown=function() return true end}
  local okUndo=bridge:key(model,'z')
  bridge:sync(model)
  check('ponte: Ctrl+Z restaura clipping e mantém UI sincronizada',
    okUndo and not model:active_layer().clipping and not d.layers[2].clipped)
  bridge:key(model,'y')
  bridge:sync(model)
  check('ponte: Ctrl+Y reaplica clipping sem duplicar undo',
    model:active_layer().clipping and d.layers[2].clipped)
  -- Restaura condições para exercitar as ferramentas raster.
  model:toggle_layer_clipping(id)
  model:set_layer_blending(id,'Normal')
  model:toggle_layer_visibility(id)
  model:set_layer_opacity(id,100)
  bridge:sync(model)
  model:set_color(200,20,10)
  model:set_tool('bucket')
  local started=bridge:press(model,view,pref,1,1024,768,cx,cy,100)
  check('ponte: balde cria trabalho cooperativo',started and bridge.job~=nil)
  local loops=0
  while bridge.job and loops<200 do bridge:update();loops=loops+1 end
  check('ponte: balde conclui sem travar estado',bridge.job==nil and loops<200)
  local r,g,b,a=require('core.fill').pixel(d.layers[2],32,32)
  check('ponte: balde modifica pixels reais',a>0 and r>g and r>b)
  model:set_tool('eyedropper');model:set_color(0,0,0)
  check('ponte: conta-gotas coleta cor composta',
    bridge:press(model,view,pref,1,1024,768,cx,cy,100)
    and model.color[1]>model.color[2])
  -- Alpha Lock no documento da UI impede novos pixels em uma camada vazia.
  local newId=model:add_layer();bridge:sync(model)
  model:toggle_layer_alpha_lock(newId)
  model:set_tool('brush')
  model:set_color(255,0,0);model:set_brush_size(12)
  started=bridge:press(model,view,pref,1,1024,768,cx,cy,100)
  bridge:finish(false)
  check('ponte: Alpha Lock está ligado ao pincel',started and next(d.layers[3].tiles)==nil)
  -- Novo projeto NPNT deve ser lido sem perder as propriedades gravadas.
  model:toggle_layer_alpha_lock(newId)
  model:toggle_layer_clipping(newId)
  bridge:sync(model)
  local saved=bridge:save()
  check('ponte: grava projeto real após editar camadas',saved==true)
  local loaded=bridge:load(model)
  check('ponte: reabre projeto e reconstruí o modelo de camadas',
    loaded and #model.layers==3 and model.layers[3].clipping and
    model.active_layer_id==model.layers[3].id)
  check('ponte: save/load preserva modo e visibilidade do motor',
    bridge.doc.layers[3].clipped and bridge.doc.layers[2].visible)
  love.keyboard=oldKeyboard
end
