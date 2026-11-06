-- v0.39: Ctrl+O não deve destruir uma operação pendente nem abandonar
-- o job cooperativo de um balde externo ao Bridge.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Doc=require('core.doc')
  local Selection=require('core.selection')
  local Project=require('core.project')
  local PNGImport=require('src.png_import')
  local Fill=require('core.fill')
  local Job=require('core.job')
  local History=require('core.history')
  local GalleryStorage=require('src.gallery_storage')

  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(64,64)
  local bridge=Bridge.new()
  local current=assert(bridge:sync(model))
  local selection=assert(Selection.rect(current,2,2,8,8))
  bridge:applySelection(selection)
  local modelDocument=model.document
  local initialLayer=current.layers[current.sel]
  local saved=Doc.new(24,20,'Reaberta do disco')
  saved.selection=assert(Selection.rect(saved,1,1,3,3))
  local file='meu-desenho.npnt'
  check('reabrir: arquivo NPNT da obra salva foi preparado',
    Project.save(saved,file) and bridge.filename==file)
  local fs=love.filesystem
  local read=fs.read
  local reads=0
  fs.read=function(path)
    reads=reads+1
    return read(path)
  end
  local function unchanged()
    return bridge.doc==current and model.document==modelDocument and
      current.layers[current.sel]==initialLayer and
      bridge.filename==file
  end

  -- Ctrl+O durante um retângulo não descarta arraste nem seleção antiga.
  model:set_tool('selection_rect')
  bridge.point=function() return 12,12 end
  check('reabrir: retângulo começou com seleção anterior',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100))
  local drag=bridge.selectionDrag
  local undoBefore,redoBefore=#current.history.undo,#current.history.redo
  local loaded,err=bridge:load(model)
  check('reabrir: arraste não pode abrir arquivo nem trocar documento',
    not loaded and type(err)=='string' and reads==0 and unchanged())
  check('reabrir: arraste e histórico permanecem intactos',
    bridge.selectionDrag==drag and current.selection==selection and
      #current.history.undo==undoBefore and
      #current.history.redo==redoBefore)
  local previousKeyboard=love.keyboard
  love.keyboard={isDown=function(...)
    for i=1,select('#',...) do
      if select(i,...)=='lctrl' then return true end
    end
    return false
  end}
  check('reabrir: atalho Ctrl+O também preserva arraste',
    bridge:key(model,'o') and bridge.selectionDrag==drag and
      reads==0 and unchanged())
  love.keyboard=previousKeyboard
  check('reabrir: aviso de bloqueio explica a operação pendente',
    bridge.status:find('operação',1,true)~=nil and unchanged())
  drag.x,drag.y=16,16
  check('reabrir: gesto recusado continua confirmável',
    bridge:finishSelection(model) and
    Selection.contains(current.selection,14,14) and
    bridge.selectionDrag==nil and reads==0)

  -- Prévia de PNG e transformação são sessões reversíveis e não podem
  -- desaparecer por um atalho de abertura no meio do gesto.
  local image=love.image.newImageData(2,2)
  image:setPixel(0,0,1,0,0,1)
  local preview=PNGImport.preview(current,image,'imagem.png')
  bridge.pngPreview=preview
  loaded,err=bridge:load(model)
  check('reabrir: prévia PNG impede reload sem perder sessão',
    not loaded and type(err)=='string' and bridge.pngPreview==preview
      and preview.active and reads==0 and unchanged())
  check('reabrir: cancelar prévia PNG libera a operação',
    bridge:cancelPNGImport() and not preview.active and bridge.pngPreview==nil)
  model:set_tool('transform')
  check('reabrir: transformação real inicia sem alterar pixels',
    bridge:startTransform(model) and bridge.transform.active)
  local transform=bridge.transform
  loaded,err=bridge:load(model)
  check('reabrir: transformação pendente bloqueia reabertura',
    not loaded and bridge.transform==transform and transform.active
      and unchanged() and reads==0)
  check('reabrir: cancelar transformação não altera histórico',
    bridge:cancelTransform() and #current.history.undo==undoBefore+1
      and #current.history.redo==redoBefore)

  -- Varinha é um Job da ponte. A leitura do arquivo não deve disparar
  -- o cancelamento silencioso do cálculo.
  model:set_tool('magic_wand')
  check('reabrir: varinha inicia job real',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100)
      and bridge.job~=nil and bridge.jobKind=='wand')
  local wand=bridge.job
  loaded,err=bridge:load(model)
  check('reabrir: varinha segue ativa e documento intacto',
    not loaded and bridge.job==wand and not wand.done
      and unchanged() and reads==0)
  bridge:cancelJob()
  check('reabrir: cancelar varinha libera job',
    wand.cancelled and bridge.job==nil)

  -- O preenchimento externo não consta de bridge.job. Ele precisa ter
  -- prioridade sobre a leitura, antes e depois de pixels provisórios.
  current.selection=nil
  local external=Fill.newJob(current,initialLayer,5,5,
    {0.8,0.2,0.1,1},0,nil,{yieldEvery=2})
  check('reabrir: balde externo adquiriu lock sem bridge.job',
    current.history._fillLock~=nil and bridge.job==nil)
  loaded,err=bridge:load(model)
  check('reabrir: lock externo bloqueia antes dos primeiros pixels',
    not loaded and unchanged() and reads==0 and
      current.history._fillLock~=nil and not external.done)
  local partial=false
  for i=1,250 do
    if external.done then break end
    Job.step(external,0)
    if current.history.stroke and next(initialLayer.tiles) then
      partial=true
      break
    end
  end
  check('reabrir: balde ainda possui pixels provisórios',
    partial and not external.done and current.history._fillLock~=nil)
  loaded,err=bridge:load(model)
  check('reabrir: bloqueio preserva pixels provisórios e job externo',
    not loaded and unchanged() and reads==0 and
      current.history.stroke~=nil and not external.cancelled)
  check('reabrir: cancelar balde reverte pixels e libera lock',
    Job.cancel(external) and current.history._fillLock==nil and
      current.history.stroke==nil and next(initialLayer.tiles)==nil)

  -- Gesto externo ao bridge e um stroke pertencente à ponte.
  History.begin(current.history)
  loaded,err=bridge:load(model)
  check('reabrir: pincelada externa bloqueia sem tocar no histórico',
    not loaded and unchanged() and reads==0 and
      current.history.stroke~=nil)
  check('reabrir: rollback de pincelada externa libera o histórico',
    History.rollback(current.history) and current.history.stroke==nil)
  local calls=0
  bridge.stroke={cancel=function() calls=calls+1 end,
    finish=function() calls=calls+1 end}
  local currentStroke=bridge.stroke
  loaded,err=bridge:load(model)
  check('reabrir: pincelada interna não é finalizada silenciosamente',
    not loaded and bridge.stroke==currentStroke and
      calls==0 and unchanged() and reads==0)
  bridge.stroke=nil

  -- Quando todos os gestos terminam, Ctrl+O continua reabrindo o NPNT.
  local expected=reads
  loaded,err=bridge:load(model)
  check('reabrir: sem operações pendentes o NPNT é lido uma vez',
    loaded==true and err==nil and reads==expected+1)
  local opened=bridge.doc
  check('reabrir: novo documento realmente veio do disco',
    opened~=current and opened.name=='Reaberta do disco'
      and opened.w==24 and opened.h==20)
  check('reabrir: modelo e seleção refletem arquivo reaberto',
    model.document.width==24 and model.document.height==20 and
      Selection.contains(opened.selection,2,2) and
      not Selection.contains(opened.selection,5,5))
  check('reabrir: novo histórico não herda ações do arquivo antigo',
    #opened.history.undo==0 and #opened.history.redo==0 and
      bridge.job==nil and bridge.transform==nil)
  check('reabrir: nome padrão e ausência de ID de galeria preservados',
    bridge.filename==file and bridge.artworkId==nil and
      model.screen=='editor')

  -- Reabrir uma obra da galeria usa seu ID, mas respeita o mesmo
  -- bloqueio do atalho durante seleção pendente.
  local gallery=Doc.new(22,18,'Obra de galeria')
  local galleryId=2579
  local path=GalleryStorage.artworkPath(galleryId)
  love.filesystem.write(path,Project.encode(gallery))
  bridge:setArtwork(galleryId)
  model:set_tool('selection_rect')
  check('reabrir: arraste inicia antes de recarregar obra da galeria',
    bridge:beginSelection(model,nil,nil,1,1024,768,100,100))
  drag=bridge.selectionDrag
  expected=reads
  loaded,err=bridge:load(model)
  check('reabrir: galeria também protege gesto e não lê arquivo',
    not loaded and bridge.selectionDrag==drag and
      bridge.artworkId==galleryId and reads==expected)
  bridge.selectionDrag=nil  -- Escape: cancelamento explícito do gesto
  loaded,err=bridge:load(model)
  check('reabrir: galeria reabre arquivo após cancelar gesto',
    loaded==true and err==nil and reads==expected+1 and
      bridge.doc.name=='Obra de galeria' and bridge.artworkId==galleryId)
  check('reabrir: galeria mantém filename derivado do ID',
    bridge.filename==path and model.document.width==22
      and #bridge.doc.history.undo==0)
  fs.read=read
end
