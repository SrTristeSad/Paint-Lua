-- Composição de camadas (correção de referência CPU).
-- C.flatten/C.flattenAsync mantêm a API histórica de saída ImageData inteira.
-- Para documentos grandes, C.flattenRegion e C.tiles evitam essa alocação.
local Doc = require('core.doc')
local Job = require('core.job')

local C = {}
local T = Doc.TILE
local min, max, floor = math.min, math.max, math.floor

local FUNC = require('core.blend').modes
local Mask = require('core.mask')

local function validInt(v)
  return type(v) == 'number' and v == v and v ~= math.huge
    and v ~= -math.huge and v == floor(v)
end

local function bounds(doc, rect)
  assert(doc and validInt(doc.w) and validInt(doc.h) and doc.w > 0 and doc.h > 0,
    'dimensões inválidas do documento')
  if rect == nil then return 0, 0, doc.w, doc.h end
  assert(type(rect) == 'table', 'região deve ser uma tabela')
  local x, y, w, h = rect.x, rect.y, rect.w, rect.h
  assert(validInt(x) and validInt(y) and validInt(w) and validInt(h)
    and x >= 0 and y >= 0 and w > 0 and h > 0
    and x + w <= doc.w and y + h <= doc.h,
    'região fora dos limites do documento')
  return x, y, w, h
end

-- Processa só tiles que intersectam o retângulo.
-- Para uma região pequena, lookup direto evita percorrer milhares de tiles fora da viewport.
-- Para uma região ampla, usa o índice esparso de tiles existentes, evitando visitar vazios.
local function eachTile(layer, x, y, w, h, fn)
  local tx0, ty0 = floor(x / T), floor(y / T)
  local tx1, ty1 = floor((x + w - 1) / T), floor((y + h - 1) / T)
  local span = (tx1 - tx0 + 1) * (ty1 - ty0 + 1)
  if span <= 64 then
    for ty = ty0, ty1 do
      for tx = tx0, tx1 do
        local key = tx .. ',' .. ty
        local tile = layer.tiles[key]
        if tile then fn(tile, tx, ty) end
      end
    end
  else
    for key, tile in pairs(layer.tiles) do
      local tx, ty = Doc.parseKey(key)
      if tx and tx >= tx0 and tx <= tx1 and ty >= ty0 and ty <= ty1 then
        fn(tile, tx, ty)
      end
    end
  end
end

-- Composição source-over comum para pixels e grupos isolados.
local function over(out, ox, oy, sr,sg,sb,sa, blend)
  if sa <= 0 then return end
  local dr,dg,db,da=out:getPixel(ox,oy)
  local outA=sa+da*(1-sa)
  if outA <= 0 then return end
  local mr=(1-da)*sr+da*blend(dr,sr)
  local mg=(1-da)*sg+da*blend(dg,sg)
  local mb=(1-da)*sb+da*blend(db,sb)
  out:setPixel(ox,oy,
    (mr*sa+dr*da*(1-sa))/outA,
    (mg*sa+dg*da*(1-sa))/outA,
    (mb*sa+db*da*(1-sa))/outA,outA)
end

-- Alfa da camada base de um clipping stack, antes das mesclagens posteriores.
-- O recorte respeita visibilidade, opacidade e máscara raster da base.
local function baseAlpha(base, tx, ty, px, py)
  if not base or not base.visible or base.opacity<=0 then return 0 end
  local tile=base.tiles[tx..','..ty]
  if not tile then return 0 end
  local a=select(4,tile:getPixel(px-tx*T,py-ty*T))
  if a<=0 then return 0 end
  local mask=base.mask
  if mask then a=a*Mask.value(mask,px,py) end
  return a*base.opacity/100
end

local function compositeTile(out, layer, tile, tx, ty, x, y, w, h, clipBase)
  local sx,sy=tx*T,ty*T
  local left,top=max(x,sx),max(y,sy)
  local right,bottom=min(x+w,sx+T),min(y+h,sy+T)
  local lo=layer.opacity/100
  local blend=FUNC[layer.blend] or FUNC.normal
  local mask=layer.mask
  local masked=mask and mask.enabled
  local maskTile=masked and Mask.getTile(mask,tx,ty,false) or nil
  for py=top,bottom-1 do
    for px=left,right-1 do
      local sr,sg,sb,sa0=tile:getPixel(px-sx,py-sy)
      if sa0>0 then
        local coverage=1
        if masked then
          coverage=maskTile and select(1,maskTile:getPixel(px-sx,py-sy)) or mask.default
          if mask.inverted then coverage=1-coverage end
        end
        local sa=sa0*lo*coverage
        if clipBase then sa=sa*baseAlpha(clipBase,tx,ty,px,py) end
        over(out,px-x,py-y,sr,sg,sb,sa,blend)
      end
    end
  end
end

-- Aplica opacidade, máscara e mesclagem ao resultado isolado do grupo.
local function compositeGroup(out, buffer, group, x, y, w, h)
  local strength=group.opacity/100
  if strength<=0 then return end
  local blend=FUNC[group.blend] or FUNC.normal
  local mask=group.mask
  for yy=0,h-1 do
    for xx=0,w-1 do
      local r,g,b,a=buffer:getPixel(xx,yy)
      if a>0 then
        local coverage=mask and Mask.value(mask,x+xx,y+yy) or 1
        if coverage>0 then over(out,xx,yy,r,g,b,a*strength*coverage,blend) end
      end
    end
  end
end

local function visibleLayer(doc,layer)
  if not layer.visible or layer.opacity<=0 then return false end
  local id=layer.groupId
  local seen={}
  while id do
    if seen[id] then return false end
    seen[id]=true
    local g=doc.groups and doc.groups[id]
    if not g or not g.visible or g.opacity<=0 then return false end
    id=g.parentId
  end
  return true
