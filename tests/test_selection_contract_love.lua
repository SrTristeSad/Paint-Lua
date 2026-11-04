-- integração: regra crítica vazio!=nil verificada com ImageData e GPU reais.
local Model=require('src.model')
local Bridge=require('app.paint_bridge')
local Selection=require('core.selection')
local Fill=require('core.fill')
local Project=require('core.project')
return function()
  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(64,64)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  assert(bridge:selectAll(model),'LÖVE integração: selecionar tudo falhou')
  assert(bridge:invertSelection(model),'LÖVE integração: inversão total falhou')
  assert(doc.selection~=nil and doc.selection.kind=='wand'
    and not Selection.contains(doc.selection,0,0)
    and not Selection.contains(doc.selection,63,63),
    'LÖVE integração: inversão total deixou pintura irrestrita')
  assert(#doc.history.undo==2,'LÖVE integração: inversão duplicou histórico')
  local layer=doc.layers[doc.sel]
  assert(Fill.fill(doc,layer,30,30,{1,0,0,1},0,doc.selection)==0,
    'LÖVE integração: balde pintou seleção vazia')
  assert(next(layer.tiles)==nil,'LÖVE integração: balde criou pixels fora da seleção')
  assert(bridge:historyStep(model,false)
    and Selection.contains(doc.selection,63,63),
    'LÖVE integração: undo da inversão não restaurou tudo')
  assert(bridge:historyStep(model,true)
    and doc.selection~=nil and not Selection.contains(doc.selection,63,63),
    'LÖVE integração: redo liberou pintura')

  -- Não deve compilar shader nem colorir pixels quando a máscara está vazia.
  local gpu=love.graphics
  local canvas=gpu.newCanvas(64,64)
  local function snapshot(seconds)
    gpu.push('all')
    gpu.setCanvas(canvas)
    gpu.clear(0.25,0.25,0.25,1)
    bridge:drawSelection(0,0,1,seconds)
    gpu.setCanvas()
    gpu.pop()
    return canvas:newImageData()
  end
  local a=snapshot(0)
  local b=snapshot(0.25)
  assert(bridge.ants.shader==nil,
    'LÖVE integração: seleção vazia compilou shader desnecessário')
  for y=0,63 do for x=0,63 do
    local ar,ag,ab=a:getPixel(x,y)
    local br,bg,bb=b:getPixel(x,y)
    assert(math.abs(ar-0.25)<0.02
      and math.abs(ag-0.25)<0.02 and math.abs(ab-0.25)<0.02,
      'LÖVE integração: contorno vazio desenhou moldura')
    assert(math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb)<0.03,
      'LÖVE integração: seleção vazia produziu animação')
  end end
  canvas:release()

  local bytes=Project.encode(doc)
  assert(bytes:sub(1,6)=='NPNT5\n','LÖVE integração: não gravou NPNT5')
  local recovered=assert(Project.decode(bytes))
  assert(recovered.selection~=nil
    and not Selection.contains(recovered.selection,32,32),
    'LÖVE integração: NPNT5 reabriu como pintura irrestrita')
  bridge.filename='ci-paint-lua-v040.npnt'
  assert(bridge:save(),'LÖVE integração: não salvou projeto')
  assert(bridge:load(model),'LÖVE integração: não reabriu projeto')
  assert(bridge.doc.selection~=nil
    and not Selection.contains(bridge.doc.selection,30,30),
    'LÖVE integração: carregamento liberou região vazia')
  love.filesystem.remove(bridge.filename)
  assert(bridge:invertSelection(model)
    and Selection.contains(bridge.doc.selection,0,0)
    and Selection.contains(bridge.doc.selection,63,63),
    'LÖVE integração: reverter vazio após load não selecionou tudo')
  assert(bridge:clearSelection() and bridge.doc.selection==nil,
    'LÖVE integração: desmarcar não restaurou edição irrestrita')
  print('PASS: LÖVE real integração: inversão total segura, NPNT5, GPU, undo/redo e balde')
end
