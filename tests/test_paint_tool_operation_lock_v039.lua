-- v0.39: ferramentas de pintura/amostragem não podem competir com uma
-- seleção arrastada ou ler pixels provisórios de um Fill.newJob externo.
return function(check)
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Doc=require('core.doc')
  local Selection=require('core.selection')
  local Fill=require('core.fill')
  local Job=require('core.job')
  local History=require('core.history')
  local Composite=require('core.composite')

  local model=Model.new()
  model:open_gallery()
  model:open_new_canvas()
  model:create_canvas(32,32)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  local layer=doc.layers[doc.sel]
  local tile,key=Doc.getTile(layer,0,0,true)
  tile:setPixel(8,8,1,0,0,1)
  Doc.markDirty(layer,key)
  local W,H=800,600
  local view={pan_x=0,pan_y=0,rotation=0,zoom=1}
  local prefs={tool_position='left'}
  local rx=62+(W-62-34)/2+(8-doc.w/2)*1.1
  local ry=62+(H-160)/2+(8-doc.h/2)*1.1
  local pointCalls=0
  bridge.point=function()
    pointCalls=pointCalls+1
    return 8,8
  end
  model:set_color(23,45,67)
  local function press()
    return bridge:press(model,view,prefs,1,W,H,rx,ry,100)
  end
  local function stable(undo,redo)
    return #doc.history.undo==undo and #doc.history.redo==redo
  end
  local original=Selection.rect(doc,5,5,10,10)
  doc.selection=original
  local drag={kind='selection_rect',mode='replace',
    startX=5,startY=5,x=10,y=10}
  bridge.selectionDrag=drag
  local undoBefore,redoBefore=#doc.history.undo,#doc.history.redo
  local initialPoints=pointCalls
  model:set_tool('brush')
  check('ferramentas lock: pincel recusa arraste de seleção ativo',
    not press() and bridge.selectionDrag==drag and
    bridge.stroke==nil and doc.history.stroke==nil and
    stable(undoBefore,redoBefore))
  check('ferramentas lock: recusa não chega a calcular coordenadas',
    pointCalls==initialPoints)
  model:set_tool('eraser')
  check('ferramentas lock: borracha também não atravessa o arraste',
    not press() and bridge.stroke==nil and
    bridge.selectionDrag==drag and stable(undoBefore,redoBefore))
  model:set_tool('bucket')
  check('ferramentas lock: balde pela interface não inicia job no arraste',
    not press() and bridge.job==nil and
    doc.history._fillLock==nil and bridge.selectionDrag==drag)
  check('ferramentas lock: API direta do balde respeita arraste',
    not bridge:bucket(model,8,8,100) and
    bridge.job==nil and bridge.selectionDrag==drag)
  model:set_tool('eyedropper')
  check('ferramentas lock: conta-gotas pela interface não muda cor',
    not press() and model.color[1]==23 and model.color[2]==45
    and model.color[3]==67 and bridge.selectionDrag==drag)
  check('ferramentas lock: API direta do conta-gotas respeita arraste',
    not bridge:pick(model,8,8) and model.color[1]==23
    and doc.selection==original and stable(undoBefore,redoBefore))
  check('ferramentas lock: mensagem explica necessidade de finalizar gesto',
    bridge.status:find('operação',1,true)~=nil and
    pointCalls==initialPoints)
  bridge.selectionDrag=nil
  check('ferramentas lock: cancelar arraste não cria histórico',
    doc.selection==original and stable(undoBefore,redoBefore))
  check('ferramentas lock: conta-gotas volta a ler pixel confirmado',
    press() and model.color[1]==255 and model.color[2]==0
    and model.color[3]==0 and stable(undoBefore,redoBefore))
  model:set_color(23,45,67)

  -- O balde é criado pelo motor, não por Bridge.job. Mesmo antes do
  -- primeiro yield, _fillLock deve bloquear TODAS as ferramentas.
  doc.selection=nil
  local job=Fill.newJob(doc,layer,12,12,{0,1,0,1},0,nil,
    {yieldEvery=2})
  check('ferramentas lock: balde externo detém token fora da ponte',
    job and not job.done and doc.history._fillLock~=nil
    and bridge.job==nil)
  local oldFlatten=Composite.flattenRegion
  local samples=0
  Composite.flattenRegion=function(...)
    samples=samples+1
    return oldFlatten(...)
  end
  model:set_tool('eyedropper')
  check('ferramentas lock: conta-gotas recusa Fill antes do primeiro pixel',
    not press() and samples==0 and model.color[1]==23)
  check('ferramentas lock: API de amostragem não compõe sob fill lock',
    not bridge:pick(model,12,12) and samples==0)
  model:set_tool('brush')
  check('ferramentas lock: pincel não cria segunda transação do balde',
    not press() and bridge.stroke==nil and
    doc.history._fillLock~=nil and stable(undoBefore,redoBefore))
  model:set_tool('bucket')
  check('ferramentas lock: segundo balde direto não toma lock externo',
    not bridge:bucket(model,12,12,100) and
    bridge.job==nil and not job.cancelled and
    doc.history._fillLock~=nil)
  local partial=false
  for _=1,400 do
    if job.done then break end
    Job.step(job,0)
    if doc.history.stroke and select(4,layer.tiles['0,0']:getPixel(12,12))>0 then
      partial=true
      break
    end
  end
  check('ferramentas lock: balde externo gerou pixels provisórios',
    partial and not job.done and doc.history.stroke~=nil)
  model:set_tool('eyedropper')
  check('ferramentas lock: amostragem não vê verde provisório do balde',
    not press() and not bridge:pick(model,12,12) and
    samples==0 and model.color[1]==23 and
    model.color[2]==45 and model.color[3]==67)
  check('ferramentas lock: cancelamento reverte pixels e token',
    Job.cancel(job) and doc.history._fillLock==nil
    and doc.history.stroke==nil and
    select(4,layer.tiles['0,0']:getPixel(12,12))==0)
  check('ferramentas lock: pixel provisório cancelado não vira cor',
    not bridge:pick(model,12,12) and
    model.color[1]==23 and model.color[2]==45)
  check('ferramentas lock: pixel vermelho permanente continua legível',
    bridge:pick(model,8,8) and samples==2
    and model.color[1]==255 and model.color[2]==0)
  Composite.flattenRegion=oldFlatten

  -- Uma pincelada externa não usa _fillLock, mas ainda detém History.stroke.
  model:set_color(12,34,56)
  History.begin(doc.history)
  check('ferramentas lock: pincelada externa detém transação',
    doc.history.stroke~=nil and doc.history._fillLock==nil)
  model:set_tool('brush')
  check('ferramentas lock: pincel recusa History.stroke externo',
    not press() and bridge.stroke==nil and
    doc.history.stroke~=nil and stable(undoBefore,redoBefore))
  model:set_tool('eyedropper')
  check('ferramentas lock: conta-gotas direto recusa stroke externo',
    not bridge:pick(model,8,8) and model.color[1]==12)
  check('ferramentas lock: balde direto recusa stroke externo',
    not bridge:bucket(model,12,12,100) and
    bridge.job==nil and doc.history.stroke~=nil)
  check('ferramentas lock: rollback do gesto externo libera ferramentas',
    History.rollback(doc.history) and doc.history.stroke==nil)

  -- Também proteger chamadas diretas enquanto um job da ponte existe.
  local concurrent=Job.new(function()
    coroutine.yield(0.4)
    return true
  end)
  bridge.job=concurrent
  bridge.jobKind='wand'
  check('ferramentas lock: job interno impede balde direto concorrente',
    not bridge:bucket(model,12,12,100) and
    bridge.job==concurrent and not concurrent.done)
  check('ferramentas lock: job interno impede conta-gotas direto',
    not bridge:pick(model,8,8) and model.color[1]==12
    and bridge.job==concurrent)
  bridge:cancelJob()
  check('ferramentas lock: cancelar job mantém histórico original',
    concurrent.cancelled and bridge.job==nil
    and stable(undoBefore,redoBefore))
  bridge.pngPreview={active=true}
  check('ferramentas lock: prévia PNG impede balde direto',
    not bridge:bucket(model,12,12,100) and bridge.job==nil)
  check('ferramentas lock: prévia PNG impede amostragem direta',
    not bridge:pick(model,8,8) and model.color[1]==12)
  bridge.pngPreview=nil
  bridge.transform={active=true}
  check('ferramentas lock: prévia transformação também impede balde',
    not bridge:bucket(model,12,12,100) and bridge.job==nil)
  bridge.transform=nil

  -- Com as operações concluídas, o pincel volta a gravar uma única
  -- ação e o balde pode começar/cancelar sem alterar pixels anteriores.
  model:set_tool('brush')
  -- Um pincel de 1 px centrado na borda do texel pode não carimbar
  -- cobertura alguma; este cenário exige pixels reais para testar undo.
  model:set_brush_size(8)
  model:set_color(0,0,255)
  check('ferramentas lock: pincel volta a começar após liberar locks',
    press() and bridge.stroke~=nil and doc.history.stroke~=nil)
  check('ferramentas lock: soltar cria só um undo de pixels',
    bridge:finish(false)==nil and bridge.stroke==nil and
    doc.history.stroke==nil and #doc.history.undo==undoBefore+1)
  check('ferramentas lock: undo reverte o traço sem apagar base vermelha',
    bridge:historyStep(model,false) and
    select(1,layer.tiles['0,0']:getPixel(8,8))==1)
  check('ferramentas lock: redo restaura pincelada confirmada',
    bridge:historyStep(model,true) and
    #doc.history.undo==undoBefore+1)
  model:set_tool('bucket')
  check('ferramentas lock: balde volta a iniciar sem lock externo',
    bridge:bucket(model,12,12,100) and bridge.job~=nil
    and doc.history._fillLock~=nil)
  local owned=bridge.job
  bridge:cancelJob()
  check('ferramentas lock: cancelar balde interno libera token',
    owned.cancelled and bridge.job==nil and
    doc.history._fillLock==nil and
    #doc.history.undo==undoBefore+1)

  -- Chamadas diretas sem editor/módulo atual nunca pintam obra antiga.
  model:set_color(33,55,77)
  model.screen='gallery'
  check('ferramentas lock: conta-gotas fora do editor não usa obra antiga',
    not bridge:pick(model,8,8) and model.color[1]==33)
  check('ferramentas lock: balde fora do editor não cria job',
    not bridge:bucket(model,12,12,100) and bridge.job==nil)
  model.screen='editor'
  local savedDocument=model.document
  model.document={width=32,height=32}
  check('ferramentas lock: conta-gotas de outro documento é recusado',
    not bridge:pick(model,8,8) and model.color[1]==33)
  check('ferramentas lock: balde de outro documento não altera obra',
    not bridge:bucket(model,12,12,100) and bridge.job==nil
    and bridge.doc==doc)
  model.document=savedDocument
end
