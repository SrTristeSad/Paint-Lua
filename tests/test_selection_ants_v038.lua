-- v0.38: shader de contorno animado, lifecycle, integração e fallback.
return function(check)
  local Ants=require('app.selection_ants')
  local Bridge=require('app.paint_bridge')
  local Selection=require('core.selection')
  local Mask=require('core.mask')
  local Doc=require('core.doc')
  local Model=require('src.model')

  local function equal(a,b) return math.abs(a-b)<0.00001 end
  check('v0.38: fase inicia em zero',Ants.phase(0)==0)
  check('v0.38: fase se desloca no tempo',equal(Ants.phase(0.25),6))
  check('v0.38: fase se repete por ciclo',equal(
    Ants.phase(0),Ants.phase(Ants.CYCLE_PX/Ants.SPEED_PX_S)))
  check('v0.38: fase permanece limitada após horas',
    Ants.phase(86400)>=0 and Ants.phase(86400)<Ants.CYCLE_PX)
  check('v0.38: fase rejeita tempo não numérico',
    Ants.phase('invalid')==0 and Ants.phase(0/0)==0)
  check('v0.38: shader opera em coordenadas de tela',
    Ants.shaderSource:find('screenCoord',1,true)~=nil
    and Ants.shaderSource:find('dashPhase',1,true)~=nil)

  local created,deleted=0,0
  local uniforms={}
  local current={name='shader-anterior'}
  local old=current
  local renderedWithShader=false
  local gpu={
    newShader=function(src)
      created=created+1
      assert(src:find('vec4 effect',1,true))
      return {
        send=function(self,name,value)
          uniforms[#uniforms+1]={name,value}
        end,
        release=function() deleted=deleted+1 end,
      }
    end,
    getShader=function() return current end,
    setShader=function(shader) current=shader end,
  }
  local state={}
  local used=Ants.render(gpu,state,0,function(animated)
    renderedWithShader=animated and current==state.shader
  end)
  check('v0.38: shader criado e aplicado na primeira renderização',
    used and renderedWithShader and created==1)
  check('v0.38: estado GPU anterior restaurado',current==old)
  local another=Ants.render(gpu,state,0.25,function(animated)
    assert(animated and current==state.shader)
  end)
  check('v0.38: animação reutiliza shader',
    another and created==1 and #uniforms==2)
  check('v0.38: uniform avança sem alterar a geometria',
    uniforms[1][1]=='dashPhase' and equal(uniforms[1][2],0)
    and equal(uniforms[2][2],6) and equal(state.lastPhase,6))
  check('v0.38: restaura shader depois de renderização repetida',
    current==old)
  local success,problem=pcall(Ants.render,gpu,state,0.5,
    function() error('erro de desenho proposital') end)
  check('v0.38: erro de desenho é propagado',
    not success and tostring(problem):find('erro de desenho proposital',1,true))
  check('v0.38: erro de desenho não deixa shader ativo',
    current==old)
  Ants.release(state)
  check('v0.38: liberação da GPU e reinicialização da fase',
    deleted==1 and state.shader==nil and state.lastPhase==nil)

  local failedAttempts,failedDraws=0,0
  local broken={
    newShader=function() failedAttempts=failedAttempts+1;error('GPU sem shader') end,
    getShader=function() return nil end,
    setShader=function() end,
  }
  local state2={}
  Ants.render(broken,state2,0,function(animated)
    if not animated then failedDraws=failedDraws+1 end
  end)
  Ants.render(broken,state2,1,function(animated)
    if not animated then failedDraws=failedDraws+1 end
  end)
  check('v0.38: falha de compilação usa contorno estático',
    state2.unavailable and failedDraws==2)
  check('v0.38: falha de compilação não repete tentativa por quadro',
    failedAttempts==1)
  local noShaderDraws=0
  Ants.render({}, {}, 0, function(animated)
    if not animated then noShaderDraws=noShaderDraws+1 end
  end)
  check('v0.38: mocks sem GPU preservam desenho',noShaderDraws==1)

  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(64,64)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  local rect=Selection.rect(doc,10,10,20,20)
  doc.selection=rect
  local lastRects={}
  local lastLines={}
  local palette={}
  local previousShader={name='pincel'}
  local activeShader=previousShader
  local shaderCreations=0
  local oldGraphics=love.graphics
  local fake={
    newShader=function()
      shaderCreations=shaderCreations+1
      return {send=function(self,name,value)
        self.lastUniform=name
        self.lastValue=value
      end}
    end,
    getShader=function()return activeShader end,
    setShader=function(shader)activeShader=shader end,
    setLineWidth=function()end,
    setColor=function(...) palette[#palette+1]={...} end,
    rectangle=function(mode,x,y,w,h)
      lastRects[#lastRects+1]={mode,x,y,w,h,activeShader}
    end,
    line=function(...)
      lastLines[#lastLines+1]={...}
    end,
  }
  love.graphics=fake
  local ok,err=pcall(function()
    bridge:drawSelection(0,0,1,0)
    bridge:drawSelection(0,0,4,0.25)
  end)
  love.graphics=oldGraphics
  check('v0.38: ponte renderiza retângulo com shader',
    ok and shaderCreations==1,err)
  check('v0.38: mesma geometria com animação em ambos quadros',
    #lastRects==2 and lastRects[1][2]==10 and lastRects[1][3]==10
    and lastRects[2][4]==11 and lastRects[2][5]==11)
  check('v0.38: shader ativo apenas durante traçado',
    lastRects[1][6]==bridge.ants.shader
    and lastRects[2][6]==bridge.ants.shader
    and activeShader==previousShader)
  check('v0.38: fase calculada em tempo opcional fixo',
    equal(bridge.ants.lastPhase,Ants.phase(0.25)))
  check('v0.38: seleção e histórico permanecem imutáveis',
    doc.selection==rect and #doc.history.undo==0
    and next(doc.layers[doc.sel].tiles)==nil)

  -- Confirma que o desenho do arraste não herda o shader das formigas.
  bridge.selectionDrag={kind='selection_rect',startX=0,startY=0,x=5,y=5}
  lastRects={}
  love.graphics=fake
  local dragOK=pcall(bridge.drawSelection,bridge,0,0,1,0.5)
  love.graphics=oldGraphics
  check('v0.38: arraste mantém cores próprias, sem shader',
    dragOK and #lastRects==2
    and lastRects[1][6]==bridge.ants.shader
    and lastRects[2][6]==previousShader)
  bridge.selectionDrag=nil

  -- A máscara invertida continua com contornos exatos e shader em cada aresta.
  local bigModel=Model.new()
  bigModel:open_gallery();bigModel:open_new_canvas();bigModel:create_canvas(1024,1024)
  local bigBridge=Bridge.new()
  local bigDoc=assert(bigBridge:sync(bigModel))
  local m=Mask.new(0)
  local tile=Mask.getTile(m,0,0,true)
  tile:setPixel(5,5,1,1,1,1)
  m.inverted=true
  local inv={kind='wand',x=0,y=0,w=1024,h=1024,mask=m}
  bigDoc.selection=inv
  lastRects={}
  lastLines={}
  love.graphics=fake
  local okInvert=pcall(function()
    for i=1,20 do bigBridge:drawSelection(0,0,0.5,i/10) end
  end)
  love.graphics=oldGraphics
  check('v0.38: contorno raster invertido não cria bbox falsa',
    okInvert and #lastRects==0 and #lastLines>0)
  local cache=bigBridge.selectionOutline
  check('v0.38: contorno incremental completa com shader',
    cache and cache.job and cache.job.done
    and not cache.job.truncated and #cache.job.lines==8)
  love.graphics=fake
  local zoomOK=pcall(bigBridge.drawSelection,bigBridge,0,0,3,4)
  love.graphics=oldGraphics
  check('v0.38: zoom mantém cache do contorno',
    zoomOK and bigBridge.selectionOutline==cache)
end
