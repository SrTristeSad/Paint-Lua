-- Ponte inicial: interface Ibis-Lua -> motor de pintura Paint-Lua v0.21.
-- A interface continua dona da navegacao; core/ continua dono dos pixels.
local Doc = require("core.doc")
local Stroke = require("core.stroke")
local History = require("core.history")
local Composite = require("core.composite")
local Project = require("core.project")

local Bridge = {}
Bridge.__index = Bridge
local blends = {
  Normal="normal", Multiply="multiply", Screen="screen",
  Overlay="overlay", Darken="darken", Lighten="lighten",
  ["Color Burn"]="color_burn", ["Color Dodge"]="color_dodge",
  ["Soft Light"]="softlight",
}
local names = {}
for label, key in pairs(blends) do names[key]=label end
local function clamp(v,lo,hi) return math.max(lo,math.min(hi,v)) end

function Bridge.new()
  return setmetatable({
    doc=nil, modelDocument=nil, byId={}, stroke=nil,
    cache=nil, gpu={}, filename="meu-desenho.npnt",
    status="Motor v0.21 conectado",
  }, Bridge)
end

function Bridge:dropImages()
  for _,image in pairs(self.gpu) do
    if image.release then image:release() end
  end
  self.gpu={}
  if self.cache then self.cache:clear() end
  self.cache=nil
end

-- Espelha somente os dados que a interface ja manipula.
-- Propriedades avancadas e grupos permanecem no documento do motor.
function Bridge:sync(model)
  if model.screen~="editor" or not model.document then return nil end
  if self.modelDocument~=model.document or not self.doc then
    self:finish(true)
    self:dropImages()
    self.doc=Doc.new(model.document.width,model.document.height,"Paint-Lua")
    self.doc.layers={}
    self.byId={}
    self.modelDocument=model.document
  end
    local layers={}
  local selected=1
  local nextMap={}
  for i,entry in ipairs(model.layers) do
    local layer=self.byId[entry.id] or Doc.newLayer(entry.name)
    layer.name=entry.name
    layer.visible=entry.visible~=false
    layer.opacity=clamp(entry.opacity or 100,0,100)
    layer.blend=blends[entry.blending] or "normal"
    layer.clipped=entry.clipping==true
    layers[i]=layer
    nextMap[entry.id]=layer
    if entry.id==model.active_layer_id then selected=i end
  end
  if #layers==0 then
    layers[1]=Doc.newLayer("Camada 1")
  end
  self.doc.layers=layers
  self.doc.sel=selected
  self.byId=nextMap
  if not self.cache then self.cache=Composite.newCache(self.doc,{maxTiles=96}) end
  return self.doc
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

function Bridge:press(model,view,prefs,uiScale,W,H,rx,ry,opacity)
  if self.stroke or not (model.active_tool=="brush" or model.active_tool=="eraser")
    then return false end
  local x,y=rx/uiScale,ry/uiScale
  -- Nao pintar sobre os controles superior e inferior.
  if y<91 or y>H-128 then return false end
  local px,py=self:toCanvas(model,view,prefs,uiScale,W,H,rx,ry)
  if not px or px<0 or py<0 or px>=self.doc.w or py>=self.doc.h then
    return false
  end
  local c=model.color or {0,0,0}
  local opts={
    size=clamp(model.brush_size or 1,0.1,1000),
    alpha=clamp((opacity or 100)/100,0,1),
    hardness=0.85,
    color={clamp(c[1]/255,0,1),clamp(c[2]/255,0,1),clamp(c[3]/255,0,1)},
    eraser=model.active_tool=="eraser",
    pressureSize=false,
    smoothing={mode="exponential",amount=0.30,catchUpOnEnd=true},
  }
  local ok,stroke=pcall(Stroke.new,self.doc,self.doc.layers[self.doc.sel],
    self.doc.history,opts)
  if not ok then self.status=tostring(stroke);return false end
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

-- Desenha sob a transformacao de zoom/rotacao que a interface ja aplicou.
-- GPU apenas para tiles presentes; cache CPU cuida de mascaras/grupos.
function Bridge:draw(x,y)
  if not self.doc or not self.cache then return end
  local seen={}
  for _,layer in ipairs(self.doc.layers) do
    for key in pairs(layer.tiles) do seen[key]=true end
  end
  local g=love.graphics
  g.setBlendMode("alpha")
  g.setColor(1,1,1,1)
  for key in pairs(seen) do
    local tx,ty=Doc.parseKey(key)
    if tx and ty then
      local before=self.cache:stats().recompositions
      local pixels=self.cache:_get(tx,ty)
      local changed=self.cache:stats().recompositions~=before
        or self.doc.history.stroke~=nil
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
  if not self.doc then return nil,"nenhum documento" end
  self:finish(false)
  local ok,err=Project.save(self.doc,self.filename)
  self.status=ok and ("Salvo: "..self.filename) or ("Erro: "..tostring(err))
  return ok,err
end

function Bridge:load(model)
  self:finish(true)
  local ok,doc,err=pcall(Project.load,self.filename)
  if not ok or not doc then
    self.status="Abertura: "..tostring(ok and err or doc)
    return nil,self.status
  end
  self:dropImages()
  self.doc=doc
  self.modelDocument={width=doc.w,height=doc.h}
  model.document=self.modelDocument
  model.screen="editor"
  model.modal=nil
  model.active_panel=nil
  model.layers={}
  self.byId={}
  for i,layer in ipairs(doc.layers) do
    model.layers[i]={
      id=i,name=layer.name,visible=layer.visible,
      opacity=layer.opacity,blending=names[layer.blend] or "Normal",
      clipping=layer.clipped or false,alpha_lock=false,locked=false,
    }
    self.byId[i]=layer
  end
  model.next_layer_id=#doc.layers+1
  model.active_layer_id=doc.sel
  self.cache=Composite.newCache(doc,{maxTiles=96})
  self.status="Aberto: "..self.filename
  return true
end

function Bridge:key(model,key)
  if model.screen~="editor" then return false end
  local k=love.keyboard
  if not (k and k.isDown("lctrl","rctrl","lgui","rgui")) then
    return false
  end
  if key=="s" then self:sync(model);self:save();return true end
  if key=="o" then self:load(model);return true end
  if key=="z" or key=="y" then
    self:finish(false)
    if self.doc then
      local fn=key=="z" and History.undo or History.redo
      local ok,err=pcall(fn,self.doc)
      self.status=ok and (key=="z" and "Desfeito" or "Refeito")
        or tostring(err)
    end
    return true
  end
  return false
end

return Bridge
