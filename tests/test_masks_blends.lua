-- Testes da v0.16. Executados após o mock do LÖVE em tests/test_core.lua.
return function(check)
  local Doc=require('core.doc')
  local L=require('core.layers')
  local H=require('core.history')
  local C=require('core.composite')
  local P=require('core.project')
  local M=require('core.mask')
  local B=require('core.blend')
  local Render=require('core.render')
  local function near(a,b,eps) return math.abs(a-b)<(eps or 0.00001) end
  local function pixel(layer,x,y,color)
    local tx,ty=math.floor(x/Doc.TILE),math.floor(y/Doc.TILE)
    local tile,key=Doc.getTile(layer,tx,ty,true)
    tile:setPixel(x%Doc.TILE,y%Doc.TILE,color[1],color[2],color[3],color[4] or 1)
    Doc.markDirty(layer,key)
  end
  local function out(doc,x,y)
    return {C.flattenRegion(doc,x,y,1,1):getPixel(0,0)}
  end
  local function count(t)
    local n=0
    for _ in pairs(t) do n=n+1 end
    return n
  end

  do
    local d=Doc.new(300,300,'v016 pixels')
    local layer=d.layers[2]
    pixel(layer,10,10,{1,0,0,1})
    pixel(layer,258,10,{0,1,0,1})
    check('v0.16: sem máscara mantém pintura legada',near(out(d,10,10)[4],1))
    local m=L.addMask(d,2)
    check('v0.16: máscara padrão branca e esparsa',m.default==1 and count(m.tiles)==0
      and near(out(d,258,10)[4],1))
    L.setMaskPixel(d,2,10,10,0)
    check('v0.16: máscara preta esconde a camada',near(out(d,10,10)[4],0))
    check('v0.16: outro tile permanece visível',near(out(d,258,10)[4],1))
    L.setMaskPixel(d,2,258,10,0.5)
    check('v0.16: tons de cinza modificam alfa proporcionalmente',near(out(d,258,10)[4],0.5))
    check('v0.16: máscara esparsa cria somente tiles editados',count(m.tiles)==2)
    check('v0.16: pixels da camada são preservados pela máscara',
      select(4,Doc.getTile(layer,0,0,false):getPixel(10,10))==1)
    L.setMaskEnabled(d,2,false)
    check('v0.16: desativar máscara revela a camada',near(out(d,10,10)[4],1))
    H.undo(d)
    check('v0.16: desfazer desativação reativa máscara',m.enabled and near(out(d,10,10)[4],0))
    H.redo(d)
    check('v0.16: refazer desativação é estável',not m.enabled and near(out(d,10,10)[4],1))
    L.setMaskEnabled(d,2,true)
    L.setMaskInverted(d,2,true)
    check('v0.16: inverter máscara troca preto por branco',near(out(d,10,10)[4],1)
      and near(out(d,258,10)[4],0.5))
    H.undo(d)
    check('v0.16: desfazer inversão restaura máscara',near(out(d,10,10)[4],0))
    local dup=L.duplicate(d)
    check('v0.16: duplicar camada clona pixels e máscara',dup.mask and dup.mask~=m
      and dup.mask.tiles['0,0']~=m.tiles['0,0'])
    L.setMaskPixel(d,3,10,10,1)
    check('v0.16: edição da cópia não modifica máscara original',
      near(M.value(m,10,10),0) and near(M.value(dup.mask,10,10),1))
  end

  do
    local d=Doc.new(32,32,'v016 histórico')
    pixel(d.layers[2],4,4,{0,0,1,1})
    local c=C.newCache(d,{maxTiles=2})
    c:tile(0,0)
    local init=c:stats().recompositions
    local m=L.addMask(d,2,0)
    c:tile(0,0)
    check('v0.16: adicionar máscara invalida cache',c:stats().recompositions==init+1
      and near(out(d,4,4)[4],0))
    L.setMaskPixel(d,2,4,4,1)
    c:tile(0,0)
    check('v0.16: alterar pixels de máscara invalida cache',
      c:stats().recompositions==init+2 and near(out(d,4,4)[4],1))
    H.undo(d)
    c:tile(0,0)
    check('v0.16: undo de máscara invalida cache e restaura pixels',
      c:stats().recompositions==init+3 and near(out(d,4,4)[4],0))
    H.redo(d)
    c:tile(0,0)
    check('v0.16: redo de máscara invalida cache e restaura pixels',
      c:stats().recompositions==init+4 and near(out(d,4,4)[4],1))
    H.undo(d)
    H.undo(d)
    check('v0.16: desfazer criação remove máscara',d.layers[2].mask==nil
      and near(out(d,4,4)[4],1))
    H.redo(d)
    check('v0.16: refazer criação recupera objeto e default',
      d.layers[2].mask==m and m.default==0)
    L.setMaskPixel(d,2,4,4,0.25)
    check('v0.16: pintar máscara cria uma entrada no histórico',
      near(out(d,4,4)[4],0.25))
    local before=#d.history.undo
    L.setMaskPixel(d,2,4,4,0.25)
    check('v0.16: edição de máscara idêntica não gera undo',#d.history.undo==before)
    L.paintMaskRect(d,2,0,0,5,5,1)
    check('v0.16: preenchimento de máscara é uma ação do histórico',
      #d.history.undo==before+1 and near(out(d,4,4)[4],1))
    H.undo(d)
    check('v0.16: undo de retângulo restaura nível anterior',near(out(d,4,4)[4],0.25))
    local removed=L.removeMask(d,2)
    check('v0.16: remover máscara revela pixels e preserva histórico',
      removed and not d.layers[2].mask and near(out(d,4,4)[4],1))
    H.undo(d)
    check('v0.16: desfazer remoção recupera máscara e pixels',
      d.layers[2].mask==m and near(out(d,4,4)[4],0.25))
    check('v0.16: erro ao editar fora da região não altera histórico',
      not pcall(L.setMaskPixel,d,2,32,0,1))
    check('v0.16: valor NaN e infinito de máscara rejeitados',
      not pcall(L.setMaskPixel,d,2,0,0,0/0)
      and not pcall(L.setMaskPixel,d,2,0,0,math.huge))
    check('v0.16: dupla criação de máscara é rejeitada',
      not pcall(L.addMask,d,2,1))
  end

  do
    local d=Doc.new(10,10,'v016 erro')
    L.addMask(d,2,1)
    local old=love.image.newImageData
    love.image.newImageData=function(w,h)
      local tile=old(w,h)
      local set=tile.setPixel
      local writes=0
      function tile:setPixel(...)
        writes=writes+1
        if writes==65538 then error('erro simulado') end
        return set(self,...)
      end
      return tile
    end
    -- A inicialização branca é parte do tile (65536 escritas); falha no segundo pixel alterado.
    local ok=pcall(L.paintMaskRect,d,2,0,0,3,3,0)
    love.image.newImageData=old
    check('v0.16: falha na pintura da máscara é propagada',not ok)
    check('v0.16: rollback limpa gesto e reverte tile novo',
      d.history.stroke==nil and count(d.layers[2].mask.tiles)==0
      and #d.history.undo==1 and near(out(d,0,0)[4],0))
    L.setMaskPixel(d,2,0,0,0)
    check('v0.16: após rollback é possível editar novamente',
      M.value(d.layers[2].mask,0,0)==0)
    local mask=d.layers[2].mask
    local tile=mask.tiles['0,0']
    local originalSet=tile.setPixel
    local writes=0
    function tile:setPixel(...)
      writes=writes+1
      if writes==4 then error('falha no tile existente') end
      return originalSet(self,...)
    end
    local hist=#d.history.undo
    local ok2=pcall(L.paintMaskRect,d,2,0,0,4,4,0.5)
    check('v0.16: erro no tile de máscara existente é capturado',not ok2)
    check('v0.16: rollback recupera máscara já existente sem gerar histórico',
      near(M.value(mask,0,0),0) and near(M.value(mask,1,1),1)
      and hist==#d.history.undo and d.history.stroke==nil)
  end

  do
    local d=Doc.new(260,30,'v016 arquivo')
    pixel(d.layers[2],4,4,{0.25,0.5,0.75,1})
    local legacy=P.encode(d)
    check('v0.16: projetos sem recursos novos permanecem NPNT1',
      legacy:sub(1,6)=='NPNT1\n')
    local old=P.decode(legacy)
    check('v0.16: arquivos NPNT1 são lidos pela nova versão',
      old and not old.layers[2].mask and near(out(old,4,4)[4],1))
    L.addMask(d,2,0)
    L.setMaskPixel(d,2,4,4,0.5)
    L.setMaskEnabled(d,2,false)
    L.setMaskInverted(d,2,true)
    local modern=P.encode(d)
    check('v0.16: projeto com máscara grava assinatura NPNT2',
      modern:sub(1,6)=='NPNT2\n')
    local copy,err=P.decode(modern)
    check('v0.16: NPNT2 round-trip preserva máscara e atributos',
      copy and copy.layers[2].mask and copy.layers[2].mask.enabled==false
      and copy.layers[2].mask.inverted and copy.layers[2].mask.default==0
      and near(M.value(copy.layers[2].mask,4,4),1),tostring(err))
    check('v0.16: NPNT2 preserva pixels originais e máscara',
      copy and near(select(4,Doc.getTile(copy.layers[2],0,0,false):getPixel(4,4)),1))
    check('v0.16: formato NPNT2 é determinístico',P.encode(d)==modern)
    check('v0.16: NPNT2 truncado e com lixo são rejeitados',
      P.decode(modern:sub(1,#modern-2))==nil
      and P.decode(modern..'lixo')==nil)
    local corrupt=modern:gsub('NPNT2\n','NPNT3\n',1)
    check('v0.16: versão desconhecida continua rejeitada',P.decode(corrupt)==nil)
    local x=Doc.new(6,6,'v016 blend v2')
    L.setBlend(x,2,'overlay')
    check('v0.16: novos blends sem máscara gravam NPNT2',
      P.encode(x):sub(1,6)=='NPNT2\n' and P.decode(P.encode(x)).layers[2].blend=='overlay')
    check('v0.16: máscaras com dados inválidos são rejeitadas ao salvar',
      not pcall(function() d.layers[2].mask.default=-1;return P.encode(d) end))
    d.layers[2].mask.default=0
  end

  do
    local modes={
      normal=0.8, multiply=0.16, screen=0.84, darken=0.2, lighten=0.8,
      overlay=0.32, hardlight=0.68, difference=0.6, exclusion=0.68,
      add=1, subtract=0, color_dodge=1, color_burn=0,
    }
    local d=Doc.new(5,5,'v016 blend reference')
    pixel(d.layers[1],2,2,{0.2,0.2,0.2,1})
    pixel(d.layers[2],2,2,{0.8,0.8,0.8,1})
    for mode,expected in pairs(modes) do
      L.setBlend(d,2,mode)
      local p=out(d,2,2)
      check('v0.16: mesclagem '..mode..' com alfa opaco',
        near(p[1],expected) and near(p[2],expected) and near(p[4],1))
    end
    L.setBlend(d,2,'softlight')
    local px=out(d,2,2)
    check('v0.16: softlight W3C produz valor válido e preserva alfa',
      px[1]>0.2 and px[1]<0.8 and near(px[4],1))
    check('v0.16: modo inválido rejeitado antes de editar histórico',
      not pcall(L.setBlend,d,2,'unknown_mode'))
    L.setBlend(d,2,'screen')
    L.addMask(d,2,0.5)
    local p=out(d,2,2)
    -- A cobertura de 0,5 mistura 50% do blend (0.84) com o fundo (0.2).
    check('v0.16: blend e máscara combinam com alfa source-over',
      near(p[1],0.52) and near(p[4],1))
    check('v0.16: função de blend valida canal e aplica clamp',
      B.isValid('softlight') and not B.isValid('lixo')
      and near(B.channel('add',0.8,0.9),1))
  end

  do
    local d=Doc.new(16,16,'v016 GPU fallback')
    pixel(d.layers[2],2,2,{0.8,0.5,0.3,1})
    L.addMask(d,2)
    local original=love.graphics
    local created,replaced,drawn,released=0,0,0,0
    love.graphics={
      setScissor=function() end, setBlendMode=function() end,
      setColor=function() end,
      draw=function() drawn=drawn+1 end,
      newImage=function(data)
        created=created+1
        return {replacePixels=function() replaced=replaced+1 end,
          release=function() released=released+1 end}
      end,
    }
    local clip={x=0,y=0,w=16,h=16}
    local ok=pcall(function()
      Render.draw(d,0,0,1,clip)
      Render.draw(d,0,0,1,clip)
      L.setMaskPixel(d,2,2,2,0)
      Render.draw(d,0,0,1,clip)
      Render.clearComposited(d)
    end)
    love.graphics=original
    check('v0.16: renderer alternativo usa composição CPU ao ter máscara',ok and drawn==3)
    check('v0.16: GPU reutiliza tile até máscara mudar',created==1 and replaced==1)
    check('v0.16: cache composto da GPU é liberável',released==1)
    local other=Doc.new(10,10,'v016 blend renderer')
    pixel(other.layers[2],1,1,{0.8,0.8,0.8,1})
    L.setBlend(other,2,'overlay')
    created,drawn,released=0,0,0
    local oldG=love.graphics
    love.graphics={setScissor=function() end,setBlendMode=function() end,
      setColor=function() end,draw=function() drawn=drawn+1 end,
      newImage=function() created=created+1;return {release=function() released=released+1 end} end}
    local ok2=pcall(function()
      Render.draw(other,0,0,1,{x=0,y=0,w=10,h=10})
      Render.clearComposited(other)
    end)
    love.graphics=oldG
    check('v0.16: modo overlay sem máscara ativa compositor CPU para exibição',
      ok2 and created==1 and drawn==1 and released==1)
  end
end
