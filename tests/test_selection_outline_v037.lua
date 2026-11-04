-- v0.37: contorno incremental, fiel a máscaras esparsas e invertidas.
return function(check)
  local Doc=require('core.doc')
  local Selection=require('core.selection')
  local Mask=require('core.mask')
  local Bridge=require('app.paint_bridge')
  local Model=require('src.model')
  local function containsLine(lines,x0,y0,x1,y1)
    for _,e in ipairs(lines) do
      if e[1]==x0 and e[2]==y0 and e[3]==x1 and e[4]==y1 then
        return true
      end
    end
    return false
  end
  local function run(job,budget)
    local n=0
    while not job.done and n<512 do
      Selection.stepOutline(job,budget or 16384)
      n=n+1
    end
    return job.done,n
  end

  local doc=Doc.new(2048,2048,'Contornos grandes')
  local mask=Mask.new(0)
  local tile=Mask.getTile(mask,0,0,true)
  for y=10,12 do
    for x=10,12 do tile:setPixel(x,y,1,1,1,1) end
  end
  local inv={kind='wand',x=0,y=0,w=doc.w,h=doc.h,mask=mask}
  mask.inverted=true
  check('v0.37: seleção inversa grande valida',Selection.validate(doc,inv))
  check('v0.37: API antiga mantém limite seguro',
    Selection.outline(inv)==nil)
  local job=Selection.startOutline(inv)
  local firstDone=Selection.stepOutline(job,1)
  check('v0.37: orçamento de um pixel realmente limita trabalho',
    not firstDone and job.scanned==1 and not job.done)
  local done,frames=run(job)
  check('v0.37: contorno grande termina em lotes',
    done and not job.truncated and frames>1)
  check('v0.37: borda externa correta da máscara inversa',
    containsLine(job.lines,0,0,2048,0)
    and containsLine(job.lines,0,2048,2048,2048)
    and containsLine(job.lines,0,0,0,2048)
    and containsLine(job.lines,2048,0,2048,2048))
  check('v0.37: bordas internas do furo são exatas',
    containsLine(job.lines,10,10,13,10)
    and containsLine(job.lines,10,13,13,13)
    and containsLine(job.lines,10,10,10,13)
    and containsLine(job.lines,13,10,13,13))
  check('v0.37: não desenha bounding box do furo como seleção cheia',
    #job.lines==8)
  check('v0.37: processamento não muda máscara da seleção',
    Selection.contains(inv,0,0) and not Selection.contains(inv,11,11)
    and mask.inverted and not job.truncated)
  local previousScan,previousCount=job.scanned,#job.lines
  local doneAgain=Selection.stepOutline(job,8192)
  check('v0.37: job concluído reutiliza cache sem recalcular',
    doneAgain and job.scanned==previousScan and #job.lines==previousCount)

  local sparse=Mask.new(0)
  Mask.getTile(sparse,0,0,true):setPixel(2,2,1,1,1,1)
  Mask.getTile(sparse,7,7,true):setPixel(255,255,1,1,1,1)
  local islands={kind='wand',x=2,y=2,w=2046,h=2046,mask=sparse}
  check('v0.37: ilhas distantes sem leitura da área intermediária',
    Selection.outline(islands)==nil)
  local islandsJob=Selection.startOutline(islands)
  local islandDone=run(islandsJob)
  check('v0.37: duas ilhas esparsas terminam',
    islandDone and not islandsJob.truncated
    and islandsJob.scanned==2*Doc.TILE*Doc.TILE)
  check('v0.37: cada ilha recebe contorno de um pixel',
    #islandsJob.lines==8
    and containsLine(islandsJob.lines,2,2,3,2)
    and containsLine(islandsJob.lines,2047,2048,2048,2048))
  check('v0.37: não desenha moldura falsa entre ilhas',
    not containsLine(islandsJob.lines,2,2,2048,2))

  local touchMask=Mask.new(0)
  local touchTile=Mask.getTile(touchMask,0,0,true)
  touchTile:setPixel(0,0,1,1,1,1)
  touchTile:setPixel(1,0,1,1,1,1)
  touchTile:setPixel(0,1,1,1,1,1)
  touchMask.inverted=true
  local touch={kind='wand',x=0,y=0,w=512,h=512,mask=touchMask}
  local edgeJob=Selection.startOutline(touch)
  run(edgeJob)
  check('v0.37: contorno externo respeita furo junto ao topo',
    containsLine(edgeJob.lines,2,0,512,0)
    and not containsLine(edgeJob.lines,0,0,512,0))
  check('v0.37: contorno externo respeita furo junto à esquerda',
    containsLine(edgeJob.lines,0,2,0,512)
    and not containsLine(edgeJob.lines,0,0,0,512))
  check('v0.37: lado interno de furo de borda aparece',
    containsLine(edgeJob.lines,2,0,2,1)
    and containsLine(edgeJob.lines,0,2,1,2))

  local blank=Mask.new(0)
  local noPixels={kind='wand',x=0,y=0,w=512,h=512,mask=blank}
  local blankJob=Selection.startOutline(noPixels)
  run(blankJob)
  check('v0.37: seleção vazia não tem moldura',
    blankJob.done and #blankJob.lines==0)
  local invertedEmptyMask=Mask.new(0)
  invertedEmptyMask.inverted=true
  local all={kind='wand',x=0,y=0,w=512,h=512,mask=invertedEmptyMask}
  local allJob=Selection.startOutline(all)
  run(allJob)
  check('v0.37: seleção inversa sem exceções mostra só perímetro',
    allJob.done and #allJob.lines==4)

  local smallJob=Selection.startOutline(inv,{maxSegments=3})
  run(smallJob)
  check('v0.37: complexidade excedente trunca sem bbox inventada',
    smallJob.done and smallJob.truncated and #smallJob.lines==3)
  local invalidBudget=not pcall(Selection.stepOutline,Selection.startOutline(inv),0)
  check('v0.37: orçamento inválido recusado',invalidBudget)

  -- Ponte: desenha somente linhas exatas, sem fallback retangular e sem
  -- reiniciar o cálculo quando o zoom é alterado.
  local model=Model.new()
  model:open_gallery();model:open_new_canvas()
  model:create_canvas(2048,2048)
  local bridge=Bridge.new()
  local bd=assert(bridge:sync(model))
  bd.selection=inv
  local oldGraphics=love.graphics
  local rendered={lines=0,rectangles=0}
  love.graphics={
    setColor=function() end,setLineWidth=function() end,
    line=function() rendered.lines=rendered.lines+1 end,
    rectangle=function() rendered.rectangles=rendered.rectangles+1 end,
  }
  local okDraw=pcall(function()
    for i=1,20 do bridge:drawSelection(0,0,0.3) end
  end)
  local cached=bridge.selectionOutline
  check('v0.37: render mock processa contorno real sem erro',
    okDraw and cached and cached.job and cached.job.done)
  check('v0.37: render mock não desenha moldura inexata',
    rendered.lines>0 and rendered.rectangles==0)
  local okReuse=pcall(bridge.drawSelection,bridge,0,0,2)
  check('v0.37: zoom reutiliza mesmos contornos',
    okReuse and bridge.selectionOutline==cached)
  bd.selection=islands
  local okReset=pcall(bridge.drawSelection,bridge,0,0,1)
  check('v0.37: mudança de seleção invalida cache',
    okReset and bridge.selectionOutline~=cached
    and bridge.selectionOutline.selection==islands)
  love.graphics=oldGraphics
end
