-- Windows-oriented editor interface preferences, no painting engine.
-- Documented ibisPaint concepts: Tool Select Position (Left/Right/Popup),
-- Popup column count (1-3), show tool labels, inverted mouse wheel.
local Preferences={}
Preferences.__index=Preferences

function Preferences.new()
    return setmetatable({
        tool_position="left",
        popup_columns=3,
        show_tool_labels=true,
        invert_wheel=false,
        show_undo_message=true
    },Preferences)
end

function Preferences:set_tool_position(position)
    assert(position=="left" or position=="right" or position=="popup",
        "Tool Select Position inválida")
    self.tool_position=position
end

function Preferences:set_popup_columns(columns)
    assert(self.tool_position=="popup",
        "Número de colunas só é definido no modo Popup")
    assert(type(columns)=="number" and columns==math.floor(columns)
        and columns>=1 and columns<=3,"Número de colunas inválido")
    self.popup_columns=columns
end

function Preferences:toggle_tool_labels()
    self.show_tool_labels=not self.show_tool_labels
    return self.show_tool_labels
end

function Preferences:toggle_invert_wheel()
    self.invert_wheel=not self.invert_wheel
    return self.invert_wheel
end

function Preferences:toggle_undo_messages()
    self.show_undo_message=not self.show_undo_message
    return self.show_undo_message
end

function Preferences:effective_tool_columns()
    if self.tool_position~="popup" then return 1 end
    return self.popup_columns
end

function Preferences:rail_x(logical_width)
    assert(type(logical_width)=="number" and logical_width>=120,
        "Largura inválida")
    if self.tool_position=="left" then return 0 end
    if self.tool_position=="right" then return logical_width-59 end
    return nil
end

function Preferences:panel_size(logical_width,logical_height)
    local cols=self:effective_tool_columns()
    local cell=cols==1 and 205 or (cols==2 and 105 or 90)
    local pw=cols*cell+24
    local row_height=cols==1 and 42 or 68
    local rows=math.ceil(15/cols)
    local ph=rows*row_height+52
    local usable_w=math.max(120,logical_width-82)
    local usable_h=math.max(120,logical_height-118)
    return math.min(pw,usable_w), math.min(ph,usable_h)
end

function Preferences:wheel_steps(steps)
    assert(type(steps)=="number", "Delta da roda inválido")
    return self.invert_wheel and -steps or steps
end

-- Editable, data-only file format. Never evaluate Lua source from disk.
function Preferences:encode()
    local yes=function(value) return value and "1" or "0" end
    return table.concat({
        "version=1",
        "tool_position="..self.tool_position,
        "popup_columns="..tostring(self.popup_columns),
        "show_tool_labels="..yes(self.show_tool_labels),
        "invert_wheel="..yes(self.invert_wheel),
        "show_undo_message="..yes(self.show_undo_message),
    },"\n").."\n"
end

function Preferences.decode(content)
    assert(type(content)=="string" and #content<=4096,
        "Configuração inválida ou excessivamente grande")
    local values={}
    local recognized={
        version=true,tool_position=true,popup_columns=true,
        show_tool_labels=true,invert_wheel=true,show_undo_message=true
    }
    for line in content:gmatch("[^\r\n]+") do
        local key,value=line:match("^([%w_]+)=([%w_]+)$")
        assert(key and recognized[key] and values[key]==nil,
            "Entrada inválida na configuração de interface")
        values[key]=value
    end
    assert(values.version=="1","Versão da configuração desconhecida")
    local result=Preferences.new()
    result:set_tool_position(values.tool_position)
    -- Save the Popup column setting even when the currently docked
    -- tool position is Left or Right.
    local position=result.tool_position
    result:set_tool_position("popup")
    result:set_popup_columns(tonumber(values.popup_columns))
    result:set_tool_position(position)
    for _,field in ipairs({
        "show_tool_labels","invert_wheel","show_undo_message"
    }) do
        local value=values[field]
        assert(value=="1" or value=="0","Valor booleano inválido")
        result[field]=value=="1"
    end
    return result
end

return Preferences
