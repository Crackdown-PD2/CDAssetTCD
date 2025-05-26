-- local
HUDTCDBuff = blt_class()

-- enums for alignment index readability
HUDTCDBuff.ALIGNMENT = {
	LEFT_CENTER = 1, -- anchored left, vertical center aligned
	RIGHT_CENTER = 2, -- anchored right, vertical center aligned
	TOP_LEFT = 3, -- anchored top, left aligned
	TOP_CENTER = 4, -- anchored top, center aligned
	TOP_RIGHT = 5, -- anchored top, right aligned
	BOTTOM_LEFT = 6, -- anchored bottom, left aligned
	BOTTOM_CENTER = 7, -- anchored bottom, center aligned
	BOTTOM_RIGHT = 8 -- anchored bottom, right aligned
}


-- layout:

--	> panel
--		> body
-- 			> dividers
--			> container frame
--				> container 1
--					> icon
--					> text
--				> container 2
--					> icon
--					> text


-- in top/bottom anchor layouts, w and h are reversed
HUDTCDBuff.CONTAINER_SIZE_LONG = 64
HUDTCDBuff.CONTAINER_SIZE_SHORT = 32

-- primary dimension is inherited from parent
HUDTCDBuff.BODY_SIZE = 64





function HUDTCDBuff:init(tcd_panel)
	self._alignment = 1 -- todo get setting
	
	self._threads = { -- animate threads, to selectively stop 
		align = {}
	}
	
	
	-- main panel for all tcd buff guiobjects
	local panel = tcd_panel:panel({
		name = "panel",
		layer = 2
	})
	self._panel = panel
	
	local body_panel = panel:panel({
		name = "body"
	})
	self._body_panel = body_panel
	
	-- holds all buff containers
	local container_frame = body_panel:panel({
		name = "container_frame",
		valign = "grow",
		halign = "grow",
		layer = 1
	})
	self._container_frame = container_frame
	
	--[[
	local divider_frame = body_panel:panel({
		name = "divider_frame",
		valign = "grow",
		halign = "grow",
		layer = 2
	})
	self._divider_frame = divider_frame
	--]]
	
	self:on_alignment_changed(self._alignment)
end

-- display data for buffs (info control is managed by tcdbuffmanager)
-- label is the text below the image (should be used for direct/important info like % effects)
-- tag is the text overlaid on the icon (should be used for secondary info like stack count)
HUDTCDBuff._buff_data = {
	pointclick = { -- [marksman] point and click
		source = "skill", -- -> texture is skill atlas
		icon_xy = {2,0}, -- coordinate on texture atlas
		aced = false -- show aced background
	},
	shotgrouping = { -- [gunner] shot grouping aced
		source = "skill",
		icon_xy = {8,2},
		aced = true
	},
	deathgrips = { -- [heavy] death grips basic
		source = "skill",
		icon_xy = {6,1},
		aced = false
	},
	shufflecut = { -- [dealer] shuffle and cut
		source = "skill",
		icon_xy = {2,11},
		aced = false
	},
	rollingcutter = { -- [fixer]
		source = "skill",
		icon_xy = {3,6},
		aced = false
	},
	staticdefense = { -- [sapper]
		source = "skill",
		icon_xy = {0,8},
		aced = false
	},
	automaticreboot = { -- [sapper]
		source = "skill",
		icon_xy = {0,10},
		aced = false
	},
	staydown = { -- [taskmaster] 
		source = "skill",
		icon_xy = {1,2},
		aced = false
	},
	checkup = { -- [medic]
		source = "skill",
		icon_xy = {3,2},
		aced = false
	},
	doctorsorders = { -- [medic]
		source = "skill",
		icon_xy = {3,0},
		aced = false
	},
	floatbutterfly = { -- [runner]
		source = "skill",
		icon_xy = {7,1},
		aced = false
	},
	killersnotebook = { -- [assassin]
		source = "skill",
		icon_xy = {11,0},
		aced = false
	}
	-- sentryinfo [engineer]
	-- joker states, protect and serve (this should be its own hud)
	-- tunedout = {}, -- [thief] camera status
	-- peoplewatching = {}, -- [thief] people watching aced
	
}

function HUDTCDBuff.format_time(t)
	local m = math.min(math.floor(t / 60),99)
	local s = t % 60
	
	return string.format("%01i:%02i",m,s)
end

