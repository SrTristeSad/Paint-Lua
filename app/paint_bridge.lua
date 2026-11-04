-- Paint-Lua: ponte entre o estado visual Ibis-Lua e o documento raster.
-- O núcleo controla pixels, composições e histórico; a UI controla navegação.
local Doc = require("core.doc")
local Stroke = require("core.stroke")
local History = require("core.history")
local Composite = require("core.composite")
local Project = require("core.project")
local Fill = require('core.fill')
local Job = require('core.job')

local Bridge = {}
Bridge.__index = Bridge
local blends = {
  Normal="normal", Multiply="multiply", Screen="screen",
  Overlay="overlay", Darken="darken", Lighten="lighten",
  ["Color Burn"]="color_burn", ["Color Dodge"]="color_dodge",
  ["Soft Light"]="softlight",
}
local reverse = {}
for label, key in pairs(blends) do reverse[key]=label end
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end
local function byte(n) return math.floor(clamp(n,0,1)*255+0.5) end
local function color(model)
  local c=model.color or {0,0,0}
  return {clamp(c[1]/255,0,1),clamp(c[2]/255,0,1),clamp(c[3]/255,0,1)}
end

function Bridge.new()
  return setmetatable({doc=nil,modelDocument=nil,byId={},uiByLayer={},
    stroke=nil,job=nil,cache=nil,gpu={},
    filename='meu-desenho.npnt',status='Motor v0.21 conectado'},Bridge)
end

function Bridge:dropImages()
  for _,image in pairs(self.gpu) do
    if image.release then image:release() end
  end
  self.gpu={}
  if self.cache then self.cache:clear() end
  self.cache=nil
end

function Bridge:cancelJob()
  if self.job then Job.cancel(self.job);self.job=nil;self.status='Preenchimento cancelado' end
end

-- Aplica somente diferenças efetivas. Uma interação de camada produz um
-- snapshot estrutural; redesenhar a UI não insere histórico adicional.
function Bridge:sync(model)
  if model.screen~='editor' or not model.document then return nil end
  local fresh = self.doc==nil or self.modelDocument~=model.document
  if fresh then
    self:finish(true)
    self:cancelJob()
    self:dropImages()
    self.doc=Doc.new(model.document.width,model.document.height,'Paint-Lua')
    self.doc.layers={}
    self.byId={}
    self.uiByLayer={}
    self.modelDocument=model.document
  end
  local doc=self.doc
  local nextLayers,nextMap={},{}
  local selected=1
  local changed = #doc.layers~=#model.layers
  for i,entry in ipairs(model.layers) do
    local layer=self.byId[entry.id]
    if not layer then layer=Doc.newLayer(entry.name) end
    nextLayers[i]=layer
    nextMap[entry.id]=layer
    self.uiByLayer[layer]=entry
    if doc.layers[i]~=layer or layer.name~=entry.name
      or layer.visible~=(entry.visible~=false)
      or layer.blend~=(blends[entry.blending] or 'normal')
      or (layer.clipped or false)~=(entry.clipping==true) then
      changed=true
    end
    if entry.id==model.active_layer_id then selected=i end
  end
  if #nextLayers==0 then
    -- Estado defensivo: o motor exige pelo menos uma camada editável.
    nextLayers[1]=Doc.newLayer('Camada 1')
    changed=true
  end
  if changed and not fresh then
    self:finish(false)
    if self.job then return nil end -- propriedades mudam após finalizar o job
    History.recordStructure(doc)
  end
  doc.layers=nextLayers
  doc.sel=selected
  self.byId=nextMap
  for i,entry in ipairs(model.layers) do
    local layer=doc.layers[i]
    layer.name=entry.name
    layer.visible=entry.visible~=false
    layer.opacity=clamp(entry.opacity or 100,0,100)
    layer.blend=blends[entry.blending] or 'normal'
    layer.clipped=entry.clipping==true
  end
  if not self.cache then self.cache=Composite.newCache(doc,{maxTiles=96}) end
  return doc
end

