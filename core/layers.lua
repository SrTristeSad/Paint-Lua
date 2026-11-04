-- Operações sobre a lista de camadas. As que mudam estrutura ou propriedades
-- gravam o estado antes no histórico (desfazíveis). Seleção e opacidade não são.
local Doc = require("core.doc")
local H = require("core.history")
local M = require("core.mask")
local Blend = require("core.blend")

local L = {}

local function clamp(v, a, b)
  return math.max(a, math.min(b, v))
end

function L.add(doc, name)
  H.recordStructure(doc)
  local layer = Doc.newLayer(name or ("Camada " .. (#doc.layers + 1)))
  layer.groupId = doc.layers[doc.sel] and doc.layers[doc.sel].groupId
  table.insert(doc.layers, doc.sel + 1, layer)
  doc.sel = doc.sel + 1
  return layer
end

function L.duplicate(doc)
  H.recordStructure(doc)
  local copy = Doc.duplicateLayer(doc.layers[doc.sel])
  table.insert(doc.layers, doc.sel + 1, copy)
  doc.sel = doc.sel + 1
  return copy
end

-- Retorna false se for a última camada.
function L.delete(doc)
  if #doc.layers <= 1 then return false end
  H.recordStructure(doc)
  table.remove(doc.layers, doc.sel)
  require('core.groups').cleanup(doc)
  doc.sel = clamp(doc.sel, 1, #doc.layers)
  -- A camada removida pode agora estar retida apenas pelo histórico.
  H.prune(doc.history)
  return true
end

function L.setVisible(doc, i, visible)
  H.recordStructure(doc)
  doc.layers[i].visible = visible and true or false
end

local BLENDS = Blend.modes

function L.setBlend(doc, i, mode)
  assert(BLENDS[mode], "modo de mesclagem desconhecido: " .. tostring(mode))
  H.recordStructure(doc)
  doc.layers[i].blend = mode
end

-- Não entra no histórico: um arraste do slider geraria itens demais.
function L.setOpacity(doc, i, opacity)
  H.assertUnlocked(doc.history)
  doc.layers[i].opacity = clamp(opacity, 0, 100)
end

function L.select(doc, i)
  H.assertUnlocked(doc.history)
  doc.sel = clamp(i, 1, #doc.layers)
end

-- Adicionar/remover/configurar máscaras é ação estrutural desfazível.
-- Revelar: default 1, ocultar: default 0.
local function getLayer(doc, i)
  assert(type(i)=='number' and i==math.floor(i) and doc.layers[i], 'camada inválida')
  return doc.layers[i]
end
local function getMask(doc, i)
  return assert(getLayer(doc,i).mask, 'camada não possui máscara')
end
function L.addMask(doc, i, default)
  local layer = getLayer(doc,i)
  assert(not layer.mask,'camada já possui máscara')
  -- Validar antes de alterar o histórico.
  local mask = M.new(default)
  H.recordStructure(doc)
  layer.mask = mask
  return mask
end
function L.removeMask(doc, i)
  local layer = getLayer(doc,i)
  if not layer.mask then return false end
  H.recordStructure(doc)
  layer.mask = nil
  H.prune(doc.history)
  return true
end
function L.setMaskEnabled(doc, i, enabled)
  assert(type(enabled)=='boolean','enabled deve ser booleano')
  local mask=getMask(doc,i)
  if mask.enabled==enabled then return false end
  H.recordStructure(doc)
  mask.enabled=enabled
  return true
end
function L.setMaskInverted(doc, i, inverted)
  assert(type(inverted)=='boolean','inverted deve ser booleano')
  local mask=getMask(doc,i)
  if mask.inverted==inverted then return false end
  H.recordStructure(doc)
  mask.inverted=inverted
  return true
end
local function inside(doc,x,y)
  return type(x)=='number' and type(y)=='number' and x==math.floor(x)
    and y==math.floor(y) and x>=0 and x<doc.w and y>=0 and y<doc.h
end
-- Pintura de máscara em uma operação atômica para o histórico.
-- A pintura altera somente a máscara, nunca os pixels da camada.
function L.paintMaskRect(doc,i,x,y,w,h,value)
  local mask=getMask(doc,i)
  assert(inside(doc,x,y) and type(w)=='number' and type(h)=='number'
    and w==math.floor(w) and h==math.floor(h) and w>0 and h>0
    and x+w<=doc.w and y+h<=doc.h, 'região de máscara inválida')
  assert(type(value)=='number' and value==value and value>=0 and value<=1
    and value~=math.huge, 'cobertura de máscara inválida')
  H.begin(doc.history)
  local ok,err=pcall(function()
    for py=y,y+h-1 do
      for px=x,x+w-1 do
        local tx,ty=math.floor(px/Doc.TILE),math.floor(py/Doc.TILE)
        local tile,key=M.getTile(mask,tx,ty,false)
        local old=tile and select(1,tile:getPixel(px%Doc.TILE,py%Doc.TILE)) or mask.default
        if old ~= value then
          H.touchMask(doc.history,mask,key)
          if not tile then tile=M.getTile(mask,tx,ty,true) end
          tile:setPixel(px%Doc.TILE,py%Doc.TILE,value,value,value,1)
          M.markDirty(mask,key)
        end
      end
    end
  end)
  if not ok then
    H.rollback(doc.history)
    error(err,0)
  end
  H.commit(doc.history)
  return true
end
function L.setMaskPixel(doc,i,x,y,value)
  return L.paintMaskRect(doc,i,x,y,1,1,value)
end
function L.maskValue(doc,i,x,y)
  assert(inside(doc,x,y),'coordenada de máscara inválida')
  return M.value(getMask(doc,i),x,y)
end

return L
