-- v0.39: alterações do painel não podem atravessar pinceladas da ponte,
-- nem congelar o movimento de um gesto quando sync adia as propriedades.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Stroke=require('core.stroke')
  local Selection=require('core.selection')
  local PNGImport=require('src.png_import')

  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(64,64)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  model:add_layer()
  check('traço sync: segunda camada criada',
    bridge:sync(model)==doc and #doc.layers==2 and doc.sel==2)
  local first,second=doc.layers[1],doc.layers[2]
  local firstId,secondId=model.layers[1].id,model.layers[2].id
  local oldName=second.name
  local baseline=#doc.history.undo
  local W,H=800,600
  local view={pan_x=0,pan_y=0,rotation=0,zoom=1}
  local prefs={tool_position='left'}
  local function screen(px,py)
    local left,right=62,34
    local aw,ah=W-left-right,H-160
    local ds=math.min(aw/doc.w,ah/doc.h,1.1)
    local cx=left+aw/2
    local cy=62+ah/2
    return cx+(px-doc.w/2)*ds,cy+(py-doc.h/2)*ds
  end
  local function newStroke(layer)
    return Stroke.new(doc,layer,doc.history,
      {size=3,alpha=1,hardness=1,color={0.9,0.2,0.1},
       smoothing={mode='exponential',amount=0}})
  end

  local stroke=newStroke(second)
  bridge.stroke=stroke
  stroke:push(8,8,1,0)
  local stamps=stroke.stampCount
  check('traço sync: pincel real abriu transação e escreveu pixels',
    stamps>0 and doc.history.stroke~=nil and
      second.tiles['0,0']~=nil and bridge.stroke==stroke)
  check('traço sync: modelo sem diferenças ainda sincroniza durante pincel',
    bridge:sync(model)==doc and #doc.history.undo==baseline
    and not stroke.closed)

  model:set_layer_opacity(secondId,42)
  local ok,value=pcall(bridge.sync,bridge,model)
  check('traço sync: opacidade adiada durante pincelada interna',
    ok and value==nil and second.opacity==100
    and doc.sel==2 and bridge.stroke==stroke and
    #doc.history.undo==baseline)
  model:select_layer(firstId)
  ok,value=pcall(bridge.sync,bridge,model)
  check('traço sync: troca de camada adiada durante pincelada interna',
    ok and value==nil and doc.sel==2 and
    second.opacity==100 and doc.history.stroke~=nil)
  model:rename_layer(secondId,'Nome após pincel')
  model:toggle_layer_visibility(firstId)
  ok,value=pcall(bridge.sync,bridge,model)
  check('traço sync: nome e visibilidade pendentes não encerram pincel',
    ok and value==nil and second.name==oldName
    and first.visible and not stroke.closed and
    doc.history.stroke~=nil and #doc.history.undo==baseline)
  check('traço sync: referência e camada original permanecem durante gesto',
    bridge.stroke==stroke and stroke.layer==second and
    doc.layers[doc.sel]==second)

  -- Conversão de coordenadas deve continuar usando doc.w/h originais
  -- enquanto as propriedades do modelo aguardam a soltura do mouse.
  local rx,ry=screen(21,20)
  local px,py=bridge:toCanvas(model,view,prefs,1,W,H,rx,ry)
  check('traço sync: coordenadas do documento continuam disponíveis',
    px and py and math.abs(px-21)<1e-6 and math.abs(py-20)<1e-6)
  check('traço sync: movimento do pincel prossegue com painel pendente',
    bridge:move(model,view,prefs,1,W,H,rx,ry) and
    stroke.stampCount>stamps and not stroke.closed)
  check('traço sync: movimento não aplicou mudanças pendentes',
    second.opacity==100 and second.name==oldName and doc.sel==2
    and #doc.history.undo==baseline)

  bridge:finish(false)
  check('traço sync: soltar mouse confirma uma única pincelada',
    stroke.closed and bridge.stroke==nil and doc.history.stroke==nil
    and #doc.history.undo==baseline+1)
  check('traço sync: confirmar traço não aplica camadas automaticamente',
    second.opacity==100 and second.name==oldName and
    doc.sel==2 and first.visible)
  check('traço sync: sincronização posterior aplica propriedades e seleção',
    bridge:sync(model)==doc and doc.sel==1 and
    second.opacity==42 and second.name=='Nome após pincel'
    and not first.visible)
  check('traço sync: alterações estruturais geram histórico separado',
    #doc.history.undo==baseline+2 and #doc.history.redo==0)
  check('traço sync: primeiro undo restaura painel e mantém tinta',
    bridge:historyStep(model,false) and
    doc.sel==2 and second.opacity==100 and
    second.name==oldName and first.visible and
    second.tiles['0,0']~=nil)
  check('traço sync: segundo undo reverte somente os pixels',
    bridge:historyStep(model,false) and
    next(second.tiles)==nil and #doc.history.undo==baseline)
  check('traço sync: refazer recoloca tinta e depois propriedades',
    bridge:historyStep(model,true) and
    second.tiles['0,0']~=nil and
    bridge:historyStep(model,true) and
    doc.sel==1 and second.opacity==42 and
    second.name=='Nome após pincel' and not first.visible)

  -- Se só opacidade/camada ativa mudarem, não há snapshot estrutural,
  -- e cancelar a pincelada deve deixar o histórico e pixels intactos.
  model:select_layer(secondId)
  check('traço sync: troca leve prepara a segunda pincelada',
    bridge:sync(model)==doc and doc.sel==2)
  baseline=#doc.history.undo
  local previousAlpha=select(4,second.tiles['0,0']:getPixel(30,30))
  stroke=newStroke(second)
  bridge.stroke=stroke
  stroke:push(30,30,1,0)
  check('traço sync: segundo gesto altera temporariamente outro pixel',
    select(4,second.tiles['0,0']:getPixel(30,30))>previousAlpha)
  model:set_layer_opacity(secondId,65)
  model:select_layer(firstId)
  ok,value=pcall(bridge.sync,bridge,model)
  check('traço sync: alterações leves são adiadas antes de cancelar',
    ok and value==nil and doc.sel==2 and second.opacity==42
    and not stroke.closed and #doc.history.undo==baseline)
  bridge:finish(true)
  check('traço sync: cancelar segundo gesto reverte pixels sem undo',
    stroke.closed and doc.history.stroke==nil and
    #doc.history.undo==baseline and
    select(4,second.tiles['0,0']:getPixel(30,30))==previousAlpha)
  check('traço sync: mudanças leves aplicam após cancelar, sem snapshot',
    bridge:sync(model)==doc and doc.sel==1 and
    second.opacity==65 and #doc.history.undo==baseline)

  -- O mesmo fallback mantém movimento da seleção quando camadas mudam
  -- no painel durante o arraste; sem ele, moveSelection devolvia false.
  model:set_tool('selection_rect')
  bridge.point=function() return 4,4 end
  check('traço sync: retângulo inicia antes da mudança pendente',
    bridge:beginSelection(model,nil,nil,1,W,H,100,100))
  local drag=bridge.selectionDrag
  model:set_layer_opacity(firstId,58)
  local sx,sy=screen(13,15)
  check('traço sync: seleção continua seguindo cursor com sync adiada',
    bridge:moveSelection(model,view,prefs,1,W,H,sx,sy)
    and bridge.selectionDrag==drag and
    math.abs(drag.x-13)<1e-6 and math.abs(drag.y-15)<1e-6
    and first.opacity==100)
  baseline=#doc.history.undo
  check('traço sync: confirmar seleção mantém região desenhada',
    bridge:finishSelection(model) and
    Selection.contains(doc.selection,10,10) and
    not Selection.contains(doc.selection,30,30) and
    #doc.history.undo==baseline+1)
  check('traço sync: opacidade pendente aplica após seleção sem undo extra',
    bridge:sync(model)==doc and first.opacity==58
    and #doc.history.undo==baseline+1)

  -- A prévia PNG também é uma sessão visual com geometria estável.
  local src=love.image.newImageData(2,2)
  src:setPixel(0,0,1,1,1,1)
  local session=PNGImport.preview(doc,src,'cursor.png')
  bridge.pngPreview=session
  model:set_layer_opacity(firstId,70)
  sx,sy=screen(32,32)
  px,py=bridge:toCanvas(model,view,prefs,1,W,H,sx,sy)
  check('traço sync: prévia PNG mantém conversão com edição pendente',
    px and py and math.abs(px-32)<1e-6 and
    math.abs(py-32)<1e-6 and bridge.pngPreview==session
    and first.opacity==58)
  check('traço sync: cancelar prévia aplica alteração apenas depois',
    bridge:cancelPNGImport() and bridge:sync(model)==doc
    and first.opacity==70 and not session.active)

  -- Fallback nunca pode usar o canvas antigo após sair do editor.
  bridge.selectionDrag={kind='selection_rect',mode='replace',
    startX=4,startY=4,x=4,y=4}
  model.screen='gallery'
  px,py=bridge:toCanvas(model,view,prefs,1,W,H,sx,sy)
  check('traço sync: fora do editor não usa geometria antiga',
    px==nil and py==nil)
  model.screen='editor'
  bridge.selectionDrag=nil
end
