-- Gallery state only. No files are imported, stored or synchronised.
-- Folders and gallery items simulate the documented ibisPaint UI behavior.
-- Windows artwork folders require Pro/Premium; this project has no licensing.
local Gallery={}
Gallery.__index=Gallery
local function integer(n)
    return type(n)=="number" and n==math.floor(n)
end
local function name_valid(name)
    return type(name)=="string" and #name>=1 and #name<=100
        and not name:match("^%s*$")
end
local function copy(item)
    local out={}
    for key,value in pairs(item) do out[key]=value end
    return out
end
function Gallery.new()
    return setmetatable({
        records={},
        order={},
        next_id=1,
        current_folder=0,
        selected={}
    },Gallery)
end
function Gallery:get(id)
    if not integer(id) or id<1 then return nil end
    local found=self.records[id]
    return found and copy(found) or nil
end
function Gallery:folder(id)
    assert(integer(id) and id>=0,"Pasta inválida")
    if id==0 then return {id=0,type="folder",name="My Gallery",parent=nil} end
    local found=self.records[id]
    assert(found and found.type=="folder","Pasta inexistente")
    return copy(found)
end
function Gallery:items(parent)
    local folder_id=parent
    if folder_id==nil then folder_id=self.current_folder end
    self:folder(folder_id)
    local out={}
    for _,id in ipairs(self.order) do
        local item=self.records[id]
        if item and item.parent==folder_id then out[#out+1]=copy(item) end
    end
    return out
end
function Gallery:folders()
    local out={{id=0,type="folder",name="My Gallery",parent=nil}}
    for _,id in ipairs(self.order) do
        local item=self.records[id]
        if item and item.type=="folder" then out[#out+1]=copy(item) end
    end
    return out
end
function Gallery:total_artworks()
    local count=0
    for _,item in pairs(self.records) do
        if item.type=="artwork" then count=count+1 end
    end
    return count
end
local function insert(self,item)
    item.id=self.next_id
    self.next_id=self.next_id+1
    self.records[item.id]=item
    self.order[#self.order+1]=item.id
    return item.id
end
function Gallery:add_folder(name)
    assert(name_valid(name),"Nome da pasta inválido")
    return insert(self,{
        type="folder",name=name,parent=self.current_folder
    })
end
function Gallery:add_artwork(width,height,name)
    assert(integer(width) and width>=1 and width<=16384
        and integer(height) and height>=1 and height<=16384,
        "Dimensões inválidas")
    local title=name or "Untitled"
    assert(name_valid(title),"Título inválido")
    return insert(self,{
        type="artwork",name=title,parent=self.current_folder,
        width=width,height=height,simulated=true
    })
end
function Gallery:enter(id)
    local target=self.records[id]
    assert(target and target.type=="folder","Não é uma pasta")
    assert(target.parent==self.current_folder,"Pasta fora da galeria atual")
    self.current_folder=id
    self.selected={}
    return target.name
end
function Gallery:back()
    if self.current_folder==0 then return false end
    self.current_folder=self:folder(self.current_folder).parent
    self.selected={}
    return true
end
function Gallery:rename(id,name)
    assert(name_valid(name),"Nome inválido")
    local item=self.records[id]
    assert(item,"Item inexistente")
    item.name=name
end
function Gallery:move(id,dest)
    local item=self.records[id]
    assert(item,"Item inexistente")
    self:folder(dest)
    assert(id~=dest,"Item não pode conter a si mesmo")
    if item.type=="folder" then
        local cursor=dest
        while cursor~=0 do
            assert(cursor~=id,"Pasta não pode ser movida para uma descendente")
            cursor=self:folder(cursor).parent
        end
    end
    item.parent=dest
    self.selected[id]=nil
end
function Gallery:select(id)
    local item=self.records[id]
    assert(item and item.parent==self.current_folder,"Item não selecionável")
    if self.selected[id] then self.selected[id]=nil;return false end
    self.selected[id]=true;return true
end
function Gallery:selection()
    local out={}
    for _,id in ipairs(self.order) do
        local item=self.records[id]
        if item and self.selected[id] then out[#out+1]=copy(item) end
    end
    return out
end
function Gallery:clear_selection()
    self.selected={}
end
function Gallery:move_selection(dest)
    local items=self:selection()
    assert(#items>0,"Nenhuma obra selecionada")
    for _,item in ipairs(items) do
        -- Validates the entire operation before mutating.
        self:folder(dest)
        assert(item.id~=dest,"Pasta para si mesma")
        if item.type=="folder" then
            local cursor=dest
            while cursor~=0 do
                assert(cursor~=item.id,"Pasta descendente")
                cursor=self:folder(cursor).parent
            end
        end
    end
    for _,item in ipairs(items) do self:move(item.id,dest) end
    self:clear_selection()
    return #items
end
return Gallery
