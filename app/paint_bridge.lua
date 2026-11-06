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
local SelectionAnts = require('app.selection_ants')
local Transform = require('core.transform')
local Layers = require('core.layers')
local Groups = require('core.groups')
local Thumbnail = require('core.thumbnail')
local GalleryStorage = require('src.gallery_storage')
local PNGExport=require('src.png_export')
local PNGImport=require('src.png_import')

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
    stroke=nil,job=nil,jobKind=nil,selectionDrag=nil,selectionMode='replace',jobSelectionMode=nil,
    transform=nil,transformDrag=nil,
    pngPreview=nil,pngDrag=nil,
    cache=nil,gpu={},ants={},selectionAnimated=true,thumbCache=setmetatable({}, {__mode='k'}),
    thumbRenders=0,maskMode=nil,maskOwner=nil,
    artworkId=nil,filename='meu-desenho.npnt',status='Paint-Lua v0.39 pronto'},Bridge)
end

-- Preferência da interface, não do documento: não entra no histórico NPNT.
-- Ao desativar, libera a GPU e volta ao traço estático da v0.37.
function Bridge:setSelectionAnimation(enabled)
  assert(type(enabled)=='boolean','animação de seleção deve ser booleana')
  if self.selectionAnimated==enabled then return false end
  self.selectionAnimated=enabled
  if not enabled then SelectionAnts.release(self.ants) end
  return true
end

function Bridge:dropImages()
  SelectionAnts.release(self.ants)
  for _,image in pairs(self.gpu) do
    if image.release then image:release() end
  end
  self.gpu={}
  for _,entry in pairs(self.thumbCache or {}) do
    for _,thumb in pairs(entry) do
      if thumb.image and thumb.image.release then thumb.image:release() end
    end
  end
  self.thumbCache=setmetatable({}, {__mode='k'})
  -- O contorno incremental retém a seleção e os tiles do documento anterior.
  -- O cache deve morrer também quando a nova obra começa sem seleção.
  self.selectionOutline=nil
  if self.cache then self.cache:clear() end
  self.cache=nil
end

function Bridge:cancelJob()
  if self.job then
    local kind=self.jobKind
    Job.cancel(self.job)
    self.job=nil;self.jobKind=nil;self.jobSelectionMode=nil
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
    self.selectionMode='replace'
    self:cancelTransform()
    self:cancelPNGImport()
    self.maskMode,self.maskOwner=nil,nil
    self.artworkId=nil
    self.filename='meu-desenho.npnt'
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
  -- Opacidade e camada ativa são mudanças leves (sem snapshot por frame),
  -- mas também precisam aguardar o fim de um preenchimento cooperativo.
  local pending=changed
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
    if layer.opacity~=clamp(entry.opacity or 100,0,100) then pending=true end
    if doc.layers[i]~=layer or layer.name~=entry.name
      or layer.visible~=(entry.visible~=false)
      or layer.blend~=(blends[entry.blending] or 'normal')
      or (layer.clipped or false)~=(entry.clipping==true) then
      changed=true
      pending=true
    end
    if entry.id==model.active_layer_id then selected=i end
  end
  if doc.sel~=selected then pending=true end
  if #nextLayers==0 then
    -- Estado defensivo: o motor exige pelo menos uma camada editável.
    nextLayers[1]=Doc.newLayer('Camada 1')
    changed=true
    pending=true
  end
  if pending and not fresh then
    -- Alterações da UI ficam pendentes enquanto uma prévia ou seleção
    -- em arraste utiliza a camada original; nenhuma propriedade ou
    -- snapshot pode vazar para a operação ainda não confirmada.
    if self.transform or self.pngPreview or self.selectionDrag then
      self.status='Confirme ou cancele a prévia/seleção antes de alterar camadas'
      return nil
    end
    -- Também adiar alterações durante o traço da própria ponte.
    -- Antes, opacidade/troca de camada atravessavam o gesto ativo e uma
    -- alteração estrutural podia finalizá-lo sem o usuário soltar o mouse.
    if self.stroke or doc.history._fillLock or doc.history.stroke
      or self.job then
      self.status='Conclua a operação antes de alterar camadas'
      return nil
    end
  end
  if changed and not fresh then
    self:finish(false)
    History.recordStructure(doc)
  end
  doc.layers=nextLayers
  doc.sel=selected
  self.byId=nextMap
  for i,entry in ipairs(model.layers) do
    local layer=doc.layers[i]
    self.uiByLayer[layer]=entry
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

