-- v0.32: cobertura de borda em PNG rotacionado; preserva pixel art e RGB.
-- Testa dados raster (sem depender apenas do filtro da prévia na GPU).
return function(check)
  local Doc=require('core.doc')
  local Hist=require('core.history')
  local Import=require('src.png_import')
  local Bridge=require('app.paint_bridge')
  local abs,pi=math.abs,math.pi
  local function near(a,b) return abs(a-b)<1e-5 end
  local function scan(layer,doc)
    local partial,full,colors,coverage=0,0,true,0
    for y=0,doc.h-1 do
      for x=0,doc.w-1 do
        local key=math.floor(x/Doc.TILE)..','..math.floor(y/Doc.TILE)
        local tile=layer.tiles[key]
        if tile then
          local r,g,b,a=tile:getPixel(x%Doc.TILE,y%Doc.TILE)
          if a>0 then
            coverage=coverage+a
            if a<0.999 then partial=partial+1 else full=full+1 end
            if abs(r-1)>1e-5 or abs(g)>1e-5 or abs(b)>1e-5 then colors=false end
          end
        end
      end
    end
    return partial,full,colors,coverage
  end

  local red=love.image.newImageData(3,3)
  for y=0,2 do for x=0,2 do red:setPixel(x,y,1,0,0,1) end end
  local smoothDoc=Doc.new(20,20,'rotação suave')
  local session=Import.preview(smoothDoc,red,'vermelho.png')
  Import.setInterpolation(session,'smooth')
  Import.adjust(session,0,0,1,pi/4)
  local before=#smoothDoc.history.undo
  check('v0.32: prévia de rotação não altera histórico',before==0 and #smoothDoc.layers==2)
  local result,painted=Import.insert(smoothDoc,red,'vermelho.png',session)
  check('v0.32: PNG rotacionado entra como camada',result and painted>0 and #smoothDoc.layers==3)
  local partial,full,correct,coverage=scan(result,smoothDoc)
  check('v0.32: rotação suave produz bordas com alfa parcial',partial>0 and full>0)
  check('v0.32: pixels subamostrados não perdem cor',correct)
  check('v0.32: cobertura aproximada preserva área original',coverage>7.5 and coverage<10.5)
  check('v0.32: confirmação cria uma única ação de histórico',#smoothDoc.history.undo==before+1)
  Hist.undo(smoothDoc)
  check('v0.32: desfazer remove imagem com AA',#smoothDoc.layers==2)
  Hist.redo(smoothDoc)
  check('v0.32: refazer preserva imagem com AA',smoothDoc.layers[3]==result)

  local sharpDoc=Doc.new(20,20,'pixel art')
  local sharp=Import.preview(sharpDoc,red,'pixel.png')
  Import.adjust(sharp,0,0,1,pi/4)
  local nearest=assert(Import.insert(sharpDoc,red,'pixel.png',sharp))
  local p,f=scan(nearest,sharpDoc)
  check('v0.32: modo pixelado não cria pixels de alfa parcial',p==0 and f>0)
  check('v0.32: suavização rotacionada difere do pixelado',partial>0 and p==0)

  local source=love.image.newImageData(3,3)
  -- Vermelho escondido deve permanecer invisível, mesmo em amostras de borda.
  for y=0,2 do for x=0,2 do source:setPixel(x,y,1,0,0,0) end end
  source:setPixel(1,1,0,0,1,1)
  local doc=Doc.new(20,20,'alfa premultiplicado')
  local s=Import.preview(doc,source,'sem-halo.png')
  Import.setInterpolation(s,'smooth')
  Import.adjust(s,0,0,1.5,pi/6)
  local layer=assert(Import.insert(doc,source,'sem-halo.png',s))
  local hasPartial,onlyBlue=false,true
  for _,tile in pairs(layer.tiles) do
    for y=0,math.min(19,Doc.TILE-1) do
      for x=0,math.min(19,Doc.TILE-1) do
        local r,g,b,a=tile:getPixel(x,y)
        if a>0 then
          if a<0.999 then hasPartial=true end
          if abs(r)>1e-5 or abs(g)>1e-5 or abs(b-1)>1e-5 then onlyBlue=false end
        end
      end
    end
  end
  check('v0.32: borda oblíqua preserva alfa parcial',hasPartial)
  check('v0.32: antialias não mistura RGB totalmente transparente',onlyBlue)
  check('v0.32: importação não altera pixel fonte',
    select(1,source:getPixel(0,0))==1 and select(4,source:getPixel(0,0))==0)

  local straight=Doc.new(20,20,'sem rotação')
  local straightSession=Import.preview(straight,source,'sem-rotacao.png')
  Import.setInterpolation(straightSession,'smooth')
  local untouched=assert(Import.insert(straight,source,'sem-rotacao.png',straightSession))
  local tile=assert(untouched.tiles['0,0'])
  check('v0.32: identidade mantém pixel sem reamostragem extra',
    select(4,tile:getPixel(8,8))==0 and near(select(4,tile:getPixel(9,9)),1))

  local broken=love.image.newImageData(3,3)
  broken:setPixel(0,0,1,1,1,1)
  local reads=0
  local old=broken.getPixel
  broken.getPixel=function(self,x,y)
    reads=reads+1
    if reads>20 then error('falha de amostragem simulada') end
    return old(self,x,y)
  end
  local safeDoc=Doc.new(20,20,'falha segura')
  local brokenPreview=Import.preview(safeDoc,broken,'falha.png')
  Import.setInterpolation(brokenPreview,'smooth')
  Import.adjust(brokenPreview,0,0,1,pi/6)
  local bad,err=Import.insert(safeDoc,broken,'falha.png',brokenPreview)
  check('v0.32: falha de supersampling não cria camada',
    not bad and type(err)=='string' and #safeDoc.layers==2 and #safeDoc.history.undo==0)

  local bridge=Bridge.new()
  bridge.pngPreview=Import.preview(Doc.new(20,20,'controle fino'),red,'giro.png')
  bridge.pngPreview.angle=pi/7
  bridge.pngPreview.dx,bridge.pngPreview.dy=3,4
  bridge.pngPreview.scaleX,bridge.pngPreview.scaleY=1.5,1.5
  check('v0.32: giro fino pode ser zerado',bridge:resetPNGImportAngle())
  check('v0.32: zerar giro preserva posição e escala',
    bridge.pngPreview.angle==0 and bridge.pngPreview.dx==3
    and bridge.pngPreview.dy==4 and bridge.pngPreview.scaleX==1.5)
end