function HUDTCDBuff:add_buff(id,data,skip_align)
	local buff_data = self._buff_data[id]
	if not id or not buff_data then
		log("ERROR: NO BUFF DATA",id)
	end
	self:remove_buff(id,true)
	
	local container = self._container_frame:panel({
		name = id,
		visible = true
	})
	do
		local dbug = container:rect({
			name = "debug",
			color = Color(math.random()^2,math.random()^2,math.random()^2),
			alpha = 0.1
		})
	end
	
	local texture,texture_rect
	local color = Color.white
	local icon_w,icon_h = 32,32
	if buff_data.source == "skill" then
		texture = "guis/textures/pd2/skilltree_2/icons_atlas_2"
		local x,y = unpack(buff_data.icon_xy or tweak_data.skilltree.skills[buff_data.icon].icon_xy)
		texture_rect = {x * 80,y * 80,80,80}
	elseif buff_data.source == "perk" then
		texture = "guis/textures/pd2/specialization/icons_atlas"
		--local skill_atlas = "guis/textures/pd2/skilltree/icons_atlas"
	end
	
	local icon_frame = container:panel({
		name = "icon_frame",
		w = icon_w,
		h = icon_h,
		layer = 2
	})
	
	local icon = icon_frame:bitmap({
		name = "icon",
		texture = texture,
		texture_rect = texture_rect,
		color = color,
		w = icon_w,
		h = icon_h,
		valign = "grow",
		halign = "grow",
		blend_mode = nil,
		layer = 1
	})
	
	local tag_bg = icon_frame:bitmap({
		name = "tag_bg",
		color = Color.black,
		--blend_mode = "multiply",
		texture = "guis/textures/pd2/equip_count",
		w = icon_w,
		h = icon_h,
		alpha = 0.5,
		render_template = "VertexColorTexturedRadial",
		valign = "grow",
		halign = "grow",
		layer = 2
	})
	tag_bg:set_center(icon_frame:w()/2,icon_frame:h()/2)
	
	--tag_bg:set_right(icon_frame:w())
	--tag_bg:set_bottom(icon_frame:h())
	local tag_text = icon_frame:text({
		name = "tag",
		text = "", --string.format("%i",math.random(1,9)),
		font = tweak_data.hud_players.ammo_font,
		font_size = 16,
		align = "right",
		vertical = "bottom",
		valign = "grow",
		halign = "grow",
		layer = 3
	})
	
	--[[
	local tag_frame = container:panel({
		name = "label_frame",
		w = 
	})
	--]]
	local label_text = container:text({
		name = "label",
		text = self.format_time(math.random(99)),
		font = tweak_data.hud_players.ammo_font,
		font_size = 18,
		x = 0,
		y = 0,
		valign = "grow",
		halign = "grow",
		align = "left",
		vertical = "top",
		layer = 3
	})
	
	-- secondary (perpendicular) divider between buffs
	local divider = container:rect({
		name = "divider",
		w = 0,
		h = 0,
		visible = false
	})
	
	local DIV_WIDTH = 2
	
	local index = self._alignment
	if		index == self.ALIGNMENT.LEFT_CENTER
		or	index == self.ALIGNMENT.RIGHT_CENTER 
		then
		container:set_size(self.CONTAINER_SIZE_LONG,self.CONTAINER_SIZE_SHORT)
		
		if		index == self.ALIGNMENT.LEFT_CENTER then
			divider:set_halign("left")
		elseif	index == self.ALIGNMENT.RIGHT_CENTER then
			divider:set_halign("right")
		end
		divider:set_valign("center")
		
		--icon_frame:set_position(0,DIV_WIDTH)
		
		label_text:set_x(icon_frame:right())
		label_text:set_align("left") -- even if right-align, keep text left-aligned
		label_text:set_vertical("center")
		
		divider:set_h(DIV_WIDTH)
		divider:animate(function(o)
			over(0.5,function(lerp)
				local sq = lerp * lerp
				o:set_w(sq * self.CONTAINER_SIZE_LONG)
			end)
			o:set_w(self.CONTAINER_SIZE_LONG)
		end)
		
	elseif 	index == self.ALIGNMENT.TOP_LEFT
		or	index == self.ALIGNMENT.TOP_CENTER
		or	index == self.ALIGNMENT.TOP_RIGHT
		or 	index == self.ALIGNMENT.BOTTOM_LEFT
		or	index == self.ALIGNMENT.BOTTOM_CENTER
		or	index == self.ALIGNMENT.BOTTOM_RIGHT
		then
		
		
		--icon_frame:set_position(DIV_WIDTH,0)
		
		label_text:set_y(icon_frame:bottom())
		label_text:set_align("center")
		label_text:set_vertical("bottom")
		
		if		index == self.ALIGNMENT.TOP_LEFT then
			divider:set_halign("left")
			divider:set_valign("top")
		elseif	index == self.ALIGNMENT.TOP_CENTER then
			divider:set_halign("center")
			divider:set_valign("top")
		elseif	index == self.ALIGNMENT.TOP_RIGHT then
			divider:set_halign("right")
			divider:set_valign("top")
		elseif 	index == self.ALIGNMENT.BOTTOM_LEFT then
			divider:set_halign("left")
			divider:set_valign("bottom")
		elseif	index == self.ALIGNMENT.BOTTOM_CENTER then
			divider:set_halign("center")
			divider:set_valign("bottom")
		elseif	index == self.ALIGNMENT.BOTTOM_RIGHT then
			divider:set_halign("right")
			divider:set_valign("bottom")
		end
		
		container:set_size(self.CONTAINER_SIZE_SHORT,self.CONTAINER_SIZE_LONG)
		divider:set_w(DIV_WIDTH)
		divider:animate(function(o)
			over(0.5,function(lerp)
				local sq = lerp * lerp
				o:set_h(sq * self.CONTAINER_SIZE_LONG)
			end)
			o:set_h(self.CONTAINER_SIZE_LONG)
		end)
	end
	
	if not skip_align then
		local index = #self._container_frame:children()
		local get_x,get_y = self:get_align_callbacks(self._alignment)
		
		-- animate organize
		self:sort_buffs_except(nil,index)
		self:_sort_buff(index,index,container,true,get_x,get_y)
	end
	
	return container