-- Renderiza apenas 40x40 pixels da fonte real (e não quadriculados falsos).
-- A cache usa identidade + revisões, inclusive de máscaras e undo/redo.
function Bridge:thumbnail(model, layerId, kind, width, height)
  if not self.doc then return nil end
  width,height=width or 40,height or 40
  kind=kind or 'layer'
  local layer=self.byId[layerId]
  if not layer then return nil end
  local owner=layer
  if kind=='group_mask' then
    owner=layer.groupId and self.doc.groups[layer.groupId]
    kind='mask'
  end
  if not owner or (kind=='mask' and not owner.mask) then return nil end
  local key=kind..':'..width..'x'..height
  local records=self.thumbCache[owner]
  if not records then records={};self.thumbCache[owner]=records end
  local sig=Thumbnail.signature(self.doc,owner,kind,width,height)
  local rec=records[key]
  if rec and Thumbnail.same(rec.signature,sig) then return rec.image end
  local pixels=Thumbnail.render(self.doc,owner,kind,width,height)
  local image=rec and rec.image
  if image and image.replacePixels then
    image:replacePixels(pixels)
  else
    image=love.graphics.newImage(pixels)
    if image.setFilter then image:setFilter('linear','linear') end
  end
  records[key]={image=image,signature=sig}
  self.thumbRenders=self.thumbRenders+1
  return image
end

-- Reordenar é uma única operação de histórico. IDs da interface continuam
-- ligados às mesmas ImageData, inclusive após desfazer/refazer.
function Bridge:reorderLayer(model, sourceId, targetId)
  local doc=self:canEditStructure(model)
  if not doc then return false end
  local from,to
  for i,entry in ipairs(model.layers) do
    if entry.id==sourceId then from=i end
    if entry.id==targetId then to=i end
  end
  if not from or not to then self.status='Camada para mover não encontrada';return false end
  local ok,changed,err=pcall(Layers.move,doc,from,to)
  if not ok or not changed then
    self.status=ok and ('Movimento recusado: '..tostring(err)) or
      ('Movimento inválido: '..tostring(changed))
    return false
  end
  self:refreshModel(model)
  self.status='Camada movida (Ctrl+Z desfaz)'
  return true
end

function Bridge:moveLayer(model,direction)
  assert(direction==1 or direction==-1,'direção de camada inválida')
  local i
  for n,entry in ipairs(model.layers) do
    if entry.id==model.active_layer_id then i=n;break end
  end
  if not i or not model.layers[i+direction] then
    self.status='Camada no limite da pilha';return false
  end
  return self:reorderLayer(model,model.active_layer_id,model.layers[i+direction].id)
end

function Bridge:moveGroup(model,direction)
  local doc=self:canEditStructure(model)
  if not doc then return false end
  local group=self:activeGroup(model)
  if not group then self.status='Selecione uma camada do grupo';return false end
  local ok,changed,err=pcall(Groups.move,doc,group.id,direction)
  if not ok or not changed then
    self.status=ok and ('Movimento recusado: '..tostring(err)) or
      ('Movimento inválido: '..tostring(changed))
    return false
  end
  self:refreshModel(model)
  self.status='Grupo movido com seus membros (Ctrl+Z desfaz)'
  return true
end

-- Controles avançados do painel Layer. Mutacoes de mascara/grupo usam
-- as APIs transacionais do nucleo; nunca reimplementamos rasterizacao na UI.
function Bridge:canEditStructure(model)
  local doc=self:sync(model)
  if not doc then
    -- sync pode recusar uma mudança pendente sem fechar o documento:
    -- preservar a razão real do bloqueio para a interface.
    if model.screen~='editor' or not model.document or not self.doc then
      self.status='Abra um documento'
    end
    return nil
  end
  if self.stroke or self.job or self.transform or self.selectionDrag
    or self.pngPreview or doc.history.stroke or doc.history._fillLock then
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
  if not self:sync(model) then
    -- Alterações do painel podem ficar pendentes durante um gesto. Nesse
    -- caso, continuar convertendo o cursor na geometria da obra original:
    -- bloquear a sincronização não deve congelar o pincel, laço ou prévia.
    -- Nunca usar o documento anterior se o modelo/tela já mudou.
    if not (self.doc and self.modelDocument==model.document
      and model.screen=='editor' and
      (self.stroke or self.selectionDrag or self.transform or self.pngPreview)
      and not self.doc.history._fillLock) then return nil end
  end
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

-- Trocar de ferramenta no meio de um arraste não autoriza uma segunda
-- operação. Bloquear também jobs/gestos iniciados diretamente no motor:
-- o conta-gotas nunca deve amostrar os pixels ainda provisórios do balde.
local function canUsePaintTool(self,model,requireDocument)
  local h=self.doc and self.doc.history
  if self.stroke or self.job or self.transform or self.pngPreview
    or self.selectionDrag or (h and (h._fillLock or h.stroke)) then
    self.status='Conclua ou cancele a operação antes de pintar ou coletar cor'
    return false
  end
  if requireDocument and (not self.doc or not model or
    model.screen~='editor' or model.document~=self.modelDocument) then
    self.status='Abra a obra correta antes de usar a ferramenta'
    return false
  end
  return true
end

function Bridge:pick(model,px,py)
  if not canUsePaintTool(self,model,true) then return false end
  local img=Composite.flattenRegion(self.doc,math.floor(px),math.floor(py),1,1)
  local r,g,b,a=img:getPixel(0,0)
  if a<=0 then self.status='Conta-gotas: pixel transparente';return false end
  model:set_color(byte(r),byte(g),byte(b))
  self.status='Cor coletada do desenho'
  return true
end

