package.path="./?.lua;./?/init.lua;"..package.path
local IconPack=require("src.icon_pack")
assert(IconPack.asset_for("brush")=="paintbrush")
assert(IconPack.asset_for("magic_wand")=="wand-sparkles")
assert(IconPack.asset_for("layer")=="layers")
assert(IconPack.asset_for("nonexistent")==nil)
assert(#IconPack.names()>=40)
assert(IconPack.load()==false)
print("PASS: mapeamento Lucide para ícones de UI")
