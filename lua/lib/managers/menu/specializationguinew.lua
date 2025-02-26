local function make_fine_text(text)
	local x, y, w, h = text:text_rect()

	text:set_size(w, h)
	text:set_position(math.round(text:x()), math.round(text:y()))
end

local function filter_hide_unavailable_items(item)
	local dlc = tweak_data:get_raw_value("skilltree", "specializations", item.specialization_id, "dlc")

	if dlc and not managers.dlc:is_dlc_unlocked(dlc) and managers.dlc:should_hide_unavailable(dlc) then
		return false
	end

	return true
end


local MOUSEOVER_COLOR = tweak_data.screen_colors.button_stage_2
local BUTTON_COLOR = tweak_data.screen_colors.button_stage_3
local S_FONT = tweak_data.menu.pd2_small_font
local S_FONT_SIZE = tweak_data.menu.pd2_small_font_size
local M_FONT = tweak_data.menu.pd2_medium_font
local M_FONT_SIZE = tweak_data.menu.pd2_medium_font_size


--only change was applying the tcd icon macros
function SpecializationGuiNew:update_detail_panels(item)
	self._details_panel:clear()
	BoxGuiObject:new(self._details_panel, {
		sides = {
			1,
			1,
			1,
			1
		}
	})

	if #self._scroll_list:items() <= 0 then
		return
	end

	local selected_item = self._scroll_list:selected_item()

	selected_item:set_horizontal_index(self._scroll_horizontal_index)
	self._details_panel:rect({
		alpha = 0.5,
		layer = 0,
		color = Color.black
	})

	local y_pos = 0
	local margin = 10
	local title_text = self._details_panel:text({
		name = "details_title",
		layer = 1,
		text = managers.localization:text(selected_item.specialization_data.name_id),
		font = M_FONT,
		font_size = S_FONT_SIZE
	})

	make_fine_text(title_text)
	title_text:set_center_x(self._details_panel:w() / 2)
	title_text:set_y(y_pos + margin)

	y_pos = title_text:bottom()
	local specialization_descs_tweak = tweak_data.upgrades.specialization_descs[selected_item.specialization_id]
	local text_params = {
		text = "",
		wrap = true,
		word_wrap = true,
		layer = 1,
		x = margin,
		w = self._details_panel:w() - margin * 2,
		font = M_FONT,
		font_size = S_FONT_SIZE
	}
	local is_dlc_locked = selected_item:is_dlc_locked()

	if is_dlc_locked then
		local dlc = tweak_data:get_raw_value("skilltree", "specializations", selected_item.specialization_id, "dlc")

		if dlc and not managers.dlc:is_dlc_unlocked(dlc) then
			local unlock_id = tweak_data:get_raw_value("lootdrop", "global_values", dlc, "unlock_id") or "bm_menu_dlc_locked"

			if managers.dlc:should_hide_unavailable(dlc) then
				unlock_id = "bm_menu_dlc_locked"
			end

			text_params.text = managers.localization:to_upper_text(unlock_id)
			text_params.color = tweak_data.screen_colors.important_1
			local lock_text = self._details_panel:text(text_params)

			ExtendedPanel.make_fine_text(lock_text)
			lock_text:set_y(y_pos + margin)

			y_pos = lock_text:bottom()
			text_params.color = Color.white
		end
	end

	if self._scroll_horizontal_index == 0 then
		local desc_string = managers.localization:text(selected_item.specialization_data.desc_id)
		desc_string = desc_string:gsub("\n\n", "\n")
		local desc_text = self._details_panel:text({
			name = "details_desc",
			wrap = true,
			word_wrap = true,
			layer = 1,
			x = margin,
			w = self._details_panel:w() - margin * 2,
			text = desc_string,
			font = M_FONT,
			font_size = S_FONT_SIZE
		})

		ExtendedPanel.make_fine_text(desc_text)
		desc_text:set_y(y_pos + margin)

		y_pos = desc_text:bottom()
		local current_tier = managers.skilltree:get_specialization_value(selected_item.specialization_id, "tiers", "current_tier")

		for index, spec_data in ipairs(selected_item.specialization_data) do
			if index % 2 ~= 0 then
				local specialization_description = specialization_descs_tweak and specialization_descs_tweak[index] or {}
				local multi_choice_specialization_descs = {}
				local choice_data = nil

				if spec_data.multi_choice then
					local choice_index = managers.skilltree:get_specialization_value(selected_item.specialization_id, "choices", index)

					if choice_index and choice_index > 0 then
						multi_choice_specialization_descs = tweak_data:get_raw_value("upgrades", "multi_choice_specialization_descs", selected_item.specialization_id, index, choice_index) or {}
						choice_data = spec_data.multi_choice[choice_index]
					end
				end

				local locked = current_tier < index
				local macroes = {
					BTN_ABILITY = managers.localization:btn_macro("throw_grenade"),
					BTN_CHANGE_EQUIPMENT = managers.localization:btn_macro("change_equipment"),
					CLONED_CARD = managers.localization:text("menu_deck_multichoice_no_choice")
				}

				for i, d in pairs(specialization_description) do
					macroes[i] = d
				end
				
				--added below line
				DeathvoxOverhaulCore.insert_tcd_macros(macroes)

				local choice_macroes = {
					BTN_ABILITY = managers.localization:btn_macro("throw_grenade"),
					BTN_CHANGE_EQUIPMENT = managers.localization:btn_macro("change_equipment"),
					CLONED_CARD = choice_data and choice_data.name_id and managers.localization:text(choice_data.name_id) or managers.localization:text("menu_deck_multichoice_no_choice")
				}

				for i, d in pairs(multi_choice_specialization_descs) do
					choice_macroes[i] = d
				end

				local desc_string = ""
				local has_desc = false

				if not choice_data or not choice_data.skip_tier_desc and not choice_data.skip_tier_name then
					desc_string = desc_string .. ((spec_data.short_id or spec_data.desc_id) and managers.localization:text(spec_data.short_id or spec_data.desc_id, macroes) or "") .. " "
					has_desc = true
				end

				if choice_data and (choice_data.short_id or choice_data.desc_id) and not is_dlc_locked then
					desc_string = desc_string .. managers.localization:text(choice_data.short_id or choice_data.desc_id, choice_macroes)
					has_desc = true
				end
				
				--added below line
				DeathvoxOverhaulCore.insert_tcd_macros(choice_macroes)

				text_params.text = has_desc and managers.localization:text("menu_specialization_tier") .. " " .. index .. ": " .. desc_string or ""
				text_params.text = text_params.text:gsub("\n\n", " ")
				text_params.text = text_params.text:gsub("\n", " ")
				text_params.alpha = locked and 0.75 or 1
				local ability_text = self._details_panel:text(text_params)

				managers.menu_component:add_colors_to_text_object(ability_text, tweak_data.screen_colors.resource)
				ExtendedPanel.make_fine_text(ability_text)
				ability_text:set_y(y_pos + margin)

				y_pos = ability_text:bottom()
			end
		end
	else
		local spec_data = selected_item.specialization_data[self._scroll_horizontal_index]
		local specialization_description = specialization_descs_tweak and specialization_descs_tweak[self._scroll_horizontal_index] or {}
		local multi_choice_specialization_descs = {}
		local choice_data = nil

		if spec_data.multi_choice then
			local choice_index = managers.skilltree:get_specialization_value(selected_item.specialization_id, "choices", self._scroll_horizontal_index)

			if choice_index and choice_index > 0 then
				multi_choice_specialization_descs = tweak_data:get_raw_value("upgrades", "multi_choice_specialization_descs", selected_item.specialization_id, self._scroll_horizontal_index, choice_index) or {}
				choice_data = spec_data.multi_choice[choice_index]
			end
		end

		local macroes = {
			BTN_ABILITY = managers.localization:btn_macro("throw_grenade"),
			BTN_CHANGE_EQUIPMENT = managers.localization:btn_macro("change_equipment")
		}

		for i, d in pairs(specialization_description) do
			macroes[i] = d
		end
		
		--added below line
		DeathvoxOverhaulCore.insert_tcd_macros(macroes)
		
		local choice_macroes = {
			BTN_ABILITY = managers.localization:btn_macro("throw_grenade"),
			BTN_CHANGE_EQUIPMENT = managers.localization:btn_macro("change_equipment")
		}
		
		for i, d in pairs(multi_choice_specialization_descs) do
			choice_macroes[i] = d
		end
				
		--added below line
		DeathvoxOverhaulCore.insert_tcd_macros(choice_macroes)

		local text_string = ""
		local name_id = spec_data.name_id
		local desc_id = spec_data.desc_id
		text_string = text_string .. string.format("%s:\n%s", managers.localization:text(name_id), managers.localization:text(desc_id, macroes))

		if choice_data and not is_dlc_locked then
			local choice_string = ""
			local choice_name_id = choice_data.name_id
			local choice_desc_id = choice_data.desc_id

			if choice_name_id then
				choice_string = choice_string .. string.format("%s:\n%s", managers.localization:text(choice_name_id), managers.localization:text(choice_desc_id, choice_macroes))
			else
				choice_string = choice_string .. string.format("%s", managers.localization:text(choice_desc_id, choice_macroes))
			end

			if choice_data.shorten_desc then
				choice_string = choice_string:gsub("\n\n", "\n")
			end

			if choice_data.skip_tier_desc then
				text_string = choice_string
			elseif choice_data.skip_tier_name then
				text_string = choice_string .. "\n\n" .. managers.localization:text(desc_id, macroes)
			else
				text_string = text_string .. "\n\n" .. choice_string
			end
		end

		if _G.IS_VR or managers.user:get_setting("show_vr_descs") then
			local vr_desc_data = tweak_data:get_raw_value("vr", "specialization_descs_addons", selected_item.specialization_id, self._scroll_horizontal_index)

			if vr_desc_data then
				local vr_string = managers.localization:text("menu_vr_skill_addon") .. " " .. managers.localization:text(vr_desc_data.desc_id, vr_desc_data.macros)
				text_string = text_string .. string.format("\n\n%s", vr_string)
			end
		end

		text_params.text = text_string
		local ability_text = self._details_panel:text(text_params)

		managers.menu_component:add_colors_to_text_object(ability_text, tweak_data.screen_colors.resource)
		ExtendedPanel.make_fine_text(ability_text)
		ability_text:set_y(y_pos + margin)

		y_pos = ability_text:bottom()
	end
