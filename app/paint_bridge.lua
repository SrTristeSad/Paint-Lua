-- Paint-Lua: ponte entre o estado visual Ibis-Lua e o documento raster.
-- O núcleo controla pixels, composições e histórico; a UI controla navegação.
local Doc = require("core.doc")
local Stroke = require("core.stroke")
local History = require("core.history")
local Composite = require("core.composite")
local Project = require("core.project")
local Fill = require('core.fill')
local Job = require('core.job')
local Selection = require('core.selection')
local Transform = require('core.transform')
local Layers = require('core.layers')
local Groups = require('core.groups')

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
    stroke=nil,job=nil,jobKind=nil,selectionDrag=nil,transform=nil,transformDrag=nil,
    cache=nil,gpu={},maskMode=nil,maskOwner=nil,
    filename='meu-desenho.npnt',status='Paint-Lua v0.25 pronto'},Bridge)
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
  if self.job then
    local kind=self.jobKind
    Job.cancel(self.job)
    self.job=nil;self.jobKind=nil
    self.status=kind=='wand' and 'Seleção por cor cancelada' or 'Preenchimento cancelado'
  end
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
    self.selectionDrag=nil
    self:cancelTransform()
    self.maskMode,self.maskOwner=nil,nil
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
    if not layer then
      layer=Doc.newLayer(entry.name)
      -- Camada nova no final de um grupo continua como sua filha.
      -- O modelo da UI insere camadas sempre ao fim da lista.
      local prev=nextLayers[i-1]
      if i==#doc.layers+1 and prev then layer.groupId=prev.groupId end
    end
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

-- Controles avançados do painel Layer. Mutacoes de mascara/grupo usam
-- as APIs transacionais do nucleo; nunca reimplementamos rasterizacao na UI.
function Bridge:canEditStructure(model)
  local doc=self:sync(model)
  if not doc then self.status='Abra um documento';return nil end
  if self.stroke or self.job or self.transform or self.selectionDrag then
    self.status='Finalize a operação atual antes de editar camadas';return nil
  end
  return doc
end

function Bridge:activeGroup(model)
  local doc=self.doc
  local layer=doc and doc.layers[doc.sel]
  return layer and layer.groupId and doc.groups[layer.groupId] or nil
end

function Bridge:maskEditMode(model)
  local layer=self.doc and self.doc.layers[self.doc.sel]
  if not layer then self.maskMode,self.maskOwner=nil,nil;return nil end
  if self.maskMode=='layer' then
    if layer==self.maskOwner and layer.mask then return 'layer' end
  elseif self.maskMode=='group' then
    local group=self:activeGroup(model)
    if group and group.id==self.maskOwner and group.mask then return 'group' end
  end
  self.maskMode,self.maskOwner=nil,nil
  return nil
end

function Bridge:editPixels()
  self:finish(false)
  self.maskMode,self.maskOwner=nil,nil
  self.status='Pintando pixels da camada'
  return true
end

function Bridge:editMask(model,kind)
  local doc=self:canEditStructure(model)
  if not doc then return false end
  assert(kind=='layer' or kind=='group','destino de máscara inválido')
  local layer=doc.layers[doc.sel]
  local group=self:activeGroup(model)
  local owner=kind=='layer' and layer or group
  if not owner or not owner.mask then
    self.status='Adicione uma máscara antes de editá-la';return false
  end
  if self.maskMode==kind and self.maskOwner==(kind=='layer' and layer or group.id) then
    return self:editPixels()
  end
  self.maskMode=kind
  self.maskOwner=kind=='layer' and layer or group.id
  if model.active_tool~='brush' and model.active_tool~='eraser' then
    model:set_tool('brush')
  end
  self.status='Máscara '..(kind=='layer' and 'da camada' or 'do grupo')..
    ': Pincel revela (branco); Borracha esconde (preto)'
  return true
end

local function invoke(self,fn,success)
  local ok,result=pcall(fn)
  if not ok then self.status=tostring(result);return false end
  if result==false then return false end
  self.status=success
  return true
end

