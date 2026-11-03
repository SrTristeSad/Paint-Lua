-- Posições compartilhadas entre hit-testing e desenho (unidade: pixels de janela).
local L = {}
L.TOP = 54
L.BOTTOM = 30
L.LEFT = 76
L.RIGHT = 270
L.LAYER_HEIGHT = 44
function L.canvas(w, h)
  return {x = L.LEFT, y = L.TOP, w = math.max(1,w-L.LEFT-L.RIGHT), h = math.max(1,h-L.TOP-L.BOTTOM)}
end
local function inRect(x,y,a,b,w,h) return x>=a and y>=b and x<a+w and y<b+h end
function L.hit(w,h,x,y,nLayers)
  local rx=w-L.RIGHT
  if y < L.TOP then
    if inRect(x,y,16,12,85,32) then return 'save' end
    if inRect(x,y,108,12,85,32) then return 'open' end
    if inRect(x,y,200,12,100,32) then return 'recenter' end
  end
  if inRect(x,y,10,L.TOP+12,56,56) then return 'brush' end
  if inRect(x,y,10,L.TOP+78,56,56) then return 'eraser' end
  if inRect(x,y,rx+12,L.TOP+48,245,36) then return 'add-layer' end
  for i=1,nLayers do
    if inRect(x,y,rx+12,L.TOP+94+(i-1)*L.LAYER_HEIGHT,245,L.LAYER_HEIGHT-4) then
      return 'layer:'..i
    end
  end
  local startY=h-145
  for i=1,12 do
    local col=(i-1)%6
    local row=math.floor((i-1)/6)
    if inRect(x,y,rx+16+col*40,startY+row*42,32,32) then return 'swatch:'..i end
  end
  return nil
end
return L
