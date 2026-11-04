-- Executado pelo test_core.lua, que prepara o mock de ImageData.
return function(check)
  local Doc=require('core.doc')
  local Stroke=require('core.stroke')
  local Hist=require('core.history')
  local d=Doc.new(64,64,'Alpha Lock')
  local layer=d.layers[2]
  local tile,key=Doc.getTile(layer,0,0,true)
  tile:setPixel(20,20,0.2,0.3,0.8,0.4)
  Doc.markDirty(layer,key)
  local opts={size=8,alpha=1,hardness=1,color={1,0,0},alphaLock=true,
    smoothing={mode='exponential',amount=0}}
  local s=Stroke.new(d,layer,d.history,opts)
  s:push(20,20,1,0)
  s:finish()
  local r,g,b,a=layer.tiles[key]:getPixel(20,20)
  check('alpha lock: conserva alfa de pixel parcialmente opaco',math.abs(a-0.4)<1e-9)
  check('alpha lock: altera canais RGB já ocupados',r>0.2 and g<0.3 and b<0.8)
  check('alpha lock: não cria novos pixels em regiões transparentes',
    select(4,layer.tiles[key]:getPixel(21,20))==0)
  Hist.undo(d)
  r,g,b,a=layer.tiles[key]:getPixel(20,20)
  check('alpha lock: undo restaura os canais originais',
    math.abs(r-0.2)<1e-9 and math.abs(g-0.3)<1e-9 and math.abs(a-0.4)<1e-9)
  Hist.redo(d)
  r,g,b,a=layer.tiles[key]:getPixel(20,20)
  check('alpha lock: redo preserva o alfa', math.abs(a-0.4)<1e-9 and r>0.2)
  local empty=Doc.new(64,64,'Alpha Lock vazio')
  local l=empty.layers[2]
  s=Stroke.new(empty,l,empty.history,opts)
  s:push(30,30,1,0)
  s:finish()
  local count=0
  for _ in pairs(l.tiles) do count=count+1 end
  check('alpha lock: não aloca tile em camada vazia', count==0)
  check('alpha lock: gesto vazio não gera histórico',#empty.history.undo==0)
  local erase={size=8,alpha=1,hardness=1,color={1,1,1},alphaLock=true,eraser=true}
  s=Stroke.new(d,layer,d.history,erase)
  s:push(20,20,1,0);s:finish()
  check('alpha lock: borracha não altera alfa',
    math.abs(select(4,layer.tiles[key]:getPixel(20,20))-0.4)<1e-9)
  check('alpha lock: borracha bloqueada não gera histórico',#d.history.undo==1)
end
