-- Formato nativo .npnt, versões NPNT1 a NPNT5: arquivo binário com metadados
-- prefixados por tamanho e tiles guardados como PNGs independentes.
-- Não executa código do arquivo ao abrir (sem loadstring / serialização Lua).
-- Acesso a disco é feito exclusivamente por love.filesystem (save directory).
local Doc = require("core.doc")
local Mask = require("core.mask")
local Blend = require("core.blend")
local Selection = require('core.selection')

local P = {}
local MAGIC = "NPNT1\n"
local MAGIC2 = "NPNT2\n"
local MAGIC3 = "NPNT3\n"
local MAGIC4 = "NPNT4\n"
local MAGIC5 = "NPNT5\n"
local MAX_TEXT = 1024 * 1024
local MAX_PNG = 16 * 1024 * 1024
local PNG_SIGNATURE = "\137PNG\r\n\26\n"

local function pngDimensions(png)
  -- IHDR é o primeiro chunk do PNG, e declara as dimensões antes da descompressão.
  -- Checar o cabeçalho evita tentar decodificar uma imagem de dimensões enormes.
  assert(#png >= 33 and png:sub(1, 8) == PNG_SIGNATURE
    and png:sub(9, 16) == "\0\0\0\13IHDR", "PNG inválido")
  local function u32(i)
    local a, b, c, d = png:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return u32(17), u32(21)
end
local MAX_LAYERS = 2048
local BLENDS = Blend.modes

local function finite(n)
  return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

local function integer(n, lo, hi)
  return finite(n) and n == math.floor(n) and n >= lo and n <= hi
end

local function validNumber(n, lo, hi)
  return finite(n) and n >= lo and n <= hi
end