function Bridge:bucket(model,px,py,opacity)
  if self.job then self.status='Balde ocupado';return false end
  if not canUsePaintTool(self,model,true) then return false end
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
  if model.active_tool~='brush' and model.active_tool~='eraser'
    and model.active_tool~='bucket' and model.active_tool~='eyedropper' then
    return false
  end
  -- Antes até de calcular o ponto, impedir intercalar pintura ou amostragem
  -- com seleção, prévias e jobs que ainda detêm o histórico.
  if not canUsePaintTool(self,model,false) then return false end
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
  if not self.doc then return false end
  -- Todas as vias de alteração (Ctrl+A, ações do painel, inversão,
  -- combinação e desmarcar) compartilham a mesma proteção.
  -- Uma seleção pendente, prévia de PNG ou pincelada não pode criar
  -- um snapshot estrutural concorrente e sobrescrever seu estado.
  if self.stroke or self.job or self.transform or self.selectionDrag
    or self.pngPreview or self.doc.history.stroke
    or self.doc.history._fillLock then
    self.status='Conclua a operação atual antes de alterar a seleção'
    return false
  end
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


-- O modo escolhido vale para o próximo gesto e não altera o documento.
function Bridge:setSelectionMode(mode)
  if mode~='replace' and mode~='add' and mode~='subtract'
    and mode~='intersect' then
    self.status='Modo de seleção desconhecido'
    return false
  end
  self.selectionMode=mode
  local names={replace='Nova',add='Adicionar',subtract='Subtrair',
    intersect='Interseção'}
  self.status='Próxima seleção: '..names[mode]
  return true
end

-- Combina o novo gesto com a seleção anterior. Um snapshot de histórico
-- só é registrado depois que o cálculo terminou sem erros.
function Bridge:combineSelection(selection,mode)
  if not self.doc or self.stroke or self.job or self.transform or self.selectionDrag
    or self.pngPreview or self.doc.history.stroke or
    self.doc.history._fillLock then
    self.status='Conclua a operação atual antes de selecionar'
    return false
  end
  local chosen=mode or self.selectionMode or 'replace'
  if chosen=='replace' then return self:applySelection(selection) end
  local ok,result,err=pcall(Selection.combine,self.doc,self.doc.selection,
    selection,chosen)
  if not ok then self.status='Combinação: '..tostring(result);return false end
  if err then self.status=err;return false end
  local changed=self:applySelection(result)
  if changed then
    local label={add='Área adicionada',subtract='Área subtraída',
      intersect='Interseção aplicada'}
    self.status=label[chosen]
  end
  return changed
end

function Bridge:selectAll(model)
  local doc=self:sync(model)
  if not doc then return false end
  return self:applySelection(Selection.rect(doc,0,0,doc.w-1,doc.h-1))
end


-- Inverte a seleção como uma única operação estrutural (sem tocar RGBA).
function Bridge:invertSelection(model)
  local doc=self:sync(model)
  if not doc then self.status='Abra um documento';return false end
  if self.stroke or self.job or self.transform or self.selectionDrag
    or self.pngPreview or doc.history.stroke or doc.history._fillLock then
    self.status='Conclua a operação atual antes de inverter a seleção'
    return false
  end
  local selection,err=Selection.invert(doc,doc.selection)
  if err then self.status=err;return false end
  local changed=self:applySelection(selection)
  if changed then self.status='Seleção invertida' end
  return changed
end

function Bridge:clearSelection()
  -- Ctrl+D/desmarcar não é um comando de cancelamento de arraste.
  -- Preservar o gesto para applySelection recusar uma mudança concorrente.
  -- Escape é o comando explícito de cancelar o arraste.
  return self:applySelection(nil)
end

