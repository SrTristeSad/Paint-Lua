-- v0.31: bilinear pré-multiplicado, pixel-art, prévia GPU e histórico.
return function(check)
  local Doc=require('core.doc')
  local Hist=require('core.history')
  local Import=require('src.png_import')
  local Transform=require('core.transform')
  local abs=math.abs
  local function near(a,b) return abs(a-b)<0.00001 end
  local function pixel(layer,x,y)
    local key=math.floor(x/Doc.TILE)..','..math.floor(y/Doc.TILE)
    local tile=layer.tiles[key]
    if not tile then return 0,0,0,0 end
    return tile:getPixel(x%Doc.TILE,y%Doc.TILE)
  end

  local src=love.image.newImageData(2,1)
  src:setPixel(0,0,1,0,0,1)
  src:setPixel(1,0,0,0,1,1)
  local smoothDoc=Doc.new(12,12,'suave')
  local smooth=Import.preview(smoothDoc,src,'fotografia.png')
  check('v0.31: API de preview preserva modo pixelado legado',smooth.interpolation=='pixelated')
  check('v0.31: modo suave pode ser escolhido',Import.setInterpolation(smooth,'smooth')=='smooth')
  Import.adjust(smooth,0,0,2)
  local before=#smoothDoc.history.undo
  local layer,count=Import.insert(smoothDoc,src,'foto.png',smooth)
  local leftR,_,leftB,leftA=pixel(layer,5,5)
  local rightR,_,rightB,rightA=pixel(layer,6,5)
  check('v0.31: suave interpola interior da fotografia',
    near(leftR,0.75) and near(leftB,0.25) and near(rightR,0.25) and near(rightB,0.75))
  check('v0.31: bilinear mantém alfa opaco e evita bordas pretas',
    near(leftA,1) and near(rightA,1))
  check('v0.31: prévia não interfere na transação',
    layer and count==8 and #smoothDoc.history.undo==before+1)
  Hist.undo(smoothDoc)
  check('v0.31: desfazer remove camada bilinear',#smoothDoc.layers==2)
  Hist.redo(smoothDoc)
  check('v0.31: refazer preserva cores bilineares',
    smoothDoc.layers[3]==layer and near(select(3,pixel(layer,5,5)),0.25))

  local sharpDoc=Doc.new(12,12,'pixel-art')
  local sharp=Import.preview(sharpDoc,src,'pixel.png')
  Import.adjust(sharp,0,0,2)
  local sharpLayer=assert(Import.insert(sharpDoc,src,'pixel.png',sharp))
  local pr,_,pb=pixel(sharpLayer,5,5)
  local qr,_,qb=pixel(sharpLayer,6,5)
  check('v0.31: pixelado mantém bordas duras',pr==1 and pb==0 and qr==0 and qb==1)
  check('v0.31: interpolação não modifica a fonte',
    select(1,src:getPixel(0,0))==1 and select(3,src:getPixel(1,0))==1)

  -- Transparência: RGB de pixels totalmente transparentes não pode contaminar
  -- as cores parcialmente visíveis (evita franja vermelha em azul sólido).
  local transparent=love.image.newImageData(2,1)
  transparent:setPixel(0,0,1,0,0,0)
  transparent:setPixel(1,0,0,0,1,1)
  local alphaDoc=Doc.new(12,12,'bordas')
  local alpha=Import.preview(alphaDoc,transparent,'alfa.png')
  Import.setInterpolation(alpha,'smooth')
  Import.adjust(alpha,0,0,2)
  local alphaLayer,painted=Import.insert(alphaDoc,transparent,'alfa.png',alpha)
  local ar,ag,ab,aa=pixel(alphaLayer,5,5)
  check('v0.31: bilinear preserva alfa de pixels misturados',near(aa,0.25))
  check('v0.31: não gera halo RGB da cor totalmente transparente',
    near(ar,0) and near(ag,0) and near(ab,1))
  check('v0.31: inclui pixels com alfa parcialmente coberto',painted>0)
  local original=love.image.newImageData(2,1)
  original:setPixel(0,0,0.25,0.5,0.75,0.2)
  original:setPixel(1,0,0,0,0,0)
  local identity=Doc.new(12,12,'escala 1:1')
  local single=Import.preview(identity,original,'original.png')
  Import.setInterpolation(single,'smooth')
  local identityLayer=assert(Import.insert(identity,original,'original.png',single))
  local ir,ig,ib,ia=pixel(identityLayer,5,5)
  check('v0.31: escala 1:1 mantém RGBA exato',
    near(ir,0.25) and near(ig,0.5) and near(ib,0.75) and near(ia,0.2))
  local bareDoc=Doc.new(12,12,'API v0.29')
  local bare=assert(Import.insert(bareDoc,src,'legado.png'))
  check('v0.31: API v0.29 sem sessão continua importando',
    select(1,pixel(bare,5,5))==1)

  check('v0.31: modo desconhecido rejeitado',
    not pcall(Import.setInterpolation,alpha,'bicubic') and alpha.interpolation=='smooth')
  local noChange=#alphaDoc.history.undo
  alpha.interpolation='unsupported'
  local bad,msg=Import.insert(alphaDoc,transparent,'invalido.png',alpha)
  check('v0.31: modo adulterado recusa operação sem modificar camadas',
    not bad and msg and #alphaDoc.history.undo==noChange)
  alpha.interpolation='smooth'
  Import.cancel(alpha)
  check('v0.31: alterar modo de sessão cancelada é rejeitado',
    not pcall(Import.setInterpolation,alpha,'pixelated'))

  -- Filtro da GPU acompanha o modo escolhido sem refazer a textura.
  local previousGraphics=love.graphics
  local filters,creations,releases={},0,0
  local fakeGraphics={}
  fakeGraphics.newImage=function()
    creations=creations+1
    return {
      setFilter=function(_,a,b) filters[#filters+1]={a,b} end,
      release=function() releases=releases+1 end,
    }
  end
  fakeGraphics.push=function() end
  fakeGraphics.pop=function() end
  fakeGraphics.translate=function() end
  fakeGraphics.rotate=function() end
  fakeGraphics.scale=function() end
  fakeGraphics.setColor=function() end
  fakeGraphics.draw=function() end
  fakeGraphics.rectangle=function() end
  love.graphics=fakeGraphics
  local visual=Import.preview(Doc.new(12,12,'GPU'),src,'gpu.png')
  Import.setInterpolation(visual,'smooth')
  Transform.drawPreview(visual,0,0)
  check('v0.31: prévia suave usa filtro linear do LÖVE',
    filters[#filters][1]=='linear' and filters[#filters][2]=='linear')
  Import.setInterpolation(visual,'pixelated')
  Transform.drawPreview(visual,0,0)
  check('v0.31: alternar modo atualiza a mesma textura GPU',
    filters[#filters][1]=='nearest' and creations==1)
  Import.cancel(visual)
  check('v0.31: cancelar libera textura GPU',releases==1)
  love.graphics=previousGraphics
end