end

function HUDTCDBuff:_sort_buff(i,total,buff,instant,get_x,get_y)
	local threads = self._threads.align
	if threads[buff] then
		buff:stop(threads[buff])
		threads[buff] = nil
	end
	local x1,y1 = buff:position()
	local x2,y2 = get_x(i,total),get_y(i,total)
	local dx = x2-x1
	local dy = y2-y1
	if instant then
		buff:set_position(x2,y2)
	else
		local thread = buff:animate(function(o)
			over(0.5,function(lerp)
				local n = lerp * lerp
				o:set_position(x1+dx*n,y1+dy*n)
			end)
			o:set_position(x2,y2)
		end)
		threads[buff] = thread
	end
		
end

function HUDTCDBuff:sort_buffs_except(instant,index)
	local get_x,get_y = self:get_align_callbacks(self._alignment)
	
	local children = self._container_frame:children()
	local num_children = #children
	for i,buff in ipairs(children) do
		if i ~= index then
			self:_sort_buff(i,num_children,buff,instant,get_x,get_y)
		end
	end
end

function HUDTCDBuff:get_align_callbacks(index)
	index = index or self._alignment
	
	local get_x
	local get_y
	
	if		index == self.ALIGNMENT.LEFT_CENTER
		or	index == self.ALIGNMENT.RIGHT_CENTER 
		then
		
		get_x = function(i,total)
			return 0
		end
		
		get_y = function(i,total)
			local center_y = self._body_panel:h() / 2
			return center_y - (self.CONTAINER_SIZE_SHORT * ((i-1)-(total/2)))
		end
	elseif 	index == self.ALIGNMENT.TOP_LEFT
		or	index == self.ALIGNMENT.TOP_CENTER
		or	index == self.ALIGNMENT.TOP_RIGHT
		or	index == self.ALIGNMENT.BOTTOM_LEFT
		or	index == self.ALIGNMENT.BOTTOM_CENTER
		or	index == self.ALIGNMENT.BOTTOM_RIGHT
		then
		
		if 		index == self.ALIGNMENT.TOP_CENTER 
			or	index == self.ALIGNMENT.BOTTOM_CENTER
			then
			
			get_x = function(i,total)
				local center_x = self._body_panel:w() / 2
				return center_x - (self.CONTAINER_SIZE_LONG * ((i-1)-(total/2)))
			end
		elseif	index == self.ALIGNMENT.TOP_LEFT
			or	index == self.ALIGNMENT.BOTTOM_LEFT
			then
		
			get_x = function(i,total)
				return self.CONTAINER_SIZE_LONG * i
			end
		elseif	index == self.ALIGNMENT.TOP_RIGHT
			or	index == self.ALIGNMENT.BOTTOM_RIGHT
			then
			
			get_x = function(i,total)
				local w = self._body_panel:w()
				return w - (self.CONTAINER_SIZE_LONG * (total-i))
			end
		end
		
		get_y = function(i,total)
			return 0
		end
	end
	
	return get_x,get_y
end

