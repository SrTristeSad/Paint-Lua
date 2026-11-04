-- v0.36: operações booleanas esparsas e histórico da seleção.
return function(check)
  local Doc=require('core.doc')
  local Sel=require('core.selection')
  local Mask=require('core.mask')
  local Project=require('core.project')
  local Bridge=require('app.paint_bridge')
  local Model=require('src.model')
  local View=require('src.viewport')
  local Pref=require('src.editor_preferences')
  local function on(s,x,y) return Sel.contains(s,x,y) end
  local doc=Doc.new(64,64,'Combinar')
  local a=assert(Sel.rect(doc,2,2,5,5))
  local b=assert(Sel.rect(doc,4,4,7,7))
  local sum=assert(Sel.combine(doc,a,b,'add'))
  check('v0.36: adição preserva duas regiões',
    on(sum,3,3) and on(sum,7,7) and not on(sum,1,1))
  check('v0.36: adição tem bounding box justo',
    sum.x==2 and sum.y==2 and sum.w==6 and sum.h==6)
  check('v0.36: adição preserva seleções de entrada',
    on(a,3,3) and not on(a,7,7) and on(b,7,7))
  local cut=assert(Sel.combine(doc,a,b,'subtract'))
  check('v0.36: subtração retira só a interseção',
    on(cut,3,3) and not on(cut,4,4) and not on(cut,7,7))
  local meet=assert(Sel.combine(doc,a,b,'intersect'))
  check('v0.36: interseção conserva apenas área comum',
    on(meet,4,4) and not on(meet,3,3) and not on(meet,7,7))
  check('v0.36: substituição mantém API antiga',
    Sel.combine(doc,a,b,'replace')==b)
  check('v0.36: adicionar sem seleção prévia cria seleção',
    Sel.combine(doc,nil,b,'add')==b)
  local noPrevious,reason=Sel.combine(doc,nil,b,'subtract')
  check('v0.36: sem seleção prévia não subtrai',
    noPrevious==nil and type(reason)=='string')
  local noIntersection,reason2=Sel.combine(doc,nil,b,'intersect')
  check('v0.36: sem seleção prévia não intersecta',
    noIntersection==nil and type(reason2)=='string')
  local empty=assert(Sel.combine(doc,a,a,'subtract'))
  check('v0.36: subtração total não vira pintura irrestrita',
    empty~=nil and empty.kind=='wand' and not on(empty,0,0)
    and not on(empty,4,4) and not on(empty,63,63))
  local far=Sel.rect(doc,20,20,23,23)
  local separated=assert(Sel.combine(doc,a,far,'intersect'))
  check('v0.36: interseção disjunta conserva máscara vazia',
    separated and not on(separated,0,0) and not on(separated,22,22))
  doc.selection=empty
  local emptyBytes=Project.encode(doc)
  local loadedEmpty=assert(Project.decode(emptyBytes))
  check('v0.36: máscara vazia sobrevive NPNT5',
    loadedEmpty.selection and not on(loadedEmpty.selection,5,5)
    and not on(loadedEmpty.selection,60,60))
  doc.selection=sum
  local bytes=Project.encode(doc)
  local loaded=assert(Project.decode(bytes))
  check('v0.36: adição mantém formato NPNT5',
    bytes:sub(1,6)=='NPNT5\n' and loaded.selection.kind=='wand')
  check('v0.36: roundtrip de regiões distantes',
    on(loaded.selection,3,3) and on(loaded.selection,7,7)
    and not on(loaded.selection,1,1))
  local poly=assert(Sel.polygon(doc,{{4,4},{16,4},{4,16}}))
  local clip=assert(Sel.combine(doc,poly,Sel.rect(doc,9,9,15,15),'intersect'))
  check('v0.36: laço combina pixel exato',
    on(clip,9,9) and not on(clip,12,12))
  local mask=Mask.new(0)
  local t=Mask.getTile(mask,0,0,true)
  t:setPixel(4,4,1,1,1,1)
  t:setPixel(9,9,1,1,1,1)
  local wand={kind='wand',x=4,y=4,w=6,h=6,mask=mask}
  local joined=assert(Sel.combine(doc,wand,a,'add'))
  check('v0.36: varinha descontínua combina com retângulo',
    on(joined,9,9) and on(joined,3,3) and on(joined,4,4)
    and not on(joined,8,8))
  local inverse=assert(Sel.invert(doc,a))
  local mixedAdd=assert(Sel.combine(doc,inverse,b,'add'))
  check('v0.36: complemento mais retângulo preenche furo parcial',
    mixedAdd.mask.inverted and not on(mixedAdd,3,3)
    and on(mixedAdd,4,4) and on(mixedAdd,0,0))
  local mixedIntersect=assert(Sel.combine(doc,inverse,b,'intersect'))
  check('v0.36: complemento intersectado não inclui origem',
    not on(mixedIntersect,4,4) and on(mixedIntersect,7,7)
    and not on(mixedIntersect,0,0))
  local mixedSubtract=assert(Sel.combine(doc,inverse,b,'subtract'))
  check('v0.36: subtrair de complemento remove alvo',
    on(mixedSubtract,0,0) and not on(mixedSubtract,7,7))
  local twoInverses=assert(Sel.combine(doc,inverse,Sel.invert(doc,b),'intersect'))
  check('v0.36: operação entre duas máscaras inversas',
    twoInverses.mask.inverted and on(twoInverses,0,0)
    and not on(twoInverses,3,3) and not on(twoInverses,7,7))
  doc.selection=twoInverses
  local restored=assert(Project.decode(Project.encode(doc)))
  check('v0.36: NPNT5 preserva resultado invertido',
    restored.selection.mask.inverted and on(restored.selection,0,0)
    and not on(restored.selection,3,3) and not on(restored.selection,7,7))
  local oversized=Doc.new(4096,4096,'Muito grande')
  local huge=Sel.rect(oversized,0,0,4095,4095)
  local small=Sel.rect(oversized,15,15,16,16)
  local denied,err=Sel.combine(oversized,huge,small,'subtract')
  check('v0.36: segurança recusa combinação maior que orçamento',
    denied==nil and type(err)=='string' and on(huge,1000,1000))
  local sparse=assert(Sel.combine(oversized,small,
    Sel.rect(oversized,4020,4020,4021,4021),'add'))
  check('v0.36: regiões afastadas não rasterizam canvas inteiro',
    sparse.kind=='wand' and on(sparse,15,15) and on(sparse,4021,4021)
    and not on(sparse,2000,2000))
  check('v0.36: máscara esparsa mantém só dois tiles',
    sparse.mask.tiles['0,0'] and sparse.mask.tiles['15,15']
    and not sparse.mask.tiles['7,7'])
  local invalid=not pcall(Sel.combine,doc,a,b,'unknown')
  check('v0.36: operação inválida rejeitada',invalid)

  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(64,64)
  local bridge=Bridge.new()
  local d=assert(bridge:sync(model))
  local layer=d.layers[d.sel]
  local pix,key=Doc.getTile(layer,0,0,true)
  pix:setPixel(12,12,1,0.2,0.1,1)
  Doc.markDirty(layer,key)
  d.selection=Sel.rect(d,10,10,17,17)
  check('v0.36: troca o modo da seleção',bridge:setSelectionMode('add')
    and bridge.selectionMode=='add')
  check('v0.36: modo inválido não muda estado',
    not bridge:setSelectionMode('invalid') and bridge.selectionMode=='add')
  local v=View.new()
  local pref=Pref.new()
  local left=pref.tool_position=='left' and 62 or 0
  local right=pref.tool_position=='right' and 75 or 34
  local cx=left+(1024-left-right)/2
  local cy=62+(768-160)/2
  local zoom=math.min((1024-left-right)/64,(768-160)/64,1.1)
  local function mouse(x,y)
    return cx+(x-32)*zoom,cy+(y-32)*zoom
  end
  local function rectGesture(x0,y0,x1,y1,mid)
    model:set_tool('selection_rect')
    local ax,ay=mouse(x0,y0)
    local bx,by=mouse(x1,y1)
    if not bridge:beginSelection(model,v,pref,1,1024,768,ax,ay) then return false end
    if mid then mid() end
    bridge:moveSelection(model,v,pref,1,1024,768,bx,by)
    return bridge:finishSelection(model,v,pref,1,1024,768,bx,by)
  end
  check('v0.36: ferramenta retangular acumula via ponte',
    rectGesture(20,20,25,25) and on(d.selection,12,12)
    and on(d.selection,22,22))
  check('v0.36: um histórico por gesto aditivo',
    #d.history.undo==1)
  check('v0.36: modo é fixado no início do arraste',
    rectGesture(30,30,33,33,function() bridge:setSelectionMode('subtract') end)
    and on(d.selection,32,32) and bridge.selectionMode=='subtract')
  check('v0.36: subtração pelo arraste',
    rectGesture(11,11,13,13) and not on(d.selection,12,12)
    and on(d.selection,16,16))
  check('v0.36: combinar não altera RGBA',
    select(4,pix:getPixel(12,12))==1)
  check('v0.36: undo restaura seleção anterior',
    bridge:historyStep(model,false) and on(d.selection,12,12))
  check('v0.36: redo restaura subtração',
    bridge:historyStep(model,true) and not on(d.selection,12,12))
  local prior=d.selection
  bridge.transform={}
  check('v0.36: transform bloqueia nova combinação',
    not bridge:combineSelection(b,'add') and d.selection==prior)
  bridge.transform=nil
  bridge:setSelectionMode('intersect')
  model:set_tool('magic_wand')
  local mx,my=mouse(35,35)
  check('v0.36: varinha inicia em modo de interseção',
    bridge:beginSelection(model,v,pref,1,1024,768,mx,my)
    and bridge.jobKind=='wand' and bridge.jobSelectionMode=='intersect')
  local before=d.selection
  local turns=0
  while bridge.job and turns<400 do bridge:update();turns=turns+1 end
  check('v0.36: varinha combina só ao fim do job',
    bridge.job==nil and d.selection~=before
    and #d.history.undo==4 and bridge.jobSelectionMode==nil)
  local afterWand=d.selection
  check('v0.36: undo do job é único',
    bridge:historyStep(model,false) and d.selection==before)
  check('v0.36: redo do job restaura seleção',
    bridge:historyStep(model,true) and d.selection==afterWand)
  bridge:setSelectionMode('subtract')
  d.selection=Sel.rect(d,1,1,3,3)
  model:set_tool('magic_wand')
  local px,py=mouse(36,36)
  bridge:beginSelection(model,v,pref,1,1024,768,px,py)
  bridge:cancelJob()
  check('v0.36: cancelar varinha preserva área e histórico',
    bridge.job==nil and bridge.jobSelectionMode==nil
    and on(d.selection,2,2))
end
