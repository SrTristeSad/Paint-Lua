-- Testes v0.28 de miniaturas e PNG (mocks do LÖVE fornecidos por test_core).
return function(check)
  local Doc=require('core.doc')
  local Mask=require('core.mask')
  local Preview=require('src.artwork_preview')
  local Export=require('src.png_export')
  local Store=require('src.gallery_storage')
  local f=love.filesystem
  local prevDir,prevGet=f.createDirectory,f.getInfo
  local seen={}
  f.createDirectory=function(path) seen[path]=true;return true end
  f.getInfo=function(path)
    local contents=f.read(path)
    return contents and {size=#contents} or nil
  end
  local d=Doc.new(16,16,'Prévia de teste')
  local l=d.layers[2]
  local tile,key=Doc.getTile(l,0,0,true)
  tile:setPixel(8,8,0.8,0.1,0.2,1)
  Doc.markDirty(l,key)
  local thumb=Preview.render(d,16,16)
  check('v0.28: miniatura respeita dimensões',thumb:getWidth()==16 and thumb:getHeight()==16)
  local r,g,b,a=thumb:getPixel(8,8)
  check('v0.28: prévia usa pixels compostos',a==1 and r>g and r>b)
  check('v0.28: fundo transparente',select(4,thumb:getPixel(0,0))==0)
  l.visible=false
  local hidden=Preview.render(d,16,16)
  check('v0.28: invisibilidade da camada aplicada',select(4,hidden:getPixel(8,8))==0)
  l.visible=true
  l.mask=Mask.new(0)
  local covered=Preview.render(d,16,16)
  check('v0.28: máscara de camada aplicada',select(4,covered:getPixel(8,8))==0)
  l.mask=nil
  local wide=Preview.render(d,12,12)
  check('v0.28: tamanho de miniatura é limitado',wide:getWidth()==12 and wide:getHeight()==12)
  check('v0.28: rejeita dimensões abusivas',not pcall(Preview.render,d,193,193))
  local p1=assert(Export.save(d,5))
  check('v0.28: exporta PNG RGBA de obra',p1=='exports/obra-5.png')
  local png=f.read(p1)
  check('v0.28: exportação tem assinatura PNG',png:sub(1,8)=='\137PNG\r\n\26\n')
  local p2=assert(Export.save(d,5))
  check('v0.28: exportações nunca sobrescrevem',p2=='exports/obra-5-2.png')
  check('v0.28: PNG anterior não é modificado',f.read(p1)==png)
  check('v0.28: pasta de exportações criada',seen['exports']==true)
  check('v0.28: IDs inseguros são rejeitados',not Export.save(d,'../malicioso'))
  local huge=Doc.new(4096,4096,'Muito grande')
  local large,reason=Export.save(huge,1)
  check('v0.28: exportação tem limite de RAM',not large and reason:find('limite',1,true))
  check('v0.28: original não afetado pelo limite',huge.w==4096 and huge.h==4096)
  check('v0.28: salva NPNT antes da prévia',Store.saveArtwork(d,777))
  local ok=Store.saveThumbnail(d,777)
  check('v0.28: salva a prévia no arquivo por ID',ok and seen['gallery/thumbs'])
  local byId=Store.thumbnailBytes(777)
  check('v0.28: prévia persiste fora do catálogo',byId and byId:sub(1,8)=='\137PNG\r\n\26\n')
  check('v0.28: miniatura recuperável sem recarregar NPNT',Store.ensureThumbnail(777)==byId)
  check('v0.28: caminho de miniatura rejeita traversal',not pcall(Store.thumbnailPath,'../../x'))
  local missing=Store.ensureThumbnail(9999)
  check('v0.28: obra ausente não cria prévia fantasma',not missing)
  f.createDirectory,f.getInfo=prevDir,prevGet
end
