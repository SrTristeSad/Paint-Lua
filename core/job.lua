-- Trabalho em fatias com coroutines: roda uma função até ela fazer yield,
-- por um orçamento de tempo, para não travar o laço principal do LÖVE.
--
-- Uso típico, dentro de love.update(dt):
--   if not job then job = Job.new(Composite.flattenJob(doc)) end
--   local done, result = Job.step(job, 0.008)   -- ~8 ms por quadro
--   if done then ... usar result ... end
local J = {}

-- `fn` deve fazer coroutine.yield(progresso) de tempos em tempos.
-- Ao retornar, o valor vira o resultado do job.
function J.new(fn, callbacks)
  callbacks = callbacks or {}
  return {co = coroutine.create(fn), done = false, result = nil, progress = 0,
    onCancel = callbacks.onCancel, onError = callbacks.onError}
end

-- Executa até `budget` segundos de CPU. Retorna done, result.
-- `clock` é opcional (ex.: love.timer.getTime); padrão os.clock.
function J.step(job, budget, clock)
  if job.done then return true, job.result end
  clock = clock or os.clock
  local t0 = clock()
  repeat
    local ok, value = coroutine.resume(job.co)
    if not ok then
      job.done = true
      job.co = nil
      if job.onError then pcall(job.onError, value) end
      error(value, 0)
    end
    if coroutine.status(job.co) == "dead" then
      job.done = true
      job.result = value
      job.progress = 1
      return true, value
    end
    if type(value) == "number" then job.progress = value end
  until clock() - t0 >= budget
  return false, nil
end

function J.cancel(job)
  if job.done then return false end
  job.done = true
  job.cancelled = true
  job.co = nil
  if job.onCancel then job.onCancel() end
  return true
end

return J
