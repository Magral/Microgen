local Interface = {}
Interface.__index = Interface

Interface.width, Interface.height = 2460, 1080

local PALE = vmath.vector4(.90,.97,.94,1)
local MINT = vmath.vector4(.47,.95,.78,1)
local DIM = vmath.vector4(.61,.78,.76,1)
local DARK = vmath.vector4(.025,.076,.094,.96)
local TILE = vmath.vector4(.042,.145,.17,.98)
local SHADE = vmath.vector4(.01,.04,.06,.78)
Interface.colors = {pale=PALE,mint=MINT,dim=DIM,gold=vmath.vector4(.99,.81,.45,1),red=vmath.vector4(1,.53,.59,1)}

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

function Interface:text(x,y,message,scale,color,width)
    local node = self:remember(gui.new_text_node(vmath.vector3(x,y,0),message))
    gui.set_font(node,"interface")
    gui.set_pivot(node,gui.PIVOT_W)
    gui.set_scale(node,vmath.vector3(scale or 1,scale or 1,1))
    gui.set_color(node,color or PALE)
    if width then
        gui.set_line_break(node,true)
        gui.set_size(node,vmath.vector3(width/(scale or 1),500,0))
    end
    return node
end

function Interface:button(x,y,w,h,label,callback,accent)
    local node = self:box(x,y,w,h,accent and vmath.vector4(.07,.30,.30,1) or TILE)
    local line = self:box(x,y-h/2+2,w,3,accent and MINT or vmath.vector4(.20,.44,.46,.8))
    local text = self:text(x-w/2+24,y,label,.94,accent and MINT or PALE)
    local button = {node=node, line=line, text=text, callback=callback}
    if callback then self.buttons[#self.buttons+1] = button end
    return button
end

function Interface.button_enabled(button,enable)
    if button.enabled==enable then return end
    button.enabled=enable
    gui.set_enabled(button.node,enable)
    gui.set_enabled(button.line,enable)
    gui.set_enabled(button.text,enable)
end

function Interface:panel(title,subtitle,close,size)
    local w = size or 1664
    local left = (Interface.width-w)/2
    self:box(1230,540,2460,1080,SHADE)
    self:box(1230,540,w,876,DARK)
    self:box(1230,975,w,6,MINT)
    self:text(left+54,896,title,1.65,MINT)
    if subtitle then self:text(left+54,825,subtitle,.88,DIM) end
    if close then self:button(left+w-62,896,72,67,"×",close,false) end
    return left
end

function Interface:image(atlas,frame,x,y,w,h)
    local node=self:box(x,y,w,h,vmath.vector4(1,1,1,1))
    gui.set_texture(node,atlas)
    gui.play_flipbook(node,frame)
    return node
end

function Interface:cards(items, row_y, callback, set_color)
    local count = #items
    local width = math.min(490, math.floor((1540-(count-1)*28)/math.max(1,count)))
    local first = 1230 - ((width+28)*count-28)/2 + width/2
    for i,item in ipairs(items) do
        local index = i
        local x = first+(width+28)*(i-1)
        self:box(x,row_y,width,348,TILE)
        self:box(x,row_y+171,width,6,set_color and set_color(item) or MINT)
        self:text(x-width/2+23,row_y+108,item.title or "",.93,PALE,width-(item.icon and 110 or 46))
        if item.icon then self:image("icons","icon_"..item.icon,x+width/2-42,row_y+119,76,76) end
        if item.detail then self:text(x-width/2+23,row_y+16,item.detail,.81,DIM,width-46) end
        if item.extra then self:text(x-width/2+23,row_y-59,item.extra,.72,MINT,width-46) end
        self:button(x,row_y-125,width-40,59,item.action or "Выбрать",function()
            callback(item,index)
        end,true)
    end
end

function Interface:clear()
    for i=#self.nodes,1,-1 do gui.delete_node(self.nodes[i]) end
    self.nodes,self.buttons = {},{}
end

function Interface:hit(x,y)
    for i=#self.buttons,1,-1 do
        local button = self.buttons[i]
        if button.enabled~=false and gui.pick_node(button.node,x,y) then return button.callback end
    end
end

return Interface