-- Inverso do espelhamento: depois de undo/redo estrutural, as propriedades
-- e a ordem da UI voltam a refletir a árvore do documento, não o contrário.
function Bridge:refreshModel(model)
  if not self.doc then return end
  local oldMap=self.uiByLayer
  local entries,nextMap={},{}
  local maxId=0
  for _,entry in ipairs(model.layers) do maxId=math.max(maxId,entry.id) end
  maxId=math.max(maxId,(model.next_layer_id or 1)-1)
  for i,layer in ipairs(self.doc.layers) do
    local entry=oldMap[layer]
    if not entry then
      maxId=maxId+1
      entry={id=maxId,alpha_lock=false,locked=false}
      oldMap[layer]=entry
    end
    entry.name=layer.name
    entry.visible=layer.visible
    entry.opacity=layer.opacity
    entry.blending=reverse[layer.blend] or 'Normal'
    entry.clipping=layer.clipped or false
    entries[i]=entry
    nextMap[entry.id]=layer
  end
  model.layers=entries
  model.active_layer_id=entries[self.doc.sel] and entries[self.doc.sel].id
  model.next_layer_id=maxId+1
  model.solo_layer_id=nil
  model.solo_before=nil
  self.byId=nextMap
end

-- Coordenadas inversas da transformacao usada pelo editor Ibis-Lua.
function Bridge:toCanvas(model,view,prefs,uiScale,W,H,rx,ry)
  if not self:sync(model) then return nil end
  local left=prefs.tool_position=="left" and 62 or 0
  local right=prefs.tool_position=="right" and 75 or 34
  local aw,ah=W-left-right,H-160
  local cx=left+aw/2+view.pan_x
  local cy=62+ah/2+view.pan_y
  local ds=math.min(aw/self.doc.w,ah/self.doc.h,1.1)*view.zoom
  if ds<=0 then return nil end
  local x,y=rx/uiScale-cx,ry/uiScale-cy
  local a=view.rotation
  local dx=(x*math.cos(a)+y*math.sin(a))/ds+self.doc.w/2
  local dy=(-x*math.sin(a)+y*math.cos(a))/ds+self.doc.h/2
  return dx,dy
end

function Bridge:point(model,view,prefs,uiScale,W,H,rx,ry)
  local x,y=rx/uiScale,ry/uiScale
  local left=prefs.tool_position=='left' and 62 or 0
  local right=prefs.tool_position=='right' and 75 or 34
  if y<91 or y>H-128 or x<left or x>W-right then return nil end
  local px,py=self:toCanvas(model,view,prefs,uiScale,W,H,rx,ry)
  if not px or px<0 or py<0 or px>=self.doc.w or py>=self.doc.h then return nil end
  return px,py
end

function Bridge:pick(model,px,py)
  local img=Composite.flattenRegion(self.doc,math.floor(px),math.floor(py),1,1)
  local r,g,b,a=img:getPixel(0,0)
  if a<=0 then self.status='Conta-gotas: pixel transparente';return false end
  model:set_color(byte(r),byte(g),byte(b))
  self.status='Cor coletada do desenho'
  return true
end

function Bridge:bucket(model,px,py,opacity)
  if self.job then self.status='Balde ocupado';return false end
  local entry=model:active_layer()
  if entry.locked then self.status='Camada bloqueada';return false end
  if entry.alpha_lock then
    self.status='Balde indisponível com Alpha Lock nesta versão'
    return false
  end
  local c=color(model)
  c[4]=clamp((opacity or 100)/100,0,1)
  local ok,job=pcall(Fill.newJob,self.doc,self.doc.layers[self.doc.sel],px,py,c,0.04,
    self.doc.selection,{yieldEvery=512})
  if not ok then self.status='Balde: '..tostring(job);return false end
  self.job=job
  self.status='Preenchendo...'
  return true
end

function Bridge:press(model,view,prefs,uiScale,W,H,rx,ry,opacity)
  if self.stroke or self.job then return false end
  if model.active_tool~='brush' and model.active_tool~='eraser'
    and model.active_tool~='bucket' and model.active_tool~='eyedropper' then
    return false
  end
  local px,py=self:point(model,view,prefs,uiScale,W,H,rx,ry)
  if not px then return false end
  if model.active_tool=='eyedropper' then return self:pick(model,px,py) end
  if model.active_tool=='bucket' then return self:bucket(model,px,py,opacity) end
  local entry=model:active_layer()
  if entry.locked then self.status='Camada bloqueada';return false end
  local opts={
    size=clamp(model.brush_size or 1,0.1,1000),
    alpha=clamp((opacity or 100)/100,0,1), hardness=0.85,
    color=color(model), eraser=model.active_tool=='eraser',
    alphaLock=entry.alpha_lock==true,
    selection=self.doc.selection, pressureSize=false,
    smoothing={mode='exponential',amount=0.30,catchUpOnEnd=true},
  }
  local ok,stroke=pcall(Stroke.new,self.doc,self.doc.layers[self.doc.sel],self.doc.history,opts)
  if not ok then self.status='Pincel: '..tostring(stroke);return false end
  self.stroke=stroke
  self:move(model,view,prefs,uiScale,W,H,rx,ry)
  return true
