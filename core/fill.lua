-- Balde scanline: execução bloqueante (fill) ou cooperativa (newJob).
-- Ambos compartilham o MESMO algoritmo para manter pixels e histórico iguais.
-- A versão cooperativa divide a leitura/escrita em lotes e admite cancelamento
-- com rollback. Chamadas externas não devem modificar doc/layer durante o job.
local Doc = require('core.doc')
local Hist = require('core.history')
local Job = require('core.job')
local Selection = require('core.selection')

local F = {}
local floor, abs, max = math.floor, math.abs, math.max
local TILE = Doc.TILE

local function finite(v)
  return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

local function pixel(layer, px, py)
  local tx, ty = floor(px / TILE), floor(py / TILE)
  local tile = layer.tiles[tx .. ',' .. ty]
  if not tile then return 0, 0, 0, 0 end
  return tile:getPixel(px - tx * TILE, py - ty * TILE)
end
F.pixel = pixel

local function distance(r, g, b, a, target)
  return max(abs(r - target[1]), abs(g - target[2]), abs(b - target[3]), abs(a - target[4]))
end

-- Faz a validação ANTES de alocar um trabalho ou bloquear o histórico.
-- nil indica que o preenchimento é legitimamente vazio.
local function prepare(doc, layer, x, y, color, tol, selection)
  assert(type(doc) == 'table' and type(layer) == 'table' and
    type(layer.tiles) == 'table' and type(layer.dirty) == 'table' and
    type(doc.history) == 'table' and finite(doc.w) and finite(doc.h) and
    doc.w > 0 and doc.h > 0 and doc.w == floor(doc.w) and doc.h == floor(doc.h),
    'documento ou camada inválidos')
  assert(finite(x) and finite(y), 'coordenadas inválidas')
  assert(type(color) == 'table', 'cor inválida')
  for i = 1, 3 do
    assert(finite(color[i]) and color[i] >= 0 and color[i] <= 1, 'canal de cor inválido')
  end
  local cr, cg, cb, ca = color[1], color[2], color[3], color[4]
  if ca == nil then ca = 1 end
  assert(finite(ca) and ca >= 0 and ca <= 1, 'canal alfa inválido')
  if tol == nil then tol = 0 end
  assert(finite(tol) and tol >= 0 and tol <= 1, 'tolerância inválida')
  assert(doc.history.stroke == nil and doc.history._fillLock == nil,
    'não é possível preencher durante outro gesto')

  local W, H = doc.w, doc.h
  x, y = floor(x), floor(y)
  if x < 0 or y < 0 or x >= W or y >= H then return nil end

  local x0, y0, x1, y1 = 0, 0, W, H -- limites exclusivos
  if selection then
    assert(type(selection) == 'table' and finite(selection.x) and finite(selection.y) and
      finite(selection.w) and finite(selection.h) and selection.w >= 0 and selection.h >= 0,
      'seleção inválida')
    x0, y0 = max(0, math.ceil(selection.x)), max(0, math.ceil(selection.y))
    x1, y1 = math.min(W, math.ceil(selection.x + selection.w)),
             math.min(H, math.ceil(selection.y + selection.h))
    if x0 >= x1 or y0 >= y1 then return nil end
  end
  if x < x0 or x >= x1 or y < y0 or y >= y1 then return nil end
  if selection and not Selection.contains(selection,x,y) then return nil end

  local tr, tg, tb, ta = pixel(layer, x, y)
  local target = {tr, tg, tb, ta}
  if tol == 0 and cr == tr and cg == tg and cb == tb and ca == ta then return nil end

  return {
    doc=doc, layer=layer, h=doc.history, x=x, y=y,
    color={cr,cg,cb,ca}, tol=tol, target=target,
    x0=x0, y0=y0, x1=x1, y1=y1, selection=selection,
    -- Se a cor nova ainda satisfaz a tolerância, precisamos registrar
    -- segmentos visitados, porque os próprios pixels não servem de marca.
    track=distance(cr,cg,cb,ca,target)<=tol,
    started=false, token=nil,
  }
end

-- Restaura os clones de antes do gesto inclusive quando a coroutine já
-- havia cedido controle. Nunca apaga redo ou cria uma entrada de undo.
local function rollback(s)
  local h = s.h
  if s.started and h.stroke then
    for _, e in ipairs(h.stroke.entries) do
      e.layer.tiles[e.key] = e.before or nil
      Doc.markDirty(e.layer, e.key)
    end
    h.stroke = nil
  end
  if h._fillLock == s.token and s.token ~= nil then h._fillLock = nil end
  s.started = false
end