function Bridge:layerMaskAction(model,action)
  local doc=self:canEditStructure(model)
  if not doc then return false end
  local index=doc.sel
  local mask=doc.layers[index].mask
  if action=='add' then
    if mask then self.status='Esta camada já tem máscara';return false end
    return invoke(self,function() return Layers.addMask(doc,index,1) end,'Máscara da camada criada')
  elseif action=='remove' then
    if not mask then self.status='Camada sem máscara';return false end
    self:editPixels()
    return invoke(self,function() return Layers.removeMask(doc,index) end,'Máscara da camada removida')
  elseif not mask then self.status='Adicione uma máscara primeiro';return false
  elseif action=='enabled' then
    return invoke(self,function() return Layers.setMaskEnabled(doc,index,not mask.enabled) end,
      mask.enabled and 'Máscara desativada' or 'Máscara ativada')
  elseif action=='inverted' then
    return invoke(self,function() return Layers.setMaskInverted(doc,index,not mask.inverted) end,
      mask.inverted and 'Máscara normalizada' or 'Máscara invertida')
  end
  self.status='Comando de máscara desconhecido';return false
end

function Bridge:createGroup(model,pair)
  local doc=self:canEditStructure(model)
  if not doc then return false end
  local last=doc.sel
  local first=pair and last-1 or last
  if first<1 then self.status='Não há camada inferior para agrupar';return false end
  local id=doc.nextGroupId or 1
  return invoke(self,function() return Groups.create(doc,first,last,'Grupo '..id) end,
    pair and 'Duas camadas agrupadas' or 'Grupo criado')
end

function Bridge:ungroup(model)
  local doc=self:canEditStructure(model)
  if not doc then return false end
  local group=self:activeGroup(model)
  if not group then self.status='Camada fora de grupo';return false end
  self:editPixels()
  return invoke(self,function() return Groups.ungroup(doc,group.id) end,'Grupo desfeito')
end

function Bridge:groupAction(model,action)
  local doc=self:canEditStructure(model)
  if not doc then return false end
  local group=self:activeGroup(model)
  if not group then self.status='Selecione uma camada de um grupo';return false end
  local id=group.id
  if action=='visible' then
    return invoke(self,function() return Groups.setVisible(doc,id,not group.visible) end,
      group.visible and 'Grupo oculto' or 'Grupo visível')
  elseif action=='opacityMinus' or action=='opacityPlus' then
    local sign=action=='opacityMinus' and -10 or 10
    local new=clamp(group.opacity+sign,0,100)
    if new==group.opacity then self.status='Opacidade do grupo no limite';return false end
    return invoke(self,function() return Groups.setOpacity(doc,id,new) end,
      ('Opacidade do grupo: %d%%'):format(new))
  elseif action=='addMask' then
    if group.mask then self.status='Grupo já tem máscara';return false end
    return invoke(self,function() return Groups.addMask(doc,id,1) end,'Máscara do grupo criada')
  elseif action=='removeMask' then
    if not group.mask then self.status='Grupo sem máscara';return false end
    self:editPixels()
    return invoke(self,function() return Groups.removeMask(doc,id) end,'Máscara do grupo removida')
  end
  if not group.mask then self.status='Adicione uma máscara ao grupo';return false end
  local m=group.mask
  if action=='maskEnabled' then
    return invoke(self,function() return Groups.setMaskEnabled(doc,id,not m.enabled) end,
      m.enabled and 'Máscara do grupo desativada' or 'Máscara do grupo ativada')
  elseif action=='maskInverted' then
    return invoke(self,function() return Groups.setMaskInverted(doc,id,not m.inverted) end,
      m.inverted and 'Máscara do grupo normalizada' or 'Máscara do grupo invertida')
  end
  self.status='Comando de grupo desconhecido';return false
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
  self.job=job;self.jobKind='fill'
  self.status='Preenchendo...'
  return true
end

