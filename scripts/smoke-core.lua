-- Teste de fumaça do núcleo, independente da janela LÖVE.
-- Execute após: sh scripts/prepare-core.sh
-- Comando: texlua scripts/smoke-core.lua

local Doc = require('core.doc')
local Layers = require('core.layers')
local History = require('core.history')
local Composite = require('core.composite')
local Project = require('core.project')

assert(type(Composite.flattenRegion) == 'function', 'compositor indisponível')
assert(type(Project.load) == 'function', 'leitor de projetos indisponível')

local doc = Doc.new(64, 48, 'Verificação Paint-Lua')
assert(doc.w == 64 and doc.h == 48 and #doc.layers == 2, 'documento inicial inválido')
local camada = Layers.add(doc, 'Camada de teste')
assert(camada.name == 'Camada de teste' and #doc.layers == 3, 'falha ao criar camada')
Layers.select(doc, 2)
assert(doc.sel == 2, 'falha ao selecionar camada')
Layers.setVisible(doc, 2, false)
assert(doc.layers[2].visible == false, 'falha de visibilidade')
History.undo(doc)
assert(doc.layers[2].visible == true, 'desfazer visibilidade falhou')
History.redo(doc)
assert(doc.layers[2].visible == false, 'refazer visibilidade falhou')

print('Paint-Lua: smoke do núcleo v0.21 OK')
