-- Paint-Lua v0.28: exportação de PNG RGBA da composição final.
-- Exporta para a pasta de dados do LÖVE sem substituir exportações antigas.
local Composite=require('core.composite')
local Export={MAX_PIXELS=4194304,MAX_SIDE=8192}
local function validInteger(n)
  return type(n)=='number' and n==math.floor(n) and n>=1
end
local function fs()
  return love and love.filesystem
end
local function target(id)
  assert(id=='atual' or (validInteger(id) and id<=2147483646),'ID inválido')
  return 'exports/obra-'..tostring(id)
end

function Export.save(doc,id)
  if not (type(doc)=='table' and validInteger(doc.w) and validInteger(doc.h)) then
    return nil,'dimensões inválidas'
  end
  if doc.w>Export.MAX_SIDE or doc.h>Export.MAX_SIDE or
    doc.w*doc.h>Export.MAX_PIXELS then
    return nil,'PNG excede o limite de 4.194.304 pixels; o arquivo NPNT permanece seguro'
  end
  local f=fs()
  if not (f and f.write and f.createDirectory and f.getInfo) then
    return nil,'love.filesystem indisponível'
  end
  local ok,base=pcall(target,id or 'atual')
  if not ok then return nil,tostring(base) end
  local path
  -- Nunca sobrescrever um PNG já exportado.
  for n=1,999 do
    local candidate=base..(n==1 and '' or ('-'..n))..'.png'
    if not f.getInfo(candidate) then path=candidate;break end
  end
  if not path then return nil,'muitas versões exportadas; organize a pasta exports' end
  local success,result,err=pcall(f.createDirectory,'exports')
  if not success or not result then
    return nil,'não foi possível criar exports: '..tostring(success and err or result)
  end
  local rendered,png=pcall(function()
    local flattened=Composite.flatten(doc)
    return flattened:encode('png'):getString()
  end)
  if not rendered then return nil,'erro de composição PNG: '..tostring(png) end
  if #png>64*1024*1024 then return nil,'PNG comprimido maior que 64 MiB' end
  local written,wrote,reason=pcall(f.write,path,png)
  if not written or not wrote then
    return nil,'erro de gravação PNG: '..tostring(written and reason or wrote)
  end
  return path
end

return Export
