-- v0.20: comparação de áreas solicitadas por ImageData, não de RAM real.
-- Usa mock esparso; evita alocar milhões de objetos de pixels de teste.
-- Executar: texlua tests/benchmark_nested_groups.lua
package.path='./?.lua;'..package.path
local calls,area,maxArea=0,0,0
local function image(w,h)
  calls=calls+1
  area=area+w*h
  maxArea=math.max(maxArea,w*h)
  local t={w=w,h=h,p={}}
  function t:getPixel(x,y)
    local p=self.p[y*self.w+x+1]
    if p then return p[1],p[2],p[3],p[4] end
    return 0,0,0,0
  end
  function t:setPixel(x,y,r,g,b,a)
    self.p[y*self.w+x+1]={r,g,b,a}
  end
  function t:mapPixel(fn,x,y,w,h)
    for py=y,y+h-1 do for px=x,x+w-1 do
      self:setPixel(px,py,fn(px,py,self:getPixel(px,py)))
    end end
  end
  return t
end
love={image={newImageData=image}}
local Doc=require('core.doc')
local Groups=require('core.groups')
local New=require('core.composite')
local Old=require('tests.reference_composite_v019')
local d=Doc.new(1024,768,'benchmark')
local tile,key=Doc.getTile(d.layers[2],0,0,true)
tile:setPixel(11,19,0.8,0.25,0.7,0.75)
Doc.markDirty(d.layers[2],key)
for i=1,4 do
  local id=Groups.create(d,2,2,'Nivel '..i)
  Groups.setOpacity(d,id,95-i*4)
end
local function measure(renderer)
  calls,area,maxArea=0,0,0
  local t0=os.clock()
  local result=renderer.flatten(d)
  local seconds=os.clock()-t0
  local output={calls=calls,area=area,largest=maxArea,seconds=seconds,
    sample={result:getPixel(11,19)}}
  return output
end
local old=measure(Old)
local new=measure(New)
for i=1,4 do assert(old.sample[i]==new.sample[i],'pixel divergente') end
assert(new.area<old.area,'buffers não reduzidos')
assert(new.largest==d.w*d.h,'maior buffer inesperado')
local function report(label,s)
  print(string.format('%s: %d ImageData | %d pixels solicitados | maior buffer %d pixels | CPU %.3fs',
    label,s.calls,s.area,s.largest,s.seconds))
end
report('v0.19',old)
report('v0.20',new)
print(string.format('Redução das áreas solicitadas: %.1f%%',100*(1-new.area/old.area)))
print('Nota: contagem teórica de áreas de ImageData em mock esparso; não mede RAM, FPS nem GPU do LÖVE.')
