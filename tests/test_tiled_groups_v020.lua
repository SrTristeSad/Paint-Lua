-- v0.20: compara cada canal contra o compositor congelado da v0.19.
-- A referência é código de teste, não participa do núcleo em produção.
return function(check)
  local Doc = require('core.doc')
  local Layers = require('core.layers')
  local Groups = require('core.groups')
  local Composite = require('core.composite')
  local Baseline = require('tests.reference_composite_v019')
  local History = require('core.history')
  local Job = require('core.job')

  local function write(layer,x,y,r,g,b,a)
    local tx,ty=math.floor(x/Doc.TILE),math.floor(y/Doc.TILE)
    local tile,key=Doc.getTile(layer,tx,ty,true)
    tile:setPixel(x%Doc.TILE,y%Doc.TILE,r,g,b,a)
    Doc.markDirty(layer,key)
  end
  local function compare(a,b,w,h)
    for y=0,h-1 do
      for x=0,w-1 do
        local ar,ag,ab,aa=a:getPixel(x,y)
        local br,bg,bb,ba=b:getPixel(x,y)
        if ar~=br or ag~=bg or ab~=bb or aa~=ba then
          return false,string.format('divergência em (%d,%d): %.8g/%.8g %.8g/%.8g %.8g/%.8g %.8g/%.8g',
            x,y,ar,br,ag,bg,ab,bb,aa,ba)
        end
      end
    end
    return true
  end
  local function sameRegion(d,x,y,w,h)
    local n=Composite.flattenRegion(d,x,y,w,h)
    local o=Baseline.flattenRegion(d,x,y,w,h)
    return compare(n,o,w,h)
  end

  do
    -- Duas pastas irmãs, clipping, blend e máscaras com pixels nos dois lados
    -- das fronteiras x=256 e y=256. Verifica o cruzamento de blocos.
    local d=Doc.new(270,261,'cenas complexas')
    for i=3,6 do Layers.add(d,'C'..i) end
    local points={{0,0},{2,2},{254,255},{255,255},{256,255},
      {259,256},{260,259},{269,260},{0,260},{269,0}}
    for i,layer in ipairs(d.layers) do
      for _,p in ipairs(points) do
        write(layer,p[1],p[2],(i%3)/3,(i%5)/5,(i%7)/7,0.22+(i%4)*0.16)
      end
    end
    local a=Groups.create(d,2,3,'A')
    local b=Groups.create(d,4,5,'B')
    local inner=Groups.create(d,5,5,'B-filho')
    Groups.setBlend(d,a,'multiply')
    Groups.setBlend(d,b,'screen')
    Groups.setBlend(d,inner,'overlay')
    Groups.setOpacity(d,a,72)
    Groups.setOpacity(d,b,66)
    Groups.setOpacity(d,inner,38)
    Layers.setBlend(d,4,'difference')
    Groups.setClipped(d,3,true)
    Layers.addMask(d,2,1)
    Layers.setMaskPixel(d,2,255,255,0.37)
    Groups.addMask(d,a,1)
    Groups.setMaskPixel(d,a,256,255,0.45)
    Groups.addMask(d,b,0.2)
    Groups.setMaskPixel(d,b,260,259,0.72)
    Groups.addMask(d,inner,0.9)
    Groups.setMaskInverted(d,inner,true)
    local ok,err=sameRegion(d,0,0,270,261)
    check('v0.20: pasta dupla, recorte, modos e máscaras preservam TODOS os pixels',ok,err)
    ok,err=sameRegion(d,254,254,12,7)
    check('v0.20: recorte regional não alinhado cruza quatro tiles sem alteração',ok,err)
    ok,err=sameRegion(d,263,257,7,4)
    check('v0.20: recorte da borda direita/inferior preserva transparência',ok,err)
    local cache=Composite.newCache(d,{maxTiles=8})
    local cr=cache:region(254,254,12,7)
    local expected=Composite.flattenRegion(d,254,254,12,7)
    ok,err=compare(cr,expected,12,7)
    check('v0.20: cache CPU devolve pixels iguais à composição em blocos',ok,err)
    History.undo(d)
    ok,err=sameRegion(d,254,254,12,7)
    check('v0.20: desfazer máscara de grupo preserva paridade',ok,err)
    History.redo(d)
    ok,err=sameRegion(d,254,254,12,7)
    check('v0.20: refazer máscara de grupo preserva paridade',ok,err)
    local steps=0
    local async=Composite.flattenAsync(d)
    repeat
      local complete=Job.step(async,0)
      steps=steps+1
      if complete then break end
      assert(steps<200,'job de composição não terminou')
    until false
    local reference=Baseline.flatten(d)
    ok,err=compare(async.result,reference,d.w,d.h)
    check('v0.20: composição assíncrona retorna pixels idênticos à referência',ok,err)
    check('v0.20: progresso assíncrono finaliza corretamente',async.done and async.progress==1)
  end

  do
    -- Um tile pintado em 8 grupos aninhados: buffer temporário jamais
    -- deve ter a área do documento completo.
    local d=Doc.new(520,290,'oito níveis')
    write(d.layers[2],1,2,0.72,0.1,0.8,0.65)
    local groups={}
    for i=1,8 do
      local id=Groups.create(d,2,2,'nível '..i)
      groups[#groups+1]=id
      Groups.setOpacity(d,id,90-i)
    end
    local make=love.image.newImageData
    local allocations,largest,tempPixels=0,0,0
    love.image.newImageData=function(w,h)
      allocations=allocations+1
      largest=math.max(largest,w*h)
      tempPixels=tempPixels+w*h
      return make(w,h)
    end
    local ok,result=pcall(Composite.flatten,d)
    love.image.newImageData=make
    check('v0.20: documento com oito níveis compõe com sucesso',ok,tostring(result))
    check('v0.20: oito níveis reutilizam um scratch por nível',allocations<=9,
      'alocações='..allocations)
    check('v0.20: área total solicitada cabe em saída + 8 tiles',
      tempPixels<=d.w*d.h+8*Doc.TILE*Doc.TILE,'pixels='..tempPixels)
    local ref=Baseline.flattenRegion(d,1,2,1,1)
    local r,g,b,a=result:getPixel(1,2)
    local rr,gg,bb,aa=ref:getPixel(0,0)
    check('v0.20: aninhamento profundo preserva os quatro canais',
      r==rr and g==gg and b==bb and a==aa)
    check('v0.20: não cria buffers do tamanho da região em cada grupo',
      allocations<=9 and largest==d.w*d.h)
    -- Reutilização de buffers também entre tiles: o limite independe
    -- da quantidade de tiles preenchidos.
    write(d.layers[2],519,289,1,0.2,0.1,1)
    allocations=0
    love.image.newImageData=function(w,h)
      allocations=allocations+1
      return make(w,h)
    end
    local ok2=pcall(Composite.flatten,d)
    love.image.newImageData=make
    check('v0.20: reutiliza scratches entre tiles distantes',ok2 and allocations<=9,
      'alocações='..allocations)
  end

  do
    -- Grupo cujo alpha é totalmente oculto por uma máscara uniforme:
    -- evita tanto render dos filhos quanto buffers intermediários.
    local d=Doc.new(280,280,'grupo invisível por máscara')
    local id=Groups.create(d,2,2,'oculto')
    write(d.layers[2],5,5,1,0,0,1)
    Groups.addMask(d,id,0)
    local original=love.image.newImageData
    local allocations=0
    love.image.newImageData=function(w,h)
      allocations=allocations+1
      return original(w,h)
    end
    local r=Composite.flattenRegion(d,0,0,8,8)
    love.image.newImageData=original
    check('v0.20: grupo com máscara zero sem tiles não ocupa buffers',allocations==1)
    check('v0.20: grupo mascarado integralmente não afeta resultado',
      select(4,r:getPixel(5,5))==0)
    Groups.setMaskInverted(d,id,true)
    local r2=Composite.flattenRegion(d,0,0,8,8)
    check('v0.20: máscara invertida volta a revelar o grupo',
      select(4,r2:getPixel(5,5))==1)
    local ok,err=sameRegion(d,0,0,8,8)
    check('v0.20: inversão e máscara padrão batem com v0.19',ok,err)
  end

  do
    -- Sem grupo, nenhuma estrutura auxiliar deve ser criada para a saída.
    local d=Doc.new(320,260,'sem grupos')
    write(d.layers[2],260,259,1,1,0,0.5)
    local make=love.image.newImageData
    local n=0
    love.image.newImageData=function(w,h)
      n=n+1
      return make(w,h)
    end
    local result=Composite.flattenRegion(d,250,250,60,10)
    love.image.newImageData=make
    check('v0.20: sem grupos continua alocando somente a saída',n==1)
    local ref=Baseline.flattenRegion(d,250,250,60,10)
    local ok,err=compare(result,ref,60,10)
    check('v0.20: caminho legado sem grupos preserva pixels',ok,err)
  end

  do
    -- Exercita explicitamente ImageData:mapPixel, disponível no LÖVE 11.5,
    -- e confirma que os scratches são limpos entre grupos irmãos e tiles.
    local d=Doc.new(270,20,'limpeza via mapPixel')
    Layers.add(d,'irmão')
    local first=Groups.create(d,2,2,'esquerda')
    local second=Groups.create(d,3,3,'direita')
    Groups.setOpacity(d,first,80)
    Groups.setOpacity(d,second,60)
    write(d.layers[2],2,2,1,0,0,0.6)
    write(d.layers[3],3,2,0,0,1,0.4)
    write(d.layers[3],260,3,0,1,0,1)
    local old=love.image.newImageData
    local clears=0
    love.image.newImageData=function(w,h)
      local image=old(w,h)
      function image:mapPixel(fn,x,y,iw,ih)
        clears=clears+1
        for py=y,y+ih-1 do
          for px=x,x+iw-1 do
            self:setPixel(px,py,fn(px,py,self:getPixel(px,py)))
          end
        end
      end
      return image
    end
    local status,result=pcall(Composite.flattenRegion,d,0,0,270,20)
    love.image.newImageData=old
    local baseline=Baseline.flattenRegion(d,0,0,270,20)
    local ok,err=false,'erro ao gerar imagem'
    if status then ok,err=compare(result,baseline,270,20) end
    check('v0.20: limpeza via mapPixel preserva os pixels de irmãos e tiles',ok,
      status and err or tostring(result))
    check('v0.20: caminho mapPixel realmente reutilizou os buffers',clears>=2,
      'limpezas='..clears)
  end

end
