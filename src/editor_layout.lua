-- Geometry for the Paint Lua editor chrome.
-- All coordinates are logical LOVE units after the application's scale.
local Layout = {}
local function in_range(x,lo,hi)
    return math.max(lo,math.min(hi,x))
end
function Layout.compute(width,height,position,tool_count)
    assert(type(width)=="number" and width>=700,"Largura lógica insuficiente")
    assert(type(height)=="number" and height>=620,"Altura lógica insuficiente")
    assert(position=="left" or position=="right" or position=="popup",
        "Posição de ferramentas inválida")
    assert(type(tool_count)=="number" and tool_count>=1
        and tool_count==math.floor(tool_count),"Número de ferramentas inválido")
    local rail_x=position=="left" and 0 or
        (position=="right" and width-59 or nil)
    local row_top=60
    local row_bottom=height-136
    local row_height=in_range((row_bottom-row_top)/tool_count,25,43)
    local dock_w=510
    local dock_y=height-66
    local left_margin=position=="left" and 72 or 17
    local right_margin=position=="right" and 75 or 18
    local slider_w=306
    local top_right=position=="right" and width-70 or width-13
    local result={
        rail={x=rail_x,y=38,w=59,h=height-112,button_y=row_top,
            each=row_height},
        top={x=top_right-266,y=45,w=258,h=45,button_w=36,
            button_gap=6,button_x=top_right-266+9},
        dock={x=(width-dock_w)/2,y=dock_y,w=dock_w,h=56,
            button_x=(width-dock_w)/2+12,button_y=dock_y+5,
            button_size=48,button_pitch=61},
        sliders={y=height-122,h=44,w=slider_w,
            left_x=left_margin,right_x=width-right_margin-slider_w},
    }
    assert(result.top.x>55 or position=="popup",
        "Top controls overlap left rail")
    assert(result.sliders.right_x-result.sliders.left_x-slider_w>=70,
        "Sliders overlap")
    assert(result.rail.button_y+tool_count*result.rail.each<=height-132,
        "Tool rows overlap bottom chrome")
    return result
end
return Layout
