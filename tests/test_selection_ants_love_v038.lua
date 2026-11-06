-- Teste LÖVE 11.5 real, isolado para evitar limite de locais do runner.
local Model=require('src.model')
local Bridge=require('app.paint_bridge')
local Selection=require('core.selection')
return function()
  -- v0.38: shader real no LÖVE, alternância temporal observável na GPU.
  -- Capturas de um retângulo com o mesmo raster em dois instantes fixos.
  local AntsModel=Model.new()
  AntsModel:open_gallery();AntsModel:open_new_canvas();AntsModel:create_canvas(64,64)
  local AntsBridge=Bridge.new()
  local AntsDoc=assert(AntsBridge:sync(AntsModel))
  AntsDoc.selection=Selection.rect(AntsDoc,10,10,50,50)
  local g=love.graphics
  local snapshotCanvas=g.newCanvas(64,64)
  local previousShader=g.getShader()
  local function antsSnapshot(seconds)
    g.push('all')
    g.setCanvas(snapshotCanvas)
    g.clear(0.5,0.5,0.5,1)
    AntsBridge:drawSelection(0,0,1,seconds)
    assert(g.getShader()==previousShader,
      'LÖVE v0.38: shader de seleção não restaurou o shader anterior')
    g.setCanvas()
    g.pop()
    return snapshotCanvas:newImageData()
  end
  local frameA=antsSnapshot(0)
  local frameB=antsSnapshot(0.25)
  assert(AntsBridge.ants.shader and not AntsBridge.ants.unavailable,
    'LÖVE v0.38: shader não foi compilado/ativado')
  local changed=0
  for py=0,63 do
    for px=0,63 do
      local ar,ag,ab=frameA:getPixel(px,py)
      local br,bg,bb=frameB:getPixel(px,py)
      if math.abs(ar-br)+math.abs(ag-bg)+math.abs(ab-bb)>0.4 then
        changed=changed+1
      end
    end
  end
  assert(changed>=8,
    'LÖVE v0.38: shader não animou pixels de borda: '..changed)
  local midA=select(1,frameA:getPixel(32,32))
  local midB=select(1,frameB:getPixel(32,32))
  assert(math.abs(midA-0.5)<0.02 and math.abs(midB-0.5)<0.02,
    'LÖVE v0.38: animação coloriu pixels interiores')
  assert(#AntsDoc.history.undo==0 and AntsDoc.selection.kind==nil,
    'LÖVE v0.38: animação alterou documento/histórico')
  assert(not next(AntsDoc.layers[AntsDoc.sel].tiles),
    'LÖVE v0.38: animação escreveu em RGBA')
  -- v0.39: desligar antes do primeiro desenho evita compilar o shader.
  local staticBridge=Bridge.new()
  local staticDoc=assert(staticBridge:sync(AntsModel))
  staticDoc.selection=Selection.rect(staticDoc,10,10,50,50)
  assert(staticBridge:setSelectionAnimation(false))
  local staticCanvas=g.newCanvas(64,64)
  local function staticFrame(seconds)
    g.push('all')
    g.setCanvas(staticCanvas)
    g.clear(0.5,0.5,0.5,1)
    staticBridge:drawSelection(0,0,1,seconds)
    assert(g.getShader()==previousShader,
      'LÖVE v0.39: render estático não restaurou shader')
    g.setCanvas()
    g.pop()
    return staticCanvas:newImageData()
  end
  local stillA=staticFrame(0)
  local stillB=staticFrame(0.25)
  local different=0
  for py=0,63 do for px=0,63 do
    local r1,g1,b1=stillA:getPixel(px,py)
    local r2,g2,b2=stillB:getPixel(px,py)
    if math.abs(r1-r2)+math.abs(g1-g2)+math.abs(b1-b2)>0.02 then
      different=different+1
    end
  end end
  assert(different==0,'LÖVE v0.39: contorno pausado mudou no tempo')
  assert(staticBridge.ants.shader==nil and staticBridge.ants.lastPhase==nil,
    'LÖVE v0.39: shader ativo mesmo com animação desligada')
  assert(staticBridge:setSelectionAnimation(true))
  staticFrame(0.25)
  assert(staticBridge.ants.shader and not staticBridge.ants.unavailable,
    'LÖVE v0.39: retomada não criou shader')
  assert(staticBridge:setSelectionAnimation(false)
    and staticBridge.ants.shader==nil,'LÖVE v0.39: pausa não liberou GPU')
  assert(#staticDoc.history.undo==0,
    'LÖVE v0.39: preferência mudou histórico')
  staticCanvas:release()
  AntsBridge:dropImages()
  assert(AntsBridge.ants.shader==nil,'LÖVE v0.38: GPU não foi liberada')
  snapshotCanvas:release()
  print('PASS: LÖVE real v0.39: pausa idêntica entre quadros, retomada e GPU liberada')
  print('PASS: LÖVE real v0.38: shader temporal na GPU, bordas exatas e estado restaurado')

end