local function writeNum(parts, n)
  parts[#parts + 1] = tostring(n) .. "\n"
end

local function writeBlob(parts, s)
  writeNum(parts, #s)
  parts[#parts + 1] = s
end

-- Uma única implementação para máscaras de camada e de grupo (NPNT4).
local function writeMask(parts, mask, limitX, limitY)
  if not mask then writeNum(parts,0); return end
  assert(type(mask)=='table' and type(mask.tiles)=='table'
    and type(mask.enabled)=='boolean' and type(mask.inverted)=='boolean'
    and validNumber(mask.default,0,1),'máscara inválida')
  writeNum(parts,1)
  writeNum(parts,mask.enabled and 1 or 0)
  writeNum(parts,mask.inverted and 1 or 0)
  writeNum(parts,mask.default)
  local keys={}
  for key in pairs(mask.tiles) do keys[#keys+1]=key end
  table.sort(keys)
  assert(#keys <= (limitX+1)*(limitY+1),'quantidade excessiva de tiles de máscara')
  writeNum(parts,#keys)
  for _,key in ipairs(keys) do
    local tx,ty=Doc.parseKey(key)
    assert(tx and ty and integer(tx,0,limitX) and integer(ty,0,limitY)
      and key==tx..','..ty,'coordenadas de máscara inválidas')
    local tile=mask.tiles[key]
    assert(tile and tile:getWidth()==Doc.TILE and tile:getHeight()==Doc.TILE,
      'dimensões de máscara inválidas')
    local png=tile:encode('png'):getString()
    assert(#png>0 and #png<=MAX_PNG,'PNG da máscara inválido')
    local mw,mh=pngDimensions(png)
    assert(mw==Doc.TILE and mh==Doc.TILE,'dimensões PNG da máscara inválidas')
    writeNum(parts,tx);writeNum(parts,ty);writeBlob(parts,png)
  end
end

local function encode(doc)
  assert(type(doc) == "table", "documento inválido")
  assert(integer(doc.w, 1, 65536) and integer(doc.h, 1, 65536), "dimensões inválidas")
  assert(type(doc.layers) == "table" and integer(#doc.layers, 1, MAX_LAYERS), "quantidade de camadas inválida")
  assert(integer(doc.sel, 1, #doc.layers), "camada selecionada inválida")
  assert(type(doc.name) == "string" and #doc.name <= MAX_TEXT, "nome do documento inválido")
  assert(type(doc.tool) == "string" and #doc.tool <= 128, "ferramenta inválida")
  assert(validNumber(doc.size, 0, 100000) and validNumber(doc.opacity, 0, 100), "configuração de ferramenta inválida")

  local complex = doc.selection and
    (doc.selection.kind=='polygon' or doc.selection.kind=='wand')
  if complex then Selection.validate(doc,doc.selection) end
  local grouped = next(doc.groups or {}) ~= nil or not not complex
  local modern = not not complex
  local extended = grouped
  for _, layer in ipairs(doc.layers) do
    if layer.clipped or layer.groupId then grouped = true; extended = true end
    if layer.mask or (layer.blend and not Blend.legacy[layer.blend]) then
      extended = true
    end
  end
  for _,g in pairs(doc.groups or {}) do
    if g.parentId or g.mask then modern = true end
  end
  if grouped then require('core.groups').validate(doc) end
  local parts = {complex and MAGIC5 or (modern and MAGIC4 or
    (grouped and MAGIC3 or (extended and MAGIC2 or MAGIC)))}
  writeNum(parts, doc.w)
  writeNum(parts, doc.h)
  writeBlob(parts, doc.name)
  writeNum(parts, #doc.layers)
  writeNum(parts, doc.sel)
  writeBlob(parts, doc.tool)
  writeNum(parts, doc.size)
  writeNum(parts, doc.opacity)

  if doc.color == nil then
    writeNum(parts, 0)
  else
    assert(type(doc.color) == "table" and (#doc.color == 3 or #doc.color == 4), "cor inválida")
    writeNum(parts, #doc.color)
    for i = 1, #doc.color do
      assert(validNumber(doc.color[i], 0, 1), "canal de cor inválido")
      writeNum(parts, doc.color[i])
    end
  end

  if doc.selection then
    local s = doc.selection
    assert(type(s) == "table" and integer(s.x, -1000000, 1000000)
      and integer(s.y, -1000000, 1000000) and integer(s.w, 1, 1000000)
      and integer(s.h, 1, 1000000), "seleção inválida")
    writeNum(parts, 1)
    writeNum(parts, s.x); writeNum(parts, s.y)
    writeNum(parts, s.w); writeNum(parts, s.h)
  else
    writeNum(parts, 0)
  end

  local limitX = math.floor((doc.w - 1) / Doc.TILE)
  local limitY = math.floor((doc.h - 1) / Doc.TILE)
  -- NPNT3: tabela de grupos antes das camadas, com IDs explícitos.
  if grouped then
    local ids = {}
    for id in pairs(doc.groups) do ids[#ids+1] = id end
    table.sort(ids)
    writeNum(parts, #ids)
    for _,id in ipairs(ids) do
      local g=doc.groups[id]
      writeNum(parts,id)
      writeBlob(parts,g.name)
      writeNum(parts,g.visible and 1 or 0)
      writeNum(parts,g.opacity)
      writeBlob(parts,g.blend)
      if modern then
        writeNum(parts,g.parentId or 0)
        writeMask(parts,g.mask,limitX,limitY)
      end
    end
  end

  for _, layer in ipairs(doc.layers) do
    assert(type(layer.name) == "string" and #layer.name <= MAX_TEXT, "nome de camada inválido")
    assert(type(layer.visible) == "boolean", "visibilidade inválida")
    assert(validNumber(layer.opacity, 0, 100), "opacidade de camada inválida")
    assert(BLENDS[layer.blend], "modo de mesclagem inválido")
    assert(type(layer.tiles) == "table", "tiles inválidos")

    writeBlob(parts, layer.name)
    writeNum(parts, layer.visible and 1 or 0)
    writeNum(parts, layer.opacity)
    writeBlob(parts, layer.blend)

    local keys = {}
    for key in pairs(layer.tiles) do keys[#keys + 1] = key end
    table.sort(keys) -- saída determinística, independente da ordem de pairs
    assert(#keys <= (limitX + 1) * (limitY + 1), "quantidade excessiva de tiles")
    writeNum(parts, #keys)
    for _, key in ipairs(keys) do
      assert(type(key) == "string", "chave de tile inválida")
      local tx, ty = Doc.parseKey(key)
      assert(tx and ty and integer(tx, 0, limitX) and integer(ty, 0, limitY)
        and key == tx .. "," .. ty, "coordenadas de tile inválidas")
      local tile = layer.tiles[key]
      assert(tile and tile:getWidth() == Doc.TILE and tile:getHeight() == Doc.TILE,
        "dimensões do tile inválidas")
      local png = tile:encode("png"):getString()
      assert(#png > 0 and #png <= MAX_PNG, "tile PNG inválido ou grande demais")
      local pngW, pngH = pngDimensions(png)
      assert(pngW == Doc.TILE and pngH == Doc.TILE, "PNG de tile com dimensões inválidas")
      writeNum(parts, tx); writeNum(parts, ty)
      writeBlob(parts, png)
    end
    if extended then writeMask(parts,layer.mask,limitX,limitY) end
    if grouped then
      writeNum(parts, layer.clipped and 1 or 0)
      writeNum(parts, layer.groupId or 0)
    end
  end
  if complex then
    if doc.selection.kind=='polygon' then
      writeNum(parts,1)
      writeNum(parts,#doc.selection.points)
      for _,p in ipairs(doc.selection.points) do
        writeNum(parts,p[1]);writeNum(parts,p[2])
      end
    else
      writeNum(parts,2)
      writeMask(parts,doc.selection.mask,limitX,limitY)
    end
  end
  return table.concat(parts)
end

function P.encode(doc)
  assert(not (doc and doc.history and doc.history._fillLock),
    'aguarde o preenchimento cooperativo terminar antes de salvar')
  assert(not (doc and doc.history and doc.history.stroke),
    'finalize ou cancele a pincelada antes de salvar')
  return encode(doc)
end

local function reader(bytes)
  return {bytes = bytes, pos = 1}
end

local function readLine(r)
  local endpos = r.bytes:find("\n", r.pos, true)
  assert(endpos and endpos - r.pos <= 128, "campo numérico ausente ou longo demais")
  local value = r.bytes:sub(r.pos, endpos - 1)
  r.pos = endpos + 1
  return value
end

local function readInt(r, lo, hi)
  local s = readLine(r)
  assert(s:match("^%-?%d+$"), "campo inteiro inválido")
  local n = tonumber(s)
  assert(integer(n, lo, hi), "campo inteiro fora do intervalo")
  return n
end

local function readNumber(r, lo, hi)
  local n = tonumber(readLine(r))
  assert(validNumber(n, lo, hi), "número inválido ou fora do intervalo")
  return n
end

local function readBlob(r, max)
  local len = readInt(r, 0, max)
  assert(len <= #r.bytes - r.pos + 1, "arquivo truncado")
  local value = r.bytes:sub(r.pos, r.pos + len - 1)
  r.pos = r.pos + len
  return value
end

local function readMask(r, maxTX, maxTY)
  if readInt(r,0,1)==0 then return nil end
  local enabled=readInt(r,0,1)==1
  local inverted=readInt(r,0,1)==1
  local default=readNumber(r,0,1)
  local mask=Mask.new(default)
  mask.enabled,mask.inverted=enabled,inverted
  local count=readInt(r,0,(maxTX+1)*(maxTY+1))
  for j=1,count do
    local tx,ty=readInt(r,0,maxTX),readInt(r,0,maxTY)
    local key=tx..','..ty
    assert(not mask.tiles[key],'tile de máscara duplicado')
    local png=readBlob(r,MAX_PNG)
    local pw,ph=pngDimensions(png)
    assert(pw==Doc.TILE and ph==Doc.TILE,'PNG de máscara com dimensões inválidas')
    local data=love.filesystem.newFileData(png,'mask.png')
    local tile=love.image.newImageData(data)
    assert(tile:getWidth()==Doc.TILE and tile:getHeight()==Doc.TILE,
      'dimensões de máscara inesperadas')
    mask.tiles[key]=tile
    Mask.markDirty(mask,key)
  end
  return mask
end

local function decode(bytes)
  assert(type(bytes) == 'string', 'projeto deve ser texto binário')
  local v5 = bytes:sub(1,#MAGIC5)==MAGIC5
  local modern = v5 or bytes:sub(1,#MAGIC4)==MAGIC4
  local grouped = modern or bytes:sub(1,#MAGIC3)==MAGIC3
  local extended = grouped or bytes:sub(1,#MAGIC2)==MAGIC2
  assert(extended or bytes:sub(1,#MAGIC)==MAGIC,
    'assinatura ou versão de projeto incompatível')
  local r = reader(bytes)
  r.pos = #(v5 and MAGIC5 or (modern and MAGIC4 or
    (grouped and MAGIC3 or (extended and MAGIC2 or MAGIC)))) + 1
  local w, h = readInt(r, 1, 65536), readInt(r, 1, 65536)
  local name = readBlob(r, MAX_TEXT)
  local layerCount = readInt(r, 1, MAX_LAYERS)
  local selected = readInt(r, 1, layerCount)
  local tool = readBlob(r, 128)
  local size = readNumber(r, 0, 100000)
  local opacity = readNumber(r, 0, 100)
  local colorCount = readInt(r, 0, 4)
  assert(colorCount == 0 or colorCount == 3 or colorCount == 4, "formato de cor inválido")
  local color
  if colorCount > 0 then
    color = {}
    for i = 1, colorCount do color[i] = readNumber(r, 0, 1) end
  end
  local hasSelection = readInt(r, 0, 1)
  local selection
  if hasSelection == 1 then
    selection = {
      x = readInt(r, -1000000, 1000000),
      y = readInt(r, -1000000, 1000000),
      w = readInt(r, 1, 1000000),
      h = readInt(r, 1, 1000000),
    }
  end

  local doc = Doc.new(w, h, name)
  doc.layers = {}
  doc.sel = selected
  doc.tool, doc.size, doc.opacity, doc.color = tool, size, opacity, color
  doc.selection = selection
  local maxTX = math.floor((w - 1) / Doc.TILE)
  local maxTY = math.floor((h - 1) / Doc.TILE)

  if grouped then
    local groupCount=readInt(r,0,2048)
    local greatest=0
    for j=1,groupCount do
      local id=readInt(r,1,2147483647)
      assert(not doc.groups[id], 'ID de grupo duplicado')
      local name=readBlob(r,MAX_TEXT)
      local visible=readInt(r,0,1)==1
      local opacity=readNumber(r,0,100)
      local blend=readBlob(r,32)
      assert(BLENDS[blend], 'modo de grupo inválido')
      local parentId, mask
      if modern then
        local parent=readInt(r,0,2147483647)
        parentId=parent~=0 and parent or nil
        mask=readMask(r,maxTX,maxTY)
      end
      doc.groups[id]={id=id,parentId=parentId,name=name,visible=visible,
        opacity=opacity,blend=blend,mask=mask}
      greatest=math.max(greatest,id)
    end
    doc.nextGroupId=greatest+1
  end

  for i = 1, layerCount do
    local layer = Doc.newLayer(readBlob(r, MAX_TEXT))
    layer.visible = readInt(r, 0, 1) == 1
    layer.opacity = readNumber(r, 0, 100)
    layer.blend = readBlob(r, 32)
    assert(BLENDS[layer.blend], "mesclagem desconhecida")
    local tileCount = readInt(r, 0, (maxTX + 1) * (maxTY + 1))
    for j = 1, tileCount do
      local tx = readInt(r, 0, maxTX)
      local ty = readInt(r, 0, maxTY)
      local key = tx .. "," .. ty
      assert(not layer.tiles[key], "tile duplicado")
      local png = readBlob(r, MAX_PNG)
      local pngW, pngH = pngDimensions(png)
      assert(pngW == Doc.TILE and pngH == Doc.TILE, "PNG de tile com dimensões inválidas")
      local fileData = love.filesystem.newFileData(png, "tile.png")
      local tile = love.image.newImageData(fileData)
      assert(tile:getWidth() == Doc.TILE and tile:getHeight() == Doc.TILE,
        "dimensões inesperadas no PNG")
      layer.tiles[key] = tile
      Doc.markDirty(layer, key)
    end
    if extended then layer.mask=readMask(r,maxTX,maxTY) end
    if grouped then
      layer.clipped=readInt(r,0,1)==1
      local id=readInt(r,0,2147483647)
      layer.groupId=id~=0 and id or nil
    end
    doc.layers[i] = layer
  end
  if grouped then require('core.groups').validate(doc) end
  if v5 then
    assert(selection~=nil,'NPNT5 exige seleção complexa')
    local shape=readInt(r,1,2)
    if shape==1 then
      local points={}
      local count=readInt(r,3,4096)
      for i=1,count do
        points[i]={readInt(r,0,doc.w),readInt(r,0,doc.h)}
      end
      selection.kind='polygon'
      selection.points=points
    else
      selection.kind='wand'
      selection.mask=readMask(r,maxTX,maxTY)
      assert(selection.mask~=nil,'máscara de varinha ausente')
    end
    Selection.validate(doc,selection)
  end
  assert(r.pos == #bytes + 1, "dados adicionais inesperados")
  -- Histórico recém-inicializado por Doc.new. Nenhuma imagem GPU é restaurada;
  -- Render.refresh irá reconstruir o cache a partir dos tiles sujos.
  return doc
end

function P.decode(bytes)
  local ok, result = pcall(decode, bytes)
  if ok then return result end
  return nil, "Projeto inválido: " .. tostring(result)
end

-- Em LÖVE, os caminhos de love.filesystem são relativos ao diretório de save.
function P.save(doc, path)
  if type(path) ~= "string" or path == "" then return nil, "caminho inválido" end
  local ok, bytes = pcall(P.encode, doc)
  if not ok then return nil, tostring(bytes) end
  if not (love and love.filesystem and love.filesystem.write) then
    return nil, "love.filesystem.write indisponível"
  end
  local written, success, err = pcall(love.filesystem.write, path, bytes)
  if not written then return nil, tostring(success) end
  if not success then return nil, err or "erro ao salvar arquivo" end
  return true
end

function P.load(path)
  if type(path) ~= "string" or path == "" then return nil, "caminho inválido" end
  if not (love and love.filesystem and love.filesystem.read) then
    return nil, "love.filesystem.read indisponível"
  end
  local ok, bytes, err = pcall(love.filesystem.read, path)
  if not ok then return nil, tostring(bytes) end
  if not bytes then return nil, err or "arquivo não encontrado" end
  return P.decode(bytes)
end

return P
