-- v0.18: teste integrado com o mock de ImageData de tests/test_core.lua.
return function(check)
  local Doc=require('core.doc')
  local Layers=require('core.layers')
  local Groups=require('core.groups')
  local Composite=require('core.composite')
  local History=require('core.history')
  local Project=require('core.project')
  local Render=require('core.render')
  local Mask=require('core.mask')
  local function near(a,b) return math.abs(a-b)<0.00001 end
  local function pixel(layer,x,y,r,g,b,a)
    local tx,ty=math.floor(x/Doc.TILE),math.floor(y/Doc.TILE)
    local tile,key=Doc.getTile(layer,tx,ty,true)
    tile:setPixel(x%Doc.TILE,y%Doc.TILE,r,g,b,a)
    Doc.markDirty(layer,key)
  end
  local function rgba(d,x,y)
    return {Composite.flattenRegion(d,x,y,1,1):getPixel(0,0)}
  end
  local function n(tbl)
    local num=0
    for _ in pairs(tbl) do num=num+1 end
    return num
  end

  do
    local d=Doc.new(8,8,'v018 clip')
    check('v0.18: projeto legado inicia sem grupos e recortes',n(d.groups)==0
      and not d.layers[1].clipped and d.layers[2].groupId==nil)
    local hist=#d.history.undo
    check('v0.18: recorte sem base é rejeitado sem alterar histórico',
      not pcall(Groups.setClipped,d,1,true) and #d.history.undo==hist)
    pixel(d.layers[1],2,2,1,0,0,0.5)
    pixel(d.layers[2],2,2,0,0,1,1)
    pixel(d.layers[2],3,2,0,0,1,1)
    check('v0.18: sem clipping camada superior aparece fora da base',near(rgba(d,3,2)[4],1))
    Groups.setClipped(d,2,true)
    local p=rgba(d,2,2)
    check('v0.18: clipping usa alfa da base e preserva cor superior',
      near(p[4],0.75) and near(p[1],1/3) and near(p[3],2/3))
    check('v0.18: clipping oculta pintura fora da base',near(rgba(d,3,2)[4],0))
    check('v0.18: clipping preserva pixels RGBA originais',
      near(select(4,Doc.getTile(d.layers[2],0,0,false):getPixel(3,2)),1))
    Layers.setOpacity(d,1,50)
    check('v0.18: alfa da base considera opacidade',near(rgba(d,2,2)[4],0.4375))
    Layers.addMask(d,1,0.5)
    check('v0.18: clipping respeita máscara da camada base',near(rgba(d,2,2)[4],0.234375))
    Layers.setVisible(d,1,false)
    check('v0.18: base invisível oculta camadas recortadas',near(rgba(d,2,2)[4],0))
    Layers.setVisible(d,1,true)
    local h=#d.history.undo
    Groups.setClipped(d,2,false)
    check('v0.18: desligar clipping revela pintura fora da base',near(rgba(d,3,2)[4],1))
    History.undo(d)
    check('v0.18: undo restaura recorte e saída',d.layers[2].clipped and near(rgba(d,3,2)[4],0))
    History.redo(d)
    check('v0.18: redo desliga recorte',not d.layers[2].clipped and near(rgba(d,3,2)[4],1))
    check('v0.18: histórico de clipping registra operação estrutural',#d.history.undo==h+1)
    check('v0.18: sem grupos/recorte e com máscara usa NPNT2',
      Project.encode(d):sub(1,6)=='NPNT2\n')
    Groups.setClipped(d,2,true)
    check('v0.18: NPNT3 é usado quando há clipping',Project.encode(d):sub(1,6)=='NPNT3\n')
    local copy=assert(Project.decode(Project.encode(d)))
    check('v0.18: clipping round-trip e máscara da base continuam válidos',
      copy.layers[2].clipped and copy.layers[1].mask~=nil
      and math.abs(rgba(copy,2,2)[4]-rgba(d,2,2)[4])<0.003)
  end

  do
    local d=Doc.new(12,12,'v018 groups')
    local l3=Layers.add(d,'Topo')
    pixel(d.layers[1],1,1,0,1,0,1) -- fundo verde
    pixel(d.layers[2],1,1,1,0,0,1) -- vermelho
    pixel(d.layers[3],1,1,0,0,1,0.5) -- azul
    local id=Groups.create(d,2,3,'Tintas')
    check('v0.18: grupo criado com identificador e membros contíguos',
      id==1 and d.groups[id].name=='Tintas' and d.layers[2].groupId==id
      and d.layers[3].groupId==id and Groups.validate(d))
    local p=rgba(d,1,1)
    check('v0.18: grupo a 100% conserva cores da pilha',
      near(p[1],0.5) and near(p[2],0) and near(p[3],0.5))
    Groups.setOpacity(d,id,50)
    local q=rgba(d,1,1)
    check('v0.18: opacidade de grupo aplicada após compor filhos isoladamente',
      near(q[1],0.25) and near(q[2],0.5) and near(q[3],0.25) and near(q[4],1))
    Groups.setVisible(d,id,false)
    check('v0.18: ocultar grupo preserva fundo',
      near(rgba(d,1,1)[2],1) and near(rgba(d,1,1)[1],0))
    History.undo(d)
    check('v0.18: undo restaura visibilidade e opacidade do grupo',
      d.groups[id].visible and near(d.groups[id].opacity,50)
      and near(rgba(d,1,1)[1],0.25))
    History.redo(d)
    check('v0.18: redo volta a ocultar o grupo',not d.groups[id].visible)
    Groups.setVisible(d,id,true)
    Groups.setBlend(d,id,'multiply')
    local m=rgba(d,1,1)
    check('v0.18: mesclagem multiply aplicada ao resultado isolado',
      near(m[1],0) and near(m[2],0.5) and near(m[3],0))
    Groups.rename(d,id,'Arte final')
    check('v0.18: renomear grupo é desfazível',d.groups[id].name=='Arte final')
    History.undo(d)
    check('v0.18: undo restaura nome anterior do grupo',d.groups[id].name=='Tintas')
    local before=Project.encode(d)
    check('v0.18: grupos fazem salvar NPNT3',before:sub(1,6)=='NPNT3\n')
    local copy,err=Project.decode(before)
    check('v0.18: grupo round-trip preserva metadados',
      copy and copy.groups[id].name=='Tintas' and copy.groups[id].blend=='multiply'
      and near(copy.groups[id].opacity,50),tostring(err))
    check('v0.18: round-trip preserva composição',
      copy and near(rgba(copy,1,1)[2],m[2]))
    check('v0.18: NPNT3 é determinístico',Project.encode(d)==before)
    check('v0.18: NPNT3 truncado é rejeitado',Project.decode(before:sub(1,#before-3))==nil)
    check('v0.18: assinatura NPNT4 não é aceita',
      Project.decode(before:gsub('NPNT3\n','NPNT4\n',1))==nil)
    local bad=Doc.new(8,8)
    local gid=Groups.create(bad,1,1)
    bad.layers[2].groupId=gid
    check('v0.18: grupo dividido é rejeitado ao salvar',not pcall(Project.encode,bad))
    local bad2=Doc.new(8,8)
    bad2.layers[2].groupId=42
    check('v0.18: referência a grupo ausente é rejeitada',not pcall(Project.encode,bad2))
    local bad3=Doc.new(8,8)
    bad3.layers[1].clipped=true
    check('v0.18: recorte órfão é rejeitado',not pcall(Project.encode,bad3))
    local saved=Project.encode(d)
    local ok=Project.save(d,'grupos-v018.npnt')
    local disk=Project.load('grupos-v018.npnt')
    check('v0.18: save/load via filesystem conserva grupos',ok and disk
      and disk.groups[id] and disk.layers[3].groupId==id)
    check('v0.18: salvar e abrir não altera serialização',Project.encode(disk)==saved)
  end

  do
    local d=Doc.new(8,8,'v018 clipped in group')
    pixel(d.layers[1],2,2,1,0,0,1)
    pixel(d.layers[2],2,2,0,0,1,1)
    pixel(d.layers[2],3,2,0,0,1,1)
    local id=Groups.create(d,1,2,'duas camadas')
    Groups.setClipped(d,2,true)
    Groups.setOpacity(d,id,50)
    check('v0.18: máscara de recorte aplica-se dentro do grupo',
      near(rgba(d,2,2)[4],0.5) and near(rgba(d,3,2)[4],0))
    local c=Composite.newCache(d,{maxTiles=4})
    c:tile(0,0)
    c:tile(0,0)
    check('v0.18: cache mantém tiles com grupos não alterados',
      c:stats().recompositions==1 and c:stats().hits==1)
    Groups.setOpacity(d,id,70)
    c:tile(0,0)
    check('v0.18: cache invalida após mudar opacidade do grupo',
      c:stats().recompositions==2)
    Groups.setClipped(d,2,false)
    c:tile(0,0)
    check('v0.18: cache invalida após desligar clipping',
      c:stats().recompositions==3)
    History.undo(d)
    c:tile(0,0)
    check('v0.18: cache invalida após desfazer clipping',
      c:stats().recompositions==4 and near(rgba(d,3,2)[4],0))
    local dup=Layers.duplicate(d)
    check('v0.18: duplicar camada herda associação e clipping',
      dup.groupId==id and dup.clipped and Groups.validate(d))
    Layers.add(d,'Nova dentro do grupo')
    check('v0.18: adicionar camada herda o grupo da seleção',
      d.layers[d.sel].groupId==id and Groups.validate(d))
    local num=n(d.groups)
    Groups.ungroup(d,id)
    check('v0.18: desagrupar remove associação dos membros',
      n(d.groups)==num-1 and d.layers[1].groupId==nil and Groups.validate(d))
    History.undo(d)
    check('v0.18: undo de desagrupar restaura grupo',
      d.groups[id] and d.layers[1].groupId==id and Groups.validate(d))
    local oldG=love.graphics
    local created,drawn=0,0
    love.graphics={setScissor=function() end,setBlendMode=function() end,
      setColor=function() end,draw=function() drawn=drawn+1 end,
      newImage=function() created=created+1
        return {replacePixels=function() end,release=function() end} end}
    local success=pcall(function()
      Render.draw(d,0,0,1,{x=0,y=0,w=8,h=8})
      Render.clearComposited(d)
    end)
    love.graphics=oldG
    check('v0.18: grupos ativam fallback composto no renderer',
      success and created==1 and drawn==1)
  end

  do
    local d=Doc.new(8,8,'v018 structural protection')
    local id=Groups.create(d,1,2,'G')
    local count=#d.history.undo
    local nested=Groups.create(d,1,1,'interno')
    check('v0.19: grupo aninhado fica dentro do pai',
      d.groups[nested].parentId==id and Groups.validate(d))
    History.undo(d) -- restaura a estrutura inicial, mantém verificações legadas
    check('v0.18: recorte inválido em primeira camada do grupo é rejeitado',
      not pcall(Groups.setClipped,d,1,true))
    check('v0.18: opacidade inválida não altera histórico',
      not pcall(Groups.setOpacity,d,id,0/0) and #d.history.undo==count)
    History.begin(d.history)
    check('v0.18: mudanças estruturais bloqueadas durante um traço',
      not pcall(Groups.setVisible,d,id,false))
    History.rollback(d.history)
    Groups.setVisible(d,id,false)
    check('v0.18: após rollback pode editar grupo',d.groups[id].visible==false)
    Groups.ungroup(d,id)
    check('v0.18: documento desagrupado volta a NPNT1',
      Project.encode(d):sub(1,6)=='NPNT1\n')
    local g=Groups.create(d,2,2,'temporário')
    Layers.select(d,2)
    Layers.delete(d)
    check('v0.18: apagar último membro remove grupo vazio',
      not d.groups[g] and Groups.validate(d))
    History.undo(d)
    check('v0.18: undo recupera camada e grupo removidos',
      d.groups[g] and d.layers[2].groupId==g and Groups.validate(d))
  end
  do
    local d=Doc.new(270,5,'v018 tiles e async')
    local l=d.layers[2]
    pixel(l,1,1,1,0,0,1)
    pixel(l,260,1,0,0,1,1)
    local g=Groups.create(d,2,2,'região')
    Groups.setOpacity(d,g,75)
    local point=rgba(d,260,1)
    check('v0.18: grupo mantém pixel do segundo tile',near(point[3],1) and near(point[4],0.75))
    local nextTile,total=Composite.tiles(d)
    local found={}
    while true do
      local x,y,data=nextTile()
      if not x then break end
      found[#found+1]={x=x,y=y,w=data:getWidth(),h=data:getHeight()}
    end
    check('v0.18: streaming conhece tiles e bordas de grupo',
      total==2 and #found==2 and found[1].x==0 and found[2].x==256
      and found[2].w==14)
    local parts={}
    local count=Composite.stream(d,function(x,y,data)
      parts[#parts+1]={x,y,data:getWidth(),data:getHeight()}
    end)
    check('v0.18: streaming de grupo retorna tiles da região',count==2 and #parts==2)
    local Job=require('core.job')
    local job=Composite.flattenAsync(d)
    local steps=0
    local ok=true
    repeat
      local complete,result=Job.step(job,0)
      steps=steps+1
      if complete then break end
      if steps>20 then ok=false;break end
    until false
    local r=job.result and {job.result:getPixel(260,1)}
    check('v0.18: composição assíncrona com grupo equivale à direta',
      ok and steps>1 and r and near(r[3],point[3]) and near(r[4],point[4]))
    Groups.setVisible(d,g,false)
    local nextHidden,numHidden=Composite.tiles(d)
    check('v0.18: tiles de grupo invisível não são entregues',
      numHidden==0 and nextHidden()==nil and near(rgba(d,260,1)[4],0))
  end

  do
    local d=Doc.new(8,8,'v018 invariantes clipping')
    local t=Layers.add(d,'terceira')
    Groups.setClipped(d,2,true)
    Groups.setClipped(d,3,true)
    local count=#d.history.undo
    check('v0.18: no-op de clipping não cria histórico',
      Groups.setClipped(d,3,true)==false and #d.history.undo==count)
    check('v0.18: grupo não separa sequência de clipping da base',
      not pcall(Groups.create,d,1,1,'quebra')
      and not pcall(Groups.create,d,2,3,'quebra')
      and #d.history.undo==count)
    local g=Groups.create(d,1,3,'recorte')
    check('v0.18: clipping com vários membros pode entrar no mesmo grupo',
      Groups.validate(d) and d.layers[3].clipped and d.layers[2].clipped)
    Layers.select(d,1)
    Layers.delete(d)
    check('v0.18: apagar base promove primeira recortada a base',
      d.layers[1].groupId==g and not d.layers[1].clipped and d.layers[2].clipped
      and Groups.validate(d))
    History.undo(d)
    check('v0.18: undo restaura base removida e seu clipping',
      #d.layers==3 and not d.layers[1].clipped and d.layers[2].clipped
      and d.layers[3].clipped and Groups.validate(d))
  end

end
