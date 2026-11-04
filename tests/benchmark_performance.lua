-- Microbenchmark reproduzível em Lua puro. Executar:
-- texlua tests/benchmark_performance.lua [caminho-raiz-do-nucleo]
-- Mostra custo relativo em um mock esparso (não mede FPS nem GPU real).
local root=arg and arg[1] or '.'
package.path=root..'/?.lua;'..package.path
local function imageData(w,h)
  local self={width=w,height=h,pixels={}}
  function self:getPixel(x,y)
    local p=self.pixels[y*self.width+x+1]
    if p then return p[1],p[2],p[3],p[4] end
    return 0,0,0,0
  end
  function self:setPixel(x,y,r,g,b,a)
    self.pixels[y*self.width+x+1]={r,g,b,a}
  end
  function self:clone()
    local b=imageData(self.width,self.height)
    for k,v in pairs(self.pixels) do
      b.pixels[k]={v[1],v[2],v[3],v[4]}
    end
    return b
  end
  return self
end
local drawCalls=0
love={image={newImageData=imageData},graphics={
  setScissor=function() end,setBlendMode=function() end,setColor=function() end,
  draw=function() drawCalls=drawCalls+1 end}}
local Doc=require('core.doc')
local Stroke=require('core.stroke')
local Tip=require('core.tip')
local Render=require('core.render')
local tip=Tip.new(4,4,{0,1,1,0, 1,0.6,0.4,1, 1,0.4,0.6,1, 0,1,1,0})
local function scenario()
  local d=Doc.new(2048,1024,'benchmark')
  local L=d.layers[2]
  local s=Stroke.new(d,L,d.history,{size=24,alpha=0.8,hardness=0.85,
    color={0.9,0.2,0.4},spacing=0.25,flow=0.5,
    tip=tip,dualBrush={tip=tip,depth=0.4,scale=0.8},
    paper={tip=tip,scale=1.5,depth=0.4},
    pressureOpacity=true,pressureMinOpacity=0.1})
  for i=1,70 do s:push(30+i*3,100+(i%7),0.4+i/150) end
  s:finish()
  local total, count=0,0
  for _,t in pairs(L.tiles) do
    for _,p in pairs(t.pixels) do
      total=total+p[1]*1.33+p[2]*2.51+p[3]*3.77+p[4]*4.97
      count=count+1
    end
  end
  return total,count
end
local function bench(f,n)
  local total=0
  for _=1,n do
    local start=os.clock();f();total=total+(os.clock()-start)
  end
  return total/n
end
local checksum,changed=scenario()
local strokeSec=bench(scenario,3)
local d=Doc.new(16384,16384,'render')
local L=d.layers[2]
for y=0,15 do
  for x=0,15 do L.images[x..','..y]={} end
end
local function draw()
  drawCalls=0
  Render.draw(d,0,0,1,{x=400,y=300,w=300,h=220})
  return drawCalls
end
local renderCalls=draw()
local renderSec=bench(draw,100)
print(string.format('versao=%s | stroke=%.6fs | amostras=%d | checksum=%.7f | drawCalls=%d | render=%.6fs',
  root,strokeSec,changed,checksum,renderCalls,renderSec))