function Bridge:press(model,view,prefs,uiScale,W,H,rx,ry,opacity)
  if self.stroke or self.job or self.transform then return false end
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
  local maskMode=self:maskEditMode(model)
  local opts={
    size=clamp(model.brush_size or 1,0.1,1000),
    alpha=clamp((opacity or 100)/100,0,1), hardness=0.85,
    color=color(model), eraser=model.active_tool=='eraser',
    alphaLock=entry.alpha_lock==true,
    selection=self.doc.selection, pressureSize=false,
    smoothing={mode='exponential',amount=0.30,catchUpOnEnd=true},
  }
  local ok,stroke
  if maskMode then
    opts.alphaLock=nil
    opts.color={1,1,1}
    opts.maskValue=entry and (model.active_tool=='eraser' and 0 or 1) or 1
    if maskMode=='layer' then
      ok,stroke=pcall(Stroke.newMask,self.doc,self.doc.layers[self.doc.sel],
        self.doc.history,opts)
    else
      local group=self:activeGroup(model)
      ok,stroke=pcall(Stroke.newGroupMask,self.doc,group.id,self.doc.history,opts)
    end
  else
    ok,stroke=pcall(Stroke.new,self.doc,self.doc.layers[self.doc.sel],
      self.doc.history,opts)
  end
  if not ok then self.status='Pincel: '..tostring(stroke);return false end
  self.stroke=stroke
  self:move(model,view,prefs,uiScale,W,H,rx,ry)
  return true
end


-- Selecao eh um estado do documento e participa do historico estrutural.
-- Objetos complexos ficam imutaveis depois de aplicados.
function Bridge:applySelection(selection)
  if not self.doc or self.stroke or self.job or self.transform then return false end
  if selection then Selection.validate(self.doc,selection) end
  local previous=self.doc.selection
  if previous==selection then return false end
  if previous==nil and selection==nil then return false end
  History.recordStructure(self.doc)
  self.doc.selection=selection
  if selection then
    self.status=selection.kind=='polygon' and 'Laço selecionado'
      or (selection.kind=='wand' and 'Área selecionada por cor' or 'Retângulo selecionado')
  else self.status='Seleção removida' end
  return true
end

function Bridge:selectAll(model)
  local doc=self:sync(model)
  if not doc then return false end
  return self:applySelection(Selection.rect(doc,0,0,doc.w-1,doc.h-1))
end

function Bridge:clearSelection()
  self.selectionDrag=nil
  return self:applySelection(nil)
end

function Bridge:beginSelection(model,view,prefs,uiScale,W,H,rx,ry)
  if self.stroke or self.job or self.transform then return false end
  local tool=model.active_tool
  if tool~='selection_rect' and tool~='lasso' and tool~='magic_wand' then
    return false
  end
  local px,py=self:point(model,view,prefs,uiScale,W,H,rx,ry)
  if not px then return false end
  if tool=='magic_wand' then
    local job=Selection.newWandJob(self.doc,self.doc.layers[self.doc.sel],px,py,0.08,
      {yieldEvery=512,maxPixels=2000000})
    self.job=job;self.jobKind='wand'
    self.status='Selecionando área por cor...'
    return true
  end
  self.selectionDrag={kind=tool,startX=px,startY=py,x=px,y=py,
    points=tool=='lasso' and {{px,py}} or nil}
  return true
end