end

-- Reconstrói somente a hierarquia da composição; doc.layers continua plano.
-- A lista de folhas e a associação a grupos não são alteradas.
local function makeTree(doc)
  local Groups=require('core.groups')
  local root={children={}}
  local open,ids={},{}
  for _,layer in ipairs(doc.layers) do
    local path=Groups.path(doc,layer.groupId)
    local common=0
    while common<#ids and common<#path and ids[common+1]==path[common+1] do
      common=common+1
    end
    for j=#ids,common+1,-1 do ids[j]=nil;open[j]=nil end
    for j=common+1,#path do
      local parent=open[j-1] or root
      local node={group=doc.groups[path[j]],children={}}
      parent.children[#parent.children+1]=node
      open[j]=node;ids[j]=path[j]
    end
    local parent=open[#path] or root
    parent.children[#parent.children+1]={layer=layer}
  end
  return root
end

local function work(doc, rect, yieldFn)
  local x,y,w,h=bounds(doc,rect)
  local out=love.image.newImageData(w,h)
  local tree=makeTree(doc)
  local total=0
  if yieldFn then
    for _,layer in ipairs(doc.layers) do
      if visibleLayer(doc,layer) then
        eachTile(layer,x,y,w,h,function() total=total+1 end)
      end
    end
  end
  local done=0
  local function compose(node,dest)
    local base=nil
    for _,child in ipairs(node.children) do
      local layer=child.layer
      if layer then
        if not layer.clipped then base=layer end
        if layer.visible and layer.opacity>0 then
          local clipBase=layer.clipped and base or nil
          eachTile(layer,x,y,w,h,function(tile,tx,ty)
            compositeTile(dest,layer,tile,tx,ty,x,y,w,h,clipBase)
            if yieldFn then
              done=done+1
              yieldFn(total>0 and done/total or 1)
            end
          end)
        end
      else
        -- Grupos são fronteiras: clipping de camadas não cruza um subgrupo.
        base=nil
        local g=child.group
        if g.visible and g.opacity>0 then
          local buffer=love.image.newImageData(w,h)
          compose(child,buffer)
          compositeGroup(dest,buffer,g,x,y,w,h)
        end
      end
    end
  end
  compose(tree,out)
  return out
end

function C.flatten(doc)
  return work(doc, nil, nil)
end

function C.flattenJob(doc)
  return function() return work(doc, nil, coroutine.yield) end
end

function C.flattenAsync(doc)
  return Job.new(C.flattenJob(doc))
end

-- Região inteira em coordenadas de documento: largura/altura resultantes = w/h.
-- Não cria uma ImageData do tamanho total do documento.
function C.flattenRegion(doc, x, y, w, h)
  return work(doc, {x = x, y = y, w = w, h = h}, nil)
end

-- Iterador esparso em ordem de leitura: retorna x, y, ImageData da área do tile.
-- Considera somente chaves de tiles de camadas visíveis/opacas na região solicitada.
-- Pode retornar tiles totalmente transparentes (pixels originais apagados); não é
-- um iterador de todos os tiles possíveis do documento, portanto a área restante
-- do documento deve ser tratada como transparente por quem consome.
-- Retorna também o número de tiles para acompanhamento de progresso.
function C.tiles(doc, rect)
  local x, y, w, h = bounds(doc, rect)
  local found, list = {}, {}
  for _, layer in ipairs(doc.layers) do
    if visibleLayer(doc,layer) then
      eachTile(layer, x, y, w, h, function(_, tx, ty)
        local key = tx .. ',' .. ty
        if not found[key] then
          found[key] = true
          list[#list + 1] = {tx = tx, ty = ty}
        end
      end)
    end
  end
  table.sort(list, function(a, b)
    if a.ty == b.ty then return a.tx < b.tx end
    return a.ty < b.ty
  end)
  local i = 0
  return function()
    i = i + 1
    local t = list[i]
    if not t then return nil end
    local px, py = max(x, t.tx * T), max(y, t.ty * T)
    local right, bottom = min(x + w, (t.tx + 1) * T), min(y + h, (t.ty + 1) * T)
    return px, py, C.flattenRegion(doc, px, py, right - px, bottom - py)
  end, #list
end

-- Consome e descarta cada ImageData por vez. Um callback que armazena os
-- resultados deixa de ter consumo limitado: responsabilidade do chamador.
function C.stream(doc, consume, rect)
  assert(type(consume) == 'function', 'consume deve ser função')
  local nextTile = C.tiles(doc, rect)
  local count = 0
  while true do
    local x, y, tile = nextTile()
    if not x then break end
    consume(x, y, tile)
    count = count + 1
  end
  return count
end

-- Retorna um Job; um yield é feito após cada tile entregue ao callback.
-- A função callback executa dentro da coroutine e deve copiar/salvar o tile
-- antes de retornar, caso queira retê-lo.
function C.streamAsync(doc, consume, rect)
  assert(type(consume) == 'function', 'consume deve ser função')
  return Job.new(function()
    local nextTile, total = C.tiles(doc, rect)
    local done = 0
    while true do
      local x, y, tile = nextTile()
      if not x then return done end
      consume(x, y, tile)
      done = done + 1
      coroutine.yield(done / total)
    end
  end)
end

-- Cache CPU explícito; sem alterar C.flatten/flattenRegion/tiles/stream.
-- Cada instância pertence a um único documento e possui limite de tiles.
function C.newCache(doc, options)
  return require('core.composite_cache').new(doc, options)
end

return C
