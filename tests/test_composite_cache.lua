-- Cache CPU da v0.15. Usa a mesma simulação ImageData de test_core.lua.
local Doc = require('core.doc')
local Composite = require('core.composite')
local Layers = require('core.layers')
local Hist = require('core.history')
local Render = require('core.render')
local Fill = require('core.fill')
local Job = require('core.job')
local Stroke = require('core.stroke')

local function near(a,b) return math.abs(a-b)<1e-9 end
local function rgba(a,x,y)
  local r,g,b,v=a:getPixel(x,y)
  return {r,g,b,v}
end
local function equal(a,b,x,y)
  local u,v=rgba(a,x,y),rgba(b,x,y)
  for i=1,4 do if not near(u[i],v[i]) then return false end end
  return true
end

return function(check)
  local d=Doc.new(520,520,'cache v0.15')
  local bottom, top=d.layers[1],d.layers[2]
  local key='0,0'
  local back=Doc.getTile(bottom,0,0,true)
  back:setPixel(254,254,0,0,1,1)
  Doc.markDirty(bottom,key)
  local a=Doc.getTile(top,0,0,true)
  a:setPixel(254,254,1,0,0,0.5)
  Doc.markDirty(top,key)
  local b=Doc.getTile(top,1,0,true)
  b:setPixel(0,254,0,1,0,0.75)
  Doc.markDirty(top,'1,0')
  local c=Doc.getTile(top,0,1,true)
  c:setPixel(254,0,1,1,0,0.75)
  Doc.markDirty(top,'0,1')
  local e=Doc.getTile(top,1,1,true)
  e:setPixel(0,0,0,1,1,1)
  Doc.markDirty(top,'1,1')

  local cache=Composite.newCache(d,{maxTiles=4})
  local original=Composite.flattenRegion(d,253,253,5,5)
  local computed=cache:region(253,253,5,5)
  local match=true
  for y=0,4 do for x=0,4 do
    if not equal(original,computed,x,y) then match=false end
  end end
  check('v0.15: cache compõe corretamente recorte entre 4 tiles',match)
  check('v0.15: primeira composição cria 4 tiles em cache',cache:stats().tiles==4 and cache:stats().misses==4)
  local repeated=cache:region(253,253,5,5)
  check('v0.15: segunda composição só reutiliza tiles',cache:stats().hits==4 and cache:stats().recompositions==4)
  check('v0.15: cache mantém pixels idênticos quando reutilizado',equal(repeated,computed,1,1) and equal(repeated,computed,3,1))

  local exposed=cache:tile(0,0)
  exposed:setPixel(254,254,0.88,0.88,0.88,0.88)
  check('v0.15: consumidor não pode corromper o buffer interno do cache',
    select(1,cache:tile(0,0):getPixel(254,254))~=0.88)

  local before=cache:stats().recompositions
  a:setPixel(254,254,0.1,0.8,0.2,0.5)
  Doc.markDirty(top,'0,0')
  local modified=cache:region(253,253,5,5)
  check('v0.15: revisão invalida apenas tile realmente alterado',cache:stats().recompositions==before+1)
  check('v0.15: pixel alterado aparece na composição',not equal(modified,original,1,1)
      and equal(modified,Composite.flattenRegion(d,253,253,5,5),1,1))

  -- Render.refresh esvazia dirty; a revisão separada ainda protege cache.
  local saved=love.graphics
  love.graphics={newImage=function(tile)
    return {replacePixels=function() end,release=function() end}
  end}
  Render.refresh(d)
  love.graphics=saved
  local previous=cache:stats().recompositions
  a:setPixel(254,254,0.8,0.1,0.4,0.6)
  Doc.markDirty(top,'0,0')
  cache:region(253,253,5,5)
  check('v0.15: invalidar funciona mesmo após limpar dirty pela GPU',cache:stats().recompositions==previous+1)

  -- Os atributos de camada são parte da assinatura, independentemente de dirty.
  local old=cache:stats().recompositions
  Layers.setOpacity(d,2,44)
  local changed=cache:region(253,253,5,5)
  check('v0.15: opacidade invalida todos os tiles do recorte',cache:stats().recompositions==old+4)
  check('v0.15: mudança de opacidade preserva equivalência visual',
     equal(changed,Composite.flattenRegion(d,253,253,5,5),1,1))
  old=cache:stats().recompositions
  Layers.setBlend(d,2,'multiply')
  cache:region(253,253,5,5)
  check('v0.15: modo de mesclagem invalida cache',cache:stats().recompositions==old+4)
  old=cache:stats().recompositions
  Layers.setVisible(d,2,false)
  cache:region(253,253,5,5)
  check('v0.15: visibilidade invalida cache',cache:stats().recompositions==old+4)
  old=cache:stats().recompositions
  Hist.undo(d)
  cache:region(253,253,5,5)
  check('v0.15: undo de propriedade invalida cache',cache:stats().recompositions==old+4)
  old=cache:stats().recompositions
  Hist.redo(d)
  cache:region(253,253,5,5)
  check('v0.15: redo de propriedade invalida cache',cache:stats().recompositions==old+4)
  Layers.setVisible(d,2,true)
  Layers.setOpacity(d,2,100)
  Layers.setBlend(d,2,'normal')
  cache:region(253,253,5,5)

  -- Conteúdo desfeito/refeito enquanto a mesma ImageData volta a ser utilizada.
  local v=cache:stats().recompositions
  Hist.begin(d.history)
  Hist.touch(d.history,top,'0,0')
  a:setPixel(254,254,0.9,0.2,0.3,1)
  Doc.markDirty(top,'0,0')
  local pending=cache:region(253,253,5,5)
  check('v0.15: durante gesto cache não guarda composição parcial',
    cache:stats().recompositions==v and equal(pending,Composite.flattenRegion(d,253,253,5,5),1,1))
  Hist.commit(d.history)
  cache:region(253,253,5,5)
  local after=cache:stats().recompositions
  check('v0.15: após commit invalida tile editado',after==v+1)
  Hist.undo(d)
  local reversed=cache:region(253,253,5,5)
  check('v0.15: undo de pixels invalida tile',cache:stats().recompositions==after+1
    and equal(reversed,Composite.flattenRegion(d,253,253,5,5),1,1))
  Hist.redo(d)
  local redone=cache:region(253,253,5,5)
  check('v0.15: redo de pixels invalida tile',cache:stats().recompositions==after+2
    and equal(redone,Composite.flattenRegion(d,253,253,5,5),1,1))

  -- Mudança estrutural (inclusão/exclusão/ordem) é observada sem notificações extras.
  local structural=cache:stats().recompositions
  Layers.add(d,'v015 adicional')
  cache:region(253,253,5,5)
  check('v0.15: adicionar camada invalida composição',cache:stats().recompositions==structural+4)
  structural=cache:stats().recompositions
  Layers.delete(d)
  cache:region(253,253,5,5)
  check('v0.15: excluir camada invalida composição',cache:stats().recompositions==structural+4)
  structural=cache:stats().recompositions
  Hist.recordStructure(d)
  d.layers[1],d.layers[2]=d.layers[2],d.layers[1]
  local ordered=cache:region(253,253,5,5)
  check('v0.15: troca de ordem invalida cache',cache:stats().recompositions==structural+4
    and equal(ordered,Composite.flattenRegion(d,253,253,5,5),1,1))
  Hist.undo(d)
  check('v0.15: desfazer reordenação preserva imagem',
    equal(cache:region(253,253,5,5),Composite.flattenRegion(d,253,253,5,5),1,1))

  -- Cache com limite estrito e recortes parciais nas bordas do documento.
  local tiny=Composite.newCache(d,{maxTiles=1})
  tiny:tile(1,1)
  tiny:tile(0,0)
  local st=tiny:stats()
  check('v0.15: política LRU respeita o número máximo de tiles',st.tiles==1 and st.evictions==1)
  check('v0.15: orçamento nominal contabiliza RGBA8',st.estimatedBytes==256*256*4)
  local count=tiny:stats().recompositions
  tiny:tile(0,0)
  check('v0.15: tile mais recente permanece no cache LRU',tiny:stats().recompositions==count)
  tiny:tile(1,1)
  check('v0.15: cache recompõe tile descartado',tiny:stats().recompositions==count+1)
  local edge=tiny:tile(2,2)
  check('v0.15: tile parcial respeita limite do documento',edge:getWidth()==8 and edge:getHeight()==8)
  local r=tiny:region(510,510,10,10)
  check('v0.15: regiões na borda são renderizáveis',r:getWidth()==10 and r:getHeight()==10)
  check('v0.15: recorte fora do documento é rejeitado',not pcall(tiny.region,tiny,512,512,20,20))
  check('v0.15: índices de tile negativos são rejeitados',not pcall(tiny.tile,tiny,-1,0))
  check('v0.15: número inválido de tiles é rejeitado',not pcall(Composite.newCache,d,{maxTiles=0})
      and not pcall(Composite.newCache,d,{maxTiles=1.5})
      and not pcall(Composite.newCache,d,{maxTiles=math.huge}))
  local oldCount=tiny:stats().recompositions
  tiny:clear()
  check('v0.15: limpeza explícita libera todas as entradas',tiny:stats().tiles==0
       and tiny:stats().estimatedBytes==0)
  tiny:tile(0,0)
  check('v0.15: após limpeza recompõe ao solicitar novamente',tiny:stats().recompositions==oldCount+1)

  -- Um job interrompido não pode poluir o cache com pixels transitórios.
  do
    local fillDoc=Doc.new(20,12,'v015 job concorrente')
    local fillLayer=fillDoc.layers[2]
    local fc=Composite.newCache(fillDoc,{maxTiles=2})
    local empty=fc:region(0,0,20,12)
    local initial=fc:stats().recompositions
    local job=Fill.newJob(fillDoc,fillLayer,1,1,{1,0,0,1},0,nil,{yieldEvery=3})
    Job.step(job,0)
    local partial=fc:region(0,0,20,12)
    check('v0.15: composição durante job usa pixels atuais, sem cachear',
      fc:stats().recompositions==initial
      and equal(partial,Composite.flattenRegion(fillDoc,0,0,20,12),1,1))
    Job.cancel(job)
    local afterCancel=fc:region(0,0,20,12)
    check('v0.15: cancelamento de job restaura resultado do cache',
      equal(afterCancel,empty,1,1) and equal(afterCancel,empty,19,11)
      and fillDoc.history._fillLock==nil)
    check('v0.15: job cancelado não grava ação no histórico',
      #fillDoc.history.undo==0 and fillDoc.history.stroke==nil)
  end

  do
    local sd=Doc.new(64,64,'v015 gesto cancelado')
    local sl=sd.layers[2]
    local sc=Composite.newCache(sd,{maxTiles=1})
    local empty=sc:region(0,0,8,8)
    local brush=Stroke.new(sd,sl,sd.history,
      {size=4,alpha=1,color={0,0,1},hardness=1})
    brush:push(3,3,1,0)
    local live=sc:region(0,0,8,8)
    check('v0.15: cache não grava resultado de traço em andamento',
      sc:stats().recompositions==1 and not equal(live,empty,3,3))
    brush:cancel()
    local restored=sc:region(0,0,8,8)
    check('v0.15: cancelamento de stroke invalida revisão corretamente',
      equal(restored,empty,3,3) and sd.history.stroke==nil)
  end

  -- Alterar dados *sem* passar por Doc.markDirty é operação não suportada.
  check('v0.15: cache não modifica APIs anteriores',type(Composite.flatten)=='function'
      and type(Composite.flattenRegion)=='function' and type(Composite.stream)=='function')
end