local function run(s, yieldEvery)
  local doc, layer, h = s.doc, s.layer, s.h
  local x0, y0, x1, y1 = s.x0, s.y0, s.x1, s.y1
  local target, tol, color = s.target, s.tol, s.color
  local cr, cg, cb, ca = color[1], color[2], color[3], color[4]
  local intervals = s.track and {} or nil
  local count = 0

  -- Uma pausa a cada N operações de pixel. O orçamento de tempo em Job.step
  -- é conferido entre yields, não interrompe uma operação de ImageData.
  local units = 0
  local function checkpoint()
    if not yieldEvery then return end
    units = units + 1
    if units >= yieldEvery then
      units = 0
      local total = (x1-x0)*(y1-y0)
      coroutine.yield(math.min(0.99, count / total))
    end
  end

  local function visited(py, px)
    if not intervals then return false end
    local runs = intervals[py]
    if not runs then return false end
    local lo, hi = 1, #runs
    while lo <= hi do
      local mid = floor((lo + hi) / 2)
      local item = runs[mid]
      if px < item[1] then hi = mid - 1
      elseif px > item[2] then lo = mid + 1
      else return true end
    end
    return false
  end

  local function addRun(py, left, right)
    if not intervals then return end
    local runs = intervals[py]
    if not runs then intervals[py] = {{left, right}}; return end
    local pos = 1
    while pos <= #runs and runs[pos][2] < left - 1 do pos = pos + 1 end
    while pos <= #runs and runs[pos][1] <= right + 1 do
      local r = runs[pos]
      left, right = math.min(left, r[1]), math.max(right, r[2])
      table.remove(runs, pos)
    end
    table.insert(runs, pos, {left, right})
  end

  local readTx, readTy, readTile
  local function matches(px, py)
    if px < x0 or px >= x1 or py < y0 or py >= y1 or visited(py, px)
      or (s.selection and not Selection.contains(s.selection,px,py)) then return false end
    checkpoint()
    local tx, ty = floor(px / TILE), floor(py / TILE)
    if tx ~= readTx or ty ~= readTy then
      readTx, readTy = tx, ty
      readTile = layer.tiles[tx .. ',' .. ty]
    end
    if not readTile then return distance(0, 0, 0, 0, target) <= tol end
    local r,g,b,a = readTile:getPixel(px-tx*TILE, py-ty*TILE)
    return distance(r,g,b,a,target) <= tol
  end

  local stack, size = {{s.x, s.y}}, 1
  local currentKey, currentTile, currentTx, currentTy
  local function paintRow(py, left, right)
    local ty = floor(py / TILE)
    for px = left, right do
      checkpoint()
      local tx = floor(px / TILE)
      if tx ~= currentTx or ty ~= currentTy then
        local key = tx .. ',' .. ty
        if key ~= currentKey then
          Hist.touch(h, layer, key, s.token)
          currentTile = Doc.getTile(layer, tx, ty, true)
          Doc.markDirty(layer, key)
          currentKey, currentTx, currentTy = key, tx, ty
        end
      end
      currentTile:setPixel(px - tx*TILE, py - ty*TILE, cr, cg, cb, ca)
    end
  end

  while size > 0 do
    local seed = stack[size]
    stack[size] = nil
    size = size - 1
    local sx, sy = seed[1], seed[2]
    if matches(sx, sy) then
      local left, right = sx, sx
      while left > x0 and matches(left-1, sy) do left = left-1 end
      while right+1 < x1 and matches(right+1, sy) do right = right+1 end
      if not s.started then Hist.begin(h, s.token); s.started=true end
      addRun(sy, left, right)
      paintRow(sy, left, right)
      readTx = nil -- paint pode ter criado tile novo antes inexistente
      count = count + right-left+1

      for dir = -1, 1, 2 do
        local ny = sy+dir
        if ny >= y0 and ny < y1 then
          local nx = left
          while nx <= right do
            if matches(nx, ny) then
              size=size+1
              stack[size] = {nx, ny}
              repeat nx=nx+1 until nx>right or not matches(nx, ny)
            else
              nx=nx+1
            end
          end
        end
      end
    end
  end
  if s.started then Hist.commit(h, s.token) end
  if s.token and h._fillLock == s.token then h._fillLock = nil end
  s.started = false
  return count
end

-- API antiga, síncrona, sem overhead de coroutine/yield.
function F.fill(doc, layer, x, y, color, tol, selection)
  local s = prepare(doc, layer, x, y, color, tol, selection)
  if not s then return 0 end
  local ok, result = pcall(run, s, nil)
  if not ok then rollback(s); error(result, 0) end
  return result
end

-- API v0.13: cria um job para rodar em love.update com Job.step(job, 0.004,
-- love.timer.getTime). Retorna #pixels ao concluir. Enquanto estiver vivo,
-- o histórico do documento fica bloqueado; Job.cancel restaura tudo.
-- opts.yieldEvery: chamadas de leitura/escrita por pausa (padrão 512).
function F.newJob(doc, layer, x, y, color, tol, selection, opts)
  opts = opts or {}
  assert(type(opts) == 'table', 'opções do job inválidas')
  local every = opts.yieldEvery
  if every == nil then every = 512 end
  assert(finite(every) and every == floor(every) and every >= 1 and every <= 65536,
    'yieldEvery deve ser inteiro entre 1 e 65536')
  local s = prepare(doc, layer, x, y, color, tol, selection)
  if not s then return Job.new(function() return 0 end) end
  local token = {}
  s.token = token
  s.h._fillLock = token
  return Job.new(function() return run(s, every) end, {
    onCancel=function() rollback(s) end,
    onError=function() rollback(s) end,
  })
end

return F
