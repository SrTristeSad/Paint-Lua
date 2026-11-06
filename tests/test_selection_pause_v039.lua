-- v0.39: controle de animação, persistência retrocompatível e GPU.
return function(check)
  local Preferences=require('src.editor_preferences')
  local Bridge=require('app.paint_bridge')
  local Selection=require('core.selection')
  local Mask=require('core.mask')
  local Model=require('src.model')
  local function close(a,b) return math.abs(a-b)<0.0001 end

  local p=Preferences.new()
  check('v0.39: contorno animado permanece default',
    p.animate_selection_outline==true)
  local defaultFile=p:encode()
  check('v0.39: arquivo salva campo aditivo na versão 1',
    defaultFile:find('version=1\n',1,true)==1 and
    defaultFile:find('animate_selection_outline=1\n',1,true)~=nil)
  check('v0.39: alternar pausa desativa',not p:toggle_selection_animation()
    and not p.animate_selection_outline)
  local pausedBytes=p:encode()
  check('v0.39: estado pausado serializa zero',
    pausedBytes:find('animate_selection_outline=0\n',1,true)~=nil)
  local restored=Preferences.decode(pausedBytes)
  check('v0.39: restauro mantém pausa',not restored.animate_selection_outline
    and restored:encode()==pausedBytes)
  check('v0.39: alternar novamente reativa',
    restored:toggle_selection_animation() and restored.animate_selection_outline)
  local oldFile=defaultFile:gsub('animate_selection_outline=1\n','')
  check('v0.39: formato v1 anterior aceita campo ausente',
    Preferences.decode(oldFile).animate_selection_outline==true)
  local bad=pausedBytes:gsub('animate_selection_outline=0',
    'animate_selection_outline=talvez')
  check('v0.39: valor inválido é rejeitado',
    not pcall(Preferences.decode,bad))
  check('v0.39: propriedade duplicada é rejeitada',
    not pcall(Preferences.decode,pausedBytes..'animate_selection_outline=1\n'))
  check('v0.39: propriedades desconhecidas seguem rejeitadas',
    not pcall(Preferences.decode,pausedBytes..'shader_code=unsafe\n'))
  check('v0.39: não altera configurações antigas',
    Preferences.decode(pausedBytes).tool_position=='left' and
    Preferences.decode(pausedBytes).show_undo_message==true)

  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(64,64)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  local selection=Selection.rect(doc,4,4,18,18)
  doc.selection=selection
  check('v0.39: novo Bridge começa animado',bridge.selectionAnimated)
  local beforeUndo=#doc.history.undo
  local created,released,uniforms=0,0,{}
  local shader,colors,rects=nil,{},{}
  local current={name='anterior'}
  local prior=current
  local fake={
    newShader=function()
      created=created+1
      return {send=function(self,key,value)
        uniforms[#uniforms+1]={key,value}
      end,release=function()released=released+1 end}
    end,
    getShader=function() return current end,
    setShader=function(s) current=s end,
    setColor=function(...) colors[#colors+1]={...} end,
    setLineWidth=function() end,
    rectangle=function(mode,x,y,w,h)
      rects[#rects+1]={mode,x,y,w,h,current}
    end,
    line=function() end,
  }
  local oldGraphics=love.graphics
  love.graphics=fake
  local ok,reason=pcall(function()
    assert(bridge:setSelectionAnimation(false))
    bridge:drawSelection(0,0,1,0)
    bridge:drawSelection(0,0,5,0.25)
  end)
  love.graphics=oldGraphics
  check('v0.39: pausa não chama compilador do shader',
    ok and created==0 and bridge.ants.shader==nil,reason)
  check('v0.39: contorno estático visível em dois quadros',
    #rects==2 and rects[1][2]==4 and rects[2][2]==4)
  check('v0.39: contorno estático mantém estado gráfico',
    current==prior and rects[1][6]==prior and rects[2][6]==prior)
  check('v0.39: pausa não registra fase de animação',
    bridge.ants.lastPhase==nil and #uniforms==0)
  check('v0.39: pausa idempotente',not bridge:setSelectionAnimation(false))
  local pausedSelection=doc.selection
  love.graphics=fake
  local resumed=pcall(function()
    assert(bridge:setSelectionAnimation(true))
    bridge:drawSelection(0,0,1,0)
    bridge:drawSelection(0,0,1,0.25)
  end)
  love.graphics=oldGraphics
  check('v0.39: retomada compila uma única vez',
    resumed and created==1 and bridge.ants.shader~=nil)
  check('v0.39: retomada avança fase novamente',
    #uniforms==2 and close(uniforms[1][2],0)
    and close(uniforms[2][2],6))
  check('v0.39: retomada preserva geometria dos quadros estáticos',
    #rects==4 and rects[3][2]==rects[1][2]
    and rects[4][4]==rects[2][4])
  check('v0.39: shader externo restaurado depois da retomada',
    current==prior)
  check('v0.39: desligar libera shader já compilado',
    bridge:setSelectionAnimation(false) and released==1
    and bridge.ants.shader==nil and bridge.ants.lastPhase==nil)
  local timeCount=#uniforms
  love.graphics=fake
  local staticOK=pcall(bridge.drawSelection,bridge,0,0,2,8)
  love.graphics=oldGraphics
  check('v0.39: pausa prolongada não envia uniforms',
    staticOK and #uniforms==timeCount and created==1)
  check('v0.39: valor não booleano é recusado sem alterar estado',
    not pcall(bridge.setSelectionAnimation,bridge,'false')
    and bridge.selectionAnimated==false)
  check('v0.39: preferência não altera máscara/pixels/histórico',
    doc.selection==pausedSelection
    and Selection.contains(doc.selection,10,10)
    and not Selection.contains(doc.selection,50,50)
    and next(doc.layers[doc.sel].tiles)==nil
    and #doc.history.undo==beforeUndo)

  -- A seleção invertida conserva o mesmo cache ao pausar e retomar.
  local mask=Mask.new(0)
  local tile=Mask.getTile(mask,0,0,true)
  tile:setPixel(9,9,1,1,1,1)
  mask.inverted=true
  doc.selection={kind='wand',x=0,y=0,w=64,h=64,mask=mask}
  love.graphics=fake
  local maskOK=pcall(bridge.drawSelection,bridge,0,0,1,20)
  love.graphics=oldGraphics
  local cache=bridge.selectionOutline
  local hasHole=false
  if cache and cache.segments then
    for _,edge in ipairs(cache.segments) do
      if edge[1]==10 and edge[2]==9
        and edge[3]==9 and edge[4]==9 then hasHole=true end
    end
  end
  check('v0.39: contorno invertido estático continua exato',
    maskOK and cache and cache.segments and hasHole)
  love.graphics=fake
  local backOn=pcall(function()
    bridge:setSelectionAnimation(true)
    bridge:drawSelection(0,0,3,20.5)
  end)
  love.graphics=oldGraphics
  check('v0.39: retomada não perde cache de máscara invertida',
    backOn and bridge.selectionOutline==cache and created==2)
  check('v0.39: seleção invertida mantém máscara/histórico',
    mask.inverted and not Selection.contains(doc.selection,9,9)
    and Selection.contains(doc.selection,0,0)
    and #doc.history.undo==beforeUndo)
end
