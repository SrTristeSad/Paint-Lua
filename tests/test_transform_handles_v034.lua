-- v0.34: alças interativas da seleção (zoom, rotação, escala, pan).
-- Testes do núcleo com ImageData mock; o LÖVE real tem E2E separado.
return function(check)
  local Doc=require('core.doc')
  local Selection=require('core.selection')
  local Transform=require('core.transform')
  local Bridge=require('app.paint_bridge')
  local Model=require('src.model')
  local Viewport=require('src.viewport')
  local Prefs=require('src.editor_preferences')
  local function close(a,b,tol) return math.abs(a-b)<(tol or 1e-5) end
  local function pixel(layer,x,y)
    local tile=Doc.getTile(layer,math.floor(x/256),math.floor(y/256),false)
    return tile and select(4,tile:getPixel(x%256,y%256)) or 0
  end
  local model=Model.new()
  model:open_gallery();model:open_new_canvas();model:create_canvas(100,100)
  local bridge=Bridge.new()
  local doc=assert(bridge:sync(model))
  local layer=doc.layers[doc.sel]
  local tile,key=Doc.getTile(layer,0,0,true)
  tile:setPixel(43,43,0.8,0.2,0.1,1)
  Doc.markDirty(layer,key)
  doc.selection=Selection.rect(doc,30,30,69,69)
  model:set_tool('transform')
  check('v0.34: inicializa transformação com alças',bridge:startTransform(model))
  local session=bridge.transform
  check('v0.34: alças são geometria da sessão',session and session.active)
  local h=Transform.handles(session,1.1)
  check('v0.34: quatro cantos coerentes',
    close(h.nw.x,30) and close(h.nw.y,30) and
    close(h.ne.x,70) and close(h.se.y,70) and close(h.sw.x,30))
  check('v0.34: alça de giro fica acima da aresta',
    close(h.rotate.x,50) and h.rotate.y<h.nw.y)
  local h2=Transform.handles(session,2.2)
  check('v0.34: distância da alça acompanha o zoom',
    close((h.top.y-h.rotate.y)*1.1,28) and
    close((h2.top.y-h2.rotate.y)*2.2,28))
  check('v0.34: rejeita escala visual inválida',
    not pcall(Transform.handles,session,0))

  local view=Viewport.new()
  local prefs=Prefs.new()
  local W,H=1024,768
  local function mouse(cx,cy)
    local left=prefs.tool_position=='left' and 62 or 0
    local right=prefs.tool_position=='right' and 75 or 34
    local aw,ah=W-left-right,H-160
    local ds=math.min(aw/doc.w,ah/doc.h,1.1)*view.zoom
    local u,v=(cx-doc.w/2)*ds,(cy-doc.h/2)*ds
    local x=left+aw/2+view.pan_x
    local y=62+ah/2+view.pan_y
    local a=view.rotation
    return x+u*math.cos(a)-v*math.sin(a), y+u*math.sin(a)+v*math.cos(a)
  end
  local function down(px,py)
    local mx,my=mouse(px,py)
    return bridge:beginTransformDrag(model,view,prefs,1,W,H,mx,my)
  end
  local function move(px,py)
    local mx,my=mouse(px,py)
    return bridge:moveTransform(model,view,prefs,1,W,H,mx,my)
  end

  -- O canto SE aumenta a seleção em torno do canto NW, que não se desloca.
  check('v0.34: clique em canto ativa escala',down(h.se.x,h.se.y)
    and bridge.transformDrag.kind=='scale')
  check('v0.34: arrastar canto redimensiona',move(h.se.x+20,h.se.y+20))
  check('v0.34: escala uniforme e sem distorção',
    close(session.scaleX,1.5) and close(session.scaleY,1.5))
  local nwX,nwY=Transform.forward(session,30,30)
  check('v0.34: canto NW não se move durante escala SE',
    close(nwX,h.nw.x) and close(nwY,h.nw.y))
  check('v0.34: prévia de escala não muda pixels/histórico',
    pixel(layer,43,43)==1 and #doc.history.undo==0)
  bridge:finishTransformDrag()
  check('v0.34: soltar botão encerra gesto, mantém prévia',
    not bridge.transformDrag and session.active)

  -- Giro por alça em vez de botão; permanece em torno do centro.
  h=Transform.handles(session,1.1)
  check('v0.34: alça superior ativa rotação',down(h.rotate.x,h.rotate.y)
    and bridge.transformDrag.kind=='rotate')
  local ux,uy=h.rotate.x-h.center.x,h.rotate.y-h.center.y
  local turn=math.pi/4
  local gx=h.center.x+ux*math.cos(turn)-uy*math.sin(turn)
  local gy=h.center.y+ux*math.sin(turn)+uy*math.cos(turn)
  check('v0.34: mouse rotaciona seleção',move(gx,gy))
  check('v0.34: giro pela alça é de 45 graus',close(session.angle,turn))
  check('v0.34: pivô não se move durante giro',
    close(Transform.handles(session,1.1).center.x,h.center.x) and
    close(Transform.handles(session,1.1).center.y,h.center.y))
  bridge:finishTransformDrag()
  h=Transform.handles(session,1.1)
  check('v0.34: cantos acompanham rotação',
    math.abs(h.nw.y-h.ne.y)>10 and math.abs(h.nw.x-h.sw.x)>10)

  -- A caixa envolvente contém espaços vazios; eles não podem mover a seleção.
  local bounds=Transform.bounds(session)
  check('v0.34: fora da área girada não move',
    not down(bounds.x+0.5,bounds.y+0.5) and bridge.transformDrag==nil)
  h=Transform.handles(session,1.1)
  check('v0.34: centro girado ativa movimento',down(h.center.x,h.center.y)
    and bridge.transformDrag.kind=='move')
  check('v0.34: arraste move por delta exato',move(h.center.x+7,h.center.y-4))
  check('v0.34: movimento não altera escala nem giro',
    close(session.dx,bridge.transformDrag.dx+7) and
    close(session.dy,bridge.transformDrag.dy-4) and
    close(session.scaleX,1.5) and close(session.angle,turn))
  bridge:finishTransformDrag()

  -- Mudanças nos controles de visualização devem preservar o hit-test.
  view.zoom=2
  view.rotation=0.24
  view.pan_x,view.pan_y=13,-9
  local zoom=bridge:transformCanvasScale(model,view,prefs,W,H)
  local scaled=Transform.handles(session,zoom)
  check('v0.34: zoom/pan/giro do canvas não quebram as alças',
    down(scaled.rotate.x,scaled.rotate.y) and bridge.transformDrag.kind=='rotate')
  bridge:finishTransformDrag()
  check('v0.34: distância em tela permanece 28px com zoom',
    close(math.sqrt((scaled.rotate.x-scaled.top.x)^2+
      (scaled.rotate.y-scaled.top.y)^2)*zoom,28))
  local bx,by=Transform.forward(session,30,30)
  check('v0.34: canto reconhecido após girar canvas',
    down(bx,by) and bridge.transformDrag.kind=='scale')
  check('v0.34: escala limitada a 8 vezes',move(bx+100000,by+100000)
    and math.abs(session.scaleX)<=8 and math.abs(session.scaleY)<=8)
  check('v0.34: escala extrema não gera histórico',#doc.history.undo==0)
  bridge:finishTransformDrag()
  check('v0.34: cancelar mantém documento intacto',
    bridge:cancelTransform() and not bridge.transform and
    pixel(layer,43,43)==1 and #doc.history.undo==0)
  check('v0.34: reinício após cancelamento',bridge:startTransform(model))
  check('v0.34: botões antigos continuam funcionando',
    bridge:adjustTransform(8,0) and close(bridge.transform.dx,8))
  local n=bridge:applyTransform(model)
  check('v0.34: aplicar após alças cria um único histórico',
    n and #doc.history.undo==1 and not bridge.transform)
  check('v0.34: undo restaura pixels da origem',
    bridge:historyStep(model,false) and pixel(layer,43,43)==1)
  check('v0.34: redo mantém uma transformação',
    bridge:historyStep(model,true) and #doc.history.undo==1)
end
