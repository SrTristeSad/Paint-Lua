-- v0.39: o arquivo NPNT precisa refletir o painel depois de Ctrl+S.
-- Uma sync recusada nunca deve permitir gravar propriedades antigas.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Project=require('core.project')
  local Stroke=require('core.stroke')
  local Fill=require('core.fill')
  local Job=require('core.job')
  local History=require('core.history')
  local GalleryStorage=require('src.gallery_storage')

  local fs=love.filesystem
  local originalWrite=fs.write
  local written,writes={},0
  fs.write=function(path,bytes)
    writes=writes+1
    written[path]=bytes
    return true
  end
  local function editor()
    local model=Model.new()
    model:open_gallery()
    model:open_new_canvas()
    model:create_canvas(32,32)
    local bridge=Bridge.new()
    local doc=assert(bridge:sync(model))
    model:add_layer()
    assert(bridge:sync(model)==doc)
    return model,bridge,doc
  end
  local function decoded(path)
    return written[path] and Project.decode(written[path]) or nil
  end
  local function opts()
    return {size=3,alpha=1,hardness=1,
      color={0.85,0.1,0.1},
      smoothing={mode='exponential',amount=0}}
  end
  local model,bridge,doc=editor()
  local one,two=doc.layers[1],doc.layers[2]
  local firstId,secondId=model.layers[1].id,model.layers[2].id
  local baseline=#doc.history.undo
  model:rename_layer(secondId,'Nome alterado antes de salvar')
  model:set_layer_opacity(secondId,41)
  model:select_layer(firstId)
  check('salvar sync: painel tem edição pendente antes de Ctrl+S',
    two.name~='Nome alterado antes de salvar'
    and two.opacity==100 and doc.sel==2)
  local ok,err=bridge:save(model)
  check('salvar sync: grava NPNT com painel sincronizado',
    ok==true and err==nil and writes==1)
  local stored=decoded(bridge.filename)
  check('salvar sync: arquivo contém nome e opacidade atualizados',
    stored and stored.layers[2].name=='Nome alterado antes de salvar'
      and stored.layers[2].opacity==41)
  check('salvar sync: arquivo conserva camada ativa escolhida',
    stored and stored.sel==1 and doc.sel==1)
  check('salvar sync: alteração estrutural preserva um único undo',
    #doc.history.undo==baseline+1 and #doc.history.redo==0)
  check('salvar sync: salvar novamente sem diferenças não cria histórico',
    bridge:save(model) and writes==2 and
    #doc.history.undo==baseline+1)

  -- Ctrl+S com pincel aberto costumava chamar sync, ignorar nil e
  -- salvar um snapshot de propriedades antigas após terminar o gesto.
  model,bridge,doc=editor()
  one,two=doc.layers[1],doc.layers[2]
  firstId,secondId=model.layers[1].id,model.layers[2].id
  baseline=#doc.history.undo
  local stroke=Stroke.new(doc,two,doc.history,opts())
  bridge.stroke=stroke
  stroke:push(8,8,1,0)
  check('salvar sync: pincel real está aberto com pixel provisório',
    doc.history.stroke~=nil and bridge.stroke==stroke and
    two.tiles['0,0']~=nil and #doc.history.undo==baseline)
  model:rename_layer(secondId,'Camada do pincel salva')
  model:set_layer_opacity(secondId,28)
  model:select_layer(firstId)
  check('salvar sync: sync adia propriedades durante pincel',
    bridge:sync(model)==nil and
    doc.sel==2 and two.opacity==100 and not stroke.closed)
  local prior=writes
  local keyboard=love.keyboard
  love.keyboard={isDown=function(...)
    for i=1,select('#',...) do
      if select(i,...)=='lctrl' then return true end
    end
    return false
  end}
  check('salvar sync: Ctrl+S confirma pincel e grava obra',
    bridge:key(model,'s') and writes==prior+1 and
    bridge.stroke==nil and stroke.closed and
    doc.history.stroke==nil)
  love.keyboard=keyboard
  stored=decoded(bridge.filename)
  check('salvar sync: Ctrl+S inclui pixels e nome do painel',
    stored and stored.layers[2].tiles['0,0']~=nil
    and stored.layers[2].name=='Camada do pincel salva')
  check('salvar sync: Ctrl+S inclui opacidade e camada ativa',
    stored and stored.layers[2].opacity==28 and stored.sel==1)
  check('salvar sync: pincel e edição de camada geram dois undo separados',
    #doc.history.undo==baseline+2 and #doc.history.redo==0)
  check('salvar sync: primeiro undo desfaz nome, mas mantém tinta',
    bridge:historyStep(model,false) and
    doc.sel==2 and two.opacity==100 and
    two.tiles['0,0']~=nil)
  check('salvar sync: segundo undo desfaz pincelada de verdade',
    bridge:historyStep(model,false) and next(two.tiles)==nil)
  check('salvar sync: dois redo restauram composição salva',
    bridge:historyStep(model,true) and
    bridge:historyStep(model,true) and doc.sel==1
    and two.opacity==28 and two.name=='Camada do pincel salva')

  -- Baldes externos e pinceladas externas nunca podem ser gravados
  -- parcialmente, nem mesmo antes do primeiro yield.
  model,bridge,doc=editor()
  two=doc.layers[doc.sel]
  secondId=model.active_layer_id
  baseline=#doc.history.undo
  prior=writes
  local job=Fill.newJob(doc,two,4,4,
    {0.9,0.2,0.1,1},0,nil,{yieldEvery=2})
  model:set_layer_opacity(secondId,52)
  check('salvar sync: balde externo possui lock sem bridge.job',
    doc.history._fillLock~=nil and bridge.job==nil)
  ok,err=bridge:save(model)
  check('salvar sync: bloqueio externo recusa antes de escrever',
    not ok and type(err)=='string' and
    err:find('operação',1,true) and writes==prior)
  check('salvar sync: balde externo preserva edição pendente e undo',
    two.opacity==100 and #doc.history.undo==baseline
    and doc.history._fillLock~=nil and not job.done)
  local partial=false
  for _=1,500 do
    if job.done then break end
    Job.step(job,0)
    if doc.history.stroke and next(two.tiles) then
      partial=true
      break
    end
  end
  check('salvar sync: balde externo produziu pixels provisórios',
    partial and not job.done and doc.history.stroke~=nil)
  ok,err=bridge:save(model)
  check('salvar sync: nem pixels provisórios viram NPNT',
    not ok and writes==prior and next(two.tiles)~=nil
    and doc.history._fillLock~=nil)
  check('salvar sync: rollback do balde libera salvamento',
    Job.cancel(job) and doc.history._fillLock==nil
      and doc.history.stroke==nil and next(two.tiles)==nil)
  check('salvar sync: depois do rollback salva opacidade pendente',
    bridge:save(model) and writes==prior+1 and
    decoded(bridge.filename).layers[2].opacity==52
    and next(two.tiles)==nil)
  check('salvar sync: mudanças só de opacidade não criam undo',
    #doc.history.undo==baseline)

  History.begin(doc.history)
  prior=writes
  ok,err=bridge:save(model)
  check('salvar sync: pincelada externa é recusada sem finalizar',
    not ok and type(err)=='string' and writes==prior
    and doc.history.stroke~=nil and bridge.stroke==nil)
  check('salvar sync: rollback externo permite salvar novamente',
    History.rollback(doc.history) and bridge:save(model)
    and writes==prior+1)

  -- Uma prévia ou seleção pendente não pode ser implicitamente
  -- confirmada nem converter as alterações do modelo em arquivo.
  bridge.selectionDrag={kind='selection_rect',mode='replace',
    startX=4,startY=4,x=8,y=8}
  prior=writes
  ok,err=bridge:save(model)
  check('salvar sync: seleção em arraste não é descartada nem gravada',
    not ok and writes==prior and bridge.selectionDrag~=nil)
  bridge.selectionDrag=nil
  bridge.pngPreview={active=true}
  ok,err=bridge:save(model)
  check('salvar sync: prévia PNG impede gravação',
    not ok and writes==prior and bridge.pngPreview~=nil)
  bridge.pngPreview=nil
  bridge.transform={active=true}
  ok,err=bridge:save(model)
  check('salvar sync: transformação pendente impede gravação',
    not ok and writes==prior and bridge.transform~=nil)
  bridge.transform=nil

  -- Um modelo que pertence a outra obra jamais deve substituir o
  -- documento da ponte durante a tentativa de salvar.
  local previousDoc=bridge.doc
  local oldModelDoc=model.document
  model.document={width=32,height=32}
  prior=writes
  ok,err=bridge:save(model)
  check('salvar sync: modelo de obra diferente é recusado',
    not ok and type(err)=='string' and writes==prior and
    bridge.doc==previousDoc and model.document~=oldModelDoc)
  model.document=oldModelDoc
  model.screen='gallery'
  ok,err=bridge:save(model)
  check('salvar sync: fora do editor não grava obra antiga',
    not ok and writes==prior and bridge.doc==previousDoc)
  model.screen='editor'

  -- O fluxo da galeria usa o mesmo save(model), incluindo a camada
  -- selecionada e propriedades pendentes, sem depender do Ctrl+S.
  local galleryId=19735
  local thumbnail=GalleryStorage.saveThumbnail
  local originalMkdir=fs.createDirectory
  -- test_core usa um filesystem mínimo sem createDirectory. A galeria
  -- precisa criá-la; simular somente a pasta de obras neste cenário.
  fs.createDirectory=function(path)
    if path=='gallery/works' then return true end
    if originalMkdir then return originalMkdir(path) end
    return nil,'pasta inesperada'
  end
  GalleryStorage.saveThumbnail=function() return true end
  bridge:setArtwork(galleryId)
  model:rename_layer(secondId,'Galeria com mudanças')
  model:set_layer_opacity(secondId,67)
  model:select_layer(model.layers[1].id)
  ok,err=bridge:save(model)
  local galleryDoc=decoded(bridge.filename)
  check('salvar sync: galeria grava arquivo NPNT com alterações pendentes',
    ok and err==nil and galleryDoc and
    galleryDoc.layers[2].name=='Galeria com mudanças'
    and galleryDoc.layers[2].opacity==67 and galleryDoc.sel==1)
  check('salvar sync: galeria manteve ID e filename original',
    bridge.artworkId==galleryId and
    bridge.filename==GalleryStorage.artworkPath(galleryId))
  check('salvar sync: API sem modelo continua compatível',
    bridge:save() and written[bridge.filename]~=nil)
  GalleryStorage.saveThumbnail=thumbnail
  fs.createDirectory=originalMkdir
  fs.write=originalWrite
end
