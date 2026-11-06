-- v0.39: falhar ao confirmar um traço não autoriza gravar nem avançar histórico.
-- Exercita um Stroke real, injetando falha no ponto de finalização.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Stroke=require('core.stroke')
  local Project=require('core.project')

  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(32,32)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  local layer=doc.layers[doc.sel]
  local fs=love.filesystem
  local oldWrite,oldInfo,oldMkdir=fs.write,fs.getInfo,fs.createDirectory
  local files,writes,folders={},0,0
  fs.write=function(path,bytes)
    writes=writes+1
    files[path]=bytes
    return true
  end
  fs.getInfo=function(path)
    return files[path] and {type='file'} or nil
  end
  fs.createDirectory=function(path)
    if path~='exports' then return nil,'pasta inesperada' end
    folders=folders+1
    return true
  end

  local function begin(x,fail)
    local s=Stroke.new(doc,layer,doc.history,{
      size=7,alpha=1,hardness=1,color={0.85,0.1,0.1},
      smoothing={mode='exponential',amount=0}
    })
    bridge.stroke=s
    s:push(x,8,1,0)
    if fail then
      s.finish=function()
        error('falha simulada na confirmação do traço')
      end
    end
    return s
  end

  local ok,err=bridge:save(model)
  check('finalização: NPNT de referência gravado',ok==true and err==nil
    and writes==1 and files[bridge.filename]~=nil)
  local original=files[bridge.filename]
  local baseUndo=#doc.history.undo
  local bad=begin(8,true)
  check('finalização: pincel possui pixels antes de confirmação',
    doc.history.stroke~=nil and next(layer.tiles)~=nil)
  model:rename_layer(model.active_layer_id,'Mudança pendente após falha')
  ok,err=bridge:save(model)
  check('finalização: salvar recusa erro do pincel',
    ok==nil and type(err)=='string'
      and err:find('falha simulada',1,true)~=nil)
  check('finalização: NPNT antigo permanece intacto',
    writes==1 and files[bridge.filename]==original)
  check('finalização: cancela traço falho sem criar histórico',
    bad.closed and bridge.stroke==nil and doc.history.stroke==nil
      and next(layer.tiles)==nil and #doc.history.undo==baseUndo)
  check('finalização: propriedades pendentes não viram arquivo após erro',
    layer.name~='Mudança pendente após falha')
  ok,err=bridge:save(model)
  local recovered=files[bridge.filename] and Project.decode(files[bridge.filename])
  check('finalização: novo salvamento normal recupera painel pendente',
    ok==true and err==nil and writes==2 and recovered
      and recovered.layers[1].name=='Mudança pendente após falha')

  local beforePNG=writes
  local beforeFolders=folders
  local failPNG=begin(12,true)
  local path,why=bridge:exportPNG(model)
  check('finalização: exportação PNG recusa pincel não confirmado',
    path==nil and type(why)=='string'
      and why:find('falha simulada',1,true)~=nil)
  check('finalização: erro não cria PNG nem diretório',
    writes==beforePNG and folders==beforeFolders
      and files['exports/obra-atual.png']==nil)
  check('finalização: exportação libera a transação após rollback',
    failPNG.closed and bridge.stroke==nil and doc.history.stroke==nil
      and next(layer.tiles)==nil)
  path,why=bridge:exportPNG(model)
  check('finalização: exportação normal volta a funcionar',
    path=='exports/obra-atual.png' and why==nil
      and files[path]~=nil and writes==beforePNG+1)

  local good=begin(10,false)
  bridge:finish(false)
  local committed=#doc.history.undo
  check('finalização: histórico contém traço de referência',
    good.closed and committed==baseUndo+2
      and doc.history.stroke==nil and next(layer.tiles)~=nil)
  local failUndo=begin(20,true)
  local undone=bridge:historyStep(model,false)
  check('finalização: Ctrl+Z não avança após erro de confirmação',
    undone==false and failUndo.closed and bridge.stroke==nil
      and doc.history.stroke==nil and #doc.history.undo==committed
      and #doc.history.redo==0)
  check('finalização: Ctrl+Z funciona depois de cancelar pincel falho',
    bridge:historyStep(model,false) and #doc.history.undo==committed-1
      and #doc.history.redo==1)

  fs.write,fs.getInfo,fs.createDirectory=oldWrite,oldInfo,oldMkdir
end
