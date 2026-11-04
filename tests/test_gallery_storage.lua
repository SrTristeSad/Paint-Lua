-- Testes puros do índice persistente, segurança e isolamento das obras.
package.path='./?.lua;./?/init.lua;'..package.path
local Gallery=require('src.gallery')
local Store=require('src.gallery_storage')
local Doc=require('core.doc')
local fsFiles={}
local failWrite=nil
love={filesystem={
  read=function(path) return fsFiles[path] end,
  write=function(path,data)
    if failWrite==path then return nil,'escrita interrompida' end
    fsFiles[path]=data
    return true
  end,
  createDirectory=function(path) assert(path=='gallery/works');return true end,
}}
local count=0
local function ok(condition,reason)
  assert(condition,reason)
  count=count+1
end
local g=Gallery.new()
local loaded=Store.load()
ok(loaded:total_artworks()==0,'galeria inicial')
local folder=g:add_folder('Álbuns / Estudo\nTeste')
local a=g:add_artwork(128,80,'Obra 1')
g:enter(folder)
local sub=g:add_folder('2026')
local b=g:add_artwork(40,64,'Obra especial')
local raw=Store.encode(g,1)
local read,gen=Store.decode(raw)
ok(read and gen==1,'roundtrip')
ok(read:get(b).parent==folder,'pai preservado')
ok(read:get(a).width==128,'dimensão preservada')
ok(read:get(folder).name=='Álbuns / Estudo\nTeste','UTF8/newline preservados')
ok(read.current_folder==folder,'pasta atual')
ok(read.next_id==g.next_id,'IDs estáveis')
local altered=raw:gsub('Obra especial','Obra alterada',1)
ok(not Store.decode(altered),'checksum impede edição')
ok(not Store.decode(raw:sub(1,-4)),'truncamento detectado')
ok(not Store.decode('PLG1\n1\n1\n0\n0\nCHECK\n0\n'),'assinatura insuficiente')
ok(Store.save(g),'primeira versão índice')
ok(fsFiles['gallery-index-a.txt']~=nil,'primeiro slot')
g:rename(a,'Pintura final')
ok(Store.save(g),'segunda geração')
ok(fsFiles['gallery-index-b.txt']~=nil,'segundo slot')
local again=Store.load()
ok(again:get(a).name=='Pintura final','última geração')
fsFiles['gallery-index-b.txt']='corrompido'
local recovered,warning=Store.load()
ok(recovered:get(a).name=='Obra 1' and warning,'recuperação de índice')
fsFiles['gallery-index-b.txt']=nil
failWrite='gallery-index-b.txt'
g:rename(a,'Tentativa falha')
local saved=Store.save(g)
ok(not saved,'gravação falhou')
ok(Store.load():get(a).name=='Obra 1','índice anterior intacto')
failWrite=nil
ok(Store.save(g),'gravação após falha')
ok(Store.load():get(a).name=='Tentativa falha','nova geração recuperada')
local invalid=Gallery.new()
invalid:add_folder('pasta')
invalid.records[1].parent=1
ok(not pcall(Store.encode,invalid,1),'ciclo de pasta rejeitado')
invalid.records[1].parent=0
invalid.next_id=1
ok(not pcall(Store.encode,invalid,1),'ID repetido rejeitado')
ok(not pcall(Store.artworkPath,'../secrets'),'traversal rejeitado')
ok(Store.artworkPath(b)=='gallery/works/'..b..'.npnt','caminho imutável por id')
local d1=Doc.new(32,32,'Primeira pintura')
local d2=Doc.new(40,64,'Outra pintura')
ok(Store.saveArtwork(d1,a),'salvar primeira obra')
ok(Store.saveArtwork(d2,b),'salvar segunda obra')
ok(fsFiles[Store.artworkPath(a)]~=fsFiles[Store.artworkPath(b)],'arquivos isolados')
local readA=Store.loadArtwork(a)
local readB=Store.loadArtwork(b)
ok(readA and readA.name=='Primeira pintura','abrir primeira')
ok(readB and readB.w==40 and readB.h==64,'abrir segunda')
d1.name='Primeira atualizada'
ok(Store.saveArtwork(d1,a),'atualizar primeira')
ok(fsFiles[Store.artworkPath(a)..'.bak']~=nil,'backup criado')
fsFiles[Store.artworkPath(a)]='arquivo interrompido'
local old,message=Store.loadArtwork(a)
ok(old and old.name=='Primeira pintura' and message,'recuperar obra do backup')
local noDoc,errorMsg=Store.loadArtwork(999)
ok(not noDoc and errorMsg,'obra inexistente não vira canvas em branco')
failWrite=Store.artworkPath(a)
local wrote=Store.saveArtwork(d1,a)
ok(not wrote,'falha de escrita comunicada')
failWrite=nil
ok(Store.loadArtwork(a).name=='Primeira pintura','falha não destrói último backup')
-- Migração da antiga instalação de arquivo único sem remover o original.
fsFiles['gallery-index-a.txt']=nil
fsFiles['gallery-index-b.txt']=nil
Store.load() -- desbloqueia porque não existe índice corrompido
local legacy=Doc.new(22,23,'Arte anterior')
local oldBytes=require('core.project').encode(legacy)
fsFiles['meu-desenho.npnt']=oldBytes
local imported=Gallery.new()
local did,id=Store.importLegacy(imported)
ok(did and id==1 and imported:get(1).width==22,'importar arquivo antigo')
ok(Store.load():get(1).name=='Arte anterior','índice legado salvo')
ok(fsFiles['meu-desenho.npnt']==oldBytes,'arquivo legado preservado')
ok(not Store.importLegacy(imported),'não duplicar migração')

-- Com os dois índices corrompidos, não gerar ID 1 sobrescrevendo obras antigas.
fsFiles['gallery-index-a.txt']='corrompido'
fsFiles['gallery-index-b.txt']='corrompido'
local empty,warning=Store.load()
ok(empty:total_artworks()==0 and warning and Store.blocked,'modo protegido')
local denied=Store.save(empty)
ok(not denied,'impedir reutilização de IDs enquanto índice está perdido')
local deniedArt=Store.saveArtwork(d1,a)
ok(not deniedArt,'impedir sobrescrita de obra existente')
print('PASS: armazenamento de galeria: '..count..' verificações')
