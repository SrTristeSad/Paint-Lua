-- Testes v0.26: miniaturas raster reais, cache, reordenação segura e histórico.
return function(check)
  local Doc=require('core.doc')
  local Thumbnail=require('core.thumbnail')
  local Layers=require('core.layers')
  local Groups=require('core.groups')
  local Mask=require('core.mask')
  local History=require('core.history')
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local Project=require('core.project')

  do
    local d=Doc.new(80,40,'Miniatura')
    local layer=d.layers[2]
    local tile=Doc.getTile(layer,0,0,true)
    tile:setPixel(11,13,0.8,0.2,0.1,1)
    Doc.markDirty(layer,'0,0')
    local preview=Thumbnail.render(d,layer,'layer',40,40)
    check('v0.26: miniatura usa ImageData real',preview:getWidth()==40 and preview:getHeight()==40)
    local r,g,b,a=preview:getPixel(5,16)
    check('v0.26: miniatura reproduz cores do tile',a>0.99 and r>g and g>b)
    check('v0.26: preserva proporção retrato/paisagem',
      select(4,preview:getPixel(5,0))==0 and select(4,preview:getPixel(5,35))==0)
    local sig=Thumbnail.signature(d,layer,'layer',40,40)
    check('v0.26: assinatura estável em redraw',
      Thumbnail.same(sig,Thumbnail.signature(d,layer,'layer',40,40)))
    tile:setPixel(11,13,0.1,0.7,0.8,1)
    Doc.markDirty(layer,'0,0')
    check('v0.26: edição de pixels invalida miniatura',
      not Thumbnail.same(sig,Thumbnail.signature(d,layer,'layer',40,40)))
    local replacement=tile:clone()
    layer.tiles['0,0']=replacement
    local sig2=Thumbnail.signature(d,layer,'layer',40,40)
    check('v0.26: troca de ImageData invalida miniatura',
      not Thumbnail.same(Thumbnail.signature(d,layer,'layer',40,40),sig))
    layer.mask=Mask.new(1)
    check('v0.26: miniatura de máscara começa branca',
      select(1,Thumbnail.render(d,layer,'mask',40,40):getPixel(5,16))==1)
    local maskTile,key=Mask.getTile(layer.mask,0,0,true)
    maskTile:setPixel(11,13,0.25,0.25,0.25,1)
    Mask.markDirty(layer.mask,key)
    local maskImg=Thumbnail.render(d,layer,'mask',40,40)
    check('v0.26: miniatura reflete cobertura real da máscara',
      math.abs(select(1,maskImg:getPixel(5,16))-0.25)<0.01)
    local beforeMask=Thumbnail.signature(d,layer,'mask',40,40)
    layer.mask.inverted=true
    check('v0.26: inversão invalida miniatura da máscara',
      not Thumbnail.same(beforeMask,Thumbnail.signature(d,layer,'mask',40,40)))
    check('v0.26: miniatura mostra a cobertura invertida',
      math.abs(select(1,Thumbnail.render(d,layer,'mask',40,40):getPixel(5,16))-0.75)<0.01)
    check('v0.26: renderer não escreve sobre tile original',
      select(1,tile:getPixel(11,13))==0.1)
    check('v0.26: dimensions inválidas são rejeitadas',
      not pcall(Thumbnail.render,d,layer,'layer',129,40))
  end

  do
    local d=Doc.new(64,64,'Ordem')
    d.layers={Doc.newLayer('A'),Doc.newLayer('B'),Doc.newLayer('C')}
    d.sel=2
    local b=d.layers[2]
    local ok=Layers.move(d,1,3)
    check('v0.26: camadas mudam de ordem realmente',
      ok and d.layers[1].name=='B' and d.layers[2].name=='C' and d.layers[3].name=='A')
    check('v0.26: seleção acompanha a identidade da camada',d.layers[d.sel]==b)
    check('v0.26: reordenar cria um único undo',#d.history.undo==1)
    check('v0.26: undo restaura a ordem',History.undo(d)
      and d.layers[1].name=='A' and d.layers[2].name=='B')
    check('v0.26: redo reaplica a ordem',History.redo(d)
      and d.layers[1].name=='B' and d.layers[3].name=='A')
    local n=#d.history.undo
    check('v0.26: no-op sem histórico',not Layers.move(d,2,2) and #d.history.undo==n)
    check('v0.26: limites rejeitados sem mudança',not pcall(Layers.move,d,0,1))
    check('v0.26: persistência NPNT5 mantém ordem',
      (function()local name='miniaturas-move-v026.npnt'
        local yes=Project.save(d,name)
        if not yes then return false end
        local restored=Project.load(name)
        return restored and restored.layers[1].name=='B'
          and restored.layers[3].name=='A' end)())
  end

  do
    local d=Doc.new(64,64,'Grupos')
    d.layers={Doc.newLayer('A'),Doc.newLayer('B'),Doc.newLayer('C')}
    d.sel=2
    local gid=Groups.create(d,1,2,'Par')
    local n=#d.history.undo
    local first=d.layers[1]
    local moved,err=Layers.move(d,1,3)
    check('v0.26: proíbe separar membros do grupo',
      not moved and d.layers[1]==first and #d.history.undo==n)
    check('v0.26: grupo inteiro move entre irmãos',
      Groups.move(d,gid,1) and d.layers[1].name=='C'
      and d.layers[2].name=='A' and d.layers[3].name=='B')
    check('v0.26: grupo movido continua válido',Groups.validate(d))
    check('v0.26: seleção acompanha grupo reordenado',d.layers[d.sel].name=='B')
    check('v0.26: undo repõe grupo inteiro',History.undo(d)
      and d.layers[1].name=='A' and d.layers[3].name=='C')
    check('v0.26: redo do grupo preserva estrutura',History.redo(d)
      and d.layers[1].name=='C' and Groups.validate(d))
    check('v0.26: grupo no topo não ultrapassa limite',not Groups.move(d,gid,1))
  end

  do
    local d=Doc.new(64,64,'Grupos aninhados')
    d.layers={Doc.newLayer('A'),Doc.newLayer('B'),
      Doc.newLayer('C'),Doc.newLayer('D')}
    d.sel=1
    local outer=Groups.create(d,1,2,'Grupo A-B')
    local child=Groups.create(d,1,1,'Filho A')
    local sibling=Groups.create(d,3,4,'Grupo C-D')
    local first=d.layers[1]
    local mask=Groups.addMask(d,outer,1)
    local n=#d.history.undo
    check('v0.26: mover grupo aninhado sobre outro irmão completo',
      Groups.move(d,outer,1) and d.layers[1].name=='C'
      and d.layers[2].name=='D' and d.layers[3]==first)
    check('v0.26: hierarquia e máscara sobrevivem ao swap',
      Groups.validate(d) and d.groups[outer].mask==mask
      and d.groups[child].parentId==outer and d.groups[sibling]~=nil)
    check('v0.26: grupo inteiro produz uma ação no histórico',
      #d.history.undo==n+1)
    check('v0.26: undo do grupo aninhado restaura origem',
      History.undo(d) and d.layers[1]==first and Groups.validate(d))
    check('v0.26: redo do grupo aninhado restaura máscara',
      History.redo(d) and d.layers[3]==first and d.groups[outer].mask~=nil)
  end

  do
    local d=Doc.new(64,64,'Recortes')
    d.layers={Doc.newLayer('A'),Doc.newLayer('B'),Doc.newLayer('C')}
    d.layers[2].clipped=true
    local before=d.layers[2]
    local n=#d.history.undo
    local ok=Layers.move(d,2,3)
    check('v0.26: impede troca da base de recorte',
      not ok and d.layers[2]==before and #d.history.undo==n)
  end

  do
    local model=Model.new()
    model:open_gallery();model:open_new_canvas();model:create_canvas(80,40)
    model:add_layer();model:add_layer()
    local bridge=Bridge.new()
    local d=bridge:sync(model)
    local chosen=model.active_layer_id
    local first=model.layers[1].id
    local top=model.layers[3].id
    check('v0.26: UI arrasta camada por identidade',
      bridge:reorderLayer(model,first,top)
      and model.layers[3].id==first and model.active_layer_id==chosen)
    check('v0.26: bridge preserva objeto raster na reordenação',
      d.layers[3]==bridge.byId[first])
    check('v0.26: reordenação da UI não cria histórico por quadro',
      (function()local n=#d.history.undo;bridge:sync(model);bridge:sync(model)
        return n==#d.history.undo end)())
    check('v0.26: bridge desfaz a ordem e atualiza painel',
      bridge:historyStep(model,false) and model.layers[1].id==first)
    check('v0.26: bridge refaz ordem e atualiza painel',
      bridge:historyStep(model,true) and model.layers[3].id==first)
    check('v0.26: mover o topo além do limite não muda histórico',
      (function()model:select_layer(first);local n=#d.history.undo
        return not bridge:moveLayer(model,1) and #d.history.undo==n end)())
  end
end
