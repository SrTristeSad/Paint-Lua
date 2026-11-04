-- Paint-Lua v0.27: catalogo persistente e obras NPNT independentes.
-- Formato declarativo, com campos prefixados por tamanho: nunca executa dados.
-- Dois indices alternados permitem recuperar a geracao anterior se uma
-- gravacao for interrompida. Obras usam nomes baseados SOMENTE em IDs.
local Gallery=require('src.gallery')
local Project=require('core.project')
local Preview=require('src.artwork_preview')
local S={blocked=false}
local HEADER='PLG1\n'
local MAX_RECORDS=4096
local MAX_FILE=2*1024*1024
local INDEX={'gallery-index-a.txt','gallery-index-b.txt'}
local ROOT='gallery/works'
local function uint(n,lo,hi)
  return type(n)=='number' and n==math.floor(n) and n>=lo and n<=hi
end
local function checkedId(id)
  assert(uint(id,1,2147483646),'id de obra inválido')
  return id
end
local function adler(body)
  local a,b=1,0
  for i=1,#body do
    a=(a+body:byte(i))%65521
    b=(b+a)%65521
  end
  return tostring(b*65536+a)
end
local function appendBlob(t,s)
  assert(type(s)=='string' and #s<=100 and #s>0,'nome inválido')
  t[#t+1]=#s..'\n';t[#t+1]=s
end
local function validate(g)
  assert(type(g)=='table' and type(g.records)=='table' and
    type(g.order)=='table' and type(g.selected)=='table','catálogo inválido')
  assert(#g.order<=MAX_RECORDS,'catálogo muito grande')
  local seen,maxId={},0
  for _,id in ipairs(g.order) do
    assert(checkedId(id) and not seen[id],'IDs duplicados')
    seen[id]=true;maxId=math.max(maxId,id)
    local entry=g.records[id]
    assert(entry and entry.id==id,'item ausente')
    assert(type(entry.name)=='string' and #entry.name>=1 and #entry.name<=100
      and not entry.name:match('^%s*$'),'nome de item inválido')
    assert(uint(entry.parent,0,2147483646),'pasta pai inválida')
    assert(entry.type=='folder' or entry.type=='artwork','tipo de item inválido')
    if entry.type=='artwork' then
      assert(uint(entry.width,1,16384) and uint(entry.height,1,16384),'tamanho inválido')
    end
  end
  for id in pairs(g.records) do assert(seen[id],'item não ordenado') end
  for _,id in ipairs(g.order) do
    local item=g.records[id]
    local parent=item.parent
    local steps=0
    while parent~=0 do
      assert(seen[parent] and g.records[parent].type=='folder','pasta inexistente')
      assert(parent~=id,'ciclo de pastas')
      parent=g.records[parent].parent
      steps=steps+1
      assert(steps<=MAX_RECORDS,'ciclo de pastas')
    end
  end
  assert(uint(g.next_id,maxId+1,2147483647),'próximo ID inválido')
  assert(uint(g.current_folder,0,2147483646),'pasta atual inválida')
  assert(g.current_folder==0 or (seen[g.current_folder] and
    g.records[g.current_folder].type=='folder'),'pasta atual ausente')
  return true
end
function S.encode(g,generation)
  assert(uint(generation,1,2147483647),'geração inválida')
  validate(g)
  local t={generation..'\n',g.next_id..'\n',g.current_folder..'\n',#g.order..'\n'}
  for _,id in ipairs(g.order) do
    local item=g.records[id]
    t[#t+1]=id..'\n'
    t[#t+1]=item.type=='folder' and 'F\n' or 'A\n'
    t[#t+1]=item.parent..'\n'
    appendBlob(t,item.name)
    if item.type=='artwork' then
      t[#t+1]=item.width..'\n';t[#t+1]=item.height..'\n'
    end
  end
  local payload=table.concat(t)
  assert(#payload<=MAX_FILE,'índice muito grande')
  return HEADER..payload..'CHECK\n'..adler(payload)..'\n'
end
local function parse(data)
  assert(type(data)=='string' and #data<=MAX_FILE+64,'índice demasiado grande')
  local payload,checksum=data:match('^PLG1\n(.*)CHECK\n(%d+)\n$')
  assert(payload and adler(payload)==checksum,'índice corrompido')
  local p=1
  local function line()
    local j=payload:find('\n',p,true)
    assert(j and j-p<=14,'campo ausente')
    local raw=payload:sub(p,j-1)
    p=j+1
    return raw
  end
  local function number(lo,hi)
    local raw=line()
    assert(raw:match('^%d+$'),'número inválido')
    local n=tonumber(raw)
    assert(uint(n,lo,hi),'número fora da faixa')
    return n
  end
  local function blob()
    local len=number(1,100)
    assert(p+len-1<=#payload,'nome truncado')
    local s=payload:sub(p,p+len-1)
    p=p+len
    return s
  end
  local generation=number(1,2147483647)
  local nextId=number(1,2147483647)
  local folder=number(0,2147483646)
  local count=number(0,MAX_RECORDS)
  local g=Gallery.new()
  local maxId=0
  for i=1,count do
    local id=number(1,2147483646)
    local kind=line()
    assert(kind=='F' or kind=='A','tipo inválido')
    local parent=number(0,2147483646)
    local name=blob()
    assert(not g.records[id],'ID duplicado')
    local item={id=id,type=kind=='F' and 'folder' or 'artwork',name=name,parent=parent}
    if kind=='A' then
      item.width=number(1,16384);item.height=number(1,16384)
      item.simulated=false
    end
    g.records[id]=item
    g.order[#g.order+1]=id
    maxId=math.max(maxId,id)
  end
  assert(p==#payload+1,'dados adicionais')
  g.next_id=nextId
  g.current_folder=folder
  validate(g)
  assert(nextId>maxId,'próximo ID colide')
  return g,generation
end
function S.decode(data)
  local ok,g,gen=pcall(parse,data)
  if not ok then return nil,tostring(g) end
  return g,gen
end
local function fs()
  return love and love.filesystem
end
local function read(path)
  local f=fs()
  if not f or not f.read then return nil end
  local ok,data=pcall(f.read,path)
  if not ok or type(data)~='string' then return nil end
  return data
end
local function write(path,bytes)
  local f=fs()
  if not f or not f.write then return nil,'love.filesystem indisponível' end
  local ok,result,err=pcall(f.write,path,bytes)
  if not ok then return nil,tostring(result) end
  if not result then return nil,err or 'erro de escrita' end
  return true
end
local function newest()
  local best,bestGen,bestSlot=nil,0,0
  local corrupt=false
  for i,path in ipairs(INDEX) do
    local raw=read(path)
    if raw then
      local decoded,gen=S.decode(raw)
      if decoded and gen>bestGen then
        best,bestGen,bestSlot=decoded,gen,i
      elseif not decoded then corrupt=true end
    end
  end
  return best,bestGen,bestSlot,corrupt
end
function S.load()
  local g,_,_,corrupt=newest()
  S.blocked = not g and corrupt or false
  if g then return g,corrupt and 'Uma cópia do índice estava corrompida; recuperada a outra' or nil end
  if corrupt then return Gallery.new(),'Índices corrompidos: salvamento BLOQUEADO para proteger obras antigas',false end
  return Gallery.new(),nil,true
end
function S.save(g)
  if S.blocked then return nil,'índice corrompido: salvamento bloqueado' end
  local _,gen,slot=newest()
  local target=slot==1 and 2 or 1
  local ok,bytes=pcall(S.encode,g,gen+1)
  if not ok then return nil,tostring(bytes) end
  return write(INDEX[target],bytes)
end
-- Importação única e não destrutiva do antigo arquivo meu-desenho.npnt.
-- O arquivo antigo é mantido no disco, mesmo se a migração der errado.
function S.importLegacy(g)
  if S.blocked or #g.order>0 then return false end
  local raw=read('meu-desenho.npnt')
  if not raw then return false end
  local doc,err=Project.decode(raw)
  if not doc then return nil,err end
  local name=doc.name
  if type(name)~='string' or #name==0 or #name>100 or name:match('^%s*$') then
    name='Obra antiga recuperada'
  end
  local id=g:add_artwork(doc.w,doc.h,name)
  local ok,savedErr=S.saveArtwork(doc,id)
  if not ok then
    g.records[id]=nil
    table.remove(g.order)
    g.next_id=id
    return nil,savedErr
  end
  local indexed,indexErr=S.save(g)
  if not indexed then return nil,indexErr end
  return true,id
end

-- PNGs de prévia são derivados e podem ser reconstruídos a partir de .npnt.
function S.thumbnailPath(id)
  checkedId(id)
  return string.format('gallery/thumbs/%d.png',id)
end

function S.thumbnailBytes(id)
  local bytes=read(S.thumbnailPath(id))
  if type(bytes)~='string' or #bytes<8 or
    bytes:sub(1,8)~='\137PNG\r\n\26\n' then
    return nil,'prévia não encontrada ou corrompida'
  end
  return bytes
end

function S.saveThumbnail(doc,id)
  if S.blocked then return nil,'galeria protegida contra sobrescrita' end
  checkedId(id)
  local f=fs()
  if not (f and f.createDirectory) then return nil,'filesystem indisponível' end
  local ok,err,detail=pcall(f.createDirectory,'gallery/thumbs')
  if not ok or not err then return nil,tostring(ok and detail or err) end
  local generated,encoded=pcall(function()
    return Preview.render(doc,160,160):encode('png'):getString()
  end)
  if not generated then return nil,'prévia: '..tostring(encoded) end
  return write(S.thumbnailPath(id),encoded)
end

function S.ensureThumbnail(id,force)
  -- force=true permite reconstruir um PNG inválido sem tocar no NPNT original.
  local bytes=not force and S.thumbnailBytes(id)
  if bytes then return bytes end
  local doc,err=S.loadArtwork(id)
  if not doc then return nil,err end
  local ok,why=S.saveThumbnail(doc,id)
  if not ok then return nil,why end
  return S.thumbnailBytes(id)
end

function S.artworkPath(id)
  checkedId(id)
  return string.format('%s/%d.npnt',ROOT,id)
end
local function ensureDirectory()
  local f=fs()
  if not f or not f.createDirectory then return nil,'createDirectory indisponível' end
  local ok,success,err=pcall(f.createDirectory,ROOT)
  if not ok then return nil,tostring(success) end
  if not success then return nil,err or 'não foi possível criar a pasta' end
  return true
end
function S.saveArtwork(doc,id)
  if S.blocked then return nil,'índice corrompido: salvamento bloqueado' end
  local path=S.artworkPath(id)
  local ok,bytes=pcall(Project.encode,doc)
  if not ok then return nil,tostring(bytes) end
  local valid,err=ensureDirectory()
  if not valid then return nil,err end
  -- Em substituições, preservar uma cópia anterior válida antes da escrita.
  -- Não remover .bak: ele é recuperável quando uma gravação falha.
  local previous=read(path)
  if previous then
    local old=Project.decode(previous)
    if old then
      valid,err=write(path..'.bak',previous)
      if not valid then return nil,'backup não gravado: '..tostring(err) end
    end
  end
  return write(path,bytes)
end
function S.loadArtwork(id)
  local path=S.artworkPath(id)
  local bytes=read(path)
  local doc,err
  if bytes then doc,err=Project.decode(bytes) end
  if doc then return doc end
  local backup=read(path..'.bak')
  if backup then
    local restored=Project.decode(backup)
    if restored then return restored,'Documento recuperado da cópia de segurança' end
  end
  return nil,err or 'Arquivo da obra não encontrado; nenhuma obra foi substituída'
end
return S
