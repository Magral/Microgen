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
    self:box(left+8,540,4,972,color("4edbb9"))
    self:box(1230,870,w-74,2,color("234650"))
    self:text(left+44,980,title,1.30,color("e2f4ed"),w-176)
    if subtitle then self:fit_text(left+44,916,subtitle,.94,color("a8c7c8"),w-118,52) end
    self:button(left+w-77,980,84,84,"×",close)
    return left
end

function Interface:meter(left,y,w,h,fill)
    local track = self:box(left+w/2,y,w,h,color("193540"))
    local node = self:box(left,y,w,h,fill)
    gui.set_pivot(node,gui.PIVOT_W)
    return node,track
end

function Interface:image(atlas,frame,x,y,w,h)
    local node=self:box(x,y,w,h,vmath.vector4(1,1,1,1))
    gui.set_texture(node,atlas)
    gui.play_flipbook(node,frame)
    return node
end

function Interface:fit_text(x,y,message,scale,shade,width,height)
    self.card_font = self.card_font or gui.get_font_resource("interface")
    local metrics
    for _ = 1, 7 do
        metrics = resource.get_text_metrics(self.card_font,message,{width=width/scale,line_break=true})
        if metrics.height*scale <= height and metrics.width*scale <= width then break end
        scale = scale*.90
    end
    if sys.get_config_string("microgen.smoke_cards","0")=="1" then
        assert(metrics.height*scale <= height and metrics.width*scale <= width,
            "Mutation text exceeds its layout slot: "..message)
    end
    return self:text(x,y,message,scale,shade,width)
end

function Interface:cards(items,row_y,callback,set_color,preview)
    local count = #items
    local gap = 22
    local width = math.min(680,math.floor(((self.panel_width or 1545)-72-(count-1)*gap)/math.max(1,count)))
    local first = 1230-((width+gap)*count-gap)/2+width/2
    for i,item in ipairs(items) do
        local index = i
        local x = first+(width+gap)*(i-1)
        local left = x-width/2+28
        local shade = set_color and set_color(item) or MINT
        self:surface(x,row_y,width+6,578,"panel")
        self:surface(x,row_y,width,570,"card")
        self:box(x,row_y+276,width-54,5,shade)
        self:box(x-width/2+3,row_y,5,510,shade)
        if item.icon or item.image_frame then
            self:surface(left+67,row_y+157,132,132,"button")
            local has_preview=item.icon and preview and preview(item,left+67,row_y+157,132)
            if not has_preview then
                local atlas=item.image_atlas or "icons"
                local frame=item.image_frame or ("icon_"..item.icon)
                self:image(atlas,frame,left+67,row_y+157,104,104)
            end
        end
        local has_icon=item.icon or item.image_frame
        local title_x = has_icon and left+151 or left+8
        local title_width = has_icon and width-206 or width-72
        self:fit_text(title_x,row_y+174,item.title or "",1.08,PALE,title_width,94)
        if item.meta then
            self:surface(title_x+title_width/2,row_y+91,title_width,38,"button")
            self:fit_text(title_x,row_y+91,item.meta,.80,MINT,title_width-20,34)
        end
        if item.rarity then
            self:surface(x+width/2-96,row_y+232,174,42,"button")
            self:box(x+width/2-96,row_y+232,5,30,shade)
            self:text(x+width/2-96,row_y+232,string.upper(item.rarity),.67,shade,154,true)
        end
        if item.detail then
            self:box(x,row_y+23,width-56,2,color("2a4a53"))
            self:fit_text(left,row_y-14,item.detail,.94,PALE,width-62,98)
        end
        if item.extra then
            local panel=self:surface(x,row_y-112,width-52,92,"button")
            gui.set_color(panel,vmath.vector4(.52,.83,.81,.28))
            self:box(x-width/2+40,row_y-112,4,60,item.extra_color or MINT)
            local state=tostring(item.extra)
            local state_label=state:find("СИНЕРГИЯ",1,true) and "СИНЕРГИЯ" or "УСЛОВИЕ"
            local state_color=item.extra_color or DIM
            if state:find("УЖЕ АКТИВНА",1,true) or state:find("АКТИВНА ·",1,true) then
                state_label="АКТИВНА"
                state_color=MINT
            elseif state:find("НЕ АКТИВНА",1,true) then
                state_label="НЕ АКТИВНА"
                state_color=color("e7ad9c")
            elseif state:find("ВКЛЮЧИТСЯ",1,true) then
                state_label="ГОТОВА"
                state_color=color("e5cc82")
            end
            self:fit_text(left+18,row_y-112,item.extra,.69,state_color,width-226,78)
            self:surface(x+width/2-92,row_y-112,136,40,"button")
            self:text(x+width/2-92,row_y-112,state_label,.60,state_color,122,true)
        else
            self:surface(x,row_y-112,width-52,74,"button")
            self:text(x,row_y-112,"ПАССИВНЫЙ ЭФФЕКТ",.72,DIM,nil,true)
        end
        local action
        if not item.sold then action=function() callback(item,index) end end
        self:button(x,row_y-220,width-52,84,item.action or "Выбрать",action,true,1.08)
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
