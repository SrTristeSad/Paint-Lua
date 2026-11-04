-- Benchmark de número de pixels solicitados para compor um documento 16K.
-- Mock esparso: não aloca realmente ImageData nem mede RAM/VRAM do LÖVE.
-- Executar: texlua tests/benchmark_composite.lua
package.path = './?.lua;' .. package.path
local calls, largestArea = 0, 0
local function newImageData(w,h)
  calls = calls + 1
  largestArea = math.max(largestArea,w*h)
  local t={w=w,h=h,p={}}
  function t:getPixel(x,y)
    local v=self.p[y*self.w+x+1] or {0,0,0,0}
    return v[1],v[2],v[3],v[4]
  end
  function t:setPixel(x,y,r,g,b,a)
    self.p[y*self.w+x+1]={r,g,b,a}
  end
  return t
end
love={image={newImageData=newImageData}}
local Doc=require('core.doc')
local C=require('core.composite')
local d=Doc.new(16384,16384,'benchmark 16K')
local t=Doc.getTile(d.layers[2],63,63,true)
t:setPixel(255,255,0.8,0.4,0.2,1)
local full=C.flatten(d)
local baseline=largestArea
local r,g,b,a=full:getPixel(16383,16383)
largestArea=0;calls=0
local emitted=C.stream(d,function(x,y,tile)
  local R,G,B,A=tile:getPixel(255,255)
  assert(x==16128 and y==16128 and R==r and G==g and B==b and A==a)
end)
print(string.format('canvas=16384x16384 | pixels solicitados na maior ImageData: '
  .. 'flatten=%d, stream=%d | tiles emitidos=%d | razão=%dx',
  baseline,largestArea,emitted,baseline/largestArea))
print('Nota: contagem de área teórica; mock esparso não mede memória real ou velocidade.')
