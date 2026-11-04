-- Conta-gotas: cor visível no ponto, considerando camadas visíveis de cima para baixo.
-- Ignora a opacidade da camada (mostra a cor pintada, não a cor composta).
local Doc = require("core.doc")

local S = {}

-- Retorna r, g, b, a (0..1) e o índice da camada, ou nil se o ponto está vazio.
function S.at(doc, x, y)
  x, y = math.floor(x), math.floor(y)
  if x < 0 or y < 0 or x >= doc.w or y >= doc.h then return nil end
  local T = Doc.TILE
  local tx, ty = math.floor(x / T), math.floor(y / T)
  local key = tx .. "," .. ty
  for i = #doc.layers, 1, -1 do
    local L = doc.layers[i]
    if L.visible then
      local tile = L.tiles[key]
      if tile then
        local r, g, b, a = tile:getPixel(x - tx * T, y - ty * T)
        if a > 0 then return r, g, b, a, i end
      end
    end
  end
  return nil
end

return S
