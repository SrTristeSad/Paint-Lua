-- Grupos hierárquicos e clipping, v0.19.
-- Camadas permanecem planas; layer.groupId identifica o grupo imediato.
-- group.parentId define grupos aninhados (profundidade máxima 8).
-- As folhas de cada grupo (incluindo descendentes) devem ser contíguas.
local Hist = require('core.history')
local Blend = require('core.blend')
local Mask = require('core.mask')
local Doc = require('core.doc')
local G = {}
local MAX_DEPTH = 8
local function validInt(n)
  return type(n)=='number' and n==math.floor(n) and n>=1 and n<math.huge
end
local function get(doc,id)
  assert(validInt(id) and doc.groups and doc.groups[id], 'grupo inexistente')
  return doc.groups[id]
end
local function validName(name)
  return type(name)=='string' and #name<=1024*1024
end

-- Caminho do grupo externo ao imediato; rejeita ciclo, IDs órfãos e profundidade excessiva.
function G.path(doc,id)
  local path, seen = {}, {}
  while id do
    assert(validInt(id) and doc.groups and doc.groups[id], 'referência de grupo inválida')
    assert(not seen[id], 'ciclo entre grupos')
    seen[id] = true
    path[#path+1] = id
    assert(#path<=MAX_DEPTH,'aninhamento de grupos excede limite')
    id = doc.groups[id].parentId
  end
  for i=1,math.floor(#path/2) do
    path[i],path[#path-i+1]=path[#path-i+1],path[i]
  end
  return path
end

-- Valida dados serializáveis e impede reentrar num grupo já encerrado.
-- Recortes só usam bases de camadas no MESMO grupo imediato; nunca cruzam
-- a passagem por um subgrupo.
function G.validate(doc)
  assert(type(doc.layers)=='table' and type(doc.groups)=='table', 'estrutura de grupos inválida')
  local used, closed, previous = {}, {}, {}
  local prevImmediate, base = nil,nil
  for _,layer in ipairs(doc.layers) do
    local path=G.path(doc,layer.groupId)
    local common=0
    while common<#previous and common<#path and previous[common+1]==path[common+1] do
      common=common+1
    end
    for j=common+1,#previous do closed[previous[j]]=true end
    for j=common+1,#path do
      assert(not closed[path[j]],'membros de grupo não contíguos')
    end
    for _,id in ipairs(path) do used[id]=true end
    previous=path
    local current=layer.groupId
    if current~=prevImmediate then base=nil end
    assert(type(layer.clipped or false)=='boolean','recorte inválido')
    if layer.clipped then
      assert(base, 'máscara de recorte sem camada base no mesmo grupo')
    else
      base=layer
    end
    prevImmediate=current
  end
  local count=0
  for id,g in pairs(doc.groups) do
    assert(validInt(id) and type(g)=='table' and g.id==id and used[id],
      'grupo vazio ou inválido')
    G.path(doc,id)
    assert(validName(g.name) and type(g.visible)=='boolean','propriedades de grupo inválidas')
    assert(type(g.opacity)=='number' and g.opacity==g.opacity and g.opacity>=0 and g.opacity<=100,
      'opacidade de grupo inválida')
    assert(Blend.modes[g.blend],'mesclagem de grupo inválida')
    if g.mask then
      assert(type(g.mask)=='table' and type(g.mask.tiles)=='table'
        and type(g.mask.enabled)=='boolean' and type(g.mask.inverted)=='boolean'
        and type(g.mask.default)=='number' and g.mask.default==g.mask.default
        and g.mask.default>=0 and g.mask.default<=1,'máscara de grupo inválida')
    end
    count=count+1
  end
  assert(count<=2048,'excesso de grupos')
  return true
end

-- Depois de apagar camadas, remove grupos sem folhas, inclusive ancestrais
-- vazios, e promove a primeira camada de cada novo trecho a base de clipping.
function G.cleanup(doc)
  local used={}
  local last
  for _,layer in ipairs(doc.layers) do
    local id=layer.groupId
    if id~=last then layer.clipped=false end
    last=id
    if id then
      local path=G.path(doc,id)
      for _,parent in ipairs(path) do used[parent]=true end
    end
  end
  for id in pairs(doc.groups or {}) do
    if not used[id] then doc.groups[id]=nil end
  end
end

-- Cria um grupo em torno de camadas irmãs contíguas. Quando essas camadas
-- pertencem a um grupo, o novo grupo é criado como filho desse grupo.
function G.create(doc, first, last, name)
  assert(validInt(first) and validInt(last) and first<=last and last<=#doc.layers,
    'intervalo de grupo inválido')
  name=name or 'Grupo'
  assert(validName(name),'nome de grupo inválido')
  local parent=doc.layers[first].groupId
  for i=first,last do
    assert(doc.layers[i].groupId==parent,
      'grupo deve conter camadas irmãs sem dividir subgrupos')
  end
  assert(not doc.layers[first].clipped,'grupo não pode começar com camada recortada')
  assert(not (doc.layers[last+1] and doc.layers[last+1].groupId==parent
    and doc.layers[last+1].clipped),
    'grupo não pode separar uma máscara de recorte da base')
  if parent then assert(#G.path(doc,parent)<MAX_DEPTH,'limite de profundidade de grupos') end
  Hist.recordStructure(doc)
  local id=doc.nextGroupId or 1
  while doc.groups[id] do id=id+1 end
  assert(id<=2147483647,'limite de IDs de grupo')
  doc.nextGroupId=id+1
  doc.groups[id]={id=id,parentId=parent,name=name,visible=true,opacity=100,blend='normal',mask=nil}
  for i=first,last do doc.layers[i].groupId=id end
  return id
end

-- Desagrupar preserva os grupos filhos, promovendo-os ao pai do grupo removido.
function G.ungroup(doc,id)
  local g=get(doc,id)
  Hist.recordStructure(doc)
  for _,layer in ipairs(doc.layers) do
    if layer.groupId==id then layer.groupId=g.parentId end
  end
  for childId,child in pairs(doc.groups) do
    if childId~=id and child.parentId==id then child.parentId=g.parentId end
  end
  doc.groups[id]=nil
  return true
end

-- Move um grupo inteiro, com todos os seus descendentes, sobre o próximo
-- irmão (camada solta ou outro grupo). Nunca quebra contiguidade ou clipping.
function G.move(doc,id,direction)
  local group=get(doc,id)
  assert(direction==1 or direction==-1,'direção de grupo inválida')
  local function subtreeContains(layer,ancestor)
    if not layer.groupId then return false end
    local path=G.path(doc,layer.groupId)
    for _,part in ipairs(path) do if part==ancestor then return true end end
    return false
  end
  local first,last
  for i,layer in ipairs(doc.layers) do
    if subtreeContains(layer,id) then
      first=first or i
      last=i
    end
  end
  assert(first,'grupo vazio')
  local adjacent=direction==1 and last+1 or first-1
  if not doc.layers[adjacent] then return false,'grupo no limite da pilha' end

  local parentPath=G.path(doc,group.parentId)
  local neighborPath=G.path(doc,doc.layers[adjacent].groupId)
  for i,part in ipairs(parentPath) do
    if neighborPath[i]~=part then return false,'grupos não são irmãos' end
  end
  local nextSibling=neighborPath[#parentPath+1]
  if nextSibling==id then return false,'grupo já está nessa posição' end
  local nfirst,nlast=adjacent,adjacent
  if nextSibling then
    if not doc.groups[nextSibling]
      or doc.groups[nextSibling].parentId~=group.parentId then
      return false,'destino não é irmão do grupo'
    end
    while nfirst>1 and subtreeContains(doc.layers[nfirst-1],nextSibling) do
      nfirst=nfirst-1
    end
    while nlast<#doc.layers and subtreeContains(doc.layers[nlast+1],nextSibling) do
      nlast=nlast+1
    end
  end
  if direction==1 and nfirst~=last+1 or
     direction==-1 and nlast~=first-1 then
    return false,'grupos não são adjacentes'
  end
  local ordered={}
  local function append(a,b)
    for i=a,b do ordered[#ordered+1]=doc.layers[i] end
  end
  if direction==1 then
    append(1,first-1);append(nfirst,nlast);append(first,last)
    append(nlast+1,#doc.layers)
  else
    append(1,nfirst-1);append(first,last);append(nfirst,nlast)
    append(last+1,#doc.layers)
  end
  local ok,err=pcall(G.validate,{layers=ordered,groups=doc.groups})
  if not ok then return false,err end
  local function clipBases(layers)
    local bases,group,base={}
    for _,layer in ipairs(layers) do
      if group~=layer.groupId then group=layer.groupId;base=nil end
      if layer.clipped then bases[layer]=base else base=layer end
    end
    return bases
  end
  local before,after=clipBases(doc.layers),clipBases(ordered)
  for layer,base in pairs(before) do
    if after[layer]~=base then return false,'movimento alteraria a base de recorte' end
  end
  local active=doc.layers[doc.sel]
  Hist.recordStructure(doc)
  doc.layers=ordered
  for i,layer in ipairs(ordered) do if layer==active then doc.sel=i;break end end
  return true
end

local function update(doc,id,field,value)
  local g=get(doc,id)
  if g[field]==value then return false end
  Hist.recordStructure(doc)
  g[field]=value
  return true
end
function G.setVisible(doc,id,v)
  assert(type(v)=='boolean','visibilidade deve ser booleano')
  return update(doc,id,'visible',v)
end
function G.setOpacity(doc,id,v)
  assert(type(v)=='number' and v==v and v>=0 and v<=100,'opacidade inválida')
  return update(doc,id,'opacity',v)
end
function G.setBlend(doc,id,mode)
  assert(Blend.modes[mode],'modo de grupo desconhecido')
  return update(doc,id,'blend',mode)
end
function G.rename(doc,id,name)
  assert(validName(name),'nome inválido')
  return update(doc,id,'name',name)
end
function G.setClipped(doc,i,enabled)
  assert(validInt(i) and doc.layers[i],'índice de camada inválido')
  assert(type(enabled)=='boolean','enabled deve ser booleano')
  local l=doc.layers[i]
  if l.clipped==enabled then return false end
  if enabled then
    local base
    for j=i-1,1,-1 do
      local prev=doc.layers[j]
      if prev.groupId~=l.groupId then break end
      if not prev.clipped then base=prev; break end
    end
    assert(base,'recorte exige camada base no mesmo grupo')
  end
  Hist.recordStructure(doc)
  l.clipped=enabled
  return true
end

-- Máscara não destrutiva aplicada ao resultado COMPOSTO de todos os filhos.
function G.addMask(doc,id,default)
  local g=get(doc,id)
  assert(not g.mask,'grupo já possui máscara')
  local mask=Mask.new(default)
  Hist.recordStructure(doc)
  g.mask=mask
  return mask
end
function G.removeMask(doc,id)
  local g=get(doc,id)
  if not g.mask then return false end
  Hist.recordStructure(doc)
  g.mask=nil
  Hist.prune(doc.history)
  return true
end
function G.setMaskEnabled(doc,id,v)
  assert(type(v)=='boolean','enabled deve ser booleano')
  local m=assert(get(doc,id).mask,'grupo não possui máscara')
  if m.enabled==v then return false end
  Hist.recordStructure(doc)
  m.enabled=v
  return true
end
function G.setMaskInverted(doc,id,v)
  assert(type(v)=='boolean','inverted deve ser booleano')
  local m=assert(get(doc,id).mask,'grupo não possui máscara')
  if m.inverted==v then return false end
  Hist.recordStructure(doc)
  m.inverted=v
  return true
end
function G.maskValue(doc,id,x,y)
  assert(type(x)=='number' and x==math.floor(x) and x>=0 and x<doc.w
    and type(y)=='number' and y==math.floor(y) and y>=0 and y<doc.h,
    'coordenada de máscara inválida')
  return Mask.value(assert(get(doc,id).mask,'grupo não possui máscara'),x,y)
end
function G.paintMaskRect(doc,id,x,y,w,h,value)
  local mask=assert(get(doc,id).mask,'grupo não possui máscara')
  assert(type(x)=='number' and type(y)=='number' and x==math.floor(x)
    and y==math.floor(y) and type(w)=='number' and type(h)=='number'
    and w==math.floor(w) and h==math.floor(h) and x>=0 and y>=0
    and w>0 and h>0 and x+w<=doc.w and y+h<=doc.h,'região de máscara inválida')
  assert(type(value)=='number' and value==value and value>=0 and value<=1
    and value~=math.huge,'cobertura de máscara inválida')
  Hist.begin(doc.history)
  local ok,err=pcall(function()
    for py=y,y+h-1 do
      for px=x,x+w-1 do
        local tx,ty=math.floor(px/Doc.TILE),math.floor(py/Doc.TILE)
        local tile,key=Mask.getTile(mask,tx,ty,false)
        local old=tile and select(1,tile:getPixel(px%Doc.TILE,py%Doc.TILE)) or mask.default
        if old~=value then
          Hist.touchMask(doc.history,mask,key)
          if not tile then tile=Mask.getTile(mask,tx,ty,true) end
          tile:setPixel(px%Doc.TILE,py%Doc.TILE,value,value,value,1)
          Mask.markDirty(mask,key)
        end
      end
    end
  end)
  if not ok then Hist.rollback(doc.history); error(err,0) end
  Hist.commit(doc.history)
  return true
end
function G.setMaskPixel(doc,id,x,y,value)
  return G.paintMaskRect(doc,id,x,y,1,1,value)
end

return G
