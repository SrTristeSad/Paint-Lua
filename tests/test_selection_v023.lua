-- Seleção retangular, poligonal, varinha, persistência e integração UI.
return function(check)
  local Doc=require('core.doc')
  local Selection=require('core.selection')
  local Stroke=require('core.stroke')
  local Hist=require('core.history')
  local Fill=require('core.fill')
  local Job=require('core.job')
  local Project=require('core.project')
  local Model=require('src.model')
  local Bridge=require('app.paint_bridge')
  local View=require('src.viewport')
  local Pref=require('src.editor_preferences')
  local function ink(doc,l,x,y)
    local tx,ty=math.floor(x/Doc.TILE),math.floor(y/Doc.TILE)
    local t=l.tiles[tx..','..ty]
    return t and select(4,t:getPixel(x%Doc.TILE,y%Doc.TILE)) or 0
  end
  local d=Doc.new(64,64,'Testes de seleção')
  local l=d.layers[2]
  local sel=Selection.rect(d,21,18,10,10)
  check('seleção: retângulo invertido é normalizado',sel.x==10 and sel.y==10 and sel.w==12 and sel.h==9)
  check('seleção: retângulo inclui borda inicial',Selection.contains(sel,10,10))
  check('seleção: retângulo exclui borda final',not Selection.contains(sel,22,18))
  check('seleção: retângulo recorta documento',Selection.rect(d,-10,-9,1,1).x==0)
  check('seleção: retângulo fora do documento retorna nil',Selection.rect(d,-9,-9,-8,-8)==nil)
  check('seleção: valida retângulo',Selection.validate(d,sel))
  local tri=assert(Selection.polygon(d,{{8,8},{28,8},{8,28}}))
  check('seleção: laço possui limites corretos',tri.kind=='polygon' and tri.w==20 and tri.h==20)
  check('seleção: laço inclui interior',Selection.contains(tri,12,12))
  check('seleção: laço exclui canto dentro do bbox',not Selection.contains(tri,25,25))
  check('seleção: laço exclui ponto externo',not Selection.contains(tri,3,3))
  check('seleção: valida laço',Selection.validate(d,tri))
  local ok=pcall(Selection.polygon,d,{{1,1},{3,3}})
  check('seleção: laço exige pelo menos três pontos',not ok)
  ok=pcall(Selection.validate,d,{x=0,y=0,w=5,h=5,kind='unknown'})
  check('seleção: formato desconhecido rejeitado',not ok)

  d.selection=tri
  local opts={size=32,alpha=1,hardness=1,color={1,0,0},smoothing={amount=0}}
  local st=Stroke.new(d,l,d.history,opts)
  st:push(15,15,1,0);st:finish()
  check('seleção: pincel atinge interior triangular',ink(d,l,12,12)>0)
  check('seleção: pincel não pinta canto fora do laço',ink(d,l,25,25)==0)
  check('seleção: pincel não pinta fora do bbox',ink(d,l,2,2)==0)
  Hist.undo(d)
  check('seleção: undo do pincel respeita laço',ink(d,l,12,12)==0)
  Hist.redo(d)
  check('seleção: redo do pincel respeita laço',ink(d,l,12,12)>0)

  local filled=Doc.new(40,40,'Balde recortado')
  local fl=filled.layers[2]
  local n=Fill.fill(filled,fl,12,12,{0,0,1,1},0,tri)
  check('seleção: balde preenche interior do laço',n>0 and ink(filled,fl,12,12)>0)
  check('seleção: balde não preenche canto exterior',ink(filled,fl,25,25)==0)
  check('seleção: balde com semente fora do laço não escreve',
    Fill.fill(filled,fl,25,25,{1,1,1,1},0,tri)==0)

  local bytes=Project.encode(d)
  check('seleção: laço ativa NPNT5',bytes:sub(1,6)=='NPNT5\n')
  local loaded,err=Project.decode(bytes)
  check('seleção: laço NPNT5 reabre',loaded and loaded.selection and loaded.selection.kind=='polygon',err)
  check('seleção: laço conserva vértices',loaded and #loaded.selection.points==3)
  check('seleção: laço conserva máscara geométrica',loaded and
    Selection.contains(loaded.selection,12,12) and not Selection.contains(loaded.selection,25,25))
  check('seleção: arquivo v5 truncado rejeitado',Project.decode(bytes:sub(1,-2))==nil)
  check('seleção: arquivo v5 com lixo rejeitado',Project.decode(bytes..'Z')==nil)
  d.selection=Selection.rect(d,5,5,10,10)
  check('seleção: retângulo mantém formato legado',Project.encode(d):sub(1,6)~='NPNT5\n')
  local rectangleOpened=Project.decode(Project.encode(d))
  check('seleção: retângulo legado reabre',rectangleOpened and
    Selection.contains(rectangleOpened.selection,8,8) and not Selection.contains(rectangleOpened.selection,20,20))

  local wd=Doc.new(32,32,'Varinha')
  local wl=wd.layers[2]
  local tile,key=Doc.getTile(wl,0,0,true)
  for y=3,7 do for x=3,7 do tile:setPixel(x,y,1,0,0,1) end end
  tile:setPixel(10,10,1,0,0,1)
  Doc.markDirty(wl,key)
  local wand=assert(Selection.wand(wd,wl,4,4,0))
  check('seleção: varinha encontra região conexa',wand.kind=='wand' and
    wand.x==3 and wand.y==3 and wand.w==5 and wand.h==5)
  check('seleção: varinha inclui pixel da região',Selection.contains(wand,7,7))
  check('seleção: varinha ignora ilha desconectada',not Selection.contains(wand,10,10))
  check('seleção: varinha exclui pixel fora da cor',not Selection.contains(wand,8,4))
  check('seleção: varinha valida máscara',Selection.validate(wd,wand))
  local outline=Selection.outline(wand)
  check('seleção: varinha calcula contorno real da região',outline and #outline==20)
  check('seleção: contorno limita área e custo',Selection.outline(wand,5)==nil)
  wd.selection=wand
  local paintLayer=wd.layers[1]
  local paintCount=Fill.fill(wd,paintLayer,4,4,{0,0,1,1},0,wd.selection)
  check('seleção: balde usa máscara exata da varinha',paintCount==25)
  check('seleção: balde não alcança ilha',ink(wd,paintLayer,10,10)==0)
  local wandBytes=Project.encode(wd)
  check('seleção: varinha ativa NPNT5',wandBytes:sub(1,6)=='NPNT5\n')
  local back=Project.decode(wandBytes)
  check('seleção: varinha reabre NPNT5',back and back.selection and back.selection.kind=='wand')
  check('seleção: varinha restaura máscara exata',back and
    Selection.contains(back.selection,4,4) and not Selection.contains(back.selection,10,10))
  local job=Selection.newWandJob(wd,wl,4,4,0,{yieldEvery=1})
  local done,value=Job.step(job,0.001)
  check('seleção: varinha cooperativa admite pausar',not done or value.kind=='wand')
  local turns=0
  while not done and turns<200 do done,value=Job.step(job,0.001);turns=turns+1 end
  check('seleção: varinha cooperativa termina',done and value.kind=='wand')
  check('seleção: varinha cooperativa equivale à síncrona',done and
    Selection.contains(value,3,3) and not Selection.contains(value,10,10))
  local cancel=Selection.newWandJob(wd,wl,4,4,0,{yieldEvery=1})
  Job.step(cancel,0.0001)
  local old=wd.selection
  Job.cancel(cancel)
  check('seleção: cancelar varinha preserva seleção anterior',wd.selection==old)
  ok=pcall(Selection.wand,wd,wl,4,4,0,{maxPixels=10})
  check('seleção: varinha respeita limite de memória',not ok)

  local hdoc=Doc.new(32,32,'Histórico de seleção')
  Hist.recordStructure(hdoc);hdoc.selection=Selection.rect(hdoc,2,2,7,7)
  Hist.recordStructure(hdoc);hdoc.selection=nil
  check('seleção: mudar seleção adiciona histórico',#hdoc.history.undo==2)
  Hist.undo(hdoc)
  check('seleção: undo restaura seleção',hdoc.selection and Selection.contains(hdoc.selection,4,4))
  Hist.undo(hdoc)
  check('seleção: undo restaura nenhuma seleção',hdoc.selection==nil)
  Hist.redo(hdoc)
  check('seleção: redo restaura região',hdoc.selection and Selection.contains(hdoc.selection,4,4))

  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(64,64)
  local bridge=Bridge.new()
  local bd=bridge:sync(model)
  local view=View.new();local prefs=Pref.new()
  local left=prefs.tool_position=='left' and 62 or 0
  local right=prefs.tool_position=='right' and 75 or 34
  local cx=left+(1024-left-right)/2
  local cy=62+(768-160)/2
  local z=math.min((1024-left-right)/64,(768-160)/64,1.1)
  local function win(x,y) return cx+(x-32)*z,cy+(y-32)*z end
  model:set_tool('selection_rect')
  local ax,ay=win(10,10)
  local bx,by=win(22,22)
  check('seleção: gesto retangular inicia pela ponte',bridge:beginSelection(model,view,prefs,1,1024,768,ax,ay))
  bridge:moveSelection(model,view,prefs,1,1024,768,bx,by)
  check('seleção: gesto retangular finaliza',bridge:finishSelection(model,view,prefs,1,1024,768,bx,by))
  check('seleção: gesto retangular recorta documento',Selection.contains(bd.selection,15,15) and
    not Selection.contains(bd.selection,30,30))
  check('seleção: gesto não modifica pixels',next(bd.layers[1].tiles)==nil)
  model:set_tool('lasso')
  ax,ay=win(8,8)
  check('seleção: laço inicia',bridge:beginSelection(model,view,prefs,1,1024,768,ax,ay))
  bx,by=win(28,8);bridge:moveSelection(model,view,prefs,1,1024,768,bx,by)
  bx,by=win(8,28);bridge:moveSelection(model,view,prefs,1,1024,768,bx,by)
  check('seleção: laço finaliza',bridge:finishSelection(model,view,prefs,1,1024,768,bx,by))
  check('seleção: laço da UI exclui canto irregular',bd.selection.kind=='polygon' and
    not Selection.contains(bd.selection,26,26))
  model:set_tool('magic_wand')
  ax,ay=win(32,32)
  local before=bd.selection
  check('seleção: varinha inicia job',bridge:beginSelection(model,view,prefs,1,1024,768,ax,ay) and
    bridge.jobKind=='wand')
  check('seleção: varinha não altera seleção antes de terminar',bd.selection==before)
  bridge:cancelJob()
  check('seleção: cancelar job preserva laço',bd.selection==before and bridge.job==nil)
  model:set_tool('selection_rect')
  bridge:selectAll(model)
  check('seleção: comando selecionar tudo',Selection.contains(bd.selection,0,0) and
    Selection.contains(bd.selection,63,63))
  bridge:clearSelection()
  check('seleção: comando desmarcar',bd.selection==nil)
  check('seleção: desfazer desmarcar',bridge:historyStep(model,false) and bd.selection~=nil)
  check('seleção: desfazer não altera camadas',#model.layers==1)
end
