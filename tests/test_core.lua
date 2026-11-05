-- Testes do núcleo sem LÖVE: usa um mock mínimo de love.image.newImageData.
-- Rodar a partir da raiz do projeto:  texlua tests/test_core.lua
-- (ou qualquer Lua 5.1+ com ./?.lua no package.path)

package.path = "./?.lua;" .. package.path

local PNG_MOCK_HEADER = "\137PNG\r\n\26\n\0\0\0\13IHDR"

local function newImageData(w, h)
  -- Simula a decodificação de FileData; não é um decodificador PNG real.
  local encoded
  if type(w) == "table" then
    encoded = w:getString()
    local sw, sh, pos = encoded:sub(25):match("^PX1(%d+)\n(%d+)\n()")
    assert(sw and sh, "imagem codificada inválida")
    w, h = tonumber(sw), tonumber(sh)
    assert(#encoded - (24 + pos) + 1 == w * h * 4, "dados de imagem truncados")
  end
  local px = {}
  for i = 1, w * h do px[i] = {0, 0, 0, 0} end
  local img = {w = w, h = h, px = px}
  function img:getWidth() return self.w end
  function img:getHeight() return self.h end
  if encoded then
    local pos = 24 + #("PX1" .. w .. "\n" .. h .. "\n") + 1
    for i = 1, w * h do
      local r, g, b, a = encoded:byte(pos, pos + 3)
      img.px[i] = {r / 255, g / 255, b / 255, a / 255}
      pos = pos + 4
    end
  end
  function img:getPixel(x, y)
    local p = self.px[y * self.w + x + 1]
    return p[1], p[2], p[3], p[4]
  end
  function img:setPixel(x, y, r, g, b, a)
    self.px[y * self.w + x + 1] = {r, g, b, a}
  end
  function img:encode(format)
    assert(format == "png", "formato inválido")
    local function be32(n)
      return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256, n % 256)
    end
    local chunks = {PNG_MOCK_HEADER .. be32(self.w) .. be32(self.h)
      .. "PX1" .. self.w .. "\n" .. self.h .. "\n"}
    local function byte(n)
      return math.floor(math.max(0, math.min(1, n)) * 255 + 0.5)
    end
    for i = 1, #self.px do
      local p = self.px[i]
      chunks[#chunks + 1] = string.char(byte(p[1]), byte(p[2]), byte(p[3]), byte(p[4]))
    end
    local bytes = table.concat(chunks)
    return {getString = function() return bytes end}
  end
  function img:clone()
    local n = newImageData(self.w, self.h)
    for i = 1, #self.px do
      local p = self.px[i]
      n.px[i] = {p[1], p[2], p[3], p[4]}
    end
    return n
  end
  return img
end

local fakeFiles = {}
love = {
  image = {newImageData = newImageData},
  filesystem = {
    newFileData = function(bytes, name)
      return {getString = function() return bytes end, name = name}
    end,
    write = function(path, bytes)
      if path == "falha.npnt" then return nil, "falha simulada de escrita" end
      fakeFiles[path] = bytes
      return true
    end,
    read = function(path)
      if not fakeFiles[path] then return nil, "arquivo ausente" end
      return fakeFiles[path]
    end,
  },
}

local Doc = require("core.doc")
local Hist = require("core.history")
local Brush = require("core.brush")
local Composite = require("core.composite")
local Layers = require("core.layers")
local Fill = require("core.fill")
local Sample = require("core.sample")
local Job = require("core.job")
local Project = require("core.project")
local Symmetry = require("core.symmetry")
local Curve = require("core.curve")
local Stroke = require("core.stroke")
local Tip = require("core.tip")

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then
    passed = passed + 1
    print("OK    " .. name)
  else
    failed = failed + 1
    print("FALHA " .. name .. (detail and (" -> " .. detail) or ""))
  end
end

local function countTiles(layer)
  local n = 0
  for _ in pairs(layer.tiles) do n = n + 1 end
  return n
end

local function opts(extra)
  local o = {size = 20, alpha = 1, color = {1, 0, 0}, eraser = false, hardness = 1, selection = nil}
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

-- 1. Documento novo
do
  local d = Doc.new(512, 512, "t")
  check("doc tem duas camadas", #d.layers == 2)
  check("camada selecionada é a 2", d.sel == 2)
  check("camadas começam sem tiles", countTiles(d.layers[2]) == 0)
end

-- 2. Pincel pinta o pixel central de vermelho opaco
do
  local d = Doc.new(512, 512, "t")
  local L = d.layers[2]
  Hist.begin(d.history)
  Brush.dab(d, L, d.history, 100, 100, opts())
  Hist.commit(d.history)
  local r, g, b, a = Doc.getTile(L, 0, 0, false):getPixel(100, 100)
  check("dab pinta pixel central", a > 0.99 and r > 0.99 and g < 0.01, string.format("rgba=%.2f %.2f %.2f %.2f", r, g, b, a))
  check("dab cria tile", countTiles(L) == 1)
  check("dab marca tile sujo", L.dirty["0,0"] == true)
end

-- 3. Traço + desfazer/refazer
do
  local d = Doc.new(512, 512, "t")
  local L = d.layers[2]
  Hist.begin(d.history)
  Brush.line(d, L, d.history, 50, 50, 300, 300, opts({size = 10}))
  Hist.commit(d.history)
  check("traço gera uma entrada de undo", #d.history.undo == 1)
  check("traço cruza tiles", countTiles(L) >= 2, "tiles=" .. countTiles(L))

  Hist.undo(d)
  check("undo remove tiles criados pelo traço", countTiles(L) == 0, "tiles=" .. countTiles(L))
  check("undo move entrada para refazer", #d.history.redo == 1 and #d.history.undo == 0)

  Hist.redo(d)
  check("refazer restaura tiles", countTiles(L) >= 2)
  check("refazer devolve entrada ao undo", #d.history.undo == 1 and #d.history.redo == 0)
end

-- 4. Novo traço limpa refazer
do
  local d = Doc.new(512, 512, "t")
  local L = d.layers[2]
  Hist.begin(d.history); Brush.dab(d, L, d.history, 50, 50, opts()); Hist.commit(d.history)
  Hist.undo(d)
  check("undo deixa item em refazer", #d.history.redo == 1)
  Hist.begin(d.history); Brush.dab(d, L, d.history, 60, 60, opts()); Hist.commit(d.history)
  check("novo traço limpa refazer", #d.history.redo == 0)
end

-- 5. Borracha apaga
do
  local d = Doc.new(512, 512, "t")
  local L = d.layers[2]
  Brush.dab(d, L, d.history, 100, 100, opts())
  Brush.dab(d, L, d.history, 100, 100, opts({eraser = true}))
  local _, _, _, a = Doc.getTile(L, 0, 0, false):getPixel(100, 100)
  check("borracha zera alpha do pixel", a < 0.01, "alpha=" .. a)
end

-- 6. Seleção restringe o pincel
do
  local d = Doc.new(512, 512, "t")
  local L = d.layers[2]
  d.selection = {x = 0, y = 0, w = 10, h = 10}
  Brush.dab(d, L, d.history, 100, 100, opts({selection = d.selection}))
  check("pincel fora da seleção não cria tiles", countTiles(L) == 0, "tiles=" .. countTiles(L))
  Brush.dab(d, L, d.history, 5, 5, opts({selection = d.selection}))
  check("pincel dentro da seleção pinta", countTiles(L) == 1)
end

-- 7. Bordas: pincel não escreve fora do documento
do
  local d = Doc.new(100, 100, "t")
  local L = d.layers[2]
  Brush.dab(d, L, d.history, 99, 99, opts({size = 40}))
  local t = Doc.getTile(L, 0, 0, false)
  check("pincel na borda não quebra", t ~= nil and select(4, t:getPixel(99, 99)) > 0)
end

-- 8. Composição e opacidade de camada
do
  local d = Doc.new(512, 512, "t")
  local L = d.layers[2]
  Brush.dab(d, L, d.history, 100, 100, opts())
  local out = Composite.flatten(d)
  local r, g, b, a = out:getPixel(100, 100)
  check("exportação traz pixel pintado", a > 0.99 and r > 0.99, string.format("rgba=%.2f %.2f %.2f %.2f", r, g, b, a))

  L.opacity = 50
  out = Composite.flatten(d)
  local _, _, _, a2 = out:getPixel(100, 100)
  check("opacidade da camada reduz alpha exportado", math.abs(a2 - 0.5) < 0.02, "alpha=" .. a2)

  L.visible = false
  out = Composite.flatten(d)
  local _, _, _, a3 = out:getPixel(100, 100)
  check("camada oculta não é exportada", a3 == 0)
end


-- 9. Histórico de camadas: adicionar, ocultar, apagar, e desfazer/refazer
do
  local d = Doc.new(64, 64, "t")
  Layers.add(d)
  check("adicionar camada aumenta a lista", #d.layers == 3)
  check("camada nova fica selecionada", d.sel == 3)
  Hist.undo(d)
  check("desfazer remove a camada adicionada", #d.layers == 2 and d.sel == 2)
  Hist.redo(d)
  check("refazer traz a camada de volta", #d.layers == 3)

  Layers.setVisible(d, 1, false)
  check("ocultar camada", d.layers[1].visible == false)
  Hist.undo(d)
  check("desfazer ocultação restaura visibilidade", d.layers[1].visible == true)

  Layers.select(d, 1)
  check("apagar a camada de baixo funciona", Layers.delete(d) == true and #d.layers == 2)
  Hist.undo(d)
  check("desfazer apagar restaura a camada", #d.layers == 3)

  local solo = Doc.new(8, 8, "solo")
  solo.layers = {solo.layers[1]}
  solo.sel = 1
  check("não apaga a última camada", Layers.delete(solo) == false and #solo.layers == 1)
end

-- 10. Opacidade não entra no histórico
do
  local d = Doc.new(8, 8, "t")
  Layers.setOpacity(d, 2, 40)
  check("opacidade muda", d.layers[2].opacity == 40)
  check("opacidade não gera item de undo", #d.history.undo == 0)
end

-- 11. Balde: preenche região contígua e respeita barreira
do
  local d = Doc.new(64, 64, "t")
  local L = d.layers[2]
  local n = Fill.fill(d, L, 5, 5, {1, 0, 0, 1}, 0, nil)
  check("balde em área vazia preenche tudo", n == 64 * 64, "n=" .. n)
  local _, _, _, a = Fill.pixel(L, 60, 60)
  check("balde pinta o canto", a == 1)

  Hist.undo(d)
  check("desfazer balde remove os tiles", countTiles(L) == 0)

  local d2 = Doc.new(64, 64, "t")
  local L2 = d2.layers[2]
  Brush.line(d2, L2, d2.history, 32, 0, 32, 63, opts({size = 3, hardness = 1}))
  Hist.commit(d2.history)
  local n2 = Fill.fill(d2, L2, 5, 5, {0, 0, 1, 1}, 0.01, nil)
  check("balde para na barreira", n2 > 0 and n2 < 64 * 64 and n2 < 32 * 64 + 1, "n=" .. n2)
  local _, _, _, a2 = Fill.pixel(L2, 60, 5)
  check("balde não passa para o outro lado", a2 == 0)
end

-- 12. Balde respeita seleção
do
  local d = Doc.new(32, 32, "t")
  local L = d.layers[2]
  local n = Fill.fill(d, L, 1, 1, {1, 1, 1, 1}, 0, {x = 0, y = 0, w = 4, h = 4})
  check("balde limitado à seleção", n == 16, "n=" .. n)
end

-- 13. Conta-gotas
do
  local d = Doc.new(64, 64, "t")
  Brush.dab(d, d.layers[2], d.history, 10, 10, opts({color = {0, 1, 0}}))
  local r, g, b, a, idx = Sample.at(d, 10, 10)
  check("conta-gotas acha a cor pintada", a > 0.99 and g > 0.99 and idx == 2)
  check("conta-gotas em ponto vazio retorna nil", Sample.at(d, 40, 40) == nil)

  Layers.add(d)
  Brush.dab(d, d.layers[3], d.history, 10, 10, opts({color = {0, 0, 1}}))
  local _, _, b2, _, idx2 = Sample.at(d, 10, 10)
  check("conta-gotas pega a camada de cima", idx2 == 3 and b2 > 0.99)
end

-- 14. Job com coroutine
do
  local job = Job.new(function()
    for i = 1, 3 do coroutine.yield(i / 3) end
    return "fim"
  end)
  local done, res = Job.step(job, 0)
  check("job com orçamento zero faz um passo", done == false and res == nil)
  check("job informa progresso", job.progress > 0 and job.progress < 1)
  done, res = Job.step(job, 1)
  check("job termina dentro do orçamento", done == true and res == "fim")
  check("job pronto devolve o resultado de novo", select(2, Job.step(job, 0)) == "fim")
end

-- 15. Composição assíncrona bate com a bloqueante
do
  local d = Doc.new(300, 300, "t")
  Brush.line(d, d.layers[2], d.history, 10, 10, 280, 250, opts({size = 14, color = {0.2, 0.4, 0.6}}))
  Brush.dab(d, d.layers[2], d.history, 150, 150, opts({size = 30, alpha = 0.5, color = {1, 0, 0}}))
  local direct = Composite.flatten(d)
  local job = Composite.flattenAsync(d)
  local steps = 0
  while true do
    local done = Job.step(job, 0)
    steps = steps + 1
    if done then break end
    if steps > 10000 then error("job não terminou") end
  end
  local async = job.result
  local same = true
  for _, p in ipairs({{10, 10}, {150, 150}, {200, 200}, {5, 5}}) do
    local a1 = select(4, direct:getPixel(p[1], p[2]))
    local a2 = select(4, async:getPixel(p[1], p[2]))
    if math.abs(a1 - a2) > 1e-9 then same = false end
  end
  check("composição assíncrona bate com a bloqueante", same)
  check("composição assíncrona faz vários passos", steps > 1, "passos=" .. steps)
end

-- 16. Caminho do pincel
check("pincel usa Lua puro fora do LuaJIT", Brush.impl == "lua", "impl=" .. tostring(Brush.impl))

-- 17. Formato de projeto: metadados, pixels, camadas e caches
 do
  local d = Doc.new(300, 270, "Desenho\nárvore 🌳")
  d.tool = "eraser"
  d.size = 14.5
  d.opacity = 64
  d.color = {0.25, 0.5, 0.75, 0.9}
  d.selection = {x = 2, y = 3, w = 290, h = 240}
  d.layers[1].name = "Fundo\nbase"
  d.layers[1].visible = false
  Layers.setOpacity(d, 1, 42.5)
  Layers.setBlend(d, 2, "multiply")
  d.layers[2].name = "Pintura [íris]"
  Brush.dab(d, d.layers[1], d.history, 20, 20, opts({color = {0, 1, 0}}))
  Brush.dab(d, d.layers[2], d.history, 270, 260, opts({color = {1, 0, 0}}))
  Layers.add(d, "Terceira")
  Layers.setVisible(d, 3, false)
  Brush.dab(d, d.layers[3], d.history, 10, 10, opts({color = {0, 0, 1}}))
  local count = #d.history.undo
  local bytes = Project.encode(d)
  local same = Project.encode(d)
  check("serialização determinística", bytes == same)
  check("serialização não altera histórico original", #d.history.undo == count)
  local ok, err = Project.save(d, "teste.npnt")
  check("salvar projeto em memória", ok == true, tostring(err))
  local loaded, loaderr = Project.load("teste.npnt")
  check("reabrir projeto", loaded ~= nil, tostring(loaderr))
  if loaded then
    check("metadados do documento preservados", loaded.w == 300 and loaded.h == 270
      and loaded.name == d.name and loaded.sel == 3 and loaded.tool == "eraser"
      and loaded.size == 14.5 and loaded.opacity == 64)
    check("cor de ferramenta preservada", loaded.color and loaded.color[4] == 0.9
      and loaded.color[2] == 0.5)
    check("seleção retangular preservada", loaded.selection and loaded.selection.x == 2
      and loaded.selection.y == 3 and loaded.selection.w == 290 and loaded.selection.h == 240)
    check("camadas e nomes com UTF-8 preservados", #loaded.layers == 3
      and loaded.layers[1].name == "Fundo\nbase" and loaded.layers[2].name == "Pintura [íris]")
    check("propriedades das camadas preservadas", not loaded.layers[1].visible
      and loaded.layers[1].opacity == 42.5 and loaded.layers[2].blend == "multiply"
      and not loaded.layers[3].visible)
    local _, g = Fill.pixel(loaded.layers[1], 20, 20)
    local r = Fill.pixel(loaded.layers[2], 270, 260)
    local _, _, b = Fill.pixel(loaded.layers[3], 10, 10)
    check("pixels de tiles diferentes preservados", g > 0.99 and r > 0.99 and b > 0.99)
    check("tiles importados marcados para renderização", loaded.layers[1].dirty["0,0"]
      and loaded.layers[2].dirty["1,1"] and loaded.layers[3].dirty["0,0"])
    check("histórico e caches começam vazios", #loaded.history.undo == 0
      and #loaded.history.redo == 0 and next(loaded.layers[2].images) == nil)
    local previous = countTiles(d.layers[2])
    Hist.begin(loaded.history)
    Brush.dab(loaded, loaded.layers[2], loaded.history, 10, 10, opts())
    Hist.commit(loaded.history)
    Hist.undo(loaded)
    check("projeto carregado pode pintar e desfazer", #loaded.history.redo == 1
      and countTiles(d.layers[2]) == previous)
    check("reabrir não modifica o documento original", loaded.layers[2] ~= d.layers[2]
      and loaded.layers[2].tiles["1,1"] ~= d.layers[2].tiles["1,1"])
  end
end

-- 18. Projeto vazio sem cor/seleção; verificações de arquivo inválido
 do
  local d = Doc.new(8, 8, "vazio")
  local encoded = Project.encode(d)
  local loaded, err = Project.decode(encoded)
  check("projeto sem tiles abre normalmente", loaded and not loaded.selection and not loaded.color)
  check("arquivo vazio é rejeitado", Project.decode("") == nil)
  check("versão desconhecida é rejeitada", Project.decode("NPNT2\n") == nil)
  check("arquivo truncado é rejeitado", Project.decode(encoded:sub(1, #encoded - 2)) == nil)
  check("dados adicionais são rejeitados", Project.decode(encoded .. "LIXO") == nil)
  check("load inexistente retorna erro", Project.load("nao_existe.npnt") == nil)
  local ok, msg = Project.save(d, "falha.npnt")
  check("falha de escrita é propagada", not ok and msg == "falha simulada de escrita")
  fakeFiles["corrompido.npnt"] = "NPNT1\n999999\n"
  check("arquivo com dimensões perigosas é rejeitado", Project.load("corrompido.npnt") == nil)
  check("caminho vazio é rejeitado", Project.save(d, "") == nil and Project.load("") == nil)
end

-- 19. Simetria geométrica inspirada no PhotoCraft.
do
  local d = Doc.new(80, 60, "simetria")
  local v = Symmetry.points(d, 20, 10, {mode = "vertical"})
  check("simetria vertical espelha pelo centro", #v == 2 and v[2][1] == 60
    and math.abs(v[2][2] - 10) < 1e-9)
  local h = Symmetry.points(d, 20, 10, {mode = "horizontal"})
  check("simetria horizontal espelha pelo centro", #h == 2
    and math.abs(h[2][1] - 20) < 1e-9 and math.abs(h[2][2] - 50) < 1e-9)
  local dual = Symmetry.points(d, 20, 10, {mode = "dual"})
  check("simetria dupla produz 4 pontos", #dual == 4)
  local axis = Symmetry.points(d, 40, 30, {mode = "dual"})
  check("simetria não duplica pontos no cruzamento", #axis == 1)
  local center = Symmetry.points(d, 40, 11, {mode = "vertical"})
  check("simetria não duplica pontos sobre o eixo", #center == 1)
  local diagonal = Symmetry.points(d, 20, 10, {mode = "diagonal", center = {0, 0}})
  check("simetria diagonal reflete a 45 graus", #diagonal == 2
    and math.abs(diagonal[2][1] - 10) < 1e-9 and math.abs(diagonal[2][2] - 20) < 1e-9)
  local rotated = Symmetry.points(d, 20, 10, {mode = "vertical", angle = 90})
  check("eixos aceitam rotação", #rotated == 2 and math.abs(rotated[2][1] - 20) < 1e-9
    and math.abs(rotated[2][2] - 50) < 1e-9)
  check("simetria rejeita modo desconhecido", not pcall(Symmetry.points, d, 10, 10, {mode = "outro"}))
  check("simetria rejeita centro não numérico", not pcall(Symmetry.points, d, 10, 10,
    {mode = "vertical", center = {"x", 10}}))
end

-- 20. Integração do pincel: pressão, simetria e espaçamento.
do
  local d = Doc.new(80, 60, "pincel avançado")
  local L = d.layers[2]
  local o = opts({size = 8, symmetry = {mode = "vertical"}})
  Hist.begin(d.history)
  Brush.dab(d, L, d.history, 20, 10, o)
  Hist.commit(d.history)
  local _, _, _, a1 = Fill.pixel(L, 20, 10)
  local _, _, _, a2 = Fill.pixel(L, 60, 10)
  check("pincel simétrico pinta os dois lados", a1 > 0.99 and a2 > 0.99)
  check("opções originais não são modificadas", o.pressure == nil and o.size == 8)
  Hist.undo(d)
  check("desfazer remove ambos os lados do pincel simétrico", select(4, Fill.pixel(L, 20, 10)) == 0
    and select(4, Fill.pixel(L, 60, 10)) == 0)

  local p = opts({size = 20, pressure = 0.25, pressureSize = true,
    pressureOpacity = true, pressureMinSize = 0.2, pressureMinOpacity = 0})
  Brush.dab(d, L, d.history, 20, 20, p)
  local a = select(4, Fill.pixel(L, 20, 20))
  local far = select(4, Fill.pixel(L, 27, 20))
  check("pressão da caneta controla a opacidade", math.abs(a - 0.25) < 1e-7)
  check("pressão da caneta controla o diâmetro", far == 0)
  check("pressão não altera configurações do pincel", p.size == 20 and p.alpha == 1)
  check("pressão inválida é rejeitada", not pcall(Brush.dab, d, L, d.history, 10, 10,
    opts({pressure = 2, pressureSize = true})))
  local L2 = Doc.new(80, 60).layers[2]
  Brush.line(d, L2, d.history, 10, 40, 60, 40, opts({size = 5, spacing = 0.5,
    pressureSize = false, pressureOpacity = true, pressureStart = 0.1, pressureEnd = 1}))
  local first = select(4, Fill.pixel(L2, 12, 40))
  local last = select(4, Fill.pixel(L2, 60, 40))
  check("pressão é interpolada ao longo do traço", last > first and first > 0,
    string.format("começo %.3f, fim %.3f", first, last))
  check("espaçamento inválido é rejeitado", not pcall(Brush.line, d, L2, d.history,
    0, 0, 10, 10, opts({spacing = -1})))
  local bytes = Project.encode(d)
  local loaded = Project.decode(bytes)
  check("pintura simétrica/pressão é salva em NPNT1 sem alterar o formato",
    loaded and select(4, Fill.pixel(loaded.layers[2], 20, 20)) > 0)
end

-- 21. Curvas de pressão do PhotoCraft (cúbicas monótonas).
do
  local points = {{1, 1}, {0.5, 0.2}, {0, 0}}
  local c = Curve.new(points)
  check("curva de pressão respeita o ponto intermediário", math.abs(c:eval(0.5) - 0.2) < 1e-9)
  check("curva fora dos limites se mantém entre 0 e 1",
    c:eval(-5) == 0 and c:eval(5) == 1)
  local prev, monotonic = -1, true
  for i = 0, 100 do
    local v = c:eval(i / 100)
    if v < prev - 1e-9 or v < 0 or v > 1 then monotonic = false end
    prev = v
  end
  check("interpolação cúbica permanece monótona", monotonic)
  check("lista de pontos não é alterada", points[1][1] == 1 and points[3][1] == 0)
  local sameX = Curve.new({{0, 0}, {0.5, 0.1}, {0.5, 0.4}, {1, 1}})
  check("curva duplicada mantém último valor", math.abs(sameX:eval(0.5) - 0.4) < 1e-9)
  check("curva com menos de dois pontos vira linear", Curve.new({{0.6, 0.8}}):eval(0.3) == 0.3)
  check("curva recusa NaN", not pcall(Curve.new, {{0, 0}, {0/0, 1}}))
  local many = {}
  for i = 0, 25 do many[#many + 1] = {i / 25, i / 25} end
  check("curva limita a quantidade de pontos", #Curve.new(many).points == Curve.MAX_POINTS)
  check("curva rejeita entrada inválida", not pcall(Curve.value, {{}}, 0.4))
end

-- 22. Dinâmicas de pressão independentes (tamanho e opacidade).
do
  local d = Doc.new(80, 50)
  local L = d.layers[2]
  local curve = {{0, 0}, {0.5, 0.2}, {1, 1}}
  local o = opts({size = 20, pressure = 0.5, pressureSize = true,
    pressureOpacity = true, pressureCurve = curve})
  Brush.dab(d, L, d.history, 25, 25, o)
  local a = select(4, Fill.pixel(L, 25, 25))
  check("curva de pressão altera a opacidade", math.abs(a - 0.2) < 1e-8)
  check("curva de pressão altera o diâmetro", select(4, Fill.pixel(L, 30, 25)) == 0)
  check("curva mantém opções do chamador", o.pressure == 0.5
    and o.size == 20 and o.pressureCurve == curve)
  Brush.dab(d, L, d.history, 60, 25, opts({size = 20, pressure = 0.5,
    pressureSize = true, pressureOpacity = true,
    pressureSizeCurve = Curve.new({{0, 0}, {1, 1}}),
    pressureOpacityCurve = {{0, 0.6}, {1, 0.6}}}))
  local a2 = select(4, Fill.pixel(L, 60, 25))
  check("curvas separadas para tamanho e opacidade", math.abs(a2 - 0.6) < 1e-8
    and select(4, Fill.pixel(L, 64, 25)) > 0)
  local segOpts = opts({size = 4, pressureOpacity = true, pressureStart = 0.5,
    pressureEnd = 0.5, pressureCurve = {{0, 0}, {0.5, 0.2}, {1, 1}}})
  Brush.line(d, L, d.history, 10, 40, 20, 40, segOpts)
  check("curva também funciona em Brush.line", select(4, Fill.pixel(L, 20, 40)) > 0
    and segOpts.pressureCurve[2][2] == 0.2)
end

-- 23. Traço contínuo: um único undo, pressão, espaçamento e cancelamento.
do
  local d = Doc.new(120, 60, "contínuo")
  local L = d.layers[2]
  local opt = opts({size = 4, spacing = 0.5, pressureOpacity = true,
    pressureCurve = {{0, 0}, {0.5, 0.15}, {1, 1}}})
  local s = Stroke.new(d, L, d.history, opt)
  check("novo traço abre histórico", d.history.stroke ~= nil)
  s:push(10, 15, 0.1, 0)
  s:push(20, 15, 0.5, 16)
  s:push(40, 15, 1, 32)
  s:finish()
  check("traço contínuo vira uma entrada do histórico", #d.history.undo == 1
    and d.history.stroke == nil)
  local beginning = select(4, Fill.pixel(L, 10, 15))
  local ending = select(4, Fill.pixel(L, 40, 15))
  check("traço contínuo interpola pressão", beginning > 0 and ending > beginning)
  check("opções originais permanecem intactas", opt.pressureCurve[2][2] == 0.15
    and opt.pressure == nil)
  Hist.undo(d)
  check("desfazer reverte todo o traço contínuo", countTiles(L) == 0)
  Hist.redo(d)
  check("refazer repõe todo o traço contínuo", select(4, Fill.pixel(L, 40, 15)) > 0)
  local before = Project.encode(d)
  local previousUndo = #d.history.undo
  local previousRedo = #d.history.redo
  local cancel = Stroke.new(d, L, d.history, opts({size = 3}))
  cancel:push(70, 15)
  cancel:push(80, 15)
  cancel:cancel()
  check("cancelamento recupera o desenho inteiro", Project.encode(d) == before)
  check("cancelamento preserva o histórico", #d.history.undo == previousUndo
    and #d.history.redo == previousRedo and d.history.stroke == nil)
  check("traço finalizado não aceita novos eventos", not pcall(s.push, s, 50, 15))
end

-- 24. Segmentação das entradas não muda o espaçamento em linha reta.
do
  local d1 = Doc.new(100, 40)
  local d2 = Doc.new(100, 40)
  local opt = opts({size = 5, alpha = 0.35, spacing = 0.7})
  local s1 = Stroke.new(d1, d1.layers[2], d1.history, opt)
  s1:push(10, 15)
  for x = 11, 74 do s1:push(x, 15) end
  s1:finish()
  local s2 = Stroke.new(d2, d2.layers[2], d2.history, opt)
  s2:push(10, 15)
  s2:push(74, 15)
  s2:finish()
  local identical = true
  for x = 6, 78 do
    local a = select(4, Fill.pixel(d1.layers[2], x, 15))
    local b = select(4, Fill.pixel(d2.layers[2], x, 15))
    if math.abs(a - b) > 1e-9 then identical = false; break end
  end
  check("espaçamento independe dos blocos de eventos", identical)
end

-- 25. Modos de suavização e validações.
do
  local d = Doc.new(100, 50)
  local L = d.layers[2]
  local s = Stroke.new(d, L, d.history, opts({size = 2, smoothing = {
    mode = "exponential", amount = 0.8, catchUpOnEnd = false}}))
  s:push(10, 20, 1, 0)
  local x, y = s:push(40, 20, 1, 16)
  check("estabilizador exponencial atrasa o traço", math.abs(x - 16) < 1e-9 and y == 20)
  s:finish()
  check("sem catch-up, traço termina na posição suavizada",
    select(4, Fill.pixel(L, 40, 20)) == 0)
  local d2 = Doc.new(100, 50)
  local q = Stroke.new(d2, d2.layers[2], d2.history, opts({size = 2, smoothing = {
    mode = "exponential", amount = 0.8, catchUpOnEnd = true}}))
  q:push(10, 20, 1, 0)
  q:push(40, 20, 1, 16)
  q:finish()
  check("catch-up termina na última posição da caneta",
    select(4, Fill.pixel(d2.layers[2], 40, 20)) > 0)
  local d3 = Doc.new(100, 50)
  local pulled = Stroke.new(d3, d3.layers[2], d3.history, opts({size = 2,
    smoothing = {mode = "pulled", amount = 0.2, catchUpOnEnd = false}}))
  pulled:push(10, 20)
  local px = pulled:push(25, 20)
  check("pulled-string segura pincel antes do limiar", px == nil)
  px = pulled:push(50, 20)
  check("pulled-string segue a uma distância da caneta", math.abs(px - 30) < 1e-9)
  pulled:finish()
  check("pulled-string mantém o afastamento configurado",
    select(4, Fill.pixel(d3.layers[2], 50, 20)) == 0)
  check("novo traço recusa configuração inválida sem abrir histórico",
    not pcall(Stroke.new, d, L, d.history, opts({smoothing = {amount = 2}}))
      and d.history.stroke == nil)
  local invalid = Stroke.new(d, L, d.history, opts({size = 2}))
  invalid:push(5, 5, 0.5, 10)
  check("pressão inválida rejeitada sem fechar traço", not pcall(invalid.push, invalid,
    10, 10, -1, 11) and not invalid.closed)
  check("evento com tempo retrocedendo é rejeitado", not pcall(invalid.push,
    invalid, 10, 10, 0.5, 9))
  invalid:cancel()
  check("cancelamento remove até o primeiro carimbo", countTiles(L) == 1
    and select(4, Fill.pixel(L, 5, 5)) == 0)
  local empty = Stroke.new(d, L, d.history, opts({size = 2}))
  local n = #d.history.undo
  empty:finish()
  check("traço vazio não entra no histórico", #d.history.undo == n)
end


-- 0.7: pontas amostradas, inclinação, dispersão e fluxo em traços contínuos.
do
  local tip = Tip.new(3, 3, {0, 0, 0, 0, 1, 0, 0, 0, 0})
  check("ponta amostrada guarda as dimensões", tip.width == 3 and tip.height == 3)
  check("ponta bilinear lê seu centro", math.abs(Tip.sample(tip, 0.5, 0.5) - 1) < 1e-9)
  check("ponta bilinear interpola cobertura", math.abs(Tip.sample(tip, 0.25, 0.5) - 0.5) < 1e-9)
  check("ponta fora dos limites não cobre", Tip.sample(tip, 1.01, 0.5) == 0)
  check("ponta rejeita dimensão exagerada", not pcall(Tip.new, 513, 1, {1}))
  check("ponta rejeita dados truncados", not pcall(Tip.new, 2, 2, {1}))
  check("ponta rejeita valores não finitos", not pcall(Tip.new, 1, 1, {math.huge}))
  local src = {0, 1, 0}
  local copy = Tip.new(3, 1, src)
  src[2] = 0
  check("ponta copia os dados da origem", Tip.sample(copy, 0.5, 0.5) == 1)
end

do
  local d = Doc.new(256, 256, "textura")
  local L = d.layers[2]
  local center = {width = 3, height = 3, data = {0,0,0,0,1,0,0,0,0}}
  local o = opts({size = 20, tip = center})
  Brush.dab(d, L, d.history, 100.5, 100.5, o)
  check("ponta em máscara pinta o centro", select(4, Fill.pixel(L, 100, 100)) > 0.99)
  check("ponta em máscara elimina pixels dos cantos", select(4, Fill.pixel(L, 110, 110)) == 0)
  check("ponta não modifica configuração externa", o.tip == center and o.tip.data[5] == 1)
  local h = {width = 3, height = 1, data = {1,1,1}}
  local horiz = Doc.new(256, 256, "horizontal")
  Brush.dab(horiz, horiz.layers[2], horiz.history, 120.5, 120.5,
    opts({size = 24, tip = h}))
  check("ponta horizontal cobre eixo longo", select(4, Fill.pixel(horiz.layers[2], 129, 120)) > 0.99)
  check("ponta horizontal não vira círculo", select(4, Fill.pixel(horiz.layers[2], 120, 129)) == 0)
  local rot = Doc.new(256, 256, "rotacionado")
  Brush.dab(rot, rot.layers[2], rot.history, 120.5, 120.5,
    opts({size = 24, tip = h, angle = 90}))
  check("ponta girada 90 graus pinta no eixo vertical", select(4, Fill.pixel(rot.layers[2], 120, 129)) > 0.99)
  check("ponta girada não pinta fora do eixo", select(4, Fill.pixel(rot.layers[2], 129, 120)) == 0)
end

do
  local d = Doc.new(256, 256, "inclinação")
  local L = d.layers[2]
  Brush.dab(d, L, d.history, 100.5, 100.5,
    opts({size = 24, tiltX = 1, tiltY = 0, tiltScale = 0.8}))
  check("tilt afina pincel no eixo perpendicular", select(4, Fill.pixel(L, 100, 106)) == 0)
  check("tilt preserva eixo principal", select(4, Fill.pixel(L, 106, 100)) > 0.9)
  local dt = Doc.new(256, 256, "tablet")
  local stroke = Stroke.new(dt, dt.layers[2], dt.history,
    opts({size = 24, tiltScale = 0.8, spacing = 0.5}))
  stroke:push(75.5, 75.5, 1, 0, 0, 1)
  stroke:push(76.5, 75.5, 1, 16, 0, 1)
  stroke:finish()
  check("traço recebe tilt de cada evento", select(4, Fill.pixel(dt.layers[2], 82, 75)) == 0
    and select(4, Fill.pixel(dt.layers[2], 75, 82)) > 0.9)
end

do
  local a = Doc.new(256, 256, "fluxo")
  local L = a.layers[2]
  local o = opts({size = 20, alpha = 0.6, flow = 0.25, spacing = 0.15})
  local stroke = Stroke.new(a, L, a.history, o)
  stroke:push(100.5, 100.5, 1, 0)
  local first = select(4, Fill.pixel(L, 100, 100))
  check("fluxo inicia com fração da opacidade", math.abs(first - 0.15) < 1e-7,
    "primeira cobertura=" .. tostring(first))
  stroke:push(112.5, 100.5, 1, 16)
  stroke:push(100.5, 100.5, 1, 32)
  stroke:finish()
  local final = select(4, Fill.pixel(L, 100, 100))
  check("fluxo acumula tinta ao repassar", final > first + 0.01)
  check("fluxo respeita teto de opacidade", final <= 0.6000001)
  check("fluxo gera um único item de desfazer", #a.history.undo == 1)
  Hist.undo(a)
  check("desfazer fluxo reverte pixels", countTiles(L) == 0)
  Hist.redo(a)
  check("refazer fluxo restaura cobertura", math.abs(select(4, Fill.pixel(L, 100, 100)) - final) < 1e-7)
  local direct = Doc.new(256, 256, "carimbo")
  Brush.dab(direct, direct.layers[2], direct.history, 100.5, 100.5,
    opts({size = 20, alpha = 0.8, flow = 0.25}))
  check("fluxo também funciona em Brush.dab", math.abs(select(4, Fill.pixel(direct.layers[2], 100, 100)) - 0.2) < 1e-7)
  local cancelled = Stroke.new(a, L, a.history, opts({size = 15, flow = 0.3}))
  cancelled:push(160, 160)
  cancelled:cancel()
  check("cancelamento remove tinta com fluxo", select(4, Fill.pixel(L, 160, 160)) == 0)
  check("cancelamento de fluxo preserva undo", #a.history.undo == 1)
end

do
  local function paint(seed)
    local d = Doc.new(256, 256, "dispersão")
    local stroke = Stroke.new(d, d.layers[2], d.history,
      opts({size = 6, scatter = 2.5, seed = seed, spacing = 0.2}))
    for x = 110, 124, 2 do stroke:push(x + 0.5, 120.5, 1) end
    stroke:finish()
    return d
  end
  local a, b, c = paint(123), paint(123), paint(124)
  local same, different = true, false
  for y = 100, 140 do
    for x = 90, 145 do
      local pa = select(4, Fill.pixel(a.layers[2], x, y))
      local pb = select(4, Fill.pixel(b.layers[2], x, y))
      local pc = select(4, Fill.pixel(c.layers[2], x, y))
      if math.abs(pa - pb) > 1e-9 then same = false end
      if math.abs(pa - pc) > 1e-9 then different = true end
    end
  end
  check("dispersão reproduz pixels com mesma seed", same)
  check("dispersão muda com seed distinta", different)
  local s = Doc.new(256, 256, "simetria")
  Brush.dab(s, s.layers[2], s.history, 100, 120,
    opts({size = 6, scatter = 1.8, seed = 17, dabIndex = 3,
      symmetry = {mode = "vertical", center = {128, 128}}}))
  local symmetric = true
  for y = 100, 140 do for x = 80, 127 do
    if math.abs(select(4, Fill.pixel(s.layers[2], x, y))
       - select(4, Fill.pixel(s.layers[2], 255 - x, y))) > 1e-7 then
      symmetric = false
    end
  end end
  check("dispersão respeita espelhamento", symmetric)
end

do
  local d = Doc.new(256, 256, "opções")
  local L = d.layers[2]
  local bad = {
    {flow = -0.1}, {flow = math.huge}, {scatter = -1}, {scatter = 11},
    {seed = -1}, {seed = 0.5}, {tiltScale = 2}, {tiltX = 2},
    {tip = {width = 2, height = 2, data = {1}}},
  }
  local all = true
  for _, extra in ipairs(bad) do
    local ok = pcall(Stroke.new, d, L, d.history, opts(extra))
    if ok then all = false; d.history.stroke = nil end
  end
  check("traço rejeita opções novas inválidas", all and d.history.stroke == nil)
  local s = Stroke.new(d, L, d.history, opts({flow = 0.2}))
  local before = #d.history.undo
  check("evento tilt inválido é rejeitado", not pcall(s.push, s, 10, 10, 1, nil, 10, 0))
  check("erro de tilt não altera pixels", countTiles(L) == 0)
  s:cancel()
  check("cancelamento não cria histórico após entrada rejeitada", #d.history.undo == before)
end


-- Fluxo e máscara precisam respeitar a tinta anterior e os limites do documento.
do
  local d = Doc.new(256, 256, "sobre fundo")
  local L = d.layers[2]
  Brush.dab(d, L, d.history, 100.5, 100.5,
    opts({size = 20, color = {0, 1, 0}}))
  local stroke = Stroke.new(d, L, d.history,
    opts({size = 20, color = {1, 0, 0}, flow = 0.5, alpha = 0.6}))
  stroke:push(100.5, 100.5)
  stroke:finish()
  local r, g, _, a = Fill.pixel(L, 100, 100)
  check("fluxo compõe sobre camada previamente opaca", math.abs(r - 0.3) < 1e-8
    and math.abs(g - 0.7) < 1e-8 and a == 1)
  Hist.undo(d)
  r, g, _, a = Fill.pixel(L, 100, 100)
  check("undo de fluxo recupera cores e alfa anteriores", r == 0 and g == 1 and a == 1)
  Hist.redo(d)
  r, g, _, a = Fill.pixel(L, 100, 100)
  check("redo de fluxo recupera cores compostas", math.abs(r - 0.3) < 1e-8)

  local eraser = Stroke.new(d, L, d.history,
    opts({size = 20, eraser = true, flow = 0.25, alpha = 0.8}))
  eraser:push(100.5, 100.5)
  eraser:push(106.5, 100.5)
  eraser:push(100.5, 100.5)
  eraser:finish()
  local ea = select(4, Fill.pixel(L, 100, 100))
  check("borracha com fluxo apaga progressivamente", ea < 0.8 and ea >= 0.2)
  Hist.undo(d)
  check("undo da borracha recupera alfa anterior", select(4, Fill.pixel(L, 100, 100)) == 1)
  Hist.redo(d)
  check("redo da borracha restaura alfa apagado", math.abs(select(4, Fill.pixel(L, 100, 100)) - ea) < 1e-8)
end

do
  local d = Doc.new(512, 256, "cruzando tiles")
  local L = d.layers[2]
  local base = opts({size = 12, alpha = 0.7, flow = 0.3, scatter = 0,
    selection = {x = 250, y = 60, w = 20, h = 20}})
  local o = {}
  for k, v in pairs(base) do o[k] = v end
  local stroke = Stroke.new(d, L, d.history, o)
  stroke:push(255, 70)
  stroke:push(264, 70)
  stroke:finish()
  check("fluxo cruza borda de tiles", countTiles(L) == 2
    and select(4, Fill.pixel(L, 252, 70)) > 0
    and select(4, Fill.pixel(L, 260, 70)) > 0)
  check("fluxo mantém máscara de seleção", select(4, Fill.pixel(L, 249, 70)) == 0
    and select(4, Fill.pixel(L, 270, 70)) == 0)
  check("novos módulos não modificam opções do chamador", o.flow == 0.3
    and o.scatter == 0 and o.dabIndex == nil and o._ink == nil)
  Hist.undo(d)
  check("undo do fluxo atravessando tiles limpa ambas", countTiles(L) == 0)
end

do
  local d = Doc.new(256, 256, "sem tinta")
  local L = d.layers[2]
  local s = Stroke.new(d, L, d.history, opts({flow = 0}))
  s:push(110, 110)
  s:finish()
  check("fluxo zero não cria tiles nem histórico", countTiles(L) == 0
    and #d.history.undo == 0)
end


-- A API de linha direta avança o índice do carimbo sem tocar nas opções externas.
do
  local a = Doc.new(256, 256, "linha dispersa")
  local b = Doc.new(256, 256, "manual")
  local o = opts({size = 8, spacing = 0.5, scatter = 2, seed = 42})
  Brush.line(a, a.layers[2], a.history, 100, 100, 120, 100, o)
  for i = 1, 5 do
    local one = opts({size = 8, spacing = 0.5, scatter = 2,
      seed = 42, dabIndex = i - 1})
    Brush.dab(b, b.layers[2], b.history, 100 + 4 * i, 100, one)
  end
  local equal = true
  for y = 75, 125 do for x = 80, 145 do
    if math.abs(select(4, Fill.pixel(a.layers[2], x, y))
      - select(4, Fill.pixel(b.layers[2], x, y))) > 1e-9 then equal = false end
  end end
  check("Brush.line usa índice de dispersão por carimbo", equal)
  check("Brush.line não altera seed ou índice do chamador", o.seed == 42 and o.dabIndex == nil)
  check("Brush.dab rejeita tilt não finito", not pcall(Brush.dab, a, a.layers[2],
    a.history, 120, 100, opts({tiltX = math.huge})))
  check("Brush.dab rejeita ângulo infinito", not pcall(Brush.dab, a, a.layers[2],
    a.history, 120, 100, opts({angle = math.huge})))
end


-- v0.8 — textura de papel, pincel duplo e mistura de pigmentos
local Texture = require('core.texture')
local Mixer = require('core.mixer')
local function approx(a,b,eps) return math.abs(a-b) <= (eps or 1e-8) end
local function alphaAt(layer,x,y) return select(4,Fill.pixel(layer,x,y)) end

-- Interpolação de textura cíclica (inclusive sobre borda negativa).
do
  local stripe=Tip.new(2,1,{1,0})
  check('repetição de textura: origem', Tip.sampleRepeat(stripe,0,0)==1)
  check('repetição de textura: próximo texel',Tip.sampleRepeat(stripe,1,0)==0)
  check('repetição de textura: volta ao início',Tip.sampleRepeat(stripe,2,0)==1)
  check('repetição de textura: índices negativos',Tip.sampleRepeat(stripe,-1,0)==0)
  check('repetição de textura: interpolação bilinear na emenda',approx(Tip.sampleRepeat(stripe,1.5,0),0.5))
  local twod=Tip.new(2,2,{0,0,0,1})
  check('repetição de textura: bilinear 2D',approx(Tip.sampleRepeat(twod,0.5,0.5),0.25))
  check('repetição de textura: tip original não alterado',stripe.data[1]==1 and stripe.data[2]==0)
end

do
  local mask=Tip.new(2,1,{1,0})
  local d=Doc.new(512,256,'papel')
  local L=d.layers[2]
  local paper={tip=mask,scale=1,depth=1}
  Hist.begin(d.history)
  Brush.dab(d,L,d.history,255.5,110.5,opts({size=18,paper=paper}))
  Hist.commit(d.history)
  check('papel: pixels alternados na borda do tile',alphaAt(L,254,110)>0.9 and alphaAt(L,255,110)==0 and alphaAt(L,256,110)>0.9)
  check('papel: repete padrão após tile',approx(alphaAt(L,254,110),alphaAt(L,258,110)))
  check('papel: produz tiles em ambos os lados',countTiles(L)==2)
  check('papel: cópia não altera configuração',paper.tip==mask and paper.scale==1 and paper.depth==1)
  check('papel: registro de undo',#d.history.undo==1)
  Hist.undo(d)
  check('papel: undo remove ambos os tiles',countTiles(L)==0)
  Hist.redo(d)
  check('papel: redo recupera padrão',alphaAt(L,254,110)>0.9 and alphaAt(L,255,110)==0)
  local inv=Doc.new(512,256,'invertido')
  Brush.dab(inv,inv.layers[2],inv.history,255.5,110.5,opts({size=18,paper={tip=mask,invert=true}}))
  check('papel: inverter máscara',alphaAt(inv.layers[2],255,110)>0.9 and alphaAt(inv.layers[2],254,110)==0)
  local shifted=Doc.new(512,256,'deslocado')
  Brush.dab(shifted,shifted.layers[2],shifted.history,255.5,110.5,opts({size=18,paper={tip=mask,offsetX=1}}))
  check('papel: deslocamento no documento',alphaAt(shifted.layers[2],255,110)>0.9 and alphaAt(shifted.layers[2],254,110)==0)
  local half=Doc.new(512,256,'profundidade')
  Brush.dab(half,half.layers[2],half.history,255.5,110.5,opts({size=18,paper={tip=mask,depth=0.5}}))
  check('papel: profundidade parcial',approx(alphaAt(half.layers[2],255,110),0.5))
  local zero=Doc.new(256,256,'sem marca')
  local sz=Stroke.new(zero,zero.layers[2],zero.history,opts({size=20,paper={tip=Tip.new(1,1,{0})}}))
  sz:push(100,100); sz:finish()
  check('papel: cobertura zero não aloca tile',countTiles(zero.layers[2])==0)
  check('papel: cobertura zero não cria undo',#zero.history.undo==0)
end

do
  local stripe=Tip.new(2,1,{1,0})
  local d=Doc.new(256,256,'dual')
  local L=d.layers[2]
  local dual={tip=stripe,angle=0,scale=1,depth=1}
  Brush.dab(d,L,d.history,100.5,100.5,opts({size=30,dualBrush=dual}))
  check('pincel duplo: máscara assimétrica',alphaAt(L,94,100)>alphaAt(L,106,100))
  check('pincel duplo: centro com cobertura parcial',alphaAt(L,100,100)>0 and alphaAt(L,100,100)<1)
  check('pincel duplo: mantém configuração do chamador',dual.tip==stripe and dual.scale==1)
  local rotated=Doc.new(256,256,'dual girado')
  Brush.dab(rotated,rotated.layers[2],rotated.history,100.5,100.5,
    opts({size=30,dualBrush={tip=stripe,angle=90}}))
  check('pincel duplo: rotação de ponta secundária',
    alphaAt(rotated.layers[2],100,94)>alphaAt(rotated.layers[2],100,106))
  for _,mode in ipairs({'multiply','subtract','darken','overlay'}) do
    local x=Texture.combine(0.7,0.3,0.75,mode)
    check('máscara dupla: combinação '..mode,x>=0 and x<=1)
  end
  check('máscara dupla: profundidade zero não altera cobertura',
    Texture.combine(0.7,0,0,'multiply')==0.7)
  local plain=Doc.new(256,256,'original')
  local disabled=Doc.new(256,256,'duplo desativado')
  Brush.dab(plain,plain.layers[2],plain.history,100.5,100.5,opts({size=30}))
  Brush.dab(disabled,disabled.layers[2],disabled.history,100.5,100.5,
    opts({size=30,dualBrush={tip=stripe,depth=0}}))
  check('pincel duplo: desativado é idêntico ao pincel antigo',
    approx(alphaAt(plain.layers[2],104,103),alphaAt(disabled.layers[2],104,103)))
end

do
  local d=Doc.new(256,256,'mistura')
  local L=d.layers[2]
  Brush.dab(d,L,d.history,100.5,100.5,opts({size=20,color={0,1,0}}))
  Brush.dab(d,L,d.history,100.5,100.5,opts({size=20,color={1,0,0},mix={strength=1}}))
  local r,g,b,a=Fill.pixel(L,100,100)
  check('mistura: força 100% coleta a tinta do documento',r==0 and g==1 and b==0 and a==1)
  Brush.dab(d,L,d.history,100.5,100.5,opts({size=20,color={1,0,0},mix={strength=0.5}}))
  r,g,b=Fill.pixel(L,100,100)
  check('mistura: 50% combina cor de tinta e superfície',approx(r,0.5) and approx(g,0.5) and b==0)
  local fresh=Doc.new(256,256,'mistura transparente')
  Brush.dab(fresh,fresh.layers[2],fresh.history,100.5,100.5,
    opts({size=20,mix={strength=1},color={1,0,0}}))
  r,g,b=Fill.pixel(fresh.layers[2],100,100)
  check('mistura: transparência pura não introduz preto',r==1 and g==0 and b==0)
  local diluted=Doc.new(256,256,'mistura alfa')
  Brush.dab(diluted,diluted.layers[2],diluted.history,100.5,100.5,
    opts({size=20,color={0,1,0},alpha=0.5}))
  Brush.dab(diluted,diluted.layers[2],diluted.history,100.5,100.5,
    opts({size=20,color={1,0,0},mix={strength=1}}))
  r,g,b=Fill.pixel(diluted.layers[2],100,100)
  check('mistura: coleta proporcional ao alfa existente',approx(r,0.5) and approx(g,0.5))
  local neighbor=Doc.new(256,256,'raio de coleta')
  Brush.dab(neighbor,neighbor.layers[2],neighbor.history,102.5,100.5,
    opts({size=1,color={0,1,0}}))
  Brush.dab(neighbor,neighbor.layers[2],neighbor.history,100.5,100.5,
    opts({size=1,color={1,0,0},mix={strength=1,radius=2}}))
  r,g=Fill.pixel(neighbor.layers[2],100,100)
  check('mistura: raio coleta pigmento vizinho',r<1 and g>0)
end

do
  local tex=Tip.new(2,1,{1,0.5})
  local d=Doc.new(256,256,'gesto completo')
  local L=d.layers[2]
  local o=opts({size=20,alpha=0.7,flow=0.35,spacing=0.2,
    paper={tip=tex,scale=2},dualBrush={tip=tex,depth=0.4},
    mix={strength=0.4,radius=1},scatter=0.1,seed=200})
  local gesture=Stroke.new(d,L,d.history,o)
  gesture:push(88.5,90.5,0.8,0)
  gesture:push(110.5,90.5,0.9,16)
  gesture:push(88.5,90.5,0.8,32)
  gesture:finish()
  local ar,ag,ab,aa=Fill.pixel(L,100,90)
  check('gesto v0.8: pinta sem estourar teto de opacidade',aa>0 and aa<=0.7+1e-8)
  check('gesto v0.8: registra uma única ação',#d.history.undo==1)
  check('gesto v0.8: preserva parâmetros externos',o.paper.tip==tex and o.dualBrush.tip==tex and o.mix.strength==0.4 and o.dabIndex==nil)
  Hist.undo(d)
  check('gesto v0.8: undo restaura pixels',alphaAt(L,100,90)==0)
  Hist.redo(d)
  local rr,rg,rb,ra=Fill.pixel(L,100,90)
  check('gesto v0.8: redo restaura pigmentos',approx(rr,ar) and approx(rg,ag) and approx(rb,ab) and approx(ra,aa))
  local active=Stroke.new(d,L,d.history,o)
  active:push(30.5,30.5)
  active:cancel()
  check('gesto v0.8: cancelamento limpa área',alphaAt(L,30,30)==0)
  check('gesto v0.8: cancelamento não altera histórico',#d.history.undo==1)
end

do
  local pattern={width=1,height=1,data={1}}
  local invalid={
    {paper={tip=pattern,scale=0}},
    {paper={tip=pattern,depth=1.1}},
    {paper={tip=pattern,offsetX=math.huge}},
    {paper={tip=pattern,mode='desconhecido'}},
    {paper={tip=pattern,invert=1}},
    {paper={scale=1}},
    {dualBrush={tip=pattern,scale=-1}},
    {dualBrush={tip=pattern,depth=-0.1}},
    {dualBrush={tip=pattern,angle=math.huge}},
    {dualBrush={tip=pattern,mode='desconhecido'}},
    {dualBrush={scale=1}},
    {mix={strength=2}},
    {mix={strength=-1}},
    {mix={radius=2.5}},
    {mix={radius=9}},
  }
  local d=Doc.new(256,256,'entradas inválidas')
  local okStroke=true
  local okDab=true
  for _,b in ipairs(invalid) do
    if pcall(Stroke.new,d,d.layers[2],d.history,opts(b)) then
      okStroke=false
      d.history.stroke=nil
    end
    if pcall(Brush.dab,d,d.layers[2],d.history,100.5,100.5,opts(b)) then okDab=false end
  end
  check('validação v0.8: Stroke.new rejeita 15 opções inválidas',okStroke)
  check('validação v0.8: Brush.dab rejeita 15 opções inválidas',okDab)
  check('validação v0.8: falhas não deixam tiles',countTiles(d.layers[2])==0)
  check('validação v0.8: falhas não abrem transação',d.history.stroke==nil)
end

-- v0.8: carimbos com pigmentos diferentes no mesmo gesto misturam os
-- pigmentos acumulados, em vez de substituir os anteriores.
do
  local d=Doc.new(256,256,'pigmentos no fluxo')
  local L=d.layers[2]
  local ink={}
  local red=opts({size=16,color={1,0,0},alpha=1,flow=0.5,_ink=ink})
  local blue=opts({size=16,color={0,0,1},alpha=1,flow=0.5,_ink=ink})
  Hist.begin(d.history)
  Brush.dab(d,L,d.history,100.5,100.5,red)
  Brush.dab(d,L,d.history,100.5,100.5,blue)
  Hist.commit(d.history)
  local r,g,b,a=Fill.pixel(L,100,100)
  check('mistura de pigmentos no fluxo: tinta de carimbos anteriores preservada',
    approx(r,2/3) and g==0 and approx(b,1/3) and approx(a,0.75))
  Hist.undo(d)
  check('mistura de pigmentos no fluxo: undo recupera transparência',countTiles(L)==0)
end

-- Compatibilidade de Brush.line e persistência com os parâmetros novos.
do
  local d=Doc.new(256,256,'arquivo com pintura v0.8')
  local L=d.layers[2]
  local brushSettings=opts({size=14,flow=0.75,
    dualBrush={tip=Tip.new(1,1,{1}),depth=0.3},
    paper={tip=Tip.new(2,1,{1,0.6}),depth=0.6},
    mix={strength=0}})
  Brush.line(d,L,d.history,40.5,40.5,60.5,40.5,brushSettings)
  check('Brush.line v0.8: novas opções integradas sem mutação',
    alphaAt(L,44,40)>0 and brushSettings.mix.strength==0
    and brushSettings.paper.depth==0.6 and brushSettings.dualBrush.depth==0.3)
  local saved=Project.encode(d)
  local copy,err=Project.decode(saved)
  check('formato .npnt preserva pixels criados pela v0.8',
    copy~=nil and approx(alphaAt(copy.layers[2],44,40),alphaAt(L,44,40),1/255+1e-8))
end

-- v0.9: reservatório de tinta, coleta de pigmento e secagem por carimbo.
do
  local MixerWet=require('core.mixer')
  local config={wet=0.75,load=0.4,mix=0.6,flow=0.9,radius=2}
  local prepared=MixerWet.prepareWet(config)
  check('tinta úmida: configuração é normalizada',prepared.wet==0.75 and prepared.radius==2)
  check('tinta úmida: configurações externas não são alteradas',
    config.wet==0.75 and config.radius==2 and getmetatable(config)==nil)
  check('tinta úmida: objeto preparado pode ser reutilizado',
    MixerWet.prepareWet(prepared)==prepared)
  local defaults=MixerWet.prepareWet({})
  check('tinta úmida: parâmetros padrão previsíveis',
    defaults.wet==0.5 and defaults.load==0.5 and defaults.mix==0.5
    and defaults.flow==1 and defaults.radius==0)
  local wetState=MixerWet.newWetState({1,0,0})
  check('tinta úmida: reservatório começa carregado',
    wetState.amount==1 and wetState.reservoir[1]==1 and wetState.pickup==nil)
  MixerWet.cleanWet(wetState)
  check('tinta úmida: limpar remove reservatório e pigmento coletado',
    wetState.amount==0 and wetState.pickup==nil and wetState.reservoir==nil)
  MixerWet.loadWet(wetState,{0,0,1})
  check('tinta úmida: carregar define nova cor sem pigmento artificial',
    wetState.amount==1 and wetState.reservoir[3]==1 and wetState.pickup==nil)
  local invalids={
    {wet=-0.1},{wet=1.1},{load=-1},{load=1.1},
    {mix=-0.5},{mix=2},{flow=-1},{flow=2},
    {radius=-1},{radius=9},{radius=1.5},{radius=math.huge},
    {wet=0/0},{mix='a'},{example=1},
  }
  local allReject=true
  for _,invalid in ipairs(invalids) do
    if pcall(MixerWet.prepareWet,invalid) then allReject=false end
  end
  check('tinta úmida: 15 configurações inválidas rejeitadas',allReject)
  check('tinta úmida: cor de carregamento inválida rejeitada',
    not pcall(MixerWet.newWetState,{-1,0,0})
    and not pcall(MixerWet.loadWet,wetState,{1,math.huge,1}))
end

do
  local MixerWet=require('core.mixer')
  local d=Doc.new(256,256,'amostra de tinta')
  local L=d.layers[2]
  local t=Doc.getTile(L,0,0,true)
  t:setPixel(100,100,0,1,0,1)
  t:setPixel(101,100,1,0,0,0)
  local color,alpha=MixerWet.sampleWet(d,L,100.5,100.5,1)
  check('tinta úmida: coleta alfa-ponderada, transparente não vira preto',
    color[1]==0 and color[2]==1 and color[3]==0 and approx(alpha,1/9))
  local none,cov=MixerWet.sampleWet(d,L,100.5,100.5,0,{x=110,y=110,w=5,h=5})
  check('tinta úmida: amostra respeita seleção',none==nil and cov==0)
  local edge,weight=MixerWet.sampleWet(d,L,-1,100,1)
  check('tinta úmida: amostragem fora do documento é segura',edge==nil and weight==0)
  local state=MixerWet.newWetState({1,0,0})
  local wet={wet=1,load=1,mix=1,flow=1,radius=0}
  local pigment,amount=MixerWet.wetDab(d,L,100.5,100.5,wet,state)
  check('tinta úmida: reservatório coleta verde ao tocar pigmento',
    pigment[1]==0 and pigment[2]==1 and pigment[3]==0 and approx(amount,0.25))
  local carried,remaining=MixerWet.wetDab(d,L,150.5,150.5,wet,state)
  check('tinta úmida: transporta cor para área transparente',
    carried and carried[2]==1 and remaining>0 and remaining<amount)
  local dry=MixerWet.newWetState({1,0,0})
  local a,b=MixerWet.wetDab(d,L,150.5,150.5,{wet=0,load=0,mix=0},dry)
  local c,dd=MixerWet.wetDab(d,L,151.5,150.5,{wet=0,load=0,mix=0},dry)
  check('tinta úmida: carga zero perde tinta de maneira progressiva',
    a[1]==1 and c[1]==1 and approx(b,1) and approx(dd,0.8))
  local full=MixerWet.newWetState({1,0,0})
  MixerWet.wetDab(d,L,150.5,150.5,{wet=0,load=1,mix=0},full)
  check('tinta úmida: carga máxima não esgota o reservatório',full.amount==1)
  local clean=MixerWet.newWetState({1,0,0})
  MixerWet.cleanWet(clean)
  local noColor,noAmount=MixerWet.wetDab(d,L,150.5,150.5,wet,clean)
  check('tinta úmida: pincel limpo não pinta o transparente',
    noColor==nil and noAmount==0)
end

do
  local d=Doc.new(256,256,'pincel úmido direto')
  local L=d.layers[2]
  local brushOpt=opts({size=10,wetPaint={wet=0,load=1,mix=0,flow=0.4}})
  Brush.dab(d,L,d.history,30.5,30.5,brushOpt)
  local r,g,b,a=Fill.pixel(L,30,30)
  check('Brush.dab úmido: fluxo controla opacidade sem alterar cor',
    approx(a,0.4) and r==1 and g==0 and b==0)
  check('Brush.dab úmido: opções externas não são alteradas',
    brushOpt.wetPaint.flow==0.4 and brushOpt._wetState==nil and brushOpt.flow==nil)
  local dry=Doc.new(256,256,'tinta úmida desligada')
  Brush.dab(dry,dry.layers[2],dry.history,30.5,30.5,opts({size=10}))
  check('Brush.dab antigo: sem wetPaint continua opaco',
    approx(alphaAt(dry.layers[2],30,30),1))
  local fullMix=Doc.new(256,256,'sem tinta em branco')
  local empty=opts({wetPaint={wet=1,load=1,mix=1,flow=1}})
  Brush.dab(fullMix,fullMix.layers[2],fullMix.history,30.5,30.5,empty)
  check('tinta úmida: absorção 100% em superfície vazia não cria tinta',
    countTiles(fullMix.layers[2])==0)
  local invalid=Doc.new(256,256,'inválido úmido')
  local rejectDab=not pcall(Brush.dab,invalid,invalid.layers[2],invalid.history,30.5,30.5,
    opts({wetPaint={wet=0.5},mix={strength=1}}))
  local rejectEraser=not pcall(Brush.dab,invalid,invalid.layers[2],invalid.history,30.5,30.5,
    opts({wetPaint={wet=0.5},eraser=true}))
  local rejectStroke=not pcall(Stroke.new,invalid,invalid.layers[2],invalid.history,
    opts({wetPaint={wet=1.1}}))
  check('tinta úmida: conflito com mix rejeitado',rejectDab)
  check('tinta úmida: conflito com borracha rejeitado',rejectEraser)
  check('tinta úmida: Stroke rejeita parâmetro inválido antes da transação',
    rejectStroke and invalid.history.stroke==nil and countTiles(invalid.layers[2])==0)
end

do
  local d=Doc.new(256,256,'pincel úmido contínuo')
  local L=d.layers[2]
  local o=opts({size=1,spacing=1,alpha=1,
    wetPaint={wet=0,load=0,mix=0,flow=1}})
  Brush.line(d,L,d.history,20.5,20.5,28.5,20.5,o)
  local early=alphaAt(L,21,20)
  local late=alphaAt(L,28,20)
  check('Brush.line úmido: reservatório compartilhado entre carimbos',
    early>late and late>0 and late<0.5)
  check('Brush.line úmido: não altera opção do chamador',
    o._ink==nil and o._wetState==nil and o.wetPaint.load==0)
  local always=Doc.new(256,256,'pincel úmido com carga cheia')
  Brush.line(always,always.layers[2],always.history,20.5,20.5,28.5,20.5,
    opts({size=1,spacing=1,wetPaint={wet=0,load=1,mix=0}}))
  check('Brush.line úmido: carga 100% mantém fluxo estável',
    approx(alphaAt(always.layers[2],21,20),alphaAt(always.layers[2],28,20)))
  local localInk=Doc.new(256,256,'mistura contínua')
  local il=localInk.layers[2]
  Doc.getTile(il,0,0,true):setPixel(40,40,0,1,0,1)
  local gesture=Stroke.new(localInk,il,localInk.history,
    opts({size=1,spacing=1,wetPaint={wet=1,load=1,mix=1,radius=0}}))
  gesture:push(40.5,40.5)
  gesture:push(42.5,40.5)
  gesture:finish()
  local r,g,b,a=Fill.pixel(il,42,40)
  check('Stroke úmido: coleta verde e deposita no próximo pixel transparente',
    r==0 and g==1 and b==0 and a>0)
  check('Stroke úmido: gesto inteiro vira um único undo',#localInk.history.undo==1)
  Hist.undo(localInk)
  check('Stroke úmido: undo restaura pigmento original e remove o novo',
    alphaAt(il,42,40)==0 and alphaAt(il,40,40)==1)
  Hist.redo(localInk)
  check('Stroke úmido: redo restaura tinta transportada',alphaAt(il,42,40)>0)
end

do
  local d=Doc.new(512,256,'v0.9 integração')
  local L=d.layers[2]
  local c=Tip.new(1,1,{1})
  local external=opts({size=15,alpha=0.7,spacing=0.4,flow=0.5,
    paper={tip=c,depth=0.3},dualBrush={tip=c,depth=0.1},
    wetPaint={wet=0,load=1,mix=0,flow=0.8},scatter=0,seed=7})
  local s=Stroke.new(d,L,d.history,external)
  s:push(250.5,100.5)
  s:push(261.5,100.5)
  s:finish()
  check('tinta úmida: pintura atravessa limite de tile',
    alphaAt(L,254,100)>0 and alphaAt(L,257,100)>0)
  check('tinta úmida: respeita teto do gesto com flow e papel',
    alphaAt(L,255,100)<=0.7+1e-8)
  check('tinta úmida: não altera papel, ponta dupla nem configuração externa',
    external._ink==nil and external._wetState==nil and external.paper.tip==c
    and external.dualBrush.tip==c and external.wetPaint.wet==0)
  local sample=alphaAt(L,257,100)
  local saved=Project.encode(d)
  local opened=Project.decode(saved)
  check('tinta úmida: pixels resultantes persistem em .npnt',
    opened and approx(alphaAt(opened.layers[2],257,100),sample,1/255+1e-8))
  Hist.undo(d)
  check('tinta úmida: undo atravessa tile',alphaAt(L,257,100)==0)
  Hist.redo(d)
  check('tinta úmida: redo atravessa tile',approx(alphaAt(L,257,100),sample))
  local cancelled=Stroke.new(d,L,d.history,external)
  cancelled:push(120.5,140.5)
  cancelled:cancel()
  check('tinta úmida: cancelamento restaura pixels sem novo histórico',
    alphaAt(L,120,140)==0 and #d.history.undo==1)
end

do
  local d=Doc.new(256,256,'limpar e carregar')
  local L=d.layers[2]
  local stroke=Stroke.new(d,L,d.history,opts({size=1,spacing=1,
    wetPaint={wet=0,load=1,mix=0,flow=1}}))
  stroke:push(20.5,20.5)
  stroke:cleanWet()
  stroke:push(23.5,20.5)
  check('tinta úmida: limpar remove depósito de tinta',
    alphaAt(L,20,20)>0 and alphaAt(L,23,20)==0)
  stroke:loadWet({0,0,1})
  stroke:push(26.5,20.5)
  local r,g,b,a=Fill.pixel(L,26,20)
  check('tinta úmida: recarregamento muda cor do pincel no mesmo gesto',
    r==0 and g==0 and b==1 and a>0)
  stroke:finish()
  check('tinta úmida: ações de limpeza/carga mantêm um só undo',#d.history.undo==1)
  check('tinta úmida: não se pode recarregar após finalizar',
    not pcall(stroke.loadWet,stroke,{1,0,0}))
  local base=Stroke.new(d,L,d.history,opts({size=1,
    wetPaint={wet=1,load=1,mix=1,flow=1}}))
  base:push(80.5,80.5)
  base:finish()
  check('tinta úmida: gesto sem pigmento não ocupa histórico',#d.history.undo==1)
end

-- v0.10: equivalência visual e custos evitados no caminho Lua puro.
do
  local Render = require('core.render')
  local d = Doc.new(1024,1024,'viewport')
  local L = d.layers[2]
  local calls, colors = {}, {}
  local old = love.graphics
  love.graphics = {
    setScissor = function(...) end,
    setBlendMode = function(...) end,
    setColor = function(...) colors[#colors+1]={...} end,
    draw = function(img,x,y) calls[#calls+1]={image=img,x=x,y=y} end,
  }
  L.images['0,0'] = {id='inside'}
  L.images['1,0'] = {id='partial'}
  L.images['2,0'] = {id='outside'}
  L.images['0,1'] = {id='below'}
  -- viewport cruza a fronteira x=256, mas não alcança x=512 ou y=256.
  Render.draw(d,0,0,1,{x=200,y=10,w=80,h=100})
  local seen={}
  for _,call in ipairs(calls) do seen[call.image.id]=true end
  check('v0.10: culling descarta tiles fora da viewport',
    #calls==2 and seen.inside and seen.partial and not seen.outside and not seen.below)
  calls={}
  -- zoom transforma coordenadas da viewport, não coordenadas do documento.
  Render.draw(d,-400,-40,2,{x=80,y=10,w=70,h=70})
  check('v0.10: culling respeita zoom e deslocamento',
    #calls==2) -- tiles 0,0 e 1,0 em zoom 2
  calls={}
  Render.draw(d,0,0,1,{x=256,y=0,w=256,h=200})
  check('v0.10: limites exatos não provocam draws extras',
    #calls==1 and calls[1].image==L.images['1,0'])
  love.graphics = old
end

do
  local d=Doc.new(512,512,'borracha vazia')
  local L=d.layers[2]
  local s=Stroke.new(d,L,d.history,opts({size=30,eraser=true,flow=0.5}))
  s:push(100,100)
  s:push(150,100)
  s:finish()
  check('v0.10: borracha sobre transparência não aloca tiles',countTiles(L)==0)
  check('v0.10: borracha sem pintura não cria histórico',#d.history.undo==0)
  check('v0.10: borracha sobre transparência não marca tiles',next(L.dirty)==nil)
  -- A borracha continua removendo tinta e é plenamente reversível.
  local paint=Stroke.new(d,L,d.history,opts({size=10,flow=0.5}))
  paint:push(100.5,100.5)
  paint:finish()
  local before=alphaAt(L,100,100)
  local erase=Stroke.new(d,L,d.history,opts({size=10,eraser=true,flow=0.6}))
  erase:push(100.5,100.5)
  erase:finish()
  local after=alphaAt(L,100,100)
  check('v0.10: borracha atua sobre tile existente',after<before)
  Hist.undo(d)
  check('v0.10: undo da borracha conserva pixel anterior',approx(alphaAt(L,100,100),before))
end

do
  local tip=Tip.new(2,2,{1,0.5,0.5,0})
  local d=Doc.new(512,512,'cache de forma')
  local L=d.layers[2]
  local cfg=opts({size=12,flow=0.3,spacing=0.2,pressureOpacity=true,
    tip=tip,angle=10,dualBrush={tip=tip,depth=0.2},
    paper={tip=tip,depth=0.4},scatter=0.1,seed=2})
  local s=Stroke.new(d,L,d.history,cfg)
  for i=0,9 do s:push(100+i*3,150,0.2+i*0.08) end
  local stat=s.opts._shapeCache
  check('v0.10: curvas só de opacidade reutilizam geometria',
    stat.built==1 and stat.reused>5)
  check('v0.10: cache tem no máximo uma geometria',
    stat.last~=nil and stat.last.coverage~=nil and stat.last.extent~=nil)
  s:finish()
  check('v0.10: cache é local a gesto, não modifica configuração externa',
    cfg._shapeCache==nil and cfg._brushPrepared==nil and cfg.tip==tip)
  Hist.undo(d)
  check('v0.10: histórico funciona com cache e textura',countTiles(L)==0)
end

do
  local d=Doc.new(512,512,'invalidação')
  local s=Stroke.new(d,d.layers[2],d.history,opts({size=10,spacing=1,
    pressureSize=true,pressureMinSize=0.1,tiltScale=0.8}))
  s:push(100.5,100.5,0.5,nil,0,0)
  s:push(111.5,100.5,0.5,nil,0,0)
  local stat=s.opts._shapeCache
  local built=stat.built
  s:push(122.5,100.5,0.8,nil,0,0)
  check('v0.10: pressão de tamanho invalida cache',stat.built>built)
  built=stat.built
  s:push(133.5,100.5,0.8,nil,0.5,0.5)
  check('v0.10: tilt invalida cache',stat.built>built)
  s:finish()
end

do
  -- Comparação contra carimbos diretos: cache não pode alterar nenhum canal.
  local tip=Tip.new(3,3,{0,1,0,1,1,0.5,0,1,0})
  local o=opts({size=11,spacing=0.4,tip=tip,angle=35,
    paper={tip=tip,scale=2,depth=0.3},
    dualBrush={tip=tip,depth=0.25},flow=0.6})
  local a,b=Doc.new(512,256,'compila'),Doc.new(512,256,'referência')
  local sa=Stroke.new(a,a.layers[2],a.history,o)
  sa:push(80,80);sa:push(110,80);sa:finish()
  local sb=Stroke.new(b,b.layers[2],b.history,o)
  -- Invalida propositalmente a cache antes de cada stamp, mantendo os demais parâmetros.
  local prev=sb._stamp
  function sb:_stamp(point)
    self.opts._shapeCache.last=nil
    return prev(self,point)
  end
  sb:push(80,80);sb:push(110,80);sb:finish()
  local equivalent=true
  for y=72,88 do
    for x=74,116 do
      local ta=Doc.getTile(a.layers[2],0,0,false)
      local tb=Doc.getTile(b.layers[2],0,0,false)
      if ta and tb then
        local ar,ag,ab,aa=ta:getPixel(x,y)
        local br,bg,bb,ba=tb:getPixel(x,y)
        if ar~=br or ag~=bg or ab~=bb or aa~=ba then equivalent=false end
      else
        equivalent=false
      end
    end
  end
  check('v0.10: cache reproduz exatamente os pixels sem cache',equivalent)
end


-- v0.11: composição regional e processamento esparso em memória limitada.
do
  local d=Doc.new(520,300,'composição regional')
  local l1,l2=d.layers[1],d.layers[2]
  l1.opacity=80
  l2.opacity=65
  l2.blend='screen'
  local function set(layer,x,y,c)
    local T=Doc.TILE
    local tx,ty=math.floor(x/T),math.floor(y/T)
    local t,key=Doc.getTile(layer,tx,ty,true)
    t:setPixel(x-tx*T,y-ty*T,c[1],c[2],c[3],c[4])
    Doc.markDirty(layer,key)
  end
  local places={{0,0},{12,12},{253,251},{254,255},{256,256},{260,260},
    {260,255},{511,20},{512,299},{519,299},{519,0}}
  for i,p in ipairs(places) do
    set(l1,p[1],p[2],{0.2,0.7,0.4,0.25+i*0.05})
    set(l2,p[1],p[2],{0.9,0.2,0.8,0.8})
  end
  local full=Composite.flatten(d)
  local function regionMatches(x,y,w,h)
    local region=Composite.flattenRegion(d,x,y,w,h)
    if region:getWidth()~=w or region:getHeight()~=h then return false end
    for py=0,h-1 do
      for px=0,w-1 do
        local ar,ag,ab,aa=region:getPixel(px,py)
        local br,bg,bb,ba=full:getPixel(x+px,y+py)
        if ar~=br or ag~=bg or ab~=bb or aa~=ba then return false end
      end
    end
    return true
  end
  check('v0.11: região sobre bordas de quatro tiles reproduz pixels',regionMatches(248,250,25,19))
  check('v0.11: recorte não alinhado à grade mantém coordenadas',regionMatches(510,0,10,25))
  check('v0.11: região sem tinta tem alpha transparente',regionMatches(400,150,24,24)
    and select(4,Composite.flattenRegion(d,400,150,1,1):getPixel(0,0))==0)
  check('v0.11: região na borda inferior direita é exata',regionMatches(505,285,15,15))

  -- Os quatro modos de mistura usam a mesma composição da exportação antiga.
  local modes={'normal','multiply','darken','lighten','screen'}
  local equal=true
  for _,mode in ipairs(modes) do
    l2.blend=mode
    full=Composite.flatten(d)
    if not regionMatches(245,245,25,25) then equal=false end
  end
  check('v0.11: cinco modos de mesclagem equivalentes ao flatten',equal)

  local iter,total=Composite.tiles(d)
  local tiles,previous={},nil
  while true do
    local x,y,img=iter()
    if not x then break end
    tiles[#tiles+1]={x=x,y=y,w=img:getWidth(),h=img:getHeight()}
    if previous and (y<previous.y or (y==previous.y and x<=previous.x)) then equal=false end
    previous={x=x,y=y}
    for yy=0,img:getHeight()-1 do
      for xx=0,img:getWidth()-1 do
        local ar,ag,ab,aa=img:getPixel(xx,yy)
        local br,bg,bb,ba=full:getPixel(x+xx,y+yy)
        if ar~=br or ag~=bg or ab~=bb or aa~=ba then equal=false end
      end
    end
  end
  check('v0.11: iterador de tiles esparsos é idêntico ao flatten',equal and #tiles==total)
  check('v0.11: iterador retorna apenas tiles existentes',total==5,'total='..total)
  check('v0.11: tile parcial na última coluna está limitado ao documento',
    tiles[#tiles].x==512 and tiles[#tiles].w==8 and tiles[#tiles].h==44)

  local roi={x=250,y=250,w=270,h=50}
  local niter,ntotal=Composite.tiles(d,roi)
  local cropped=true
  local count=0
  while true do
    local x,y,img=niter()
    if not x then break end
    count=count+1
    if x<roi.x or y<roi.y or x+img:getWidth()>520 or y+img:getHeight()>300
      or not regionMatches(x,y,img:getWidth(),img:getHeight()) then cropped=false end
  end
  check('v0.11: iterador respeita a região e recorta os tiles',cropped and count==ntotal and count==5)

  local called={}
  local n=Composite.stream(d,function(x,y,im)
    called[#called+1]={x,y,im:getWidth(),im:getHeight()}
  end,roi)
  check('v0.11: streaming síncrono emite os mesmos tiles',n==5 and #called==5)
  local calledAsync={}
  local job=Composite.streamAsync(d,function(x,y,im)
    calledAsync[#calledAsync+1]={x,y,im:getWidth(),im:getHeight()}
  end,roi)
  local firstDone=Job.step(job,0)
  check('v0.11: streaming assíncrono cede entre tiles',not firstDone and
    #calledAsync==1 and job.progress>0 and job.progress<1)
  local finished,result=Job.step(job,10)
  local same=finished and result==5 and #calledAsync==#called
  for i=1,#called do
    if table.concat(called[i],',')~=table.concat(calledAsync[i] or {},',') then same=false end
  end
  check('v0.11: streaming assíncrono mantém ordem e progresso',same and job.progress==1)

  l1.visible=false;l2.visible=false
  local nextEmpty,emptyCount=Composite.tiles(d)
  check('v0.11: camadas invisíveis não emitem tiles',emptyCount==0 and nextEmpty()==nil)
  check('v0.11: exportar documento sem camadas visíveis fica transparente',
    select(4,Composite.flattenRegion(d,250,251,1,1):getPixel(0,0))==0)
end

do
  local d=Doc.new(16384,16384,'alta resolução esparsa')
  local t=Doc.getTile(d.layers[2],63,63,true)
  t:setPixel(255,255,0.3,0.5,0.7,1)
  local old=love.image.newImageData
  local maxArea=0
  love.image.newImageData=function(w,h)
    maxArea=math.max(maxArea,w*h)
    assert(w*h<=Doc.TILE*Doc.TILE,'tentativa de alocar documento inteiro')
    return old(w,h)
  end
  local positions={}
  local n=Composite.stream(d,function(x,y,tile)
    positions[#positions+1]={x=x,y=y,w=tile:getWidth(),h=tile:getHeight(),a=select(4,tile:getPixel(255,255))}
  end)
  love.image.newImageData=old
  check('v0.11: streaming de 16K não aloca imagem do documento',
    n==1 and #positions==1 and positions[1].x==16128 and positions[1].a==1)
  check('v0.11: buffer temporário permanece limitado ao tamanho do tile',
    maxArea==65536, 'pixels máximos='..maxArea)
end

do
  local Render=require('core.render')
  local d=Doc.new(1024,512,'cache visível')
  local l=d.layers[2]
  for _,key in ipairs({'0,0','3,0'}) do
    l.tiles[key]=newImageData(256,256)
    l.dirty[key]=true
  end
  local old=love.graphics
  local created,freed=0,0
  love.graphics={newImage=function()
    created=created+1
    return {release=function() freed=freed+1 end,replacePixels=function() end}
  end}
  local left={x=0,y=0,w=250,h=250}
  Render.refresh(d,0,0,1,left)
  check('v0.11: refresh limitado à viewport converte apenas tiles visíveis',
    created==1 and l.images['0,0']~=nil and l.images['3,0']==nil)
  check('v0.11: refresh preserva sujeira em tiles fora da viewport',
    l.dirty['3,0']==true and l.dirty['0,0']==nil)
  Render.refresh(d,-768,0,1,left)
  check('v0.11: tile distante é atualizado ao entrar na viewport',
    created==2 and l.images['3,0']~=nil and next(l.dirty)==nil)
  local evicted=Render.evictOutside(d,-768,0,1,left)
  check('v0.11: descarte de GPU libera apenas a imagem fora da tela',
    evicted==1 and freed==1 and l.images['0,0']==nil and l.images['3,0']~=nil)
  check('v0.11: tile removido da GPU volta à fila de atualização',l.dirty['0,0']==true)
  Render.refresh(d,0,0,1,left)
  check('v0.11: refresh reconstitui cache de GPU após descarte',
    created==3 and l.images['0,0']~=nil and next(l.dirty)==nil)
  -- Exclusão de pixels: a imagem remanescente também precisa ser liberada.
  l.tiles['0,0']=nil
  l.dirty['0,0']=true
  Render.refresh(d,0,0,1,left)
  check('v0.11: exclusão libera imagem de GPU imediatamente',
    l.images['0,0']==nil and freed==2)
  love.graphics=old
end

do
  local d=Doc.new(256,256,'validação de região')
  local cases={{-1,0,1,1},{0,-1,1,1},{0,0,0,1},{0,0,1,0},
    {255,0,2,1},{0,255,1,2},{0,0,math.huge,1},{0/0,0,1,1},{0,0,1.5,1}}
  local allInvalid=true
  for _,r in ipairs(cases) do
    if pcall(Composite.flattenRegion,d,r[1],r[2],r[3],r[4]) then allInvalid=false end
  end
  check('v0.11: regiões inválidas são rejeitadas sem alocar imagem',allInvalid)
  check('v0.11: callback obrigatório para streaming é validado',
    not pcall(Composite.stream,d,nil) and not pcall(Composite.streamAsync,d,nil))
end

-- v0.12: regressão de preenchimento por segmentos, seleção e histórico.
do
  local d = Doc.new(780, 24, 'balde em vários tiles')
  local L = d.layers[2]
  local n = Fill.fill(d, L, 1, 1, {0.2, 0.4, 0.6}, 0, nil)
  check('v0.12: preenche área vazia em quatro tiles', n == 780 * 24 and countTiles(L) == 4, 'n=' .. n)
  check('v0.12: preserva alfa padrão ao cruzar fronteiras',
    select(4, Fill.pixel(L, 0, 0)) == 1 and select(4, Fill.pixel(L, 256, 23)) == 1
    and select(4, Fill.pixel(L, 779, 23)) == 1)
  check('v0.12: registra uma entrada por tile tocado',
    #d.history.undo == 1 and #d.history.undo[1] == 4)
  Hist.undo(d)
  check('v0.12: desfazer remove todos os tiles novos', countTiles(L) == 0)
  Hist.redo(d)
  check('v0.12: refazer recupera a região inteira', countTiles(L) == 4
    and select(1, Fill.pixel(L, 779, 23)) == 0.2)
  -- Mesmo RGBA e tolerância zero: gesto vazio não deve apagar a pilha de redo.
  Hist.undo(d)
  local undoBefore, redoBefore = #d.history.undo, #d.history.redo
  local noop = Fill.fill(d, L, 0, 0, {0, 0, 0, 0}, 0)
  check('v0.12: preencher com a mesma cor e tol=0 não cria tiles',
    noop == 0 and countTiles(L) == 0)
  check('v0.12: gesto vazio não elimina o refazer',
    #d.history.undo == undoBefore and #d.history.redo == redoBefore)
end

do
  local d = Doc.new(15, 10, 'seleção e tolerância')
  local L = d.layers[2]
  local t = Doc.getTile(L, 0, 0, true)
  for y = 0, 9 do
    t:setPixel(6, y, 0, 0, 0, 1) -- barreira de alfa
    if y % 3 == 0 then t:setPixel(3, y, 0, 0, 0, 0.1) end
  end
  local n = Fill.fill(d, L, 2, 2, {0.01, 0, 0, 0}, 0.1)
  check('v0.12: tinta dentro da tolerância não causa laço infinito', n == 60, 'n=' .. n)
  check('v0.12: barreira de alfa interrompe a região',
    select(4, Fill.pixel(L, 8, 2)) == 0 and select(4, Fill.pixel(L, 6, 2)) == 1)
  check('v0.12: alfa dos pixels visitados continua correto',
    select(1, Fill.pixel(L, 2, 2)) == 0.01 and select(4, Fill.pixel(L, 3, 0)) == 0)
  Hist.undo(d)
  check('v0.12: desfazer restaura diferenças cobertas pela tolerância',
    select(1, Fill.pixel(L, 2, 2)) == 0 and select(4, Fill.pixel(L, 3, 0)) == 0.1)

  -- Mesmo alvo e saída, mas tolerância > 0: outros tons DEVEM ser normalizados.
  n = Fill.fill(d, L, 2, 2, {0, 0, 0, 0}, 0.1)
  check('v0.12: a mesma tinta com tol>0 ainda corrige pixels próximos', n == 60)
  check('v0.12: pixels ligeiramente distintos são corrigidos',
    select(4, Fill.pixel(L, 3, 0)) == 0)
end

do
  local d = Doc.new(540, 20, 'seleção atravessando tiles')
  local L = d.layers[2]
  local n = Fill.fill(d, L, 300, 8, {0, 1, 0, 1}, 0,
    {x = 254.2, y = 2.5, w = 270.5, h = 8.2})
  check('v0.12: seleção fracionária mantém limites originais',
    n == (525 - 255) * (11 - 3), 'n=' .. n)
  check('v0.12: seleção cruza três tiles sem vazamento', countTiles(L) == 3
    and select(4, Fill.pixel(L, 255, 3)) == 1
    and select(4, Fill.pixel(L, 524, 10)) == 1
    and select(4, Fill.pixel(L, 254, 3)) == 0
    and select(4, Fill.pixel(L, 525, 10)) == 0)
  check('v0.12: seed fora da seleção é ignorada',
    Fill.fill(d, L, 255, 11, {1, 0, 0, 1}, 0, {x=255,y=3,w=270,h=8}) == 0)
  Hist.undo(d)
  check('v0.12: desfazer seleção cruzando tiles preserva pixels externos', countTiles(L) == 0)
end

do
  local d=Doc.new(20,20,'segurança balde')
  local L=d.layers[2]
  local invalid={
    {0,0,{1,0,0},-0.01}, {0,0,{1,0,0},1.01},
    {0,0,{1,0,0},0/0}, {0,0,{1,0,0},math.huge},
    {math.huge,0,{1,0,0},0}, {0,0,{0/0,0,0},0},
    {0,0,{1,0,0,-1},0}, {0,0,{1,0,0,math.huge},0},
    {0,0,{1,0,0},0,{x=0,y=0,w=-1,h=3}},
    {0,0,{1,0,0},0,{x=0,y=0,w=0/0,h=3}},
  }
  local allRejected=true
  for _, args in ipairs(invalid) do
    if pcall(Fill.fill,d,L,args[1],args[2],args[3],args[4],args[5]) then
      allRejected=false
    end
  end
  check('v0.12: rejeita coordenadas/tolerância/cor/seleção inválidas',allRejected)
  check('v0.12: erros de entrada não deixam traço nem tiles',
    d.history.stroke==nil and countTiles(L)==0 and #d.history.undo==0)
  Hist.begin(d.history)
  check('v0.12: não sobrescreve um gesto já aberto',
    not pcall(Fill.fill,d,L,0,0,{1,0,0},0) and d.history.stroke~=nil)
  d.history.stroke=nil
  check('v0.12: preenchimento fora do documento é vazio',
    Fill.fill(d,L,-1,0,{1,0,0},0)==0 and countTiles(L)==0)
end

do
  -- Oráculo independente com BFS em uma imagem pequena e irregular.
  local w,h=31,23
  local d=Doc.new(w,h,'equivalência com busca em largura')
  local L=d.layers[2]
  local t=Doc.getTile(L,0,0,true)
  local original={}
  for y=0,h-1 do
    for x=0,w-1 do
      local v=(x*17+y*11+x*y*3)%13
      local p
      if v < 2 then p={0,0,0,1}
      elseif v < 6 then p={0.05,0,0,0}
      elseif v < 9 then p={0.12,0,0,0}
      else p={0,0,0,0} end
      original[y*w+x+1]=p
      t:setPixel(x,y,p[1],p[2],p[3],p[4])
    end
  end
  local function oracle(sx,sy,tol,col,sel)
    local out,seen,stack={}, {}, {{sx,sy}}
    for i,p in ipairs(original) do out[i]={p[1],p[2],p[3],p[4]} end
    local target=original[sy*w+sx+1]
    local count=0
    while #stack>0 do
      local p=table.remove(stack)
      local x,y=p[1],p[2]
      local idx=y*w+x+1
      if x>=0 and y>=0 and x<w and y<h and not seen[idx] and
        (not sel or x>=sel.x and y>=sel.y and x<sel.x+sel.w and y<sel.y+sel.h) then
        seen[idx]=true
        local c=original[idx]
        if math.max(math.abs(c[1]-target[1]),math.abs(c[2]-target[2]),
          math.abs(c[3]-target[3]),math.abs(c[4]-target[4]))<=tol then
          out[idx]={col[1],col[2],col[3],col[4] or 1}
          count=count+1
          stack[#stack+1]={x+1,y};stack[#stack+1]={x-1,y}
          stack[#stack+1]={x,y+1};stack[#stack+1]={x,y-1}
        end
      end
    end
    return out,count
  end
  local cases={
    {0,0,0,{1,0,0,1}}, {15,11,0.05,{0.07,0,0,0}},
    {12,12,0.12,{0,1,0,0.2}}, {20,5,0.12,{0.09,0,0,0}},
    {3,18,1,{1,0,1,1},{x=0,y=10,w=19,h=13}},
    {25,12,1,{0.5,0,0,0.5},{x=18,y=5,w=13,h=18}},
    {0,22,0.1,{0,0,1,1}},
  }
  local verified=true
  for _,c in ipairs(cases) do
    local sx,sy,tol,col,sel=c[1],c[2],c[3],c[4],c[5]
    local out,count=oracle(sx,sy,tol,col,sel)
    local got=Fill.fill(d,L,sx,sy,col,tol,sel)
    if got~=count then verified=false end
    for y=0,h-1 do
      for x=0,w-1 do
        local ex=out[y*w+x+1]
        local r,g,b,a=t:getPixel(x,y)
        if r~=ex[1] or g~=ex[2] or b~=ex[3] or a~=ex[4] then
          verified=false
        end
      end
    end
    Hist.undo(d)
    t=Doc.getTile(L,0,0,false)
  end
  check('v0.12: equivalência de pixels e contagem com BFS em regiões irregulares',verified)
  check('v0.12: oráculo confirma um gesto por preenchimento',#d.history.undo==0)
end


-- v0.12: rollback se o backend ImageData falhar em uma escrita.
do
  local d=Doc.new(40,10,'falha no backend')
  local L=d.layers[2]
  local old=love.image.newImageData
  local writes=0
  love.image.newImageData=function(w,h)
    local t=old(w,h)
    local setter=t.setPixel
    function t:setPixel(...)
      writes=writes+1
      if writes==40 then error('falha simulada no setPixel') end
      return setter(self,...)
    end
    return t
  end
  local ok=pcall(Fill.fill,d,L,1,1,{1,0,0,1},0)
  love.image.newImageData=old
  check('v0.12: falha em ImageData interrompe o preenchimento',not ok and writes==40)
  check('v0.12: rollback de tiles recém-criados ao falhar',
    countTiles(L)==0 and d.history.stroke==nil and #d.history.undo==0)

  local tile=Doc.getTile(L,0,0,true)
  tile:setPixel(1,1,0,0,0,1) -- âncora opaca fora da região alvo
  local base=tile.setPixel
  local counter=0
  function tile:setPixel(...)
    counter=counter+1
    if counter==50 then error('falha em tile existente') end
    return base(self,...)
  end
  ok=pcall(Fill.fill,d,L,8,8,{0,1,0,1},0)
  check('v0.12: falha ao alterar tile existente é interceptada', not ok)
  check('v0.12: rollback preserva todos os pixels anteriores',
    select(4,Fill.pixel(L,1,1))==1 and
    select(4,Fill.pixel(L,8,8))==0 and
    d.history.stroke==nil and #d.history.undo==0)
end

-- v0.13: execução cooperativa e rollback testados com o mesmo mock.
require('tests.test_fill_cooperative')(check)

-- v0.14: retenção do histórico e composição sem pré-varredura.
require('tests.test_history_memory')(check)

-- v0.15: cache CPU de composição regional.
require('tests.test_composite_cache')(check)

require('tests.test_masks_blends')(check)

require('tests.test_mask_brush')(check)

require('tests.test_groups_clipping')(check)

require('tests.test_nested_groups')(check)

-- v0.20: grupos processados por blocos com buffers reciclados.
require('tests.test_tiled_groups_v020')(check)

-- v0.21: índices esparsos por tile e equivalência com v0.20 congelada.
require('tests.test_sparse_composite_v021')(check)

require('tests.test_core_alpha_lock')(check)
require('tests.test_bridge_core_v022')(check)
require('tests.test_selection_v023')(check)
require('tests.test_transform_v024')(check)
require('tests.test_groups_ui_v025')(check)
require('tests.test_thumbnail_reorder_v026')(check)
require('tests.test_gallery_preview_v028')(check)
require('tests.test_png_import_v029')(check)
require('tests.test_png_placement_v030')(check)
require('tests.test_png_interpolation_v031')(check)
require('tests.test_png_rotation_aa_v032')(check)
require('tests.test_transform_smooth_v033')(check)
require('tests.test_transform_handles_v034')(check)
require('tests.test_selection_invert_v035')(check)
require('tests.test_selection_combine_v036')(check)
require('tests.test_selection_outline_v037')(check)
require('tests.test_selection_ants_v038')(check)
require('tests.test_selection_pause_v039')(check)
require('tests.test_selection_contract_integration')(check)
require('tests.test_selection_operation_lock_v039')(check)

print(string.format("\n%d passou, %d falhou", passed, failed))
if failed > 0 then os.exit(1) end
