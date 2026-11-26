local ScreenLayout = require "main.run.screen_layout"

local Interface = {}
Interface.__index = Interface

Interface.width, Interface.height = 2460, 1080
local PANEL_WIDTH = 2140
local CENTER_X = Interface.width / 2

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
local SHADE = vmath.vector4(.008,.023,.035,.56)
Interface.colors = {pale=PALE,mint=MINT,dim=DIM,gold=color("dbbd8c"),red=color("efb6a9")}

local function assert_inside_safe_area(self,node,label)
    if not self.safe_left or sys.get_config_string("microgen.smoke_cards","0")~="1" then return end
    local position,size=gui.get_position(node),gui.get_size(node)
    local epsilon=1
    assert(position.x-size.x/2>=self.safe_left-epsilon
        and position.x+size.x/2<=self.safe_right+epsilon
        and position.y-size.y/2>=self.safe_bottom-epsilon
        and position.y+size.y/2<=self.safe_top+epsilon,
        ("Interface element outside safe area (%s): center %.1f,%.1f size %.1f,%.1f bounds %.1f..%.1f / %.1f..%.1f")
            :format(label or "unnamed",position.x,position.y,size.x,size.y,
                self.safe_left,self.safe_right,self.safe_bottom,self.safe_top))
end

function Interface.new()
    return setmetatable({nodes={}, buttons={}, group="overlay"},Interface)
end