function Bridge:moveSelection(model,view,prefs,uiScale,W,H,rx,ry)
  local drag=self.selectionDrag
  if not drag then return false end
  local px,py=self:toCanvas(model,view,prefs,uiScale,W,H,rx,ry)
  if not px then return false end
  px=clamp(px,0,self.doc.w);py=clamp(py,0,self.doc.h)
  drag.x,drag.y=px,py
  if drag.points and #drag.points<4096 then
    local prev=drag.points[#drag.points]
    local dx,dy=px-prev[1],py-prev[2]
    if dx*dx+dy*dy>=2 then drag.points[#drag.points+1]={px,py} end
  end
  return true
end

function Bridge:finishSelection(model,view,prefs,uiScale,W,H,rx,ry)
  local drag=self.selectionDrag
  if not drag then return false end
  if rx then self:moveSelection(model,view,prefs,uiScale,W,H,rx,ry) end
  self.selectionDrag=nil
  local selection
  if drag.kind=='selection_rect' then
    selection=Selection.rect(self.doc,drag.startX,drag.startY,drag.x,drag.y)
  elseif drag.points and #drag.points>=3 then
    local ok,value=pcall(Selection.polygon,self.doc,drag.points)
    if not ok then self.status='Laço inválido: '..tostring(value);return false end
    selection=value
  end
  if not selection then self.status='Seleção vazia';return false end
  return self:applySelection(selection)
end

-- A prévia retém o ImageData da camada ativa; o documento só muda ao aplicar.
function Bridge:startTransform(model)
  if self.transform then return true end
  local doc=self:sync(model)
  if not doc or self.stroke or self.job or self.selectionDrag then
    self.status='Conclua a operação anterior';return false
  end
  if not doc.selection then
    self.status='Selecione uma área antes de transformar (Ctrl+A seleciona tudo)'
    return false
  end
  local entry=model:active_layer()
  if entry.locked then self.status='Camada bloqueada';return false end
  local ok,session=pcall(Transform.begin,doc,doc.layers[doc.sel])
  if not ok then self.status='Transformação: '..tostring(session);return false end
  self.transform=session
  self.status='Prévia: arraste, ajuste ângulo/escala e confirme'
  return true
end

function Bridge:adjustTransform(dx,dy,scale,angle)
  local t=self.transform
  if not t then return false end
  local ok,err=pcall(Transform.set,t,t.dx+(dx or 0),t.dy+(dy or 0),
    t.scaleX*(scale or 1),t.scaleY*(scale or 1),t.angle+(angle or 0))
  if not ok then self.status='Ajuste inválido: '..tostring(err);return false end
  return true
end

function Bridge:beginTransformDrag(model,view,prefs,uiScale,W,H,rx,ry)
  if model.active_tool~='transform' then return false end
  if not self:startTransform(model) then return false end
  local px,py=self:point(model,view,prefs,uiScale,W,H,rx,ry)
  if not px then return false end
  local b=Transform.bounds(self.transform)
  if px<b.x or py<b.y or px>b.x+b.w or py>b.y+b.h then
    self.status='Clique dentro dos limites da seleção para mover'
    return false
  end
  self.transformDrag={x=px,y=py,dx=self.transform.dx,dy=self.transform.dy}
  return true
end

function Bridge:moveTransform(model,view,prefs,uiScale,W,H,rx,ry)
  if not self.transform or not self.transformDrag then return false end
  local px,py=self:toCanvas(model,view,prefs,uiScale,W,H,rx,ry)
  if not px then return false end
  local d=self.transformDrag
  local t=self.transform
  local ok,err=pcall(Transform.set,t,d.dx+px-d.x,d.dy+py-d.y,
    t.scaleX,t.scaleY,t.angle)
  if not ok then self.status=tostring(err);return false end
  return true
end

function Bridge:finishTransformDrag()
  self.transformDrag=nil
end

function Bridge:cancelTransform()
  self.transformDrag=nil
  if not self.transform then return false end
  Transform.cancel(self.transform)
  self.transform=nil
  self.status='Transformação cancelada; pixels intactos'
  return true
end

function Bridge:applyTransform(model)
  if not self.transform then return false end
  local n,err=Transform.commit(self.transform)
  if n==nil then self.status='Transformação: '..tostring(err);return false end
  self.transform=nil
  self.transformDrag=nil
  self.status=('Transformação aplicada: %d pixels'):format(n)
  return true
end

function Bridge:transformKey(model,key)
  if not self.transform then return false end
  if key=='escape' then self:cancelTransform();return true end
  if key=='return' or key=='kpenter' then self:applyTransform(model);return true end
  if key=='left' then self:adjustTransform(-1,0);return true end
  if key=='right' then self:adjustTransform(1,0);return true end
  if key=='up' then self:adjustTransform(0,-1);return true end
  if key=='down' then self:adjustTransform(0,1);return true end
  if key=='q' then self:adjustTransform(0,0,1,-math.pi/12);return true end
  if key=='r' then self:adjustTransform(0,0,1,math.pi/12);return true end
  if key=='=' or key=='kp+' then self:adjustTransform(0,0,1.1);return true end
  if key=='-' or key=='kp-' then self:adjustTransform(0,0,1/1.1);return true end
  -- A prévia precisa ser confirmada antes de qualquer outro comando.
  if key=='b' or key=='e' then
    self.status='Confirme ou cancele a transformação antes de trocar de ferramenta'
    return true
  end
  return false
end

-- A UI fornece transformacao/zoom antes da chamada; as coordenadas locais
-- da borda são iguais às usadas por Bridge:draw para os tiles.
function Bridge:drawSelection(x,y,canvasScale)
  if not self.doc then return end
  local sel=self.doc.selection
  local drag=self.selectionDrag
  if not sel and not drag then return end
  local g=love.graphics
  g.setLineWidth(1/math.max(canvasScale,0.01))
  g.setColor(0.96,0.30,0.20,0.95)
  if self.transform then
    Transform.drawPreview(self.transform,x,y)
  end
  if sel then
    if sel.kind=='polygon' then
      local p=sel.points
      for i=1,#p do
        local a,b=p[i],p[i%#p+1]
        g.line(x+a[1],y+a[2],x+b[1],y+b[2])
      end
    elseif sel.kind=='wand' then
      if not self.selectionOutline or self.selectionOutline.selection~=sel then
        self.selectionOutline={selection=sel,segments=Selection.outline(sel)}
      end
      local segments=self.selectionOutline.segments
      if segments then
        for _,edge in ipairs(segments) do
          g.line(x+edge[1],y+edge[2],x+edge[3],y+edge[4])
        end
      else
        -- Fallback para áreas imensas: só a moldura; o interior continua
        -- sendo a máscara raster exata usada pelo pincel e pelo balde.
        g.rectangle('line',x+sel.x,y+sel.y,sel.w,sel.h)
      end
    else
      g.rectangle('line',x+sel.x,y+sel.y,sel.w,sel.h)
    end
  end
  if drag then
    g.setColor(0.17,0.62,0.95,0.98)
    if drag.kind=='selection_rect' then
      local ax,ay,bx,by=drag.startX,drag.startY,drag.x,drag.y
      g.rectangle('line',x+math.min(ax,bx),y+math.min(ay,by),
        math.abs(bx-ax),math.abs(by-ay))
    elseif drag.points then
      local p=drag.points
      for i=2,#p do
        g.line(x+p[i-1][1],y+p[i-1][2],x+p[i][1],y+p[i][2])
      end
      local a=p[#p]
      g.line(x+a[1],y+a[2],x+p[1][1],y+p[1][2])
    end
  end
  g.setColor(1,1,1,1)
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
  local kind=self.jobKind
  local ok,done,value=pcall(Job.step,job,0.004,love.timer and love.timer.getTime or os.clock)
  if not ok then
    self.job=nil;self.jobKind=nil
    self.status=(kind=='wand' and 'Varinha: ' or 'Balde: ')..tostring(done)
    return self.status
  elseif done then
    self.job=nil;self.jobKind=nil
    if kind=='wand' then
      if value then self:applySelection(value) else self.status='Seleção vazia' end
    else
      self.status='Preenchimento: '..tostring(value or 0)..' pixels'
    end
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
  if self.transform then return nil,'confirme ou cancele a transformação primeiro' end
  if not self.doc then return nil,'nenhum documento' end
  if self.job then return nil,'operação em andamento' end
  if self.selectionDrag then return nil,'finalize a seleção antes de salvar' end
  self:finish(false)
  local ok,err=Project.save(self.doc,self.filename)
  self.status=ok and ('Salvo: '..self.filename) or ('Erro: '..tostring(err))
  return ok,err
end

function Bridge:load(model)
  self:cancelTransform()
  self:finish(true)
  self:cancelJob()
  self.selectionDrag=nil
  self.maskMode,self.maskOwner=nil,nil
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
  if self.transform then self.status='Confirme ou cancele a transformação antes do histórico';return false end
  if self.job then
    self.status='Finalize ou cancele o trabalho antes do histórico'
    return false
  end
  self:finish(false)
  self.selectionDrag=nil
  self:sync(model)
  if not self.doc then return false end
  local fn=redo and History.redo or History.undo
  local ok,changed=pcall(fn,self.doc)
  self.status=not ok and tostring(changed) or
    (changed and (redo and 'Refeito' or 'Desfeito') or 'Nada para alterar')
  if ok and changed then
    self:refreshModel(model)
    self:maskEditMode(model) -- undo pode excluir a máscara ou o grupo ativo
  end
  return ok and changed or false
end

function Bridge:key(model,key)
  if model.screen~='editor' then return false end
  local k=love.keyboard
  if not (k and k.isDown('lctrl','rctrl','lgui','rgui')) then return false end
  if key=='a' then self:selectAll(model);return true end
  if key=='d' then self:clearSelection();return true end
  if key=='s' then
    self:sync(model)
    local ok,err=self:save()
    if not ok then self.status=tostring(err) end
    return true
  end
  if key=='o' then self:load(model);return true end
  if key=='z' then self:historyStep(model,false);return true end
  if key=='y' then self:historyStep(model,true);return true end
  return false
end

return Bridge
