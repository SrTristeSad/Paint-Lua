-- v0.17: pinceladas na máscara, executadas sob o mock de tests/test_core.lua.
return function(check)
  local Doc = require('core.doc')
  local Layers = require('core.layers')
  local Mask = require('core.mask')
  local Hist = require('core.history')
  local Stroke = require('core.stroke')
  local Brush = require('core.brush')
  local Composite = require('core.composite')
  local Project = require('core.project')
  local function near(a,b,eps) return math.abs(a-b) <= (eps or 1e-8) end
  local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
  local function setLayerPixel(layer,x,y)
    local tx,ty = math.floor(x/Doc.TILE),math.floor(y/Doc.TILE)
    local tile,key = Doc.getTile(layer,tx,ty,true)
    tile:setPixel(x%Doc.TILE,y%Doc.TILE,0.25,0.5,0.75,1)
    Doc.markDirty(layer,key)
  end
  local function coverage(d,x,y)
    return Mask.value(d.layers[2].mask,x,y)
  end
  local function newDoc(w,h,initial)
    local d=Doc.new(w or 32,h or 32,'v0.17')
    Layers.addMask(d,2,initial == nil and 1 or initial)
    return d,d.layers[2]
  end
  local function opt(o)
    local v={size=4,hardness=1,alpha=1,spacing=0.15,maskValue=0}
    for k,x in pairs(o or {}) do v[k]=x end
    return v
  end
  local function paint(d,L,x,y,options,pressure)
    local s=Stroke.newMask(d,L,d.history,opt(options))
    s:push(x+0.5,y+0.5,pressure or 1)
    s:finish()
    return s
  end

  do
    local d,L=newDoc()
    setLayerPixel(L,8,8)
    local original={Doc.getTile(L,0,0,false):getPixel(8,8)}
    local before=#d.history.undo
    paint(d,L,8,8)
    local rgb={Doc.getTile(L,0,0,false):getPixel(8,8)}
    check('v0.17: pincel preto oculta via máscara',near(coverage(d,8,8),0))
    check('v0.17: RGBA da camada não é modificado',rgb[1]==original[1] and rgb[2]==original[2]
      and rgb[3]==original[3] and rgb[4]==original[4])
    check('v0.17: compositor respeita pintura da máscara',near(select(4,Composite.flattenRegion(d,8,8,1,1):getPixel(0,0)),0))
    check('v0.17: um gesto gera uma operação de histórico',#d.history.undo==before+1)
    Hist.undo(d)
    check('v0.17: undo restaura cobertura branca',near(coverage(d,8,8),1))
    Hist.redo(d)
    check('v0.17: redo restaura cobertura preta',near(coverage(d,8,8),0))
    paint(d,L,8,8,{maskValue=1})
    check('v0.17: pincel branco revela novamente',near(coverage(d,8,8),1))
    paint(d,L,8,8,{maskValue=1,eraser=true})
    check('v0.17: borracha na máscara pinta preto',near(coverage(d,8,8),0))
    local changed=#d.history.undo
    paint(d,L,8,8,{maskValue=0})
    check('v0.17: pincelada que não altera pixels não cria histórico',#d.history.undo==changed)
    local t=L.mask.tiles['0,0']
    check('v0.17: os canais de máscara permanecem cinza e opacos',(function()
      local r,g,b,a=t:getPixel(8,8)
      return near(r,g) and near(g,b) and a==1
    end)())
  end

  do
    local d,L=newDoc(512,28,0)
    local before=count(L.mask.tiles)
    paint(d,L,12,8,{maskValue=0})
    check('v0.17: pintar mesma cor do default não aloca tiles',count(L.mask.tiles)==before)
    local s=Stroke.newMask(d,L,d.history,opt({maskValue=1,size=6}))
    s:push(254.5,12.5,1)
    s:push(260.5,12.5,1)
    s:finish()
    check('v0.17: pinceladas cruzam o limite dos tiles',coverage(d,255,12)>0 and coverage(d,256,12)>0)
    check('v0.17: apenas tiles atingidos são alocados',count(L.mask.tiles)==2)
    Hist.undo(d)
    check('v0.17: undo limpa tiles que não existiam antes',count(L.mask.tiles)==0)
    Hist.redo(d)
    check('v0.17: redo recria máscara nos dois tiles',count(L.mask.tiles)==2)
  end

  do
    local d,L=newDoc(32,32,1)
    local before=#d.history.undo
    local s=Stroke.newMask(d,L,d.history,opt({alpha=0.4,maskValue=0,flow=0.5}))
    s:push(10.5,10.5)
    s:push(10.5,10.5)
    s:finish()
    local level=coverage(d,10,10)
    check('v0.17: fluxo 0.5 respeita teto de opacidade 0.4',level>=0.6 and level<1)
    check('v0.17: fluxo cria apenas um item de undo',#d.history.undo==before+1)
    local t=L.mask.tiles['0,0']
    check('v0.17: fluxo mantém alfa de máscara 1',select(4,t:getPixel(10,10))==1)
    local old=level
    local s2=Stroke.newMask(d,L,d.history,opt({maskValue=1,alpha=0.5,pressureOpacity=true}))
    s2:push(10.5,10.5,0)
    s2:finish()
    check('v0.17: pressão zero não modifica máscara quando mínimo é zero',near(coverage(d,10,10),old))
    local s3=Stroke.newMask(d,L,d.history,opt({maskValue=1,alpha=1,pressureOpacity=true,
      pressureCurve={{0,0},{0.5,0.2},{1,1}}}))
    s3:push(10.5,10.5,0.5)
    s3:finish()
    check('v0.17: curva de pressão controla a cobertura',near(coverage(d,10,10),old+(1-old)*0.2,1e-6))
    local s4=Stroke.newMask(d,L,d.history,opt({maskValue=0,alpha=1,pressureSize=true,size=12}))
    s4:push(20.5,20.5,0)
    s4:finish()
    check('v0.17: pressão altera diâmetro no modo máscara',near(coverage(d,25,20),1))
  end

  do
    local d,L=newDoc(50,50,1)
    d.selection={x=5,y=5,w=7,h=7}
    local s=Stroke.newMask(d,L,d.history,opt({maskValue=0,size=20}))
    s:push(9.5,9.5)
    s:finish()
    check('v0.17: nova máscara adota seleção retangular do documento',near(coverage(d,8,8),0)
      and near(coverage(d,13,8),1) and near(coverage(d,8,13),1))
    check('v0.17: mudar seleção depois da criação não afeta gesto terminado',near(coverage(d,8,8),0))
    local x=coverage(d,8,8)
    local before=#d.history.undo
    local s2=Stroke.newMask(d,L,d.history,opt({maskValue=1,size=8}))
    s2:push(30.5,30.5)
    s2:finish()
    check('v0.17: área fora da seleção não cria ação',#d.history.undo==before and near(coverage(d,8,8),x))
  end

  do
    local d,L=newDoc(60,60,1)
    local before=#d.history.undo
    local s=Stroke.newMask(d,L,d.history,opt({size=6,maskValue=0,spacing=0.1,
      smoothing={mode='exponential',amount=0.5},symmetry={mode='vertical',center={30,30}}}))
    s:push(12.5,20.5,1,0)
    s:push(14.5,20.5,1,16)
    s:push(16.5,20.5,1,32)
    s:finish()
    check('v0.17: estabilização funciona ao pintar máscara',coverage(d,12,20)<1)
    check('v0.17: simetria gera cópia na mesma máscara',coverage(d,47,20)<1)
    check('v0.17: estabilização e simetria formam uma ação',#d.history.undo==before+1)
    Hist.undo(d)
    check('v0.17: desfazer traço estabilizado restaura os dois lados',near(coverage(d,12,20),1) and near(coverage(d,47,20),1))
  end

  do
    local d,L=newDoc(30,30,1)
    local tip={width=2,height=2,data={1,0,0,1}}
    local paper={tip={width=2,height=1,data={1,0}},scale=1,depth=1,mode='multiply'}
    local s=Stroke.newMask(d,L,d.history,opt({size=10,maskValue=0,tip=tip,paper=paper,
      dualBrush={tip={width=1,height=1,data={1}},scale=1,depth=0.3},tiltScale=0.5,
      scatter=0.05,seed=123}))
    s:push(10.5,10.5,0.8,nil,0.5,0.1)
    s:finish()
    check('v0.17: pontas, papel, dual brush, tilt e scatter processados',count(L.mask.tiles)==1
      and (function() for y=4,16 do for x=4,16 do if coverage(d,x,y)<1 then return true end end end return false end)())
    local before=coverage(d,10,10)
    Hist.undo(d)
    check('v0.17: textura de máscara é desfazível',near(coverage(d,10,10),1))
    Hist.redo(d)
    check('v0.17: textura de máscara é refeita',near(coverage(d,10,10),before))
  end

  do
    local d,L=newDoc(60,40,1)
    local cache=Composite.newCache(d,{maxTiles=2})
    setLayerPixel(L,9,9)
    local one=cache:tile(0,0)
    local initial=cache:stats().recompositions
    paint(d,L,9,9)
    cache:tile(0,0)
    check('v0.17: pintura na máscara invalida cache CPU',cache:stats().recompositions==initial+1)
    Hist.undo(d)
    cache:tile(0,0)
    check('v0.17: desfazer pintura invalida cache CPU',cache:stats().recompositions==initial+2)
    local before=#d.history.undo
    local s=Stroke.newMask(d,L,d.history,opt({maskValue=0}))
    s:push(9.5,9.5)
    check('v0.17: mascaramento aparece durante o gesto',near(coverage(d,9,9),0))
    s:cancel()
    check('v0.17: cancelar restaura cobertura anterior',near(coverage(d,9,9),1))
    check('v0.17: cancelar não consome undo ou redo',#d.history.undo==before and #d.history.redo==1)
    local redraw=cache:stats().recompositions
    cache:tile(0,0)
    check('v0.17: cancelamento invalida o cache',cache:stats().recompositions==redraw+1)
    check('v0.17: não é possível continuar gesto cancelado',not pcall(s.push,s,10,10))
  end

  do
    local d,L=newDoc(30,30,1)
    local i0=#d.history.undo
    local invalid={
      {maskValue=-0.1}, {maskValue=1.1}, {maskValue=0/0},
      {wetPaint={wet=1}}, {mix={strength=0.5}}, {size=0}, {alpha=-1},
    }
    local rejected=true
    for _,extra in ipairs(invalid) do
      local o=opt(extra)
      if pcall(Stroke.newMask,d,L,d.history,o) then rejected=false; Hist.rollback(d.history) end
    end
    check('v0.17: opções inválidas não iniciam gesto',rejected and d.history.stroke==nil)
    check('v0.17: erros de validação preservam histórico',#d.history.undo==i0)
    local noMaskDoc=Doc.new(10,10,'sem máscara')
    check('v0.17: pintar em camada sem máscara é rejeitado',not pcall(Stroke.newMask,noMaskDoc,noMaskDoc.layers[2],noMaskDoc.history,opt()))
    local outsider=Doc.newLayer('outro documento')
    outsider.mask=Mask.new()
    check('v0.17: pintar em camada de fora é rejeitado',not pcall(Stroke.newMask,d,outsider,d.history,opt()))
    check('v0.17: Brush.dab em máscara exige histórico iniciado',not pcall(Brush.dab,d,L,d.history,5,5,
      {target='mask',size=4,alpha=1,hardness=1,maskValue=0,color={1,1,1}}))
    Hist.begin(d.history)
    local ok=pcall(Brush.dab,d,L,d.history,5.5,5.5,
      {target='mask',size=4,alpha=1,hardness=1,maskValue=0,color={1,1,1}})
    Hist.commit(d.history)
    check('v0.17: Brush.dab suporta alvo de máscara',ok and near(coverage(d,5,5),0))
  end

  do
    local d,L=newDoc(30,30,1)
    local old=love.image.newImageData
    local failOnWrite=0
    love.image.newImageData=function(w,h)
      local t=old(w,h)
      local base=t.setPixel
      local n=0
      function t:setPixel(...)
        n=n+1
        if n==65538 then failOnWrite=failOnWrite+1; error('falha de IO simulada') end
        return base(self,...)
      end
      return t
    end
    local before=#d.history.undo
    local s=Stroke.newMask(d,L,d.history,opt({size=7}))
    local ok=pcall(s.push,s,10.5,10.5)
    love.image.newImageData=old
    check('v0.17: falha simulada na máscara é propagada',not ok and failOnWrite==1)
    check('v0.17: falha automática reverte tile parcialmente escrito',count(L.mask.tiles)==0 and near(coverage(d,10,10),1))
    check('v0.17: falha fecha o gesto, sem entrada de histórico',s.closed and d.history.stroke==nil and #d.history.undo==before)
    local s2=Stroke.newMask(d,L,d.history,opt())
    s2:push(10.5,10.5)
    s2:finish()
    check('v0.17: é possível pintar após recuperação',near(coverage(d,10,10),0))
  end

  do
    local d,L=newDoc(64,32,1)
    setLayerPixel(L,5,5)
    paint(d,L,5,5,{maskValue=0.35})
    local data=Project.encode(d)
    check('v0.17: salvar pintura de máscara produz NPNT2',data:sub(1,6)=='NPNT2\n')
    local other,err=Project.decode(data)
    check('v0.17: NPNT2 reabre pixels pintados pela máscara',other and near(coverage(other,5,5),0.35,1/255+1e-5),tostring(err))
    check('v0.17: abrir máscara conserva pixels de camada',(function()
      if not other then return false end
      local t=Doc.getTile(other.layers[2],0,0,false)
      local r,g,b,a=t:getPixel(5,5)
      return near(r,0.25,1/255+1e-5) and near(g,0.5,1/255+1e-5) and a==1
    end)())
  end

  do
    local d,L=newDoc(32,32,1)
    setLayerPixel(L,8,8)
    Layers.setMaskInverted(d,2,true)
    paint(d,L,8,8,{maskValue=0})
    check('v0.17: pincel escreve dados brutos mesmo com máscara invertida',
      near(select(1,L.mask.tiles['0,0']:getPixel(8,8)),0))
    check('v0.17: máscara invertida revela preto após pintura',
      near(coverage(d,8,8),1))
    Layers.setMaskEnabled(d,2,false)
    local oldCount=#d.history.undo
    paint(d,L,10,8,{maskValue=0.25})
    check('v0.17: pincel pode editar máscara desativada',
      near(select(1,L.mask.tiles['0,0']:getPixel(10,8)),0.25)
      and #d.history.undo==oldCount+1)
    check('v0.17: máscara desligada não reduz alfa da camada',
      near(select(4,Composite.flattenRegion(d,8,8,1,1):getPixel(0,0)),1))
  end

  do
    local d,L=newDoc(30,30,1)
    local opts0=opt({maskValue=0,alpha=1,size=5,pressureOpacity=true})
    local before=#d.history.undo
    Hist.begin(d.history)
    local options={}
    for k,v in pairs(opts0) do options[k]=v end
    options.target='mask'
    options.pressureStart=0
    options.pressureEnd=1
    Brush.line(d,L,d.history,5.5,10.5,18.5,10.5,options)
    Hist.commit(d.history)
    check('v0.17: Brush.line suporta interpolação de pressão em máscara',
      coverage(d,18,10)<coverage(d,7,10))
    check('v0.17: Brush.line pinta em um único histórico',#d.history.undo==before+1)
    Hist.undo(d)
    check('v0.17: Brush.line restaura máscara após undo',
      near(coverage(d,18,10),1) and near(coverage(d,7,10),1))
    local s=Stroke.newMask(d,L,d.history,opt())
    check('v0.17: operações estruturais são bloqueadas durante traço de máscara',
      not pcall(Layers.removeMask,d,2))
    check('v0.17: salvamento de estado parcial é bloqueado',
      not pcall(Project.encode,d))
    s:cancel()
    check('v0.17: cancelamento libera novas operações de estrutura',
      pcall(Layers.setMaskEnabled,d,2,false))
  end

end