function Interface:remember(node)
    self.nodes[#self.nodes+1] = node
    gui.set_layer(node,self.group)
    return node
end

function Interface:fit_safe_area()
    local window_width,window_height=window.get_size()
    local scene_width,scene_height=gui.get_width(),gui.get_height()
    local left,right,top,bottom=ScreenLayout.safe_bounds(
        window_width,window_height,scene_width,scene_height,window.get_safe_area(),42,33)
    self.safe_left,self.safe_right,self.safe_top,self.safe_bottom=left,right,top,bottom
    self.safe_width=right-left
    self.safe_height=top-bottom
    self.center_x=(left+right)/2
    self.center_y=(top+bottom)/2
    self.horizontal_scale=math.max(.01,math.min(1,self.safe_width/Interface.width))
    self.vertical_scale=math.max(.01,math.min(1,self.safe_height/Interface.height))
    self.font_scale=math.min(1,math.sqrt(self.horizontal_scale*self.vertical_scale))
end

function Interface:widen(width)
    local target=math.max(1,math.min(PANEL_WIDTH,self.safe_width or PANEL_WIDTH))
    self.horizontal_scale=target/math.max(1,width)
    self.font_scale=math.min(1.18,math.sqrt(
        self.horizontal_scale*(self.vertical_scale or 1)))
end

function Interface:layout_x(x)
    local center=self.center_x or CENTER_X
    return center + (x - CENTER_X) * (self.horizontal_scale or 1)
end

function Interface:layout_y(y)
    local center=self.center_y or Interface.height/2
    return center + (y - Interface.height/2) * (self.vertical_scale or 1)
end

function Interface:box(x,y,w,h,color)
    x = self:layout_x(x)
    y = self:layout_y(y)
    w = w * (self.horizontal_scale or 1)
    local node = self:remember(gui.new_box_node(
        vmath.vector3(x,y,0),vmath.vector3(w,h*(self.vertical_scale or 1),0)))
    gui.set_color(node,color or DARK)
    return node
end

local function place_text(self,x,y,message,scale,color,width,center)
    local node = self:remember(gui.new_text_node(vmath.vector3(x,self:layout_y(y),0),message))
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

function Interface:text(x,y,message,scale,color,width,center)
    local font_scale = (scale or 1) * (self.font_scale or 1)
    return place_text(self,self:layout_x(x),y,message,font_scale,color,width and width*(self.horizontal_scale or 1),center)
end

function Interface:surface(x,y,w,h,frame)
    local node = self:box(x,y,w,h,vmath.vector4(1,1,1,1))
    gui.set_texture(node,"skin")
    gui.play_flipbook(node,frame or "card")
    gui.set_slice9(node,vmath.vector4(24,24,24,24))
    return node
end

function Interface:button(x,y,w,h,label,callback,accent,scale)
    local node = self:surface(x,y,w,h,callback and (accent and "primary" or "button") or "disabled")
    assert_inside_safe_area(self,node,"button: "..(label or ""))
    local shade = callback and (accent and color("09272c") or color("d6eeea")) or color("637b82")
    local text
    if self.horizontal_scale and label ~= "" then
        text = self:fit_text(x,y,label,scale or 1,shade,w-24,h-12,true)
    else
        text = self:text(x,y,label,scale or 1,shade,nil,true)
    end
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

function Interface:panel(title,subtitle,close,size,variant)
    local w = size or 1545
    local left = (Interface.width-w)/2
    self.panel_width=w
    local backdrop=variant=="mutation" and vmath.vector4(.008,.023,.035,.30) or SHADE
    local shade=self:remember(gui.new_box_node(
        vmath.vector3(CENTER_X,Interface.height/2,0),
        vmath.vector3(Interface.width,Interface.height,0)))
    gui.set_color(shade,backdrop)
    self:widen(w)
    local shell=self:surface(1230,540,w,1038,"panel")
    assert_inside_safe_area(self,shell,"modal panel")
    gui.set_color(shell,vmath.vector4(.54,.84,.85,variant=="mutation" and .12 or .76))
    self:box(left+8,540,4,972,color("4edbb9"))
    self:box(1230,870,w-74,2,color("39727b"))
    if variant=="mutation" then
        self:box(left+75,980,440,3,color("b57ee3"))
        self:box(left+w-515,980,440,3,color("b57ee3"))
        self:fit_text(1230,980,title,1.38,color("e2f4ed"),w-820,72,true)
        if subtitle then self:fit_text(1230,916,subtitle,.94,color("a8c7c8"),w-118,52,true) end
    else
        self:fit_text(left+44,980,title,1.30,color("e2f4ed"),w-176,72)
        if subtitle then self:fit_text(left+44,916,subtitle,.94,color("a8c7c8"),w-118,52) end
    end
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
    local horizontal=self.horizontal_scale or 1
    local vertical=self.vertical_scale or 1
    local uniform=math.min(horizontal,vertical)
    local node=self:box(x,y,w*uniform/horizontal,h*uniform/vertical,vmath.vector4(1,1,1,1))
    gui.set_texture(node,atlas)
    gui.play_flipbook(node,frame)
    return node
end

function Interface:fit_text(x,y,message,scale,shade,width,height,center)
    self.card_font = self.card_font or gui.get_font_resource("interface")
    width = width * (self.horizontal_scale or 1)
    height = height * (self.vertical_scale or 1)
    scale = scale * (self.font_scale or 1)
    local metrics
    for _ = 1, 7 do
        metrics = resource.get_text_metrics(self.card_font,message,{width=width/scale,line_break=true})
        if metrics.height*scale <= height and metrics.width*scale <= width then break end
        scale = scale*.90
    end
    if sys.get_config_string("microgen.smoke_cards","0")=="1" then
        assert(metrics.height*scale <= height and metrics.width*scale <= width,
            "Interface text exceeds its layout slot: "..message)
    end
    return place_text(self,self:layout_x(x),y,message,scale,shade,width,center)
end

function Interface:cards(items,row_y,callback,set_color,preview)
    local count = #items
    local gap = 22
    local width = math.min(680,math.floor(((self.panel_width or 1545)-72-(count-1)*gap)/math.max(1,count)))
    local first = 1230-((width+gap)*count-gap)/2+width/2
    for i,item in ipairs(items) do
        local index = i
        local x = first+(width+gap)*(i-1)
        local shade = set_color and set_color(item) or MINT
        local height=690
        self:surface(x,row_y,width+8,height+8,"panel")
        local card=self:surface(x,row_y,width,height,"card")
        gui.set_color(card,vmath.vector4(.72,.91,.91,.74))
        self:box(x,row_y+height/2-12,width-54,4,shade)
        self:box(x-width/2+3,row_y,5,height-30,shade)
        self:box(x+width/2-3,row_y,2,height-30,vmath.vector4(shade.x,shade.y,shade.z,.45))
        local has_icon=item.icon or item.image_frame
        local art_y=row_y+184
        if has_icon then
            local halo=self:image("cells","surge",x,art_y,380,380)
            gui.set_color(halo,vmath.vector4(shade.x,shade.y,shade.z,.34))
            local has_preview=item.icon and preview and preview(item,x,art_y,106)
            if not has_preview then
                local atlas=item.image_atlas or "icons"
                local frame=item.image_frame or ("icon_"..item.icon)
                local emblem=self:image(atlas,frame,x,art_y,176,176)
                gui.set_color(emblem,vmath.vector4(1,1,1,1))
            end
        end
        self:fit_text(x,row_y+15,item.title or "",1.24,PALE,width-64,68,true)
        if item.meta then
            local badge=self:surface(x,row_y-53,math.min(width-82,330),48,"button")
            gui.set_color(badge,vmath.vector4(shade.x,shade.y,shade.z,.20))
            self:fit_text(x,row_y-53,item.meta,.92,MINT,width-98,42,true)
        end
        if item.rarity then
            self:fit_text(x,row_y-106,string.upper(item.rarity),.78,shade,width-90,38,true)
        end
        if item.detail then
            self:box(x,row_y-133,width-56,2,color("50727a"))
            self:fit_text(x,row_y-176,item.detail,.90,PALE,width-78,82,true)
        end
        if item.extra then
            local panel=self:surface(x,row_y-291,width-52,86,"button")
            gui.set_color(panel,vmath.vector4(.35,.70,.71,.28))
            self:box(x-width/2+40,row_y-291,5,58,item.extra_color or MINT)
            local state=tostring(item.extra)
            local state_color=item.extra_color or DIM
            if state:find("НЕ АКТИВНА",1,true) then
                state_color=color("e7ad9c")
            elseif state:find("УЖЕ АКТИВНА",1,true) or state:find("АКТИВНА ·",1,true) then
                state_color=MINT
            elseif state:find("ВКЛЮЧИТСЯ",1,true) then
                state_color=color("e5cc82")
            end
            self:fit_text(x-width/2+63,row_y-291,item.extra,.76,state_color,width-112,72)
        elseif not item.service then
            local passive=self:surface(x,row_y-291,width-52,72,"button")
            gui.set_color(passive,vmath.vector4(.35,.70,.71,.20))
            self:text(x,row_y-291,"ПАССИВНЫЙ ЭФФЕКТ",.78,DIM,nil,true)
        end
        local action
        if not item.sold then action=function() callback(item,index) end end
        self:button(x,row_y-390,width-52,84,item.action or "Выбрать",action,true,1.18)
    end
end

function Interface:clear()
    for i=#self.nodes,1,-1 do gui.delete_node(self.nodes[i]) end
    self.nodes,self.buttons,self.panel_width = {},{},nil
    self.horizontal_scale,self.vertical_scale,self.font_scale = nil,nil,nil
    self.center_x,self.center_y,self.safe_width,self.safe_height = nil,nil,nil,nil
    self.safe_left,self.safe_right,self.safe_top,self.safe_bottom = nil,nil,nil,nil
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
