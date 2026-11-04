-- v0.29: PNG->camada, histórico, transparência e limites (ImageData simulado).
return function(check)
  local Doc=require('core.doc')
  local Hist=require('core.history')
  local Import=require('src.png_import')
  local function png(w,h)
    return '\137PNG\r\n\26\n'..string.char(0,0,0,13)..'IHDR'
      ..string.char(0,0,0,w,0,0,0,h)..string.rep('\0',9)
  end
  local d=Doc.new(16,12,'Camadas existentes')
  local original=d.layers[2]
  local src=love.image.newImageData(4,2)
  src:setPixel(0,0,0.8,0.1,0.2,0.5)
  src:setPixel(3,1,0.2,0.9,0.1,1)
  local before=#d.history.undo
  local layer,count=Import.insert(d,src,'imagem.png')
  check('v0.29: importa pixels em camada extra',layer and #d.layers==3 and d.layers[2]==original)
  check('v0.29: importa somente os pixels existentes',count==2)
  check('v0.29: nova camada vira selecionada',d.sel==3 and d.layers[3]==layer)
  check('v0.29: nome da camada preserva filename',layer.name=='PNG: imagem')
  local tile=assert(layer.tiles['0,0'])
  local r,g,b,a=tile:getPixel(6,5)
  check('v0.29: rgba importado sem perder alfa',r==0.8 and g==0.1 and b==0.2 and a==0.5)
  check('v0.29: centraliza e posiciona extremos',select(4,tile:getPixel(9,6))==1)
  check('v0.29: não escreve fora do PNG',select(4,tile:getPixel(5,5))==0)
  check('v0.29: cria uma ação de histórico',#d.history.undo==before+1)
  Hist.undo(d)
  check('v0.29: undo remove apenas a importação',#d.layers==2 and d.layers[2]==original)
  Hist.redo(d)
  check('v0.29: redo recupera PNG intacto',#d.layers==3 and d.layers[3]==layer and
    select(4,d.layers[3].tiles['0,0']:getPixel(6,5))==0.5)

  local allClear=love.image.newImageData(2,2)
  before=#d.history.undo
  local none=Import.insert(d,allClear,'vazio.png')
  check('v0.29: PNG transparente não cria camada',not none and #d.history.undo==before)
  check('v0.29: não altera ordem quando nada é importado',#d.layers==3)
  check('v0.29: rejeita dados sem IHDR',not Import.inspect('abc'))
  check('v0.29: valida tamanho pelo IHDR',Import.inspect(png(4,2))==4)
  local oversized=png(0,1)
  check('v0.29: rejeita largura zero',not Import.inspect(oversized))
  -- Header inválido não deve chamar o backend.
  local invalid=png(4,2):sub(1,12)..'BAD!'..png(4,2):sub(17)
  check('v0.29: IHDR inválido não decodifica',not Import.decode(invalid))
  local big=love.image.newImageData(1,1)
  function big:getWidth() return 9000 end
  check('v0.29: limites validados antes de criar camada',not Import.insert(d,big,'grande.png'))
  local failure=love.image.newImageData(2,2)
  failure:setPixel(0,0,1,1,1,1)
  function failure:getPixel() error('decodificação falhou') end
  before=#d.history.undo
  check('v0.29: falha de leitura não muda camadas',not Import.insert(d,failure,'erro.png')
    and #d.layers==3 and #d.history.undo==before)
  local clip=Doc.new(3,2,'recorte')
  local visible=Import.insert(clip,src,'cropped.png')
  check('v0.29: recorta PNG ao canvas pequeno',visible and #clip.layers==3)
end
