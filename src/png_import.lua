-- Paint-Lua v0.29: PNG local como nova camada, sem apagar camadas existentes.
-- Valida o cabeçalho antes de pedir ao LÖVE para descompactar a imagem.
-- A camada é preparada separadamente; somente uma importação completa
-- modifica o documento (uma ação de desfazer/refazer).
local Doc = require('core.doc')
local Layers = require('core.layers')
local Import = {MAX_PIXELS=2097152, MAX_SIDE=8192, MAX_BYTES=16*1024*1024}
local SIGNATURE='\137PNG\r\n\26\n'
local floor, min, max = math.floor, math.min, math.max

local function be32(s,i)
  local a,b,c,d=s:byte(i,i+3)
  if not d then return nil end
  return ((a*256+b)*256+c)*256+d
end
local function validSize(w,h)
  return type(w)=='number' and type(h)=='number' and w==floor(w)
    and h==floor(h) and w>=1 and h>=1
    and w<=Import.MAX_SIDE and h<=Import.MAX_SIDE
    and w*h<=Import.MAX_PIXELS
end
function Import.inspect(bytes)
  if type(bytes)~='string' or #bytes<33 then
    return nil,'arquivo PNG vazio ou truncado'
  end
  if #bytes>Import.MAX_BYTES then return nil,'PNG maior que 16 MiB' end
  if bytes:sub(1,8)~=SIGNATURE or be32(bytes,9)~=13
    or bytes:sub(13,16)~='IHDR' then
    return nil,'não é um PNG válido (assinatura/IHDR)'
  end
  local w,h=be32(bytes,17),be32(bytes,21)
  if not validSize(w,h) then
    return nil,'imagem PNG excede 2.097.152 pixels ou 8.192 por lado'
  end
  return w,h
end

function Import.decode(bytes)
  local w,h,reason=Import.inspect(bytes)
  if not w then return nil,h end
  if not (love and love.filesystem and love.filesystem.newFileData
    and love.image and love.image.newImageData) then
    return nil,'decodificador do LÖVE indisponível'
  end
  local ok,pixels=pcall(function()
    local file=love.filesystem.newFileData(bytes,'import.png')
    return love.image.newImageData(file)
  end)
  if not ok or not pixels or not pixels.getWidth or not pixels.getPixel then
    return nil,'não foi possível decodificar PNG: '..tostring(pixels)
  end
  if pixels:getWidth()~=w or pixels:getHeight()~=h then
    return nil,'dimensões PNG inconsistentes'
  end
  return pixels
end

local function displayName(filename)
  if type(filename)~='string' then return 'Imagem PNG' end
  local name=filename:match('[^/\\]+$') or 'Imagem PNG'
  if not name:lower():match('%.png$') then return 'Imagem PNG' end
  name=name:sub(1,-5)
  -- Evita nomes muito extensos e inválidos na interface do LÖVE.
  if #name<1 or #name>80 or name:find('%c') then return 'Imagem PNG' end
  if utf8 and not utf8.len(name) then return 'Imagem PNG' end
  return name
end

-- Posiciona a imagem no centro do canvas. Partes fora do documento são
-- recortadas; pixels transparentes não criam tiles desnecessários.
function Import.insert(doc, pixels, filename)
  if type(doc)~='table' or type(doc.w)~='number' or type(doc.h)~='number'
    or type(doc.layers)~='table' or not pixels or not pixels.getWidth
    or not pixels.getHeight or not pixels.getPixel then
    return nil,'documento ou imagem inválidos'
  end
  local w,h=pixels:getWidth(),pixels:getHeight()
  if not validSize(w,h) then
    return nil,'imagem PNG excede 2.097.152 pixels ou 8.192 por lado'
  end
  local originX=floor((doc.w-w)/2)
  local originY=floor((doc.h-h)/2)
  local x0,y0=max(0,originX),max(0,originY)
  local x1,y1=min(doc.w,originX+w),min(doc.h,originY+h)
  if x1<=x0 or y1<=y0 then return nil,'a imagem ficou fora do canvas' end
  local title='PNG: '..displayName(filename)
  local detached=Doc.newLayer(title)
  local marked,painted={},0
  -- Qualquer falha de alocação é isolada nesta camada temporária.
  local copied,reason=pcall(function()
    for y=y0,y1-1 do
      for x=x0,x1-1 do
        local r,g,b,a=pixels:getPixel(x-originX,y-originY)
        if a>0 then
          local tx,ty=floor(x/Doc.TILE),floor(y/Doc.TILE)
          local tile,key=Doc.getTile(detached,tx,ty,true)
          tile:setPixel(x%Doc.TILE,y%Doc.TILE,r,g,b,a)
          marked[key]=true
          painted=painted+1
        end
      end
    end
  end)
  if not copied then return nil,'falha ao preparar a imagem: '..tostring(reason) end
  if painted==0 then return nil,'imagem totalmente transparente dentro do canvas' end
  for key in pairs(marked) do Doc.markDirty(detached,key) end
  -- Grava um único snapshot estrutural. Não substitui camadas já pintadas.
  local ok,layer=pcall(Layers.add,doc,title)
  if not ok then return nil,'não foi possível criar camada: '..tostring(layer) end
  layer.tiles=detached.tiles
  layer.dirty=detached.dirty
  layer.revisions=detached.revisions
  return layer,painted
end
function Import.fromBytes(doc,bytes,filename)
  local img,reason=Import.decode(bytes)
  if not img then return nil,reason end
  return Import.insert(doc,img,filename)
end
return Import
