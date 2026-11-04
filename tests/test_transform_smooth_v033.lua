-- v0.33: suavização de seleções raster; mantém o modo pixelado legado.
return function(check)
  local Doc=require('core.doc')
  local Sel=require('core.selection')
  local T=require('core.transform')
  local Hist=require('core.history')
  local Bridge=require('app.paint_bridge')
  local Model=require('src.model')
  local function put(l,x,y,r,g,b,a)
    local tile,key=Doc.getTile(l,math.floor(x/256),math.floor(y/256),true)
    tile:setPixel(x%256,y%256,r,g,b,a)
    Doc.markDirty(l,key)
  end
  local function get(l,x,y)
    local tile=Doc.getTile(l,math.floor(x/256),math.floor(y/256),false)
    if tile then return tile:getPixel(x%256,y%256) end
    return 0,0,0,0
  end
  local function gradient(mode)
    local d=Doc.new(64,64,'amostragem')
    local layer=d.layers[2]
    put(layer,30,30,1,0,0,1)
    put(layer,31,30,0,0,1,1)
    d.selection=Sel.rect(d,30,30,31,30)
    local s=T.begin(d,layer)
    check('v0.33: sessões da API continuam pixeladas por padrão',s.interpolation=='pixelated')
    check('v0.33: seleciona modo '..mode,T.setInterpolation(s,mode)==mode)
    T.set(s,0,0,2,2,0)
    check('v0.33: prévia não muda pixels',select(1,get(layer,30,30))==1 and #d.history.undo==0)
    local n=assert(T.commit(s))
    check('v0.33: commit com escala cria pixels',n>=4)
    check('v0.33: commit é um único undo',#d.history.undo==1)
    return d,layer
  end
  local pixelDoc,pixelLayer=gradient('pixelated')
  local pR,_,pB,pA=get(pixelLayer,30,30)
  check('v0.33: pixelado mantém cor nítida',pR>0.99 and pB<0.01 and pA>0.99)
  local smoothDoc,smoothLayer=gradient('smooth')
  local r,g,b,a=get(smoothLayer,30,30)
  check('v0.33: bilinear mistura duas cores',r>0.70 and r<0.80 and b>0.20 and b<0.30 and a>0.99)
  check('v0.33: interpolação suave não cria componente inexistente',g<0.01)
  check('v0.33: undo do suave restaura origem e seleção',Hist.undo(smoothDoc)
    and select(1,get(smoothLayer,30,30))==1
    and smoothDoc.selection.kind==nil)
  check('v0.33: redo do suave preserva pixels e máscara',Hist.redo(smoothDoc)
    and select(1,get(smoothLayer,30,30))<0.8
    and smoothDoc.selection.kind=='wand'
    and Sel.contains(smoothDoc.selection,30,30))

  local plain=Doc.new(32,32,'identidade')
  local l=plain.layers[2]
  put(l,9,9,0.28,0.8,0.35,0.45)
  plain.selection=Sel.rect(plain,9,9,9,9)
  local intact=T.begin(plain,l,nil,{interpolation='smooth'})
  check('v0.33: begin aceita qualidade explícita',intact.interpolation=='smooth')
  check('v0.33: identidade suave mantém alfa',assert(T.commit(intact))==1
    and math.abs(select(4,get(l,9,9))-0.45)<0.00001)
  check('v0.33: identidade suave mantém RGB',math.abs(select(1,get(l,9,9))-0.28)<0.00001)

  local rotated=Doc.new(32,32,'bordas inclinadas')
  local rl=rotated.layers[2]
  for y=13,15 do for x=13,15 do put(rl,x,y,0.93,0.1,0.04,1) end end
  rotated.selection=Sel.rect(rotated,13,13,15,15)
  local session=T.begin(rotated,rl,nil,{interpolation='smooth'})
  T.set(session,0,0,1,1,math.pi/4)
  check('v0.33: prévia oblíqua não altera histórico',#rotated.history.undo==0)
  assert(T.commit(session))
  local partial,solid,colored=false,false,true
  for y=10,19 do for x=10,19 do
    local rr,gg,bb,aa=get(rl,x,y)
    if aa>0 and aa<0.99 then partial=true end
    if aa>0.99 then solid=true end
    if aa>0 then colored=colored and rr>gg and gg>bb end
  end end
  check('v0.33: rotação suave gera borda parcialmente transparente',partial)
  check('v0.33: rotação suave preserva interior',solid)
  check('v0.33: borda não ganha halos coloridos',colored)
  check('v0.33: giro fica em uma entrada do histórico',#rotated.history.undo==1)
  check('v0.33: desfaz transformação suave',Hist.undo(rotated)
    and math.abs(select(4,get(rl,13,13))-1)<0.001)
  check('v0.33: refaz transformação suave',Hist.redo(rotated))

  local polygon=Doc.new(40,40,'laço suave')
  local pl=polygon.layers[2]
  for y=10,20 do for x=10,20 do put(pl,x,y,1,0,0,1) end end
  put(pl,24,24,0,1,0,1)
  polygon.selection=assert(Sel.polygon(polygon,{{10,10},{20,10},{10,20}}))
  local poly=T.begin(polygon,pl,nil,{interpolation='smooth'})
  T.set(poly,4,0,1.35,1.35,math.pi/6)
  local count,selection=T.commit(poly)
  check('v0.33: seleção irregular suavizada confirma',count and count>0 and selection.kind=='wand')
  check('v0.33: laço não modifica pixel externo',select(2,get(pl,24,24))==1)
  check('v0.33: laço gera histórico único',#polygon.history.undo==1)
  local incomplete=T.begin(polygon,pl,nil,{interpolation='smooth'})
  check('v0.33: cancela prévia suave',T.cancel(incomplete) and not incomplete.active)
  check('v0.33: cancelamento não cria histórico',#polygon.history.undo==1)
  check('v0.33: modo inválido é rejeitado',not pcall(T.setInterpolation,incomplete,'bicubic'))
  check('v0.33: begin rejeita filtro desconhecido',not pcall(T.begin,plain,l,nil,{interpolation='bogus'}))

  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(32,32)
  local bridge=Bridge.new()
  local bd=assert(bridge:sync(model))
  local bl=bd.layers[1]
  put(bl,16,16,1,0,0,1)
  bd.selection=Sel.rect(bd,16,16,16,16)
  model:set_tool('transform')
  check('v0.33: transformação da UI inicia suave',bridge:startTransform(model) and bridge.transform.interpolation=='smooth')
  check('v0.33: UI alterna para Pixelado',bridge:setTransformInterpolation('pixelated') and bridge.transform.interpolation=='pixelated')
  check('v0.33: UI volta para Suave',bridge:setTransformInterpolation('smooth') and bridge.transform.interpolation=='smooth')
  check('v0.33: UI rejeita interpolação errada',not bridge:setTransformInterpolation('bicubic') and bridge.transform.interpolation=='smooth')
  check('v0.33: UI cancela sem alterar pintura',bridge:cancelTransform() and #bd.history.undo==0 and select(4,get(bl,16,16))==1)
end
