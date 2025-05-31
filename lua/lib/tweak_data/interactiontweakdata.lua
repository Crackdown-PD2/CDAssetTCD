Hooks:PostHook(InteractionTweakData, "init", "tcd_interactiontweakdata_init", function(self, tweak_data)
	local function tweak_interaction(id,category,upgrade,cb)
		-- for the interaction given by each id:
			-- remove singular "upgrade_timer_multiplier" and transfer it into the plural "upgrade_timer_multipliers" (creating it if it does not exist);
			
			-- check if the interaction already has the given category/upgrade that grants an interaction speed multiplier;
			-- if it does not, add it.
			
			-- then (if supplied), run the callback function on that data, supplying the id and data table as respective arguments 
	 
		local data = self[id]
		if data then
			local upgrade_timer_multipliers = data.upgrade_timer_multipliers or {}
			if data.upgrade_timer_multiplier then
				-- if using a single timer mul, 
				-- slap it in the plural mul table
				
				-- assume that the tweakdata doesn't already contain it
				table.insert(upgrade_timer_multipliers,data.upgrade_timer_multiplier)
				data.upgrade_timer_multiplier = nil
			end
			
			local already_contains_mul = false
			
			if category and upgrade then
				for _,mul_data in pairs(upgrade_timer_multipliers) do 
					if mul_data.upgrade == upgrade and mul_data.category == category then
						already_contains_mul = true
						break
					end
				end
				if not already_contains_mul then
					table.insert(upgrade_timer_multipliers,
						{
							upgrade = upgrade,
							category = category
						}
					)
				end
			end
			data.upgrade_timer_multipliers = upgrade_timer_multipliers
			
			if cb then
				cb(id,data)
			end
		end
	end
	
	local drill_place_list = {
		"drill",
		"suburbia_drill",
		"huge_lance",
		"goldheist_drill",
		"secret_stash_saw",
		"apartment_saw",
		"hospital_saw",
		"gen_int_saw"
	}
	for _,id in pairs(drill_place_list) do 
		tweak_interaction(id,"player","drill_place_interaction_speed_multiplier")
	end
	local drill_upgrade_list = {
		"gen_int_saw_upgrade",
		"drill_upgrade"
	}
	for _,id in pairs(drill_upgrade_list) do 
		tweak_interaction(id,"player","drill_upgrade_interaction_speed_multiplier")
	end
	local drill_jammed_list = {
		"suburbia_drill_jammed",
		"apartment_drill_jammed",
		"goldheist_drill_jammed",
		"huge_lance_jammed"
	}
	for _,id in pairs(drill_jammed_list) do 
		tweak_interaction(id,"player","drill_fix_interaction_speed_multiplier")
	end
	
	local hack_list = {
		"hack_ipad",
		"hack_ipad_bp1",
		"hack_ipad_jammed",
		"corp_hack_lead_email",
		"corp_hack_email",
		"hack_trai_outline",
		"trai_hold_disable_alarm",
		"chca_start_hacking",
		"chas_prop_hack_box",
		"pex_armory_hack",
		"start_hacking_axis",
		"start_hacking",
		"hacking_barrier",
		"hold_new_hack_tag",
		"tag_laptop",
		"hack_dah_jammed_x",
		"hold_hack_server_room",
		"drk_hold_hack_computer",
		"hack_skylight_barrier", --ggc?
		"timelock_hack",
		"rewire_electric_box",
		"hack_electric_box",
		"hack_ship_control",
		"hold_hack_comp",
		"hack_numpad",
		"big_computer_not_hackable",
		"big_computer_hackable_axis",
		"big_computer_hackable",
		
		-- counterfeit
		"hack_suburbia",
		"hack_suburbia_axis",
		"hack_suburbia_jammed",
		"hack_suburbia_jammed_y",
		"hack_suburbia_jammed_axis",
		"hack_suburbia_outline"
	}
	for _,id in pairs(hack_list) do 
		tweak_interaction(id,"player","pick_lock_easy_speed_multiplier",function(_id,data)
			data.is_hack = true
		end)
	end
	
	
	for _,data in pairs(self) do 
		if type(data) == "table" then
			if data.required_deployable == "ecm_jammer" then
				data.required_deployable = nil
				data.timer = 20
				
				data.icon = "equipment_key_chain"
				-- not used by base game or cd (holdover from pdth), but may be used by other mods
				-- such as "interaction indicator" 
				
				data.requires_upgrade = {
					category = "player",
					upgrade = "can_hack_electronic_locks"
				}
			end
		end
	end
	
	
	
	--these shouldn't be used, since the "interaction" has been turned into a deployable placement
	-- but just in case they are
	self.hostage_convert.required_deployable = "sentry_gun_silent"
	self.hostage_convert.deployable_consume = true
	self.hostage_convert.timer = 3
	self.hostage_convert.interact_distance = 150
	
	self.take_pardons.timer = 0
	self.take_pardons.sound_start = "money_grab"
	self.take_pardons.sound_event = "money_grab"
	self.take_pardons.sound_done = "money_grab"
	self.gage_assignment.timer = 0
	self.gage_assignment.sound_start = "money_grab"
	self.gage_assignment.sound_event = "money_grab"
	self.gage_assignment.sound_done = "money_grab"
	
	
	self.first_aid_kit.upgrade_timer_multipliers = {
		{
			upgrade = "interaction_speed_multiplier",
			category = "first_aid_kit"
		}
	}
	
	self.sentry_gun.upgrade_timer_multipliers = {
		{
			upgrade = "interaction_speed_multiplier",
			category = "sentry_gun"
		}
	}
	self.sentry_gun.text_id = "hud_interact_edit_sentry_gun"
	self.sentry_gun.action_text_id = "hud_action_editing_sentry_gun"
	
	
	--self.sentry_gun_fire_mode.requires_upgrade = nil --remove ap skill requirement for toggling sentry firemode/ammotype
	
	self.sentry_gun_vent_weapon_heat = {
		text_id = "hud_sentry_gun_vent_heat",
		action_text_id = "hud_action_sentry_gun_vent_heat",
		contour = "deployable",
		sound_start = "bar_turret_ammo",
		sound_interupt = "bar_turret_ammo_cancel",
		sound_done = "bar_turret_ammo_finished",
		timer = 2,
		start_active = false,
		no_contour = true
	}
	
	self.armor_plates = {
		icon = "equipment_armor_kit",
		text_id = "debug_interact_armor_plates_take",
		contour = "deployable",
		timer = 3.5,
		blocked_hint = "already_has_armor_plates",
		sound_start = "bar_helpup", --todo change the sound?
		sound_interupt = "bar_helpup_cancel",
		sound_done = "bar_helpup_finished",
		action_text_id = "hud_action_taking_armor_plates",
		upgrade_timer_multipliers = {
			{
				upgrade = "deploy_interact_faster",
				category = "player"
			}
		}
		
	}
	
	self.pick_lock_hard.upgrade_timer_multipliers = { 
		{
			upgrade = "pick_lock_hard_speed_multiplier",
			category = "player"
		}
		--[[
		--normal lockpick speed skills don't apply to safe locks... but they could
		,{
			upgrade = "pick_lock_easy_speed_multiplier",
			category = "player"
		}
		--]]
	}
	
	self.requires_ecm_jammer = {
		icon = "equipment_key_chain",
		contour = "interactable_icon",
		text_id = "hud_int_pick_electronic_lock",
		timer = 20,
		requires_upgrade = {
			upgrade = "can_hack_electronic_locks",
			category = "player"
		},
		action_text_id = "hud_action_picking_electronic_lock",
		sound_start = "bar_keyboard",
		sound_interupt = "bar_keyboard_cancel",
		sound_done = "bar_keyboard_finished",
		is_lockpicking = true
	}
	
	self.trip_mine.requires_upgrade = nil
	self.trip_mine.interact_distance = 2000
	self.shaped_sharge.timer = 1
	
	self.hospital_security_cable.is_snip = true
	self.hospital_security_cable_red.is_snip = true
	self.hospital_security_cable_blue.is_snip = true
	self.hospital_security_cable_green.is_snip = true
	self.hospital_security_cable_yellow.is_snip = true
	self.security_cable_grey.is_snip = true
	self.cut_fence.is_snip = true
	self.hold_cut_cable.is_snip = true
	self.hold_cut_wires.is_snip = true
	self.pex_cut_open_chains.is_snip = true
end)