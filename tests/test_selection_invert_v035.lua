-- v0.35: seleção inversa e persistência NPNT5 (ImageData mock).
return function(check)
  local Doc=require('core.doc')
  local Sel=require('core.selection')
  local Mask=require('core.mask')
  local Project=require('core.project')
  local Bridge=require('app.paint_bridge')
  local Model=require('src.model')
  local d=Doc.new(64,64,'Invert')
  local s=Sel.rect(d,2,3,5,6)
  local inv=assert(Sel.invert(d,s))
  check('v0.35: máscara inversa',inv.kind=='wand' and inv.mask.inverted)
  check('v0.35: exterior selecionado',Sel.contains(inv,0,0) and Sel.contains(inv,63,63))
  check('v0.35: interior excluído',not Sel.contains(inv,3,4) and Sel.contains(s,3,4))
  check('v0.35: seleção antiga imutável',not Sel.contains(s,0,0))
  local back=assert(Sel.invert(d,inv))
  check('v0.35: dupla inversão recupera limites',
    back.x==2 and back.y==3 and back.w==4 and back.h==4)
  check('v0.35: dupla inversão recupera máscara',
    Sel.contains(back,3,4) and not Sel.contains(back,0,0))
  d.selection=inv
  local bytes=Project.encode(d)
  check('v0.35: grava em NPNT5',bytes:sub(1,6)=='NPNT5\n')
  local loaded=assert(Project.decode(bytes))
  check('v0.35: carrega seleção invertida',loaded.selection.mask.inverted
    and Sel.contains(loaded.selection,0,0)
    and not Sel.contains(loaded.selection,3,4))
  local double=assert(Sel.invert(loaded,loaded.selection))
  check('v0.35: dupla inversão após carregar',double.w==4
    and Sel.contains(double,3,4))
  local poly=assert(Sel.polygon(d,{{4,4},{16,4},{4,16}}))
  local invPoly=assert(Sel.invert(d,poly))
  check('v0.35: laço irregular respeitado',
    not Sel.contains(invPoly,6,6) and Sel.contains(invPoly,15,15))
  local mask=Mask.new(0)
  local tile=Mask.getTile(mask,0,0,true)
  tile:setPixel(9,9,1,1,1,1);tile:setPixel(10,9,1,1,1,1)
  local wand={kind='wand',x=9,y=9,w=2,h=1,mask=mask}
  local invWand=assert(Sel.invert(d,wand))
  check('v0.35: varinha invertida',not Sel.contains(invWand,9,9)
    and Sel.contains(invWand,8,9))
  local reWand=assert(Sel.invert(d,invWand))
  check('v0.35: dupla inversão da varinha',reWand.x==9
    and reWand.w==2 and Sel.contains(reWand,10,9))
  check('v0.35: varinha original imutável',not wand.mask.inverted)
  check('v0.35: inexistente vira selecionar tudo',
    Sel.contains(Sel.invert(d,nil),63,63))
  local emptyFull=assert(Sel.invert(d,Sel.rect(d,0,0,63,63)))
  check('v0.40: inverter seleção total preserva área vazia',
    emptyFull.kind=='wand' and not Sel.contains(emptyFull,0,0)
    and not Sel.contains(emptyFull,63,63))
  local large=Doc.new(4096,4096,'Grande')
  local small=Sel.rect(large,12,12,13,13)
  local bigInverse=assert(Sel.invert(large,small))
  check('v0.35: documento grande não gera máscara gigante',
    bigInverse.w==4096 and Sel.contains(bigInverse,4000,4000)
    and not Sel.contains(bigInverse,12,12))
  local huge=Sel.rect(large,0,0,3000,3000)
  local denied,err=Sel.invert(large,huge)
  check('v0.35: área excessiva recusada',
    denied==nil and type(err)=='string' and Sel.contains(huge,100,100))
  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(64,64)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  doc.selection=Sel.rect(doc,12,12,15,15)
  local layer=doc.layers[doc.sel]
  local t,key=Doc.getTile(layer,0,0,true)
  t:setPixel(13,13,1,0,0,1);Doc.markDirty(layer,key)
  check('v0.35: ponte inverte',bridge:invertSelection(model))
  check('v0.35: histórico único',#doc.history.undo==1 and
    not Sel.contains(doc.selection,13,13))
  check('v0.35: pixels intactos',select(4,t:getPixel(13,13))==1)
  check('v0.35: undo recupera seleção',bridge:historyStep(model,false)
    and Sel.contains(doc.selection,13,13))
  check('v0.35: redo recupera inversão',bridge:historyStep(model,true)
    and not Sel.contains(doc.selection,13,13))
  local previous=doc.selection
  bridge.transform={}
  check('v0.35: transformação bloqueia inversão',
    not bridge:invertSelection(model) and doc.selection==previous)
  bridge.transform=nil
  check('v0.35: reinverte via ponte',bridge:invertSelection(model)
    and Sel.contains(doc.selection,13,13))
  local oldKeyboard=love.keyboard
  love.keyboard={isDown=function(...) return true end}
  check('v0.35: atalho Ctrl+Shift+I',bridge:key(model,'i')
    and not Sel.contains(doc.selection,13,13))
  love.keyboard=oldKeyboard
end
