-- Microbenchmark reproduzível do balde de tinta, com mock esparso de ImageData.
-- Rodar: texlua tests/benchmark_fill.lua
-- Para comparar, copiar este arquivo para os testes da v0.11 e executar ali.
-- Mede só CPU Lua/os.clock; NÃO mede FPS, VRAM nem ImageData do LÖVE real.
package.path = './?.lua;' .. package.path
local created, written, read = 0, 0, 0
local function imageData(w,h)
  created = created + 1
  local t = {w=w,h=h,p={}}
  function t:getPixel(x,y)
    read = read + 1
    local px=self.p[y*self.w+x+1]
    if not px then return 0,0,0,0 end
    return px[1],px[2],px[3],px[4]
  end
  function t:setPixel(x,y,r,g,b,a)
    written = written + 1
    self.p[y*self.w+x+1]={r,g,b,a}
  end
  function t:clone()
    local copy=imageData(self.w,self.h)
    for k,p in pairs(self.p) do copy.p[k]={p[1],p[2],p[3],p[4]} end
    return copy
  end
  return t
end
love={image={newImageData=imageData}}
local Doc=require('core.doc')
local Fill=require('core.fill')
local H=require('core.history')
local W,Hh=512,256
local d=Doc.new(W,Hh,'benchmark do balde')
local L=d.layers[2]
local start=os.clock()
local n=Fill.fill(d,L,8,8,{0.3,0.6,0.9,1},0)
local elapsed=os.clock()-start
assert(n==W*Hh,'contagem errada: '..tostring(n))
assert(#d.history.undo==1,'uma entrada de histórico era esperada')
for _,xy in ipairs({{0,0},{255,127},{256,127},{511,255}}) do
  local r,g,b,a=Fill.pixel(L,xy[1],xy[2])
  assert(r==0.3 and g==0.6 and b==0.9 and a==1,'pixel inesperado')
end
H.undo(d)
assert(next(L.tiles)==nil,'undo não recuperou a área vazia')
print(string.format('area=%dx%d; preenchidos=%d; tempo_cpu_lua=%.4fs; image_data_criadas=%d; leituras=%d; escritas=%d',
 W,Hh,n,elapsed,created,read,written))
print('Nota: benchmark em mock esparso, não equivale a FPS nem desempenho do LÖVE em hardware.')
