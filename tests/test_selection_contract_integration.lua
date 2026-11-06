-- integração: auditoria de integração v0.35-v0.39: nenhuma seleção != seleção vazia.
return function(check)
  local Doc=require('core.doc')
  local Sel=require('core.selection')
  local Mask=require('core.mask')
  local Project=require('core.project')
  local Fill=require('core.fill')
  local Stroke=require('core.stroke')
  local Bridge=require('app.paint_bridge')
  local Model=require('src.model')
  local function selected(s,x,y) return Sel.contains(s,x,y) end
  local doc=Doc.new(32,32,'Inversão sem liberação')
  local all=assert(Sel.rect(doc,0,0,31,31))
  local empty=assert(Sel.invert(doc,all))
  check('integração: inverter tudo retorna seleção vazia real',
    empty~=nil and empty.kind=='wand' and not empty.mask.inverted)
  check('integração: seleção vazia não contém nenhum canto',
    not selected(empty,0,0) and not selected(empty,31,31))
  check('integração: seleção antiga integral permanece intacta',
    selected(all,0,0) and selected(all,31,31))
  check('integração: seleção vazia valida no documento',
    Sel.validate(doc,empty))
  check('integração: nil continua significando pintura irrestrita',
    selected(nil,0,0) and selected(nil,31,31))
  check('integração: máscara vazia não tem pixels nem tiles alocados',
    next(empty.mask.tiles)==nil and empty.w==32 and empty.h==32)
  check('integração: seleção vazia não tem contorno síncrono',
    #Sel.outline(empty)==0)
  local incremental=Sel.startOutline(empty)
  local completed=Sel.stepOutline(incremental,128)
  check('integração: seleção vazia não tem contorno incremental',
    completed and #incremental.lines==0 and not incremental.truncated)
  local inverted=assert(Sel.invert(doc,empty))
  check('integração: reinverter vazio seleciona tudo',
    inverted.mask.inverted and selected(inverted,0,0)
    and selected(inverted,31,31))
  local invertedTwice=assert(Sel.invert(doc,inverted))
  check('integração: reinverter máscara plena não vira nil',
    invertedTwice~=nil and not selected(invertedTwice,0,0)
    and not selected(invertedTwice,31,31))
  check('integração: inverter nenhuma seleção seleciona tudo',
    selected(assert(Sel.invert(doc,nil)),31,31))
  local chain=assert(Sel.invert(doc,assert(Sel.invert(doc,nil))))
  check('integração: cadeia nil -> tudo -> vazio é segura',
    chain and not selected(chain,0,0))
  doc.selection=empty
  local saved=Project.encode(doc)
  check('integração: seleção vazia usa arquivo NPNT5',
    saved:sub(1,6)=='NPNT5\n')
  local loaded=assert(Project.decode(saved))
  check('integração: roundtrip NPNT5 não libera seleção vazia',
    loaded.selection~=nil and not selected(loaded.selection,0,0)
    and not selected(loaded.selection,31,31))
  local loadedInvert=assert(Sel.invert(loaded,loaded.selection))
  check('integração: reinversão depois de reabrir permite tudo',
    selected(loadedInvert,0,0) and selected(loadedInvert,31,31))
  doc.selection=empty
  local layer=doc.layers[1]
  local beforeCount=Fill.fill(doc,layer,12,12,{1,0,0,1},0,doc.selection)
  check('integração: balde não atravessa seleção vazia',beforeCount==0
    and next(layer.tiles)==nil)
  local stroke=Stroke.new(doc,layer,doc.history,
    {size=8,alpha=1,hardness=1,color={1,0,0},smoothing={amount=0}})
  stroke:push(12,12,1,0)
  stroke:finish()
  check('integração: pincel não atravessa seleção vazia',
    next(layer.tiles)==nil)
  local newArea=Sel.rect(doc,3,3,5,5)
  local union=assert(Sel.combine(doc,empty,newArea,'add'))
  check('integração: somar a vazio seleciona apenas área nova',
    selected(union,4,4) and not selected(union,20,20))
  local intersect=assert(Sel.combine(doc,empty,newArea,'intersect'))
  check('integração: interseção com vazio continua restrita',
    not selected(intersect,4,4) and not selected(intersect,20,20))
  local subtract=assert(Sel.combine(doc,empty,newArea,'subtract'))
  check('integração: subtrair de vazio não libera pintura',
    not selected(subtract,4,4) and not selected(subtract,20,20))
  local fullMask=Mask.new(0)
  local fullTile=Mask.getTile(fullMask,0,0,true)
  for y=0,31 do for x=0,31 do
    fullTile:setPixel(x,y,1,1,1,1)
  end end
  local fullWand={kind='wand',x=0,y=0,w=32,h=32,mask=fullMask}
  local emptyWand=assert(Sel.invert(doc,fullWand))
  check('integração: varinha inteira invertida vira vazio',
    emptyWand.mask.inverted and not selected(emptyWand,0,0)
    and not selected(emptyWand,31,31))
  local backWand=assert(Sel.invert(doc,emptyWand))
  check('integração: varinha inteira recupera tudo no duplo invert',
    selected(backWand,0,0) and selected(backWand,31,31))
  local invertedBlankMask=Mask.new(0)
  invertedBlankMask.inverted=true
  local invertedBlank={kind='wand',x=0,y=0,w=32,h=32,mask=invertedBlankMask}
  local fromInverse=assert(Sel.invert(doc,invertedBlank))
  check('integração: complemento sem exceções vira vazio real',
    fromInverse and next(fromInverse.mask.tiles)==nil
    and not selected(fromInverse,0,0))
  local oversized=Doc.new(4096,4096,'Tudo gigante')
  local hugeFull=Sel.rect(oversized,0,0,4095,4095)
  local hugeEmpty=assert(Sel.invert(oversized,hugeFull))
  check('integração: inverter canvas grande usa memória esparsa',
    hugeEmpty.w==4096 and next(hugeEmpty.mask.tiles)==nil
    and not selected(hugeEmpty,2048,2048))
  check('integração: entrada inválida para máscara vazia é recusada',
    not pcall(Sel.empty,nil))

  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(64,64)
  local bridge=Bridge.new()
  local d=assert(bridge:sync(model))
  check('integração: ponte inicia sem seleção e pintura livre',
    d.selection==nil and selected(d.selection,1,1))
  check('integração: ponte seleciona todo o documento',bridge:selectAll(model)
    and selected(d.selection,63,63))
  local previous=d.selection
  check('integração: ponte inverte tudo para vazio',
    bridge:invertSelection(model) and d.selection~=nil
    and not selected(d.selection,1,1) and not selected(d.selection,63,63))
  check('integração: invert gera um único snapshot estrutural',
    #d.history.undo==2)
  check('integração: undo da inversão restaura tudo',
    bridge:historyStep(model,false) and d.selection==previous
    and selected(d.selection,63,63))
  check('integração: redo da inversão restaura vazio',
    bridge:historyStep(model,true) and d.selection~=nil
    and not selected(d.selection,63,63))
  check('integração: reinverter vazio não modifica RGBA',
    bridge:invertSelection(model) and selected(d.selection,0,0)
    and next(d.layers[d.sel].tiles)==nil)
  check('integração: desmarcar é a única forma de limpar seleção',
    bridge:clearSelection() and d.selection==nil)
  check('integração: undo de desmarcar recupera região',
    bridge:historyStep(model,false) and d.selection~=nil)
  check('integração: redo de desmarcar recupera pintura livre',
    bridge:historyStep(model,true) and d.selection==nil)

  -- Uma seleção vazia nem sequer deve inicializar o shader, mesmo
  -- quando marching ants está ativado por padrão.
  d.selection=Sel.empty(d)
  local oldGraphics=love.graphics
  local attempts,rectangles,lines=0,0,0
  love.graphics={
    newShader=function() attempts=attempts+1;error('shader desnecessário') end,
    getShader=function()return nil end,
    setShader=function()end,
    setColor=function()end,
    setLineWidth=function()end,
    rectangle=function()rectangles=rectangles+1 end,
    line=function()lines=lines+1 end,
  }
  local idle=pcall(function()
    for i=1,6 do bridge:drawSelection(0,0,0.5,i/10) end
  end)
  check('integração: seleção vazia não compila shader',
    idle and attempts==0 and bridge.ants.shader==nil)
  check('integração: seleção vazia não desenha moldura enganosa',
    rectangles==0 and lines==0)
  bridge.selectionDrag={kind='selection_rect',startX=0,startY=0,x=5,y=5}
  local dragged=pcall(bridge.drawSelection,bridge,0,0,1,0)
  check('integração: arraste permanece visível mesmo com seleção vazia',
    dragged and rectangles==1 and attempts==0)
  bridge.selectionDrag=nil
  love.graphics=oldGraphics
  check('integração: render não tocou no documento ou histórico',
    d.selection~=nil and not selected(d.selection,0,0)
    and #d.history.undo==4)
end