end

function Bridge:move(model,view,prefs,uiScale,W,H,rx,ry)
  if not self.stroke then return false end
  local x,y=self:toCanvas(model,view,prefs,uiScale,W,H,rx,ry)
  if not x then return false end
  local tm=(love.timer and love.timer.getTime() or os.clock())*1000
  local ok,err=pcall(self.stroke.push,self.stroke,x,y,1,tm)
  if not ok then self.status="Pincel: "..tostring(err);self:finish(true) end
  return true
end

function Bridge:finish(cancel)
  if not self.stroke then return end
  local s=self.stroke
  self.stroke=nil
  local ok,err=pcall(cancel and s.cancel or s.finish,s)
  if not ok then
    self.status="Finalizacao: "..tostring(err)
    pcall(s.cancel,s)
  end
end

function Bridge:update()
  if not self.job then return end
  local job=self.job
  local ok,done,value=pcall(Job.step,job,0.004,love.timer and love.timer.getTime or os.clock)
  if not ok then
    self.job=nil
    self.status='Balde: '..tostring(done)
    return self.status
  elseif done then
    self.job=nil
    self.status='Preenchimento: '..tostring(value or 0)..' pixels'
    return self.status
  end
end

function Bridge:draw(x,y)
  if not self.doc or not self.cache then return end
  local seen={}
  for _,layer in ipairs(self.doc.layers) do
    for key in pairs(layer.tiles) do seen[key]=true end
  end
  local g=love.graphics
  g.setBlendMode('alpha')
  g.setColor(1,1,1,1)
  for key in pairs(seen) do
    local tx,ty=Doc.parseKey(key)
    if tx and ty then
      local before=self.cache:stats().recompositions
      local pixels=self.cache:_get(tx,ty)
      local changed=self.cache:stats().recompositions~=before
        or self.doc.history.stroke~=nil or self.job~=nil
      local image=self.gpu[key]
      if not image then
        image=g.newImage(pixels)
        self.gpu[key]=image
      elseif changed then image:replacePixels(pixels) end
      g.draw(image,x+tx*Doc.TILE,y+ty*Doc.TILE)
    end
  end
  for key,image in pairs(self.gpu) do
    if not seen[key] then
      if image.release then image:release() end
      self.gpu[key]=nil
    end
  end
  g.setColor(1,1,1,1)
end

function Bridge:save()
  if not self.doc then return nil,'nenhum documento' end
  if self.job then return nil,'balde em andamento' end
  self:finish(false)
  local ok,err=Project.save(self.doc,self.filename)
  self.status=ok and ('Salvo: '..self.filename) or ('Erro: '..tostring(err))
  return ok,err
end

function Bridge:load(model)
  self:finish(true)
  self:cancelJob()
  local ok,doc,err=pcall(Project.load,self.filename)
  if not ok or not doc then
    self.status='Abertura: '..tostring(ok and err or doc)
    return nil,self.status
  end
  self:dropImages()
  self.doc=doc
  self.modelDocument={width=doc.w,height=doc.h}
  model.document=self.modelDocument
  model.screen='editor'
  model.modal=nil
  model.active_panel=nil
  model.layers={}
  model.next_layer_id=1
  self.byId={}
  self.uiByLayer={}
  self:refreshModel(model)
  self.cache=Composite.newCache(doc,{maxTiles=96})
  self.status='Aberto: '..self.filename
  return true
end

function Bridge:historyStep(model,redo)
  if model.screen~='editor' then return false end
  if self.job then
    self.status='Finalize ou cancele o balde antes do histórico'
    return false
  end
  self:finish(false)
  self:sync(model)
  if not self.doc then return false end
  local fn=redo and History.redo or History.undo
  local ok,changed=pcall(fn,self.doc)
  self.status=not ok and tostring(changed) or
    (changed and (redo and 'Refeito' or 'Desfeito') or 'Nada para alterar')
  if ok and changed then self:refreshModel(model) end
  return ok and changed or false
end

function Bridge:key(model,key)
  if model.screen~='editor' then return false end
  local k=love.keyboard
  if not (k and k.isDown('lctrl','rctrl','lgui','rgui')) then return false end
  if key=='s' then self:sync(model);self:save();return true end
  if key=='o' then self:load(model);return true end
  if key=='z' then self:historyStep(model,false);return true end
  if key=='y' then self:historyStep(model,true);return true end
  return false
end

return Bridge
