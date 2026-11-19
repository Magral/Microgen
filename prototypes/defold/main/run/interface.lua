local Interface = {}
Interface.__index = Interface

Interface.width, Interface.height = 2460, 1080

function Interface.color(hex,alpha)
    return vmath.vector4(
        tonumber(hex:sub(1,2),16)/255,
        tonumber(hex:sub(3,4),16)/255,
        tonumber(hex:sub(5,6),16)/255,
        alpha or 1)
end

local color = Interface.color
local PALE = color("d4e7e7")
local MINT = color("9ce3cf")
local DIM = color("a5c4c4")
local DARK = color("0c202b")
local SHADE = vmath.vector4(.015,.035,.05,.88)
Interface.colors = {pale=PALE,mint=MINT,dim=DIM,gold=color("dbbd8c"),red=color("efb6a9")}

function Interface.new()
    return setmetatable({nodes={}, buttons={}, group="overlay"},Interface)
end

function Interface:remember(node)
    self.nodes[#self.nodes+1] = node
    gui.set_layer(node,self.group)
    return node
end

function Interface:box(x,y,w,h,color)
    local node = self:remember(gui.new_box_node(vmath.vector3(x,y,0),vmath.vector3(w,h,0)))
    gui.set_color(node,color or DARK)
    return node
end

function Interface:text(x,y,message,scale,color,width,center)
    local node = self:remember(gui.new_text_node(vmath.vector3(x,y,0),message))
    gui.set_font(node,"interface")
    gui.set_pivot(node,center and gui.PIVOT_CENTER or gui.PIVOT_W)
    gui.set_scale(node,vmath.vector3(scale or 1,scale or 1,1))
    gui.set_color(node,color or PALE)
    if width then
        gui.set_line_break(node,true)
        gui.set_size(node,vmath.vector3(width/(scale or 1),0,0))
    end
    return node
end

function Interface:surface(x,y,w,h,frame)
    local node = self:image("skin",frame or "card",x,y,w,h)
    gui.set_slice9(node,vmath.vector4(24,24,24,24))
    return node
end

function Interface:button(x,y,w,h,label,callback,accent,scale)
    local node = self:surface(x,y,w,h,callback and (accent and "primary" or "button") or "disabled")
    local text = self:text(x,y,label,scale or 1,
        callback and (accent and color("09272c") or color("d6eeea")) or color("637b82"),nil,true)
    local button = {node=node,text=text,callback=callback}
    if callback then self.buttons[#self.buttons+1] = button end
    return button
end

function Interface.button_enabled(button,enable)
    if button.enabled==enable then return end
    button.enabled=enable
    gui.set_enabled(button.node,enable)
    gui.set_enabled(button.text,enable)
end

function Interface:panel(title,subtitle,close,size)
    local w = size or 1545
    local left = (Interface.width-w)/2
    self.panel_width=w
    self:box(1230,540,2460,1080,SHADE)
    self:surface(1230,540,w,1038,"panel")
    self:text(left+33,980,title,1.25,color("e2f4ed"),w-150)
    if subtitle then self:text(left+33,907,subtitle,.92,color("94b5b8"),w-72) end
    self:button(left+w-77,980,84,84,"×",close)
    return left
end

function Interface:meter(left,y,w,h,fill)
    self:box(left+w/2,y,w,h,color("193540"))
    local node = self:box(left,y,w,h,fill)
    gui.set_pivot(node,gui.PIVOT_W)
    return node
end

function Interface:image(atlas,frame,x,y,w,h)
    local node=self:box(x,y,w,h,vmath.vector4(1,1,1,1))
    gui.set_texture(node,atlas)
    gui.play_flipbook(node,frame)
    return node
end

function Interface:cards(items,row_y,callback,set_color)
    local count = #items
    local gap = 18
    local width = math.min(532,math.floor(((self.panel_width or 1545)-66-(count-1)*gap)/math.max(1,count)))
    local first = 1230-((width+gap)*count-gap)/2+width/2
    for i,item in ipairs(items) do
        local index = i
        local x = first+(width+gap)*(i-1)
        local left = x-width/2+24
        local shade = set_color and set_color(item) or MINT
        self:surface(x,row_y,width,380)
        if item.icon then self:image("icons","icon_"..item.icon,left+46,row_y+118,92,92) end
        self:text(left+(item.icon and 109 or 0),row_y+118,item.title or "",.92,shade,width-(item.icon and 157 or 48))
        if item.detail then self:text(left,row_y+24,item.detail,.79,DIM,width-48) end
        if item.extra then self:text(left,row_y-47,item.extra,.76,MINT,width-48) end
        local action
        if not item.sold then action=function() callback(item,index) end end
        self:button(x,row_y-130,width-48,72,item.action or "Выбрать",action,true,.86)
    end
end

function Interface:clear()
    for i=#self.nodes,1,-1 do gui.delete_node(self.nodes[i]) end
    self.nodes,self.buttons,self.panel_width = {},{},nil
end

function Interface:visible(value)
    for _,node in ipairs(self.nodes) do gui.set_visible(node,value) end
end

function Interface:hit(x,y)
    for i=#self.buttons,1,-1 do
        local button = self.buttons[i]
        if button.enabled~=false and gui.pick_node(button.node,x,y) then return button.callback end
    end
end

return Interface