function Bridge:beginSelection(model,view,prefs,uiScale,W,H,rx,ry)
  if self.stroke or self.job or self.transform or self.selectionDrag
    or self.pngPreview then return false end
  -- A varinha lê pixels do documento. Não iniciar um trabalho de seleção
  -- sobre pixels temporários de um balde externo à ponte.
  if not self.doc or self.doc.history._fillLock or self.doc.history.stroke then
    self.status='Finalize a pincelada ou preenchimento antes de selecionar'
    return false
  end
  local tool=model.active_tool
  if tool~='selection_rect' and tool~='lasso' and tool~='magic_wand' then
    return false
  end
  local px,py=self:point(model,view,prefs,uiScale,W,H,rx,ry)
  if not px then return false end
  if tool=='magic_wand' then
    local job=Selection.newWandJob(self.doc,self.doc.layers[self.doc.sel],px,py,0.08,
      {yieldEvery=512,maxPixels=2000000})
    self.job=job;self.jobKind='wand';self.jobSelectionMode=self.selectionMode
    self.status='Selecionando área por cor...'
    return true
  end
  self.selectionDrag={kind=tool,mode=self.selectionMode,
    startX=px,startY=py,x=px,y=py,
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
  -- Um balde ou gesto externo pode adquirir o lock APÓS beginSelection.
  -- Não descartar o arraste antes de saber se é possível confirmá-lo:
  -- a recusa precisa preservar pontos, seleção anterior e undo/redo.
  local doc=self.doc
  if not doc or self.stroke or self.job or self.transform or self.pngPreview
    or doc.history._fillLock or doc.history.stroke then
    self.status='Conclua a operação atual antes de confirmar a seleção'
    return false
  end
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
  return self:combineSelection(selection,drag.mode)
end

-- A prévia retém o ImageData da camada ativa; o documento só muda ao aplicar.
function Bridge:startTransform(model)
  if self.transform then return true end
  local doc=self:sync(model)
  if not doc or self.stroke or self.job or self.selectionDrag or self.pngPreview then
    self.status='Conclua a operação anterior';return false
  end
  if not doc.selection then
    self.status='Selecione uma área antes de transformar (Ctrl+A seleciona tudo)'
    return false
  end
  local entry=model:active_layer()
  if entry.locked then self.status='Camada bloqueada';return false end
  local ok,session=pcall(Transform.begin,doc,doc.layers[doc.sel],nil,
    {interpolation='smooth'})
  if not ok then self.status='Transformação: '..tostring(session);return false end
  self.transform=session
  self.status='Prévia suave: arraste, ajuste ângulo/escala e confirme'
  return true
end

function Bridge:setTransformInterpolation(mode)
  if not self.transform then return false end
  local ok,err=pcall(Transform.setInterpolation,self.transform,mode)
  if not ok then self.status='Filtro: '..tostring(err);return false end
  self.status=mode=='smooth' and 'Transformação: Suave' or 'Transformação: Pixelado'
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

-- Escala visual para detectar alças sempre com o mesmo raio em tela,
-- mesmo quando o usuário aplica zoom, pan ou rotação no canvas.
function Bridge:transformCanvasScale(model,view,prefs,W,H)
  local left=prefs.tool_position=='left' and 62 or 0
  local right=prefs.tool_position=='right' and 75 or 34
  local aw,ah=W-left-right,H-160
  if aw<=0 or ah<=0 or not self.doc then return nil end
  return math.min(aw/self.doc.w,ah/self.doc.h,1.1)*view.zoom
end

local oppositeCorner={nw='se',ne='sw',se='nw',sw='ne'}
local transformCorners={'nw','ne','se','sw'}
local function dragAngle(y,x)
  return math.atan2 and math.atan2(y,x) or math.atan(y,x)
end
function Bridge:beginTransformDrag(model,view,prefs,uiScale,W,H,rx,ry)
  if model.active_tool~='transform' then return false end
  if not self:startTransform(model) then return false end
  -- Não usar :point(): alças de rotação podem estar fora do documento.
  local px,py=self:toCanvas(model,view,prefs,uiScale,W,H,rx,ry)
  if not px then return false end
  local t=self.transform
  local visualScale=self:transformCanvasScale(model,view,prefs,W,H)
  if not visualScale or visualScale<=0 then return false end
  local h=Transform.handles(t,visualScale)
  local radius=12/visualScale
  local closest,best=nil,radius*radius
  -- Um único pixel selecionado ainda precisa poder ser ARRASTADO.
  -- Quando as alças se sobrepõem (<28px de tela por lado), os botões
  -- antigos ampliam a seleção até existir espaço para os controles.
  local enoughRoom=math.min(t.w*math.abs(t.scaleX),
    t.h*math.abs(t.scaleY))*visualScale>=28
  if enoughRoom then
    for _,name in ipairs({'rotate','nw','ne','se','sw'}) do
      local dx,dy=px-h[name].x,py-h[name].y
      local sq=dx*dx+dy*dy
      if sq<best then closest,best=name,sq end
    end
  end
  local drag={x=px,y=py,dx=t.dx,dy=t.dy,
    scaleX=t.scaleX,scaleY=t.scaleY,angle=t.angle}
  if closest=='rotate' then
    local pivot=h.center
    drag.kind='rotate'
    drag.pivotX,drag.pivotY=pivot.x,pivot.y
    drag.startAngle=dragAngle(py-pivot.y,px-pivot.x)
    self.status='Girando seleção pela alça superior'
  elseif closest then
    drag.kind='scale'
    drag.corner=closest
    local anchor=h[oppositeCorner[closest]]
    local corner=h[closest]
    drag.anchorX,drag.anchorY=anchor.x,anchor.y
    drag.cornerX,drag.cornerY=corner.x,corner.y
    drag.vx,drag.vy=corner.x-anchor.x,corner.y-anchor.y
    self.status='Redimensionando seleção; proporção preservada'
  else
    -- Hit-test na forma girada, não no retângulo envolvente.
    local sx,sy=Transform.inverse(t,px,py)
    if sx<t.x or sx>t.x+t.w or sy<t.y or sy>t.y+t.h then
      self.status='Arraste dentro da seleção ou pelas alças'
      return false
    end
    drag.kind='move'
    self.status='Movendo seleção'
  end
  self.transformDrag=drag
  return true
end

function Bridge:moveTransform(model,view,prefs,uiScale,W,H,rx,ry)
  if not self.transform or not self.transformDrag then return false end
  local px,py=self:toCanvas(model,view,prefs,uiScale,W,H,rx,ry)
  if not px then return false end
  local d,t=self.transformDrag,self.transform
  local dx,dy,sx,sy,angle=d.dx,d.dy,d.scaleX,d.scaleY,d.angle
  if d.kind=='move' then
    dx,dy=d.dx+px-d.x,d.dy+py-d.y
  elseif d.kind=='rotate' then
    local current=dragAngle(py-d.pivotY,px-d.pivotX)
    local delta=current-d.startAngle
    -- Evita saltos ao atravessar -180°/+180°.
    delta=dragAngle(math.sin(delta),math.cos(delta))
    angle=d.angle+delta
  elseif d.kind=='scale' then
    -- O canto oposto é a âncora fixa. Movimento proporcional da diagonal
    -- permite redimensionar com mouse sem inverter a imagem.
    local vx,vy=d.vx,d.vy
    local denominator=vx*vx+vy*vy
    if denominator<1e-12 then return false end
    local tx,ty=d.cornerX+(px-d.x)-d.anchorX,
      d.cornerY+(py-d.y)-d.anchorY
    local factor=(tx*vx+ty*vy)/denominator
    local minimum=math.max(0.125/math.abs(d.scaleX),0.125/math.abs(d.scaleY))
    local maximum=math.min(8/math.abs(d.scaleX),8/math.abs(d.scaleY))
    factor=clamp(factor,minimum,maximum)
    sx,sy=d.scaleX*factor,d.scaleY*factor
    -- Refaz a posição do canto oposto sem alterar o ângulo original.
    local cx,cy=t.x+t.w/2,t.y+t.h/2
    local ax,ay
    if d.corner=='nw' then ax,ay=t.x+t.w,t.y+t.h
    elseif d.corner=='ne' then ax,ay=t.x,t.y+t.h
    elseif d.corner=='se' then ax,ay=t.x,t.y
    else ax,ay=t.x+t.w,t.y end
    local ux,uy=(ax-cx)*sx,(ay-cy)*sy
    local translatedX=cx+ux*math.cos(angle)-uy*math.sin(angle)
    local translatedY=cy+ux*math.sin(angle)+uy*math.cos(angle)
    dx,dy=d.anchorX-translatedX,d.anchorY-translatedY
  else return false end
  local ok,err=pcall(Transform.set,t,dx,dy,sx,sy,angle)
  if not ok then self.status='Ajuste inválido: '..tostring(err);return false end
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
function Bridge:drawSelection(x,y,canvasScale,seconds)
  if not self.doc then return end
  local sel=self.doc.selection
  local drag=self.selectionDrag
  if not sel and not drag then return end
  -- A ausência de tiles numa máscara positiva significa ZERO pixels
  -- selecionados, não ausência de seleção. Não inicializar GPU à toa.
  local emptyWand=sel and sel.kind=='wand' and not sel.mask.inverted
    and next(sel.mask.tiles)==nil
  if emptyWand and not drag and not self.transform then return end
  local g=love.graphics
  g.setLineWidth(1/math.max(canvasScale,0.01))
  g.setColor(0.96,0.30,0.20,0.95)
  if self.transform then
    Transform.drawPreview(self.transform,x,y,canvasScale)
  end
  if sel and not self.transform and not emptyWand then
    local now=seconds
    if now==nil then
      now=love.timer and love.timer.getTime() or os.clock()
    end
    local function drawOutline(animated)
      if animated then g.setColor(1,1,1,0.95)
      else g.setColor(0.96,0.30,0.20,0.95) end
      -- A geometria é sempre a mesma da v0.37. Apenas as cores dos pixels
      -- de linha alternam na tela; nunca se inventam segmentos ou bboxes.
      if sel.kind=='polygon' then
        local p=sel.points
        for i=1,#p do
          local a,b=p[i],p[i%#p+1]
          g.line(x+a[1],y+a[2],x+b[1],y+b[2])
        end
      elseif sel.kind=='wand' then
        if not self.selectionOutline or self.selectionOutline.selection~=sel then
          local simple=sel.w*sel.h<=16384 and
            Selection.outline(sel,16384,8192) or nil
          self.selectionOutline={selection=sel,segments=simple,
            job=not simple and Selection.startOutline(sel,{maxSegments=8192}) or nil}
        end
        local cache=self.selectionOutline
        if cache.job and not cache.job.done then
          Selection.stepOutline(cache.job,8192)
        end
        local segments=cache.job and cache.job.lines or cache.segments
        for _,edge in ipairs(segments or {}) do
          g.line(x+edge[1],y+edge[2],x+edge[3],y+edge[4])
        end
      else
        g.rectangle('line',x+sel.x,y+sel.y,sel.w,sel.h)
      end
    end
    if self.selectionAnimated then
      SelectionAnts.render(g,self.ants,now,drawOutline)
    else
      -- Sem shader, sem uniform temporal e sem custo de animação.
      drawOutline(false)
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
    -- A falha não pode ser confundida com pincelada confirmada por
    -- Ctrl+S, exportação PNG ou desfazer/refazer.
    return false,self.status
  end
end

function Bridge:update()
  if not self.job then return end
  local job=self.job
  local kind=self.jobKind
  local selectionMode=self.jobSelectionMode
  local ok,done,value=pcall(Job.step,job,0.004,love.timer and love.timer.getTime or os.clock)
  if not ok then
    self.job=nil;self.jobKind=nil;self.jobSelectionMode=nil
    self.status=(kind=='wand' and 'Varinha: ' or 'Balde: ')..tostring(done)
    return self.status
  elseif done then
    self.job=nil;self.jobKind=nil;self.jobSelectionMode=nil
    if kind=='wand' then
      if value then self:combineSelection(value,selectionMode)
      else self.status='Seleção vazia' end
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

function Bridge:setArtwork(id)
  self.artworkId=id
  self.filename=GalleryStorage.artworkPath(id)
end

-- Recebe um documento já decodificado e validado; preserva o documento
-- atual caso o arquivo solicitado não tenha podido ser aberto.
function Bridge:attachDocument(model,doc,id)
  assert(doc and doc.w and doc.h,'documento inválido')
  if id then GalleryStorage.artworkPath(id) end
  self:cancelTransform()
  self:cancelPNGImport()
  self:finish(true)
  self:cancelJob()
  self.selectionDrag=nil
  self.maskMode,self.maskOwner=nil,nil
  self:dropImages()
  self.doc=doc
  -- attachDocument e sync(fresh) devem ter a mesma política de troca de obra:
  -- nenhum mapa de camadas antigo nem modo de seleção pendente é herdado.
  -- uiByLayer tem chaves fortes; preservá-lo reteria os pixels das obras antigas.
  self.uiByLayer={}
  self.selectionMode='replace'
  self.jobSelectionMode=nil
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
  if id then self:setArtwork(id)
  else self.artworkId=nil;self.filename='meu-desenho.npnt' end
  self.status='Obra aberta'
  return true
end

function Bridge:save(model)
  if self.transform or self.pngPreview then return nil,'confirme ou cancele a prévia antes de salvar' end
  if not self.doc then return nil,'nenhum documento' end
  if model and (model.screen~='editor' or model.document~=self.modelDocument) then
    return nil,'documento alterado antes de salvar'
  end
  if self.job then return nil,'operação em andamento' end
  if self.selectionDrag then return nil,'finalize a seleção antes de salvar' end
  -- Jobs iniciados fora da ponte também podem manter pixels provisórios.
  -- Recusar antes de finalizar o traço ou acessar o sistema de arquivos.
  if self.doc.history._fillLock or
    (self.doc.history.stroke and not self.stroke) then
    return nil,'conclua ou cancele a operação antes de salvar'
  end
  -- A pincelada pertencente à ponte pode ser confirmada ao salvar, como
  -- antes; só depois disso é seguro aplicar as edições pendentes do painel.
  local finalized,finishErr=self:finish(false)
  if finalized==false then return nil,finishErr end
  if model and not self:sync(model) then
    return nil,self.status or 'não foi possível sincronizar as camadas antes de salvar'
  end
  local ok,err
  if self.artworkId then
    ok,err=GalleryStorage.saveArtwork(self.doc,self.artworkId)
  else
    ok,err=Project.save(self.doc,self.filename)
  end
  if ok and self.artworkId then
    -- A obra NPNT já está protegida; falha de miniatura não desfaz o salvamento.
    local previewOK,previewErr=GalleryStorage.saveThumbnail(self.doc,self.artworkId)
    self.status=previewOK and ('Salvo: '..self.filename) or
      ('Obra salva; miniatura pendente: '..tostring(previewErr))
  else
    self.status=ok and ('Salvo: '..self.filename) or ('Erro: '..tostring(err))
  end
  return ok,err
end

-- Importa o PNG em camada própria e registra uma única ação de histórico.
-- A pré-validação, a decodificação e os tiles temporários precedem qualquer
-- mutação da pilha. O NPNT original permanece intacto até o próximo salvar.
-- A importação é uma sessão visual: nenhum pixel/undo muda até Aplicar.
function Bridge:importPNGBytes(model,bytes,filename)
  local doc=self:canEditStructure(model)
  if not doc then return nil,self.status end
  if self.maskMode then
    self.status='Volte a Pintar pixels antes de importar PNG'
    return nil,self.status
  end
  local pixels,reason=PNGImport.decode(bytes)
  if not pixels then self.status='Importar PNG: '..tostring(reason);return nil,self.status end
  local ok,session=pcall(PNGImport.preview,doc,pixels,filename)
  if not ok then self.status='Importar PNG: '..tostring(session);return nil,self.status end
  PNGImport.setInterpolation(session,'smooth')
  self.pngPreview=session
  self.pngModel=model
  self.pngDrag=nil
  self.status='PNG em prévia: arraste, ajuste a escala ou confirme'
  return true
end

function Bridge:cancelPNGImport()
  self.pngDrag=nil
  local session=self.pngPreview
  if not session then return false end
  PNGImport.cancel(session)
  self.pngPreview=nil
  self.pngModel=nil
  self.status='Importação cancelada; pintura preservada'
  return true
end

function Bridge:adjustPNGImport(dx,dy,scale,angle)
  if not self.pngPreview then return false end
  local ok,why=pcall(PNGImport.adjust,self.pngPreview,dx,dy,scale,angle)
  if not ok then self.status='Ajuste do PNG: '..tostring(why);return false end
  return true
end

-- Permite zerar o giro com precisão, sem deslocar ou redimensionar a prévia.
function Bridge:resetPNGImportAngle()
  local session=self.pngPreview
  if not session then return false end
  local ok,err=pcall(Transform.set,session,
    session.dx,session.dy,session.scaleX,session.scaleY,0)
  if not ok then self.status='Giro PNG: '..tostring(err);return false end
  self.status='Rotação PNG zerada'
  return true
end

function Bridge:setPNGInterpolation(mode)
  if not self.pngPreview then return false end
  local ok,reason=pcall(PNGImport.setInterpolation,self.pngPreview,mode)
  if not ok then self.status='Filtro PNG: '..tostring(reason);return false end
  self.status=mode=='smooth' and 'PNG: suavização bilinear ativada'
    or 'PNG: pixels nítidos (sem suavização)'
  return true
end

function Bridge:applyPNGImport(model)
  local session=self.pngPreview
  if not session then return false end
  local doc=self.doc
  if not doc or self.modelDocument~=model.document then
    self.status='Documento alterado durante a prévia'
    return false
  end
  -- sync adia as alterações do painel durante a prévia. Guardá-las antes
  -- de refreshModel, que reescreve as entradas da UI e descartaria nomes,
  -- opacidade e até camadas adicionadas enquanto o PNG era posicionado.
  -- As cópias são necessárias porque refreshModel reutiliza as tabelas.
  local pendingLayers={}
  for i,entry in ipairs(model.layers) do
    local copy={}
    for key,value in pairs(entry) do copy[key]=value end
    pendingLayers[i]=copy
  end
  local requestedActive=model.active_layer_id
  local originalActive
  for id,existing in pairs(self.byId) do
    if existing==doc.layers[doc.sel] then originalActive=id;break end
  end
  local ok,layer,count=pcall(PNGImport.insert,doc,session.source,session.filename,session)
  if not ok or not layer then
    self.status='PNG: '..tostring(ok and count or layer)
    return false
  end
  self:cancelPNGImport()
  self:refreshModel(model)
  -- O PNG passa a ser a camada ativa por padrão. Se o usuário mudou
  -- explicitamente a seleção no painel, respeitar esse pedido pendente.
  local imported=self.uiByLayer[layer]
  pendingLayers[#pendingLayers+1]=imported
  model.layers=pendingLayers
  if requestedActive and requestedActive~=originalActive then
    model.active_layer_id=requestedActive
  end
  -- Registra as mudanças pendentes depois da importação, como operação
  -- estrutural independente: undo primeiro desfaz o painel, depois o PNG.
  if not self:sync(model) then
    self.status='PNG aplicado; sincronização de camadas pendente'
    return false
  end
  self:dropImages()
  self.cache=Composite.newCache(doc,{maxTiles=96})
  self.status='PNG aplicado: '..tostring(count)..' pixels (Ctrl+Z desfaz)'
  return true
end

function Bridge:drawPNGImport(x,y)
  if self.pngPreview then PNGImport.drawPreview(self.pngPreview,x,y) end
end

function Bridge:beginPNGDrag(model,view,prefs,uiScale,W,H,rx,ry)
  local s=self.pngPreview
  if not s then return false end
  local x,y=self:toCanvas(model,view,prefs,uiScale,W,H,rx,ry)
  if not x then return false end
  local b=PNGImport.bounds(s)
  if x<b.x or y<b.y or x>b.x+b.w or y>b.y+b.h then return false end
  self.pngDrag={x=x,y=y,dx=s.dx,dy=s.dy}
  return true
end

function Bridge:movePNGImport(model,view,prefs,uiScale,W,H,rx,ry)
  if not self.pngPreview or not self.pngDrag then return false end
  local x,y=self:toCanvas(model,view,prefs,uiScale,W,H,rx,ry)
  if not x then return false end
  local drag=self.pngDrag
  local session=self.pngPreview
  local ok,err=pcall(Transform.set,session,
    drag.dx+x-drag.x,drag.dy+y-drag.y,
    session.scaleX,session.scaleY,session.angle)
  if not ok then self.status=tostring(err);return false end
  return true
end

function Bridge:pngImportKey(key)
  if not self.pngPreview then return false end
  if key=='escape' then self:cancelPNGImport();return true end
  if key=='return' or key=='kpenter' then self:applyPNGImport(self.pngModel);return true end
  if key=='left' then self:adjustPNGImport(-1,0);return true end
  if key=='right' then self:adjustPNGImport(1,0);return true end
  if key=='up' then self:adjustPNGImport(0,-1);return true end
  if key=='down' then self:adjustPNGImport(0,1);return true end
  if key=='q' then self:adjustPNGImport(0,0,1,-math.pi/12);return true end
  if key=='r' then self:adjustPNGImport(0,0,1,math.pi/12);return true end
  if key=='=' or key=='kp+' then self:adjustPNGImport(0,0,1.1);return true end
  if key=='-' or key=='kp-' then self:adjustPNGImport(0,0,1/1.1);return true end
  self.status='Aplique ou cancele a importação primeiro'
  return true
end

function Bridge:importPNGFromFolder(model,filename)
  if type(filename)~='string' or #filename<5 or #filename>120
    or filename:find('[/\\%z]') or filename:find('..',1,true)
    or not filename:lower():match('%.png$') then
    self.status='Nome de arquivo PNG inválido'
    return nil,self.status
  end
  local fs=love and love.filesystem
  if not fs or not fs.read then
    self.status='love.filesystem indisponível'
    return nil,self.status
  end
  local path='imports/'..filename
  local info=fs.getInfo and fs.getInfo(path)
  if not info or info.type~='file' then
    self.status='Arquivo PNG não encontrado em imports/'
    return nil,self.status
  end
  if info.size and info.size>PNGImport.MAX_BYTES then
    self.status='PNG maior que 16 MiB'
    return nil,self.status
  end
  local ok,bytes,err=pcall(fs.read,path)
  if not ok or type(bytes)~='string' then
    self.status='Não foi possível ler PNG: '..tostring(ok and err or bytes)
    return nil,self.status
  end
  return self:importPNGBytes(model,bytes,filename)
end

-- A exportação nunca modifica a pintura nem substitui um PNG existente.
function Bridge:exportPNG(model)
  if not self.doc then return nil,'nenhum documento aberto' end
  -- Uma chamada de outra obra não pode trocar o documento via sync,
  -- nem exportar uma tela nova no lugar da pintura atualmente anexada.
  if model and (model.screen~='editor' or model.document~=self.modelDocument) then
    self.status='Documento alterado antes de exportar'
    return nil,self.status
  end
  if self.transform or self.job or self.selectionDrag or self.pngPreview
    or self.doc.history._fillLock or
    (self.doc.history.stroke and not self.stroke) then
    self.status='Conclua ou cancele a operação antes de exportar'
    return nil,self.status
  end
  local finalized,finishErr=self:finish(false)
  if finalized==false then return nil,finishErr end
  -- Se alterações de camada ainda não puderem ser sincronizadas,
  -- não exportar uma composição desatualizada.
  if model and not self:sync(model) then
    self.status='Não foi possível sincronizar as camadas antes de exportar'
    return nil,self.status
  end
  local path,err=PNGExport.save(self.doc,self.artworkId or 'atual')
  self.status=path and ('PNG exportado em '..path) or ('Exportação: '..tostring(err))
  return path,err
end

function Bridge:load(model)
  -- Reabrir o arquivo atual (Ctrl+O) não é uma troca deliberada de obra
  -- pela galeria. Não descartar gestos, prévias ou jobs ainda pendentes:
  -- especialmente baldes externos cujo token não pertence a self.job.
  if self.stroke or self.job or self.selectionDrag
    or self.transform or self.pngPreview or
    (self.doc and self.doc.history and
      (self.doc.history._fillLock or self.doc.history.stroke)) then
    self.status='Conclua ou cancele a operação antes de reabrir a obra'
    return nil,self.status
  end
  local doc,err
  if self.artworkId then
    doc,err=GalleryStorage.loadArtwork(self.artworkId)
  else
    doc,err=Project.load(self.filename)
  end
  if not doc then
    self.status='Abertura: '..tostring(err)
    return nil,self.status
  end
  local id=self.artworkId
  self:attachDocument(model,doc,id)
  self.status='Aberto: '..self.filename
  return true
end

function Bridge:historyStep(model,redo)
  if model.screen~='editor' then return false end
  if self.transform or self.pngPreview then self.status='Confirme ou cancele a prévia antes do histórico';return false end
  if self.job then
    self.status='Finalize ou cancele o trabalho antes do histórico'
    return false
  end
  -- Não cancelar silenciosamente um laço/retângulo ao pressionar
  -- Ctrl+Z/Y. O gesto pendente não entrou no histórico ainda.
  if self.selectionDrag then
    self.status='Finalize ou cancele o arraste antes do histórico'
    return false
  end
  -- Jobs externos à ponte também seguram o token de preenchimento.
  if self.doc and (self.doc.history._fillLock or
    (self.doc.history.stroke and not self.stroke)) then
    self.status='Finalize o preenchimento antes do histórico'
    return false
  end
  if self:finish(false)==false then return false end
  local doc=self:sync(model)
  if not doc then return false end
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
  if key=='i' and k.isDown('lshift','rshift') then
    self:invertSelection(model);return true
  end
  if key=='a' then self:selectAll(model);return true end
  if key=='d' then self:clearSelection();return true end
  if key=='s' then
    local ok,err=self:save(model)
    if not ok then self.status=tostring(err) end
    return true
  end
  if key=='o' then self:load(model);return true end
  if key=='z' then self:historyStep(model,false);return true end
  if key=='y' then self:historyStep(model,true);return true end
  return false
end

return Bridge
