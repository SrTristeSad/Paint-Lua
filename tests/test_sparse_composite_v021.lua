-- v0.21: árvore parcial por tile. Referência integral v0.20 preservada.
return function(check)
  local Doc=require('core.doc')
  local Layers=require('core.layers')
  local Groups=require('core.groups')
  local Hist=require('core.history')
  local New=require('core.composite')
  local Old=require('tests.reference_composite_v020')
  local Job=require('core.job')
  local function pixel(layer,x,y,r,g,b,a)
    local tx,ty=math.floor(x/Doc.TILE),math.floor(y/Doc.TILE)
    local tile,key=Doc.getTile(layer,tx,ty,true)
    tile:setPixel(x%Doc.TILE,y%Doc.TILE,r,g,b,a)
    Doc.markDirty(layer,key)
  end
  local function equal(a,b,w,h)
    for y=0,h-1 do for x=0,w-1 do
      local ar,ag,ab,aa=a:getPixel(x,y)
      local br,bg,bb,ba=b:getPixel(x,y)
      if ar~=br or ag~=bg or ab~=bb or aa~=ba then
        return false,string.format('divergência (%d,%d)',x,y)
      end
    end end
    return true
  end
  local function region(d,x,y,w,h)
    return equal(New.flattenRegion(d,x,y,w,h),Old.flattenRegion(d,x,y,w,h),w,h)
  end
  local function parity(d,label,rect)
    local r=rect or {0,0,d.w,d.h}
    local ok,err=region(d,r[1],r[2],r[3],r[4])
    check('v0.21: '..label,ok,err)
  end

  do
    local d=Doc.new(272,262,'grupos + recorte em tiles esparsos')
    for i=3,9 do Layers.add(d,'L'..i) end
    local positions={{0,0},{254,255},{255,255},{256,255},{259,256},
      {271,261},{270,1},{2,260},{260,259}}
    for i=1,9 do
      local p=positions[i]
      pixel(d.layers[i],p[1],p[2],(i%3)/3,(i%5)/5,(i%7)/7,0.2+i*0.07)
    end
    local outer=Groups.create(d,2,8,'externo')
    local inner=Groups.create(d,4,6,'interno')
    local sibling=Groups.create(d,7,8,'irmão')
    Groups.setBlend(d,outer,'multiply')
    Groups.setBlend(d,inner,'screen')
    Groups.setBlend(d,sibling,'overlay')
    Groups.setOpacity(d,outer,67)
    Groups.setOpacity(d,inner,88)
    Groups.setOpacity(d,sibling,92)
    Groups.setClipped(d,5,true)
    Groups.addMask(d,outer,0)
    Groups.setMaskPixel(d,outer,256,255,1)
    Groups.setMaskPixel(d,outer,259,256,0.37)
    Layers.addMask(d,4,1)
    Layers.setMaskPixel(d,4,255,255,0.8)
    parity(d,'pixel a pixel na área inteira com máscaras de grupo esparsas')
    parity(d,'recorte regional atravessa quatro tiles',{251,252,13,8})
    parity(d,'recorte na borda do documento',{263,257,9,5})
    Groups.setMaskInverted(d,outer,true)
    parity(d,'inversão de máscara mantém paridade')
    Groups.setVisible(d,inner,false)
    parity(d,'subgrupo oculto não altera outras camadas')
    Groups.setVisible(d,inner,true)
    parity(d,'subgrupo reativado recompõe os mesmos pixels')
    Groups.setOpacity(d,sibling,0)
    parity(d,'grupo irmão com opacidade zero é excluído')
    Groups.setOpacity(d,sibling,92)
    parity(d,'opacidade restaurada')
    Hist.undo(d)
    parity(d,'undo de propriedade estrutural')
    Hist.redo(d)
    parity(d,'redo de propriedade estrutural')
    local c=New.newCache(d,{maxTiles=8})
    local a=c:region(251,252,13,8)
    local b=Old.flattenRegion(d,251,252,13,8)
    check('v0.21: cache regional mantém os quatro canais',equal(a,b,13,8))
    local output={}
    local count=New.stream(d,function(x,y,data)
      output[#output+1]={x=x,y=y,data=data}
    end)
    local matches=count==#output and count>0
    for _,s in ipairs(output) do
      local ref=Old.flattenRegion(d,s.x,s.y,s.data:getWidth(),s.data:getHeight())
      if not equal(s.data,ref,s.data:getWidth(),s.data:getHeight()) then
        matches=false
      end
    end
    check('v0.21: streaming de tiles mantém pixels e coordenadas',matches)
    local job=New.flattenAsync(d)
    local countSteps=0
    repeat
      local done=Job.step(job,0)
      countSteps=countSteps+1
      if done then break end
      if countSteps>200 then break end
    until false
    check('v0.21: composição assíncrona termina e progride',job.done and job.progress==1 and countSteps<=200)
    check('v0.21: composição assíncrona mantém pixels v0.20',
      job.done and equal(job.result,Old.flatten(d),d.w,d.h))
  end

  do
    -- Nenhum tile de uma camada recortada sem alfa da base pode contribuir.
    local d=Doc.new(270,8,'base de clipping ausente')
    local base=d.layers[2]
    local clip=Layers.add(d,'recorte')
    Groups.setClipped(d,3,true)
    pixel(clip,260,3,1,0,0,1)
    local g=Groups.create(d,2,3,'recorte isolado')
    parity(d,'camada recortada sem alfa base não contribui',{256,0,14,8})
    pixel(base,260,3,0,0,1,0.4)
    parity(d,'camada base criada volta a permitir clipping',{256,0,14,8})
    Layers.addMask(d,2,0)
    parity(d,'máscara zero da base bloqueia recorte',{256,0,14,8})
    Layers.setMaskPixel(d,2,260,3,1)
    parity(d,'revelação parcial da base permite recorte',{256,0,14,8})
    Groups.addMask(d,g,0)
    parity(d,'máscara uniforme zero exclui grupo',{256,0,14,8})
    Groups.setMaskPixel(d,g,260,3,0.5)
    parity(d,'máscara de grupo com tile pintado revela',{256,0,14,8})
  end

  do
    -- A v0.20 consultava TODAS as folhas por tile ativo, após indexar
    -- seus tiles. A v0.21 consulta somente folhas presentes naquele bloco.
    local d=Doc.new(1024,4,'muitas camadas esparsas')
    for i=3,10 do Layers.add(d,'camada '..i) end
    for i=2,10 do
      pixel(d.layers[i],(i-2)%4*256+(i%3),0,i*17/255,0,(255-i*17)/255,178/255)
    end
    local g=Groups.create(d,2,10,'grupo maior')
    local g2=Groups.create(d,5,7,'subgrupo')
    local readings=0
    for _,layer in ipairs(d.layers) do
      setmetatable(layer.tiles,{__index=function() readings=readings+1 end})
    end
    local old=Old.flattenRegion(d,0,0,1024,1)
    local oldReads=readings
    readings=0
    local new=New.flattenRegion(d,0,0,1024,1)
    local newReads=readings
    check('v0.21: imagem esparsa mantém equivalência em quatro tiles',equal(new,old,1024,1))
    check('v0.21: índice evita consultas de folhas ausentes em cada bloco',
      newReads<oldReads, string.format('acessos ausentes: v0.20=%d v0.21=%d',oldReads,newReads))
    check('v0.21: caminho agrupado realmente percorre menos chaves',
      newReads<=oldReads*0.8, string.format('acessos ausentes: v0.20=%d v0.21=%d',oldReads,newReads))
    -- Nenhuma mudança nos formatos do arquivo nem nas APIs antigas.
    local Project=require('core.project')
    local encoded=Project.encode(d)
    local loaded=Project.decode(encoded)
    check('v0.21: arquivo existente reabre mantendo grupos',loaded~=nil and #loaded.layers==#d.layers)
    check('v0.21: saída após reabrir continua equivalente à v0.20',loaded and
      equal(New.flattenRegion(loaded,0,0,1024,1),New.flattenRegion(d,0,0,1024,1),1024,1))
  end
end
