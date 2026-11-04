-- Casos da v0.13. Importado pelo test_core.lua após instalar mock do LÖVE.
local Doc = require('core.doc')
local Hist = require('core.history')
local Fill = require('core.fill')
local Job = require('core.job')
local Brush = require('core.brush')
local Layers = require('core.layers')
local Project = require('core.project')
local T = Doc.TILE

return function(check)
  local function tileCount(layer)
    local c=0
    for _ in pairs(layer.tiles) do c=c+1 end
    return c
  end
  local function samePixels(a,b,w,h)
    for y=0,h-1 do
      for x=0,w-1 do
        local a1,a2,a3,a4 = Fill.pixel(a,x,y)
        local b1,b2,b3,b4 = Fill.pixel(b,x,y)
        if a1~=b1 or a2~=b2 or a3~=b3 or a4~=b4 then
          return false, x..','..y
        end
      end
    end
    return true
  end
  local function finish(job)
    local steps, prev = 0, 0
    local monotone = true
    while not job.done do
      local done=Job.step(job,0)
      steps=steps+1
      monotone=monotone and job.progress>=prev and job.progress<=1
      prev=job.progress
      if steps>100000 then error('job não terminou') end
      if done then break end
    end
    return job.result,steps,monotone
  end
  local cases={
    {name='vazio entre tiles', x=1,y=1, tol=0, color={0.1,0.5,0.9,1}},
    {name='mesma cor na tolerância', x=20,y=12,tol=0.15,color={0.02,0,0,0}},
    {name='seleção fracionária', x=260,y=8,tol=1,color={0.8,0.4,0,0.7}, sel={x=254.2,y=4.3,w=267.3,h=19.1}},
    {name='alfa e paredes',x=3,y=3,tol=0.2,color={1,0,0,0.7}},
  }
  for _,c in ipairs(cases) do
    local a,b=Doc.new(541,26,c.name),Doc.new(541,26,c.name)
    local la,lb=a.layers[2],b.layers[2]
    -- Barras de alfa que atravessam dois tiles, com aberturas.
    for _,d in ipairs({a,b}) do
      local l=d.layers[2]
      local t=Doc.getTile(l,1,0,true)
      for y=0,25 do
        t:setPixel(9,y,0,0,0,1)
        t:setPixel(95,y,0,0,0,1)
        if y%3==0 then t:setPixel(30,y,0.09,0,0,0) end
      end
    end
    local expected=Fill.fill(a,la,c.x,c.y,c.color,c.tol,c.sel)
    local job=Fill.newJob(b,lb,c.x,c.y,c.color,c.tol,c.sel,{yieldEvery=19})
    local result,steps,progress=finish(job)
    local equal,where=samePixels(la,lb,541,26)
    check('v0.13: pixels equivalentes ao síncrono ('..c.name..')',equal,where)
    check('v0.13: contagem equivalente ('..c.name..')',result==expected)
    check('v0.13: progresso monotônico ('..c.name..')',progress and job.progress==1)
    check('v0.13: histórico equivalente ('..c.name..')',
      #a.history.undo==#b.history.undo and #a.history.redo==#b.history.redo and
      b.history.stroke==nil and b.history._fillLock==nil)
    if expected>0 then
      check('v0.13: preenche em mais de uma fatia ('..c.name..')',steps>1)
      local u1,u2=Hist.undo(a),Hist.undo(b)
      local sameUndo=samePixels(la,lb,541,26)
      check('v0.13: desfazer equivalente ('..c.name..')',u1 and u2 and sameUndo)
      Hist.redo(a);Hist.redo(b)
      local sameRedo=samePixels(la,lb,541,26)
      check('v0.13: refazer equivalente ('..c.name..')',sameRedo)
    end
  end

  do
    local d=Doc.new(300,22,'cancelamento e bloqueio')
    local l=d.layers[2]
    local tile=Doc.getTile(l,0,0,true)
    tile:setPixel(2,4,0,0,0,1)
    local base=tile:clone()
    local job=Fill.newJob(d,l,5,5,{1,0,0,1},0,nil,{yieldEvery=2})
    check('v0.13: bloqueia histórico antes da primeira fatia',
      d.history._fillLock~=nil and not pcall(Hist.begin,d.history) and
      not pcall(Fill.fill,d,l,5,5,{0,1,0,1},0))
    check('v0.13: bloqueia outro job e operações de camadas',
      not pcall(Fill.newJob,d,l,5,5,{1,1,0,1}) and
      not pcall(Layers.add,d,'interferência') and
      not pcall(Layers.setOpacity,d,2,60) and
      not pcall(Layers.select,d,1))
    check('v0.13: bloqueia pincel e desfazer/refazer',
      not pcall(Brush.dab,d,l,d.history,5,5,
        {size=2,alpha=1,color={1,0,0},hardness=1}) and
      not pcall(Hist.undo,d) and not pcall(Hist.redo,d))
    local saved,saveError=Project.save(d,'durante-preenchimento.npnt')
    check('v0.13: salvar projeto incompleto é rejeitado',
      not saved and type(saveError)=='string' and
      not pcall(Project.encode,d))
    local partially=false
    for _=1,500 do
      Job.step(job,0)
      if d.history.stroke and select(4,Fill.pixel(l,5,5))==1 then partially=true;break end
    end
    check('v0.13: produz pixels antes de ser cancelado',partially and job.progress<1)
    local wasCancelled=Job.cancel(job)
    local r,g,b,a=Fill.pixel(l,2,4)
    local rr,gg,bb,aa=Fill.pixel(l,5,5)
    check('v0.13: cancelar restaura tile original',
      wasCancelled and r==0 and g==0 and b==0 and a==1 and
      rr==0 and gg==0 and bb==0 and aa==0 and l.tiles['0,0']~=base)
    check('v0.13: cancelar limpa histórico e lock',
      d.history.stroke==nil and d.history._fillLock==nil and
      #d.history.undo==0 and #d.history.redo==0 and l.dirty['0,0'])
    check('v0.13: job cancelado não volta a pintar',
      select(1,Job.step(job,0)) and not Job.cancel(job))
    check('v0.13: documento volta a aceitar edições',
      Fill.fill(d,l,10,10,{0,1,0,1})>0)
    check('v0.13: projeto pode ser salvo após cancelamento',
      Project.save(d,'apos-cancelamento.npnt')==true)
  end

  do
    local d=Doc.new(9,9,'cancela sem iniciar')
    local l=d.layers[2]
    local j=Fill.newJob(d,l,1,1,{1,0,0,1},0)
    local a=Job.cancel(j)
    check('v0.13: cancela antes do primeiro passo sem criar pixels',
      a and #d.history.undo==0 and tileCount(l)==0 and d.history._fillLock==nil)
    local j2=Fill.newJob(d,l,-1,1,{1,0,0,1},0)
    local done,count=Job.step(j2,0)
    check('v0.13: região vazia conclui sem bloquear o documento',
      done and count==0 and d.history._fillLock==nil)
    local invalid={0,-1,65537,1.5,0/0,math.huge,'100'}
    local allBad=true
    for _,v in ipairs(invalid) do
      if pcall(Fill.newJob,d,l,1,1,{1,0,0,1},0,nil,{yieldEvery=v}) then allBad=false end
    end
    check('v0.13: valida orçamento de operações e não bloqueia',
      allBad and d.history._fillLock==nil)
    check('v0.13: valida seleção e cor antes de criar trabalho',
      not pcall(Fill.newJob,d,l,1,1,{2,0,0},0) and
      not pcall(Fill.newJob,d,l,1,1,{1,0,0},0,{x=0,y=0,w=-1,h=2}) and
      d.history._fillLock==nil)
  end

  do
    local d=Doc.new(513,7,'grandes linhas')
    local l=d.layers[2]
    -- Uma única linha > tamanho do lote: não deve travar dentro da pintura.
    local job=Fill.newJob(d,l,2,2,{0,0,1,1},0,{x=0,y=2,w=513,h=1},{yieldEvery=8})
    Job.step(job,0)
    check('v0.13: linha longa cede antes de terminar',not job.done and job.progress<1)
    local n,steps=finish(job)
    check('v0.13: linha longa completa atravessando três tiles',
      n==513 and steps>10 and select(4,Fill.pixel(l,512,2))==1)
  end

  do
    local d=Doc.new(60,15,'falha assíncrona')
    local l=d.layers[2]
    local old=love.image.newImageData
    local writes=0
    love.image.newImageData=function(w,h)
      local t=old(w,h)
      local setter=t.setPixel
      function t:setPixel(...)
        writes=writes+1
        if writes==140 then error('erro de escrita assíncrona') end
        return setter(self,...)
      end
      return t
    end
    local job=Fill.newJob(d,l,1,1,{1,0,0,1},0,nil,{yieldEvery=3})
    local ok=pcall(function()
      while not job.done do Job.step(job,0) end
    end)
    love.image.newImageData=old
    check('v0.13: erro de escrita é propagado ao executar job',not ok and writes==140)
    check('v0.13: erro restaura os tiles e libera histórico',
      job.done and tileCount(l)==0 and d.history.stroke==nil and
      d.history._fillLock==nil and #d.history.undo==0)
    check('v0.13: novo job pode iniciar após erro',
      Fill.fill(d,l,1,1,{1,0,0,1},0)==900)
  end

  do
    local d=Doc.new(11,11,'job e redo')
    local l=d.layers[2]
    Fill.fill(d,l,1,1,{1,0,0,1})
    Hist.undo(d)
    local job=Fill.newJob(d,l,2,2,{0,1,0,1},0,nil,{yieldEvery=3})
    Job.step(job,0)
    local before=#d.history.redo
    Job.cancel(job)
    check('v0.13: cancelar preserva a pilha de redo',
      before==1 and #d.history.redo==1 and #d.history.undo==0)
    local j2=Fill.newJob(d,l,1,1,{0,1,0,1},0,nil,{yieldEvery=3})
    local pixels=finish(j2)
    check('v0.13: conclusão cria um único undo e limpa redo',
      pixels==121 and #d.history.undo==1 and #d.history.redo==0)
    local j3=Fill.newJob(d,l,1,1,{0,1,0,1},0,nil,{yieldEvery=3})
    local done,number=Job.step(j3,0)
    check('v0.13: mesma cor e tolerância zero não mexe no histórico',
      done and number==0 and #d.history.undo==1 and #d.history.redo==0)
  end

  do
    local j=Job.new(function() coroutine.yield(0.2);return 9 end)
    local cancelled=Job.cancel(j)
    check('v0.13: Job.cancel padrão continua compatível',
      cancelled and j.cancelled and j.done and select(1,Job.step(j,0)))
    local j2=Job.new(function() error('falha de job genérico') end)
    check('v0.13: erros de jobs genéricos continuam propagados',
      not pcall(Job.step,j2,0) and j2.done)
  end
end
