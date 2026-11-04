-- Comparação sintética v0.20 vs v0.21 em documento com muitas camadas esparsas.
-- Executar: texlua tests/benchmark_sparse_composite_v021.lua
-- O mock não representa o custo real de ImageData nem GPU no LÖVE.
package.path='./?.lua;'..package.path
local reads=0
local function newImageData(w,h)
  local img={w=w,h=h,p={}}
  function img:getWidth() return self.w end
  function img:getHeight() return self.h end
  function img:getPixel(x,y)
    local p=self.p[y*self.w+x+1]
    if p then return p[1],p[2],p[3],p[4] end
    return 0,0,0,0
  end
  function img:setPixel(x,y,r,g,b,a)
    self.p[y*self.w+x+1]={r,g,b,a}
  end
  function img:mapPixel(fn,x,y,w,h)
    for py=y,y+h-1 do for px=x,x+w-1 do
      self:setPixel(px,py,fn(px,py,self:getPixel(px,py)))
    end end
  end
  return img
end
love={image={newImageData=newImageData}}
local Doc=require('core.doc')
local Layers=require('core.layers')
local Groups=require('core.groups')
local Old=require('tests.reference_composite_v020')
local New=require('core.composite')
local d=Doc.new(2048,4,'benchmark esparso')
for i=3,122 do Layers.add(d,'L'..i) end
for i=2,122 do
  local layer=d.layers[i]
  local tx=(i-2)%8
  local tile,key=Doc.getTile(layer,tx,0,true)
  tile:setPixel((i*19)%Doc.TILE,0,(i%17)/17,(i%23)/23,(i%29)/29,0.5)
  Doc.markDirty(layer,key)
  setmetatable(layer.tiles,{__index=function() reads=reads+1 end})
end
local outer=Groups.create(d,2,122,'topo')
for _,range in ipairs({{12,37},{48,75},{89,114}}) do
  local sub=Groups.create(d,range[1],range[2],'subgrupo')
  Groups.setOpacity(d,sub,90)
end
Groups.setOpacity(d,outer,94)

local function compare(a,b)
  for x=0,2047 do for y=0,3 do
    local ar,ag,ab,aa=a:getPixel(x,y)
    local br,bg,bb,ba=b:getPixel(x,y)
    assert(ar==br and ag==bg and ab==bb and aa==ba,
      string.format('pixel divergente (%d,%d)',x,y))
  end end
end

local function measure(renderer)
  local times,missing={},0
  local result
  for i=1,7 do
    reads=0
    collectgarbage('collect')
    local t0=os.clock()
    local im=renderer.flattenRegion(d,0,0,d.w,d.h)
    local delta=os.clock()-t0
    times[#times+1]=delta
    if i==1 then result=im;missing=reads end
  end
  table.sort(times)
  return {median=times[4],missing=missing,result=result}
end
local old=measure(Old)
local new=measure(New)
compare(old.result,new.result)
assert(new.missing < old.missing,'índice não reduziu consultas de tiles ausentes')
print(string.format('v0.20: CPU mediana %.6f s; buscas de tiles ausentes %d',old.median,old.missing))
print(string.format('v0.21: CPU mediana %.6f s; buscas de tiles ausentes %d',new.median,new.missing))
print(string.format('Redução de consultas ausentes: %.1f%%',100*(1-new.missing/old.missing)))
print('Saída RGBA idêntica; teste sintético em Lua puro, sem FPS ou RAM real do LÖVE.')
