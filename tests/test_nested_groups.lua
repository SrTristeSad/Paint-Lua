-- Regressões de v0.19. Executar pelo mock ImageData de tests/test_core.lua.
return function(check)
  local Doc=require('core.doc')
  local Layers=require('core.layers')
  local Groups=require('core.groups')
  local Mask=require('core.mask')
  local History=require('core.history')
  local Composite=require('core.composite')
  local Project=require('core.project')
  local Render=require('core.render')
  local function near(a,b,tolerance) return math.abs(a-b)<(tolerance or 0.00001) end
  local function pixel(layer,x,y,r,g,b,a)
    local tx,ty=math.floor(x/Doc.TILE),math.floor(y/Doc.TILE)
    local tile,key=Doc.getTile(layer,tx,ty,true)
    tile:setPixel(x%Doc.TILE,y%Doc.TILE,r,g,b,a)
    Doc.markDirty(layer,key)
  end
  local function rgba(d,x,y)
    return {Composite.flattenRegion(d,x,y,1,1):getPixel(0,0)}
  end

  do
    local d=Doc.new(9,9,'Nested')
    Layers.add(d,'Azul')
    pixel(d.layers[1],2,2,0,1,0,1)
    pixel(d.layers[2],2,2,1,0,0,1)
    pixel(d.layers[3],2,2,0,0,1,0.5)
    local outer=Groups.create(d,2,3,'Pasta principal')
    local inner=Groups.create(d,3,3,'Subpasta')
    check('v0.19: subgrupo aponta para grupo pai',d.groups[inner].parentId==outer)
    check('v0.19: folhas mantêm IDs do grupo imediato',
      d.layers[2].groupId==outer and d.layers[3].groupId==inner)
    check('v0.19: hierarquia aninhada é validada',Groups.validate(d))
    local path=Groups.path(d,inner)
    check('v0.19: caminho devolve pai e filho em ordem',#path==2 and path[1]==outer and path[2]==inner)
    local p=rgba(d,2,2)
    check('v0.19: composição aninhada a 100% equivale a flat',
      near(p[1],0.5) and near(p[2],0) and near(p[3],0.5) and near(p[4],1))
    Groups.setOpacity(d,outer,50)
    p=rgba(d,2,2)
    check('v0.19: opacidade coletiva do grupo pai',
      near(p[1],0.25) and near(p[2],0.5) and near(p[3],0.25) and near(p[4],1))
    Groups.setOpacity(d,inner,50)
    p=rgba(d,2,2)
    check('v0.19: opacidades pai e filho são aplicadas separadamente',
      near(p[1],0.375) and near(p[2],0.5) and near(p[3],0.125))
    local outerMask=Groups.addMask(d,outer,1)
    check('v0.19: máscara de grupo inicia revelando',
      outerMask.default==1 and Groups.maskValue(d,outer,2,2)==1)
    check('v0.19: máscara do grupo pai força NPNT4',
      Project.encode(d):sub(1,6)=='NPNT4\n')
    Groups.setMaskPixel(d,outer,2,2,0.5)
    p=rgba(d,2,2)
    check('v0.19: máscara pai afeta resultado dos filhos após composição',
      near(p[1],0.1875) and near(p[2],0.75) and near(p[3],0.0625))
    check('v0.19: máscara não altera pixels do filho',
      near(select(4,Doc.getTile(d.layers[3],0,0,false):getPixel(2,2)),0.5))
    History.undo(d)
    check('v0.19: undo restaura a máscara do grupo',near(Groups.maskValue(d,outer,2,2),1))
    History.redo(d)
    check('v0.19: redo reaplica a máscara do grupo',near(Groups.maskValue(d,outer,2,2),0.5))
    Groups.setMaskInverted(d,outer,true)
    check('v0.19: inverter máscara afeta cobertura',near(Groups.maskValue(d,outer,2,2),0.5)
      and near(Groups.maskValue(d,outer,1,1),0))
    Groups.setMaskEnabled(d,outer,false)
    check('v0.19: desligar máscara equivale a cobertura integral',
      near(Groups.maskValue(d,outer,1,1),1))
    Groups.setMaskEnabled(d,outer,true)
    Groups.setMaskInverted(d,outer,false)
    local childMask=Groups.addMask(d,inner,1)
    Groups.paintMaskRect(d,inner,2,2,1,1,0)
    p=rgba(d,2,2)
    check('v0.19: máscara do subgrupo oculta só os filhos dele',
      near(p[1],0.25) and near(p[2],0.75) and near(p[3],0))
    check('v0.19: máscara filha preserva máscara pai',
      near(Groups.maskValue(d,outer,2,2),0.5) and near(Groups.maskValue(d,inner,2,2),0))
    Groups.setMaskEnabled(d,inner,false)
    p=rgba(d,2,2)
    check('v0.19: máscara desabilitada não reduz subgrupo',near(p[3],0.0625))
    Groups.setMaskEnabled(d,inner,true)
    local encoded=Project.encode(d)
    local copy,err=Project.decode(encoded)
    check('v0.19: NPNT4 roundtrip preserva aninhamento e máscaras',
      copy~=nil and copy.groups[inner].parentId==outer
      and copy.groups[outer].mask and copy.groups[inner].mask,tostring(err))
    check('v0.19: NPNT4 preserva pixels compostos',copy~=nil
      and near(rgba(copy,2,2)[1],rgba(d,2,2)[1],0.005))
    check('v0.19: NPNT4 tem serialização determinística',Project.encode(d)==encoded)
    check('v0.19: NPNT4 truncado é rejeitado',Project.decode(encoded:sub(1,-2))==nil)
    check('v0.19: NPNT5 desconhecido é rejeitado',Project.decode(encoded:gsub('NPNT4\n','NPNT5\n',1))==nil)
    check('v0.19: salvar NPNT4 funciona via filesystem',Project.save(d,'grupo-v019.npnt')==true)
    local disk=Project.load('grupo-v019.npnt')
    check('v0.19: abrir NPNT4 restaura hierarquia',disk~=nil
      and disk.groups[inner].parentId==outer)
    local cache=Composite.newCache(d,{maxTiles=2})
    cache:tile(0,0); cache:tile(0,0)
    check('v0.19: cache reutiliza grupo aninhado',cache:stats().hits==1)
    Groups.setMaskPixel(d,outer,2,2,0.8)
    cache:tile(0,0)
    check('v0.19: editar máscara do grupo invalida cache',cache:stats().recompositions==2)
    Groups.setOpacity(d,inner,20)
    cache:tile(0,0)
    check('v0.19: opacidade do grupo filho invalida cache',cache:stats().recompositions==3)
    Groups.setVisible(d,outer,false)
    check('v0.19: ocultar pai oculta todos os descendentes',near(rgba(d,2,2)[2],1))
    local _,count=Composite.tiles(d)
    check('v0.19: streaming ignora tiles de pai invisível',count==1) -- fundo verde
    Groups.setVisible(d,outer,true)
    History.undo(d)
    check('v0.19: desfazer visibilidade restaura grupo pai oculto',not d.groups[outer].visible)
    History.redo(d)
    check('v0.19: refazer visibilidade reaparece grupo pai',d.groups[outer].visible)
    Groups.removeMask(d,inner)
    check('v0.19: remover máscara de grupo não apaga camadas',
      d.groups[inner].mask==nil and d.layers[3].tiles['0,0']~=nil)
    History.undo(d)
    check('v0.19: undo recupera máscara removida',d.groups[inner].mask~=nil)
    Groups.ungroup(d,outer)
    check('v0.19: desagrupar pai promove subgrupo à raiz',
      d.groups[inner].parentId==nil and d.layers[2].groupId==nil and Groups.validate(d))
    History.undo(d)
    check('v0.19: undo de desagrupar restaura hierarquia',
      d.groups[inner].parentId==outer and Groups.validate(d))
    History.redo(d)
    check('v0.19: redo de desagrupar promove filho novamente',
      d.groups[inner].parentId==nil and Groups.validate(d))
    local oldGraphics=love.graphics
    local created,drawn=0,0
    love.graphics={setScissor=function() end,setBlendMode=function() end,
      setColor=function() end,draw=function() drawn=drawn+1 end,
      newImage=function() created=created+1
        return {replacePixels=function() end,release=function() end} end}
    local ok=pcall(function()
      Render.draw(d,0,0,1,{x=0,y=0,w=9,h=9})
      Render.clearComposited(d)
    end)
    love.graphics=oldGraphics
    check('v0.19: fallback CPU/GPU compõe grupos aninhados',ok and created==1 and drawn==1)
  end

  do
    local d=Doc.new(8,8,'mask rollback')
    local id=Groups.create(d,1,2)
    Groups.addMask(d,id,0)
    local m=d.groups[id].mask
    local tile=Mask.getTile(m,0,0,true)
    local oldSet=tile.setPixel
    local called=0
    tile.setPixel=function(self,...)
      called=called+1
      if called==2 then error('falha simulada') end
      return oldSet(self,...)
    end
    local before=#d.history.undo
    local success=pcall(Groups.paintMaskRect,d,id,0,0,2,1,1)
    check('v0.19: erro de escrita na máscara do grupo aborta edição',not success)
    check('v0.19: rollback restaura pixels e encerra gesto',
      not d.history.stroke and near(Groups.maskValue(d,id,0,0),0))
    check('v0.19: rollback não cria histórico',#d.history.undo==before)
    Groups.paintMaskRect(d,id,0,0,2,1,1)
    check('v0.19: máscara pode ser editada após rollback',near(Groups.maskValue(d,id,0,0),1))
    History.begin(d.history)
    check('v0.19: salvar durante gesto na máscara é proibido',not pcall(Project.encode,d))
    History.rollback(d.history)
    local maskBefore=Groups.maskValue(d,id,0,0)
    local count=#d.history.undo
    check('v0.19: valor inválido não altera máscara nem histórico',
      not pcall(Groups.setMaskPixel,d,id,0,0,0/0)
      and Groups.maskValue(d,id,0,0)==maskBefore and #d.history.undo==count)
    local other=Doc.new(8,8,'v019 test')
    local plain=Groups.create(other,1,2)
    check('v0.19: grupo plano sem máscara mantém NPNT3',
      Project.encode(other):sub(1,6)=='NPNT3\n')
    check('v0.19: NPNT3 antigo ainda pode ser aberto',
      Project.decode(Project.encode(other))~=nil)
    check('v0.19: máscara transforma grupo plano em NPNT4',
      Groups.addMask(other,plain,1) and Project.encode(other):sub(1,6)=='NPNT4\n')
    Groups.removeMask(other,plain)
    check('v0.19: sem recursos novos volta a NPNT3',
      Project.encode(other):sub(1,6)=='NPNT3\n')
  end


  do
    local Stroke=require('core.stroke')
    local d=Doc.new(16,16,'brush group mask')
    pixel(d.layers[2],6,6,1,0,0,1)
    local g=Groups.create(d,2,2)
    Groups.addMask(d,g,0)
    check('v0.19: máscara de grupo inicialmente oculta camada',
      near(rgba(d,6,6)[4],0))
    local opts={size=5,alpha=1,hardness=1,spacing=0.2,
      pressureSize=true,pressureOpacity=true,flow=1,
      smoothing={mode='exponential',amount=0}}
    local s=Stroke.newGroupMask(d,g,d.history,opts)
    s:push(6.5,6.5,1)
    check('v0.19: salvar traço aberto em máscara de grupo é proibido',
      not pcall(Project.encode,d))
    s:finish()
    check('v0.19: pincel revela máscara do grupo sem alterar alfa da camada',
      Groups.maskValue(d,g,6,6)>0.99
      and near(select(4,Doc.getTile(d.layers[2],0,0,false):getPixel(6,6)),1))
    check('v0.19: pintura na máscara revela composição final',
      rgba(d,6,6)[4]>0.99)
    History.undo(d)
    check('v0.19: undo de pincelada oculta máscara novamente',
      near(Groups.maskValue(d,g,6,6),0))
    History.redo(d)
    check('v0.19: redo de pincelada revela máscara',
      Groups.maskValue(d,g,6,6)>0.99)
    local eraser=Stroke.newGroupMask(d,g,d.history,{size=5,alpha=1,
      hardness=1,eraser=true,color={0,0,0}})
    eraser:push(6.5,6.5,1)
    eraser:finish()
    check('v0.19: borracha apaga cobertura da máscara de grupo',
      Groups.maskValue(d,g,6,6)<0.01)
    local undo=#d.history.undo
    local canceled=Stroke.newGroupMask(d,g,d.history,opts)
    canceled:push(6.5,6.5,1)
    canceled:cancel()
    check('v0.19: cancelar pincelada da máscara restaura resultado e histórico',
      Groups.maskValue(d,g,6,6)<0.01 and #d.history.undo==undo)
    check('v0.19: máscara de grupo não aceita tinta úmida',
      not pcall(Stroke.newGroupMask,d,g,d.history,{size=5,alpha=1,
        hardness=1,wetPaint={wet=1,load=1,mix=1,flow=1}}))
    Groups.removeMask(d,g)
    check('v0.19: não pinta grupo cuja máscara foi removida',
      not pcall(Stroke.newGroupMask,d,g,d.history,opts))
  end

  do
    local d=Doc.new(8,8,'invalid nested')
    local parent=Groups.create(d,1,2)
    local child=Groups.create(d,1,1)
    local initial=#d.history.undo
    check('v0.19: criar subgrupo não afeta posições de camadas',
      #d.layers==2 and d.layers[1].groupId==child)
    d.groups[parent].parentId=child
    check('v0.19: ciclos são rejeitados na validação',not pcall(Groups.validate,d))
    check('v0.19: ciclos são rejeitados no salvamento',not pcall(Project.encode,d))
    d.groups[parent].parentId=nil
    check('v0.19: corrigir ciclo restaura estrutura válida',Groups.validate(d))
    d.groups[child].parentId=12345
    check('v0.19: pai inexistente é rejeitado',not pcall(Groups.validate,d))
    d.groups[child].parentId=parent
    check('v0.19: caminho restaurado após ID órfão',Groups.validate(d))
    d.groups[child].mask={default=0/0,enabled=true,inverted=false,tiles={}}
    check('v0.19: máscara de grupo com NaN é rejeitada',not pcall(Project.encode,d))
    d.groups[child].mask=nil
    local before=#d.history.undo
    check('v0.19: criação que divide base do clipping é rejeitada',
      (function()
        Groups.setClipped(d,2,false)
        Groups.ungroup(d,child)
        -- a camada 2 é a base de clipping do topo ainda livre
        Groups.setClipped(d,2,true)
        return not pcall(Groups.create,d,1,1,'separa')
      end)())
    local x=Doc.new(8,8,'v019 test')
    local top=Groups.create(x,2,2)
    for j=2,8 do Groups.create(x,2,2) end
    check('v0.19: oito níveis de grupos são aceitos',Groups.validate(x))
    local num=#x.history.undo
    check('v0.19: nono nível rejeitado sem criar histórico',
      not pcall(Groups.create,x,2,2) and #x.history.undo==num)
    local encoded=Project.encode(x)
    check('v0.19: NPNT4 salva e reabre hierarquia de 8 níveis',
      Project.decode(encoded)~=nil)
    local only=Doc.new(8,8,'v019 test')
    local outer=Groups.create(only,2,2)
    local inner=Groups.create(only,2,2)
    Layers.select(only,2)
    Layers.delete(only)
    check('v0.19: apagar última folha remove ancestrais vazios',
      not only.groups[inner] and not only.groups[outer] and Groups.validate(only))
  end
end