end

-- =========================
-- perk deck shake code below
local ANGLE = 10 --angle that the icon will rotate in either direction
local ROTATION_SPEED = 0.5 --rotation cycles per second
local TIME_OFFSET = 0.33 --seconds delay for the shadow bitmap
local ROTATION_OFFSET = 0 --degrees delay for the shadow bitmap (functionally the same as TIME_OFFSET but by a different measure)
local SCANLINES_SPEED = 10 --px/sec

local SCANLINES_RESTING_ALPHA = 0.33
local SHADOW_RESTING_ALPHA = 0.33

Hooks:PostHook(SpecializationGuiNew,"update","tcd_specguinew_update",function(self,t,dt)
	local list_items = self._scroll_list and self._scroll_list:items()
	
	for index, item in ipairs(list_items) do
		if item.specialization_data.shake then
			local shake_t = item._shake_t + dt
			item._shake_t = shake_t
			
			local current_tier = item:get_current_tier()
			
			for i,card_panel in ipairs(item._card_panels) do
				if alive(card_panel) then
					if item._shake_selected then
						if current_tier >= i then 
							card_panel:child("icon"):set_rotation(math.sin(shake_t * 360 * ROTATION_SPEED) * ANGLE)
							card_panel:child("icon_shadow"):set_rotation(math.sin((shake_t - TIME_OFFSET) * 360 * ROTATION_SPEED) * ANGLE)
						
							local scanlines_panel = card_panel:child("scanlines_panel")
							local tier_scanlines = scanlines_panel:child("tier_scanlines")
							
--							tier_scanlines:set_alpha(math.sin(
							local scanline_y = tier_scanlines:y() + (dt * SCANLINES_SPEED)
							if scanline_y >= 0 then 
								tier_scanlines:set_y(-scanlines_panel:h())
							else
								tier_scanlines:set_y(scanline_y)
							end
							scanlines_panel:set_x((card_panel:w() - scanlines_panel:w()) / 2)
						end
					end
				end
			end
		end
	end
end)


local function animate_fade(o,to_a,duration)
	local from_a = o:alpha()
	local d_a = to_a - from_a
	local lerp2 = 0
	duration = duration or 1
	over(duration,function(lerp)
		lerp2 = math.bezier(
			{
				0,
				0,
				1,
				1
			},
			lerp
		)
		o:set_alpha(from_a+(d_a*lerp2))
	end)
	o:set_alpha(to_a)
end

local function animate_lerp(o,to_rot,duration)
	local from_rot = o:rotation()
	local d_rot = to_rot - from_rot
	local lerp2 = 0
	duration = duration or 1
	over(duration,function(lerp)
		lerp2 = math.bezier(
			{
				0,
				0,
				1,
				1
			},
			lerp
		)
		o:set_rotation(from_rot+(d_rot*lerp2))
	end)
	o:set_rotation(to_rot)
end

Hooks:PostHook(SpecializationListItem,"_selected_changed","tcd_speclistitem_onselectedchanged",function(self,state)
	if self.specialization_data.shake then 
		-- animate the neat elements to invisibility again
		self._shake_selected = state
		self._shake_t = 0
		
		local current_tier = self:get_current_tier()
		for index, item in ipairs(self.specialization_data) do
			local locked = current_tier < index
			if not locked then
				local card_panel = self._card_panels[index]
				local icon = card_panel:child("icon")
				local shadow = card_panel:child("icon_shadow")
				local scanlines_panel = card_panel:child("scanlines_panel")
				if state then
					-- animate in
					icon:stop()
					shadow:stop()
					scanlines_panel:stop()
					shadow:animate(animate_fade,SHADOW_RESTING_ALPHA,0.5)
					scanlines_panel:animate(animate_fade,1,0.5)
				else
					-- animate out
					icon:stop()
					icon:animate(animate_lerp,0)
					shadow:stop()
					scanlines_panel:stop()
					shadow:animate(animate_lerp,0)
					shadow:animate(animate_fade,0,1)
					scanlines_panel:animate(animate_fade,0,1)
				end
			end
		end
	end
end)

Hooks:PostHook(SpecializationListItem,"setup","tcd_speclistitem_setup",function(self)
	-- create other visual elements such as scanlines and shadow
	if self.specialization_data.shake then
		self._shake_t = 0
		for index, item in ipairs(self.specialization_data) do
			local current_tier = self:get_current_tier()
			local locked = current_tier < index
			
			local card_panel = self._card_panels[index]
			
			local guis_catalog = "guis/"
			
			if item.texture_bundle_folder then
				guis_catalog = guis_catalog .. "dlcs/" .. tostring(item.texture_bundle_folder) .. "/"
			end

			local atlas_name = item.icon_atlas or "icons_atlas"
			local icon_atlas_texture = guis_catalog .. "textures/pd2/specialization/" .. atlas_name
			local texture_rect_x = item.icon_xy and item.icon_xy[1] or 0
			local texture_rect_y = item.icon_xy and item.icon_xy[2] or 0
			local icon_texture_rect = item.icon_texture_rect or {
				64,
				64,
				64,
				64
			}
			
			card_panel:child("icon"):set_layer(locked and 5 or 6) -- bump the layer up one so that there's room for the shadow
			
			local icon_shadow = card_panel:bitmap({
				name = "icon_shadow",
				texture = icon_atlas_texture,
				texture_rect = {
					texture_rect_x * icon_texture_rect[1],
					texture_rect_y * icon_texture_rect[2],
					icon_texture_rect[3],
					icon_texture_rect[4],
				},
				halign = "scale",
				valign = "scale",
				rotation = ROTATION_OFFSET,
				layer = locked and 4 or 5,
				color = Color("000000"),
				alpha = 0 -- updated on selection change
			})
			icon_shadow:grow(-16,-16)
			icon_shadow:set_center(card_panel:w() / 2, card_panel:h() / 2)
			icon_shadow:move(0,4)
			
			local scanlines_w = 64 - 22
			local scanlines_h = 92 - 34
			local scanlines_panel = card_panel:panel({
				name = "scanlines_panel",
				w = scanlines_w - 2,
				h = scanlines_h,
				x = (card_panel:w() - scanlines_w) / 2,
				y = 3,
				alpha = 0, -- updated on selection change
				layer = 4
			})
			local tier_scanlines = scanlines_panel:bitmap({
				name = "tier_scanlines",
				texture = "guis/textures/pd2/damage_overlay_sociopath/scanlines_overlay",
				texture_rect = {
					0,math.random(360 - 92),1,92 + math.random(-4,4) --360 is the scanlines file height
				},
				x = 1,
				w = scanlines_panel:w(),
				h = scanlines_panel:h() * 2,
				y = -scanlines_h,
				blend_mode = "add",
				halign = "scale",
				valign = "scale",
				alpha = SCANLINES_RESTING_ALPHA,
				layer = 10
			})
		end
	end
end)