function HUDTCDBuff:sort_buffs(instant)
	local get_x,get_y = self:get_align_callbacks(self._alignment)
	
	local children = self._container_frame:children()
	local num_children = #children
	for i,buff in ipairs(children) do
		self:_sort_buff(i,num_children,buff,instant,get_x,get_y)
	end
end

function HUDTCDBuff.animate_buff_intro(o)

end

function HUDTCDBuff.animate_buff_outro(o)
	
end

function HUDTCDBuff.animate_sort_buff(o,x,y)

end


-- add listener on align setting changed

-- resize/reposition body panel
-- recreate dividers
-- sorts all current buffs

function HUDTCDBuff:on_alignment_changed(index)
	self:align_body(index)
	
end

function HUDTCDBuff:align_body(index)
	if		index == self.ALIGNMENT.LEFT_CENTER
		or	index == self.ALIGNMENT.RIGHT_CENTER 
		then
		
		-- resize
		self._body_panel:set_size(self.BODY_SIZE,self._panel:h())
		
		-- anchor
		if index == self.ALIGNMENT.LEFT_CENTER then
			self._body_panel:set_left(0)
		elseif index == self.ALIGNMENT.RIGHT_CENTER then
			self._body_panel:set_right(self._panel:w())
		end
		
		-- align
		self._body_panel:set_center_y(self._panel:h()/2)
		
	elseif 	index == self.ALIGNMENT.TOP_LEFT
		or	index == self.ALIGNMENT.TOP_CENTER
		or	index == self.ALIGNMENT.TOP_RIGHT
		then
		
		-- resize
		self._body_panel:set_size(self._panel:w(),self.BODY_SIZE)
		
		-- anchor
		if index == self.ALIGNMENT.TOP_LEFT then
			self._body_panel:set_left(0)
		elseif index == self.ALIGNMENT.TOP_CENTER then
			self._body_panel:set_center_x(self._panel:w()/2)
		elseif index == self.ALIGNMENT.TOP_RIGHT then
			self._body_panel:set_right(self._panel:w())
		end
		
		-- align
		self._body_panel:set_top(0)
		
	elseif 	index == self.ALIGNMENT.BOTTOM_LEFT
		or	index == self.ALIGNMENT.BOTTOM_CENTER
		or	index == self.ALIGNMENT.BOTTOM_RIGHT
		then
		
		-- resize
		self._body_panel:set_size(self._panel:w(),self.BODY_SIZE)
		
		-- anchor
		if index == self.ALIGNMENT.BOTTOM_LEFT then
			self._body_panel:set_left(0)
		elseif index == self.ALIGNMENT.BOTTOM_CENTER then
			self._body_panel:set_center_x(self._panel:w()/2)
		elseif index == self.ALIGNMENT.BOTTOM_RIGHT then
			self._body_panel:set_right(self._panel:w())
		end
		
		-- align
		self._body_panel:set_bottom(self._panel:h())
	end
	
	-- remove dividers
end

function HUDTCDBuff:set_icon_color(id,color)
	local buff = self._container_frame:child(id)
	if buff then
		buff:child("icon_frame"):child("icon"):set_color(color)
	end
end

function HUDTCDBuff:set_label_color(id,color)
	local buff = self._container_frame:child(id)
	if buff then
		buff:child("label"):set_color(color)
	end
end

function HUDTCDBuff:set_label_text(id,text)
	local buff = self._container_frame:child(id)
	if buff then
		buff:child("label"):set_text(text)
	end
end

function HUDTCDBuff:set_tag_color(id,color)
	local buff = self._container_frame:child(id)
	if buff then
		buff:child("icon_frame"):child("tag"):set_color(color)
	end
end

function HUDTCDBuff:set_tag_text(id,text)
	local buff = self._container_frame:child(id)
	if buff then
		buff:child("icon_frame"):child("tag"):set_text(text)
	end
end

function HUDTCDBuff:set_progress(id,current,total)
	local buff = self._container_frame:child(id)
	if buff then
		buff:child("icon_frame"):child("tag_bg"):set_color(Color(current/total,1,0))
	end
end

function HUDTCDBuff:has_buff(id)
	return self._container_frame:child(id) and true or false
end

function HUDTCDBuff:remove_buff(id,skip_sort)
	
	local child = self._container_frame:child(id)
	if child then
		for category,threads in pairs(self._threads) do 
			threads[child] = nil
		end
		self._container_frame:remove(child)
		if not skip_sort then
			self:sort_buffs()
		end
	end
	
end

-- not used
function HUDTCDBuff:pre_destroy()
	-- clear any residual data
end

return HUDTCDBuff