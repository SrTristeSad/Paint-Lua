-- v0.39: PNG não pode capturar pixels parciais nem camadas não sincronizadas.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Fill=require('core.fill')
  local Job=require('core.job')
  local History=require('core.history')
  local PNGExport=require('src.png_export')

  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(24,24)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  local layer=doc.layers[doc.sel]
  local fs=love.filesystem
  local savedWrite,savedGetInfo,savedMkdir=fs.write,fs.getInfo,fs.createDirectory
  local written={},directories=0
  fs.getInfo=function(path)
    return written[path] and {type='file'} or nil
  end
  fs.createDirectory=function(path)
    if path~='exports' then return nil,'pasta inesperada' end
    directories=directories+1
    return true
  end
  fs.write=function(path,bytes)
    written[path]=bytes
    return true
  end
  local function count()
    local n=0
    for _ in pairs(written) do n=n+1 end
    return n
  end
  local undoBefore=#doc.history.undo
  local opacityBefore=layer.opacity
  local job=Fill.newJob(doc,layer,5,5,{1,0.2,0.1,1},0,nil,
    {yieldEvery=2})
  model:set_layer_opacity(model.active_layer_id,47)
  check('PNG lock: balde externo não pertence à ponte',
    job and bridge.job==nil and doc.history._fillLock~=nil)
  local direct,err=PNGExport.save(doc,'atual')
  check('PNG lock: API recusa job antes da primeira fatia',
    direct==nil and type(err)=='string' and err:find('operação',1,true)~=nil)
  local out,why=bridge:exportPNG(model)
  check('PNG lock: editor recusa job externo sem tocar no arquivo',
    out==nil and type(why)=='string' and why:find('operação',1,true)~=nil)
  check('PNG lock: sem PNG ou diretório temporário antes da pintura',
    count()==0 and directories==0 and layer.opacity==opacityBefore
      and #doc.history.undo==undoBefore)

  local started=false
  for _=1,500 do
    if job.done then break end
    Job.step(job,0)
    if doc.history.stroke and next(layer.tiles) then
      started=true
      break
    end
  end
  check('PNG lock: balde escreveu pixels que ainda podem sofrer rollback',
    started and not job.done and doc.history._fillLock~=nil)
  direct,err=PNGExport.save(doc,'atual')
  check('PNG lock: API rejeita captura de pixels provisórios',
    direct==nil and err:find('operação',1,true)~=nil)
  out,why=bridge:exportPNG(model)
  check('PNG lock: ponte rejeita captura de pixels provisórios',
    out==nil and why:find('operação',1,true)~=nil)
  check('PNG lock: bloqueio preserva opacidade pendente e histórico',
    count()==0 and directories==0 and layer.opacity==opacityBefore
      and #doc.history.undo==undoBefore and doc.history.stroke~=nil)
  check('PNG lock: cancelar desfaz o balde sem criar ação',
    Job.cancel(job) and doc.history.stroke==nil
      and doc.history._fillLock==nil and next(layer.tiles)==nil
      and #doc.history.undo==undoBefore)

  out,why=bridge:exportPNG(model)
  check('PNG lock: exportação após rollback conclui e grava PNG',
    out=='exports/obra-atual.png' and why==nil
      and type(written[out])=='string' and #written[out]>20)
  check('PNG lock: exportação aplica opacidade pendente sem undo por frame',
    layer.opacity==47 and #doc.history.undo==undoBefore)
  check('PNG lock: nova exportação preserva arquivo anterior',
    PNGExport.save(doc,'atual')=='exports/obra-atual-2.png'
      and count()==2 and written['exports/obra-atual.png']~=nil)

  -- Uma pincelada iniciada diretamente no motor ainda não foi
  -- confirmada: tampouco deve ser exportada.
  History.begin(doc.history)
  check('PNG lock: histórico registra gesto externo ainda aberto',
    doc.history.stroke~=nil and doc.history._fillLock==nil)
  direct,err=PNGExport.save(doc,'atual')
  check('PNG lock: API recusa pincelada externa não confirmada',
    direct==nil and err:find('operação',1,true)~=nil)
  out,why=bridge:exportPNG(model)
  check('PNG lock: ponte recusa pincelada externa não confirmada',
    out==nil and why:find('operação',1,true)~=nil
      and count()==2 and doc.history.stroke~=nil)
  check('PNG lock: cancelamento de gesto externo recupera exportação',
    History.rollback(doc.history) and doc.history.stroke==nil)
  check('PNG lock: operação liberada exporta nova versão',
    bridge:exportPNG(model)=='exports/obra-atual-3.png'
      and count()==3 and #doc.history.undo==undoBefore)

  -- A sincronização deve ser verificada. Estar fora do editor
  -- não pode produzir um PNG da antiga obra por engano.
  model:open_gallery()
  local past=count()
  out,why=bridge:exportPNG(model)
  check('PNG lock: fora do editor não exporta documento anterior',
    out==nil and type(why)=='string' and count()==past)
  check('PNG lock: nada no teste alterou a pintura ou o histórico',
    next(layer.tiles)==nil and #doc.history.undo==undoBefore
      and doc.history.stroke==nil and doc.history._fillLock==nil)
  fs.write,fs.getInfo,fs.createDirectory=savedWrite,savedGetInfo,savedMkdir
end
