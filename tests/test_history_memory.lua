-- v0.14: histórico limitado, reversão por transferência de ImageData e composição.
-- Importado após o mock de ImageData do test_core.lua.
local Doc = require('core.doc')
local H = require('core.history')
local Layers = require('core.layers')
local Composite = require('core.composite')
local Job = require('core.job')
local T = Doc.TILE

return function(check)
  local function edit(doc, key, value)
    local layer = doc.layers[2]
    H.begin(doc.history)
    H.touch(doc.history, layer, key)
    local tile = layer.tiles[key]
    if not tile then
      tile = love.image.newImageData(T, T)
      layer.tiles[key] = tile
    end
    tile:setPixel(0, 0, value, 0, 0, 1)
    layer.dirty[key] = true
    H.commit(doc.history)
  end
  local nominal = T * T * 4
  do
    local d = Doc.new(768, 300, 'v014 limites padrão')
    local h = d.history
    check('v0.14: histórico tem limite padrão de ações', h.maxEntries == 100)
    check('v0.14: histórico tem limite padrão de bytes equivalentes RGBA8', h.maxBytes == 128*1024*1024)
    local stats = H.stats(h)
    check('v0.14: histórico vazio reporta zero snapshots', stats.totalBytes == 0 and stats.undoEntries == 0)
    edit(d, '0,0', 0.1)
    check('v0.14: tile novo não ocupa snapshot de antes', H.stats(h).undoBytes == 0)
    edit(d, '0,0', 0.2)
    check('v0.14: modificação de tile conta uma cópia nominal', H.stats(h).undoBytes == nominal)
    edit(d, '0,0', 0.3)
    check('v0.14: duas edições de tile contabilizam dois snapshots', H.stats(h).undoBytes == nominal*2)
    H.undo(d)
    local s=H.stats(h)
    check('v0.14: undo transfere o snapshot ao redo sem duplicar memória nominal',
      s.undoBytes == nominal and s.redoBytes == nominal and s.totalBytes == nominal*2)
    H.redo(d)
    check('v0.14: redo transfere o tile de volta ao undo', H.stats(h).undoBytes == nominal*2)
    local tile = d.layers[2].tiles['0,0']
    check('v0.14: pixels sobrevivem a undo/redo', select(1,tile:getPixel(0,0)) == 0.3)
  end

  do
    local d=Doc.new(256,256,'v014 sem cópias em undo')
    local tile=Doc.getTile(d.layers[2],0,0,true)
    tile:setPixel(0,0,0.1,0,0,1)
    local cloneCount=0
    local original=tile.clone
    function tile:clone()
      cloneCount=cloneCount+1
      return original(self)
    end
    edit(d,'0,0',0.5)
    check('v0.14: início do gesto ainda clona estado antes de pintar', cloneCount==1)
    local before=d.history.undo[1][1].before
    local after=d.layers[2].tiles['0,0']
    H.undo(d)
    check('v0.14: undo não chama clone adicional',cloneCount==1)
    check('v0.14: undo aplica a mesma referência registrada',d.layers[2].tiles['0,0']==before)
    check('v0.14: redo retém referência nova sem clone',d.history.redo[1][1].before==after)
    H.redo(d)
    check('v0.14: redo restaura o mesmo ImageData pós-gesto',d.layers[2].tiles['0,0']==after)
    H.undo(d)
    edit(d,'0,0',0.9)
    check('v0.14: novo gesto após desfazer não corrompe o estado original',
      d.history.redo[1] == nil and select(1,d.history.undo[#d.history.undo][1].before:getPixel(0,0))==0.1)
    H.undo(d)
    check('v0.14: gesto divergente desfaz sem alterar estado anterior',
      select(1,d.layers[2].tiles['0,0']:getPixel(0,0)) == 0.1)
  end

  do
    local d=Doc.new(768,256,'v014 limite ações')
    local h=d.history
    H.setLimits(h,{maxEntries=2})
    edit(d,'0,0',0.1);edit(d,'1,0',0.2);edit(d,'2,0',0.3)
    check('v0.14: remove a ação mais antiga após exceder limite',#h.undo==2)
    check('v0.14: preserva primeiro estado descartado no desenho',
      select(1,d.layers[2].tiles['0,0']:getPixel(0,0))==0.1)
    H.undo(d);H.undo(d)
    check('v0.14: ações remanescentes desfazem normalmente',
      d.layers[2].tiles['1,0']==nil and d.layers[2].tiles['2,0']==nil)
    check('v0.14: ação removida não está disponível', H.undo(d)==false)
    H.redo(d);H.redo(d)
    check('v0.14: redo restaura as ações remanescentes',
      d.layers[2].tiles['1,0'] ~= nil and d.layers[2].tiles['2,0'] ~= nil)
    edit(d,'1,0',0.8)
    check('v0.14: nova edição elimina redo e mantém orçamento',
      #h.redo==0 and #h.undo==2)
  end

  do
    local d=Doc.new(768,256,'v014 limite bytes')
    local h=d.history
    H.setLimits(h,{maxBytes=nominal})
    edit(d,'0,0',0.1);edit(d,'0,0',0.2);edit(d,'0,0',0.3)
    check('v0.14: orçamento de 1 tile remove snapshots antigos',
      #h.undo==1 and H.stats(h).undoBytes==nominal)
    check('v0.14: ação mais recente é desfazível mesmo após truncamento',
      H.undo(d) and select(1,d.layers[2].tiles['0,0']:getPixel(0,0))==0.2)
    H.redo(d)
    check('v0.14: refazer respeita o orçamento de memória',
      #h.undo==1 and H.stats(h).undoBytes==nominal)
    H.setLimits(h,{maxBytes=0})
    check('v0.14: último gesto é preservado mesmo maior que orçamento zero',
      #h.undo==1 and H.stats(h).undoBytes > h.maxBytes)
    check('v0.14: reduzir limites após edições poda imediatamente',
      H.setLimits(h,{maxEntries=1}).undoEntries==1)
  end

  do
    local d=Doc.new(256,256,'v014 estrutura')
    local layer=d.layers[2]
    local t=Doc.getTile(layer,0,0,true)
    t:setPixel(3,3,0.2,0.3,0.4,1)
    Layers.delete(d)
    local s=H.stats(d.history)
    check('v0.14: snapshot estrutural estima tiles da camada removida',
      s.undoBytes >= nominal and s.undoEntries == 1)
    H.undo(d)
    check('v0.14: restaurar camada removida preserva seus pixels',
      d.layers[2]==layer and select(1,layer.tiles['0,0']:getPixel(3,3))==0.2)
    H.redo(d)
    check('v0.14: refazer remoção mantém documento coerente',#d.layers==1)
  end
  do
    local d=Doc.new(256,256,'v014 estrutura sem clone')
    local t=Doc.getTile(d.layers[2],0,0,true)
    t:setPixel(0,0,0.1,0,0,1)
    Layers.setVisible(d,2,false)
    check('v0.14: mudar visibilidade não cobra memória de tiles ainda vivos',
      H.stats(d.history).undoBytes == 0)
    H.undo(d)
    check('v0.14: reversão estrutural conserva imagem existente',
      d.layers[2].tiles['0,0'] == t)
  end

  do
    local d=Doc.new(256,256,'v014 parâmetros')
    local h=d.history
    for _,bad in ipairs({{maxEntries=0},{maxEntries=1.5},{maxEntries=0/0},
      {maxBytes=-1},{maxBytes=math.huge},{maxBytes=0/0}}) do
      check('v0.14: limite inválido rejeitado '..tostring(bad.maxEntries or bad.maxBytes),
        not pcall(H.setLimits,h,bad))
    end
    check('v0.14: opções devem ser tabela',not pcall(H.setLimits,h,nil))
    check('v0.14: entradas inválidas preservam limites vigentes',
      h.maxEntries==100 and h.maxBytes==128*1024*1024)
    H.begin(h)
    check('v0.14: limites não mudam durante gesto aberto',not pcall(H.setLimits,h,{maxEntries=2}))
    check('v0.14: estrutura e undo bloqueados durante gesto aberto',
      not pcall(Layers.add,d,'não') and not pcall(H.undo,d))
    h.stroke=nil
    h._fillLock={}
    check('v0.14: configuração bloqueada durante balde cooperativo',
      not pcall(H.setLimits,h,{maxEntries=1}))
    h._fillLock=nil
  end

  do
    local d=Doc.new(4096,4096,'v014 scans compositor')
    local l=d.layers[2]
    for i=0,12 do
      local tx=i % 9
      local ty=math.floor(i / 9)
      local tile=Doc.getTile(l,tx,ty,true)
      tile:setPixel(0,0,(i+1)/20,0,0,1)
    end
    -- Usa buffer de saída esparso para testar viewport grande sem alocar
    -- milhões de pequenas tabelas do mock ImageData.
    local originalImage=love.image.newImageData
    love.image.newImageData=function(w,h)
      local data={}
      return {getWidth=function() return w end, getHeight=function() return h end,
        getPixel=function(_,x,y)
          local c=data[x..','..y]
          if c then return c[1],c[2],c[3],c[4] end
          return 0,0,0,0
        end,
        setPixel=function(_,x,y,r,g,b,a) data[x..','..y]={r,g,b,a} end}
    end
    local origParse=Doc.parseKey
    local calls=0
    Doc.parseKey=function(key) calls=calls+1; return origParse(key) end
    local x,y,w,h=0,0,9*T,9*T
    local success, img = pcall(Composite.flattenRegion,d,x,y,w,h)
    local syncCount=calls
    local valid=success and select(1,img:getPixel(0,0))==1/20
    calls=0
    -- Evite uma composição integral de 4096²: apenas testa o job regional
    -- com o mesmo percurso via wrapper temporário, inclusive progresso.
    local smaller=Doc.new(9*T,9*T,'v014 async')
    smaller.layers[2]=l
    local async=Composite.flattenAsync(smaller)
    while not async.done do Job.step(async,0) end
    local asyncCount=calls
    local identical=valid and select(1,async.result:getPixel(0,0))==select(1,img:getPixel(0,0))
    Doc.parseKey=origParse
    love.image.newImageData=originalImage
    check('v0.14: composição regional síncrona percorre tiles uma vez',syncCount==13,'visitas='..syncCount)
    check('v0.14: composição assíncrona preserva progresso de duas passagens',asyncCount==26,'visitas='..asyncCount)
    check('v0.14: composição síncrona e assíncrona preservam pixels',identical)
  end
end
