
local alive_g = alive
local mvec3_cpy = mvector3.copy
local tostring_g = tostring

Drill.EVENT_IDS = {
	melee_restart_success = 3, -- basegame
	autorepair = 1, -- basegame
	melee_restart_client = 2, -- basegame
	shock_trap_proc = 4 --tcd
}

function Drill.get_upgrades(drill_unit, player)
	local is_drill = drill_unit:base() and drill_unit:base().is_drill
	local is_saw = drill_unit:base() and drill_unit:base().is_saw
	local upgrades = nil

	if is_drill or is_saw then
		local player_skill = PlayerSkill
		upgrades = {
			shocktrap_level = player_skill.skill_level("player","drill_shock_trap_zap",0,player),
			auto_repair_level = player_skill.skill_level("player", "drill_auto_repair_guaranteed", 0, player),
			speed_upgrade_level = player_skill.skill_level("player", "drill_speed_multiplier", 0, player),
			silent_drill = player_skill.has_skill("player", "silent_drill", player),
			shocktrap_alert = player_skill.has_skill("player","drill_shock_trap_alert",player)
		}
	end

	return upgrades
end

function Drill.create_upgrades(shocktrap_level, auto_repair_level, speed_upgrade_level, silent_drill, shocktrap_alert)
	return {
		shocktrap_level = shocktrap_level or 0, -- [0-2] Static Defense Basic/Aced
		auto_repair_level = auto_repair_level or 0, -- [0-2] Automatic Reboot
		speed_upgrade_level = speed_upgrade_level or 0, -- [0-2] Investigating IBE
		silent_drill = silent_drill or false, -- [bool] Perfect Alignment silent drill
		shocktrap_alert = shocktrap_alert or false -- [bool] Static Defense alert (intrinsic to basic)
	}
end

Hooks:PostHook(Drill,"init","tcd_drill_init",function(self)
	-- tcd upgrade flags
	self._autorepair_delay = nil
	self._shocktrap_cooldown_t = 0 -- time at which shock trap can trigger again
	self._shocktrap_cooldown_interval = nil
	self._shocktrap_aoe_radius = nil
	self._shocktrap_alert = nil
	self._has_done_guaranteed_autorepair = false
	
	self._has_done_melee_restart = false
end)

Hooks:OverrideFunction(Drill,"set_skill_upgrades",function(self,upgrades)
	if self._disable_upgrades then
		return
	end

	local background_icons = {}
	local timer_gui_ext = self._unit:timer_gui()
	local background_icon_template = {
		texture = "guis/textures/pd2/skilltree/",
		alpha = 1,
		h = 128,
		y = 100,
		w = 128,
		x = 30,
		layer = 2
	}
	local background_icon_x = 30

	local function add_bg_icon_func(bg_icon_table, texture_name, color)
		local icon_data = deep_clone(background_icon_template)
		icon_data.texture = icon_data.texture .. texture_name
		icon_data.color = color
		icon_data.x = background_icon_x

		table.insert(bg_icon_table, icon_data)

		background_icon_x = background_icon_x + icon_data.w + 2
	end

	if self.is_drill or self.is_saw then
		local UPGRADE_COLOR_0 = timer_gui_ext:get_upgrade_icon_color("upgrade_color_0")
		local UPGRADE_COLOR_1 = timer_gui_ext:get_upgrade_icon_color("upgrade_color_1")
		local UPGRADE_COLOR_2 = timer_gui_ext:get_upgrade_icon_color("upgrade_color_2")
		
		local new_shocktrap_level = upgrades.shocktrap_level or 0
		local shocktrap_level = self._skill_upgrades.shocktrap_level or 0
		
		local new_auto_repair_level = upgrades.auto_repair_level or 0
		local auto_repair_level = self._skill_upgrades.auto_repair_level or 0
		
		local new_speed_upgrade_level = upgrades.speed_upgrade_level or 0
		local speed_upgrade_level = self._skill_upgrades.speed_upgrade_level or 0
		
		local new_silent_drill = upgrades.silent_drill or false
		local silent_drill = self._skill_upgrades.silent_drill or false
		
		local new_shocktrap_alert = upgrades.shocktrap_alert or false
		local shocktrap_alert = self._skill_upgrades.shocktrap_alert or false

		if speed_upgrade_level > 0 or new_speed_upgrade_level > 0 then
			if new_speed_upgrade_level > speed_upgrade_level then
				speed_upgrade_level = new_speed_upgrade_level
				upgrades.speed_upgrade_level = speed_upgrade_level

				local timer_multiplier = managers.player:upgrade_value_by_level("player","drill_speed_multiplier",speed_upgrade_level,1)
				timer_gui_ext:set_timer_multiplier(timer_multiplier)
			end
			
			if speed_upgrade_level > 1 then
				add_bg_icon_func(background_icons, "drillgui_icon_faster", UPGRADE_COLOR_2)
			else
				add_bg_icon_func(background_icons, "drillgui_icon_faster", UPGRADE_COLOR_1)
			end
			
		else
			add_bg_icon_func(background_icons, "drillgui_icon_faster", UPGRADE_COLOR_0)
		end
		if silent_drill or new_silent_drill then
			self:set_alert_radius(nil)
			timer_gui_ext:set_skill(BaseInteractionExt.SKILL_IDS.aced)

			upgrades.silent_drill = true

			add_bg_icon_func(background_icons, "drillgui_icon_silent", UPGRADE_COLOR_2)
		else
			self:set_alert_radius(tweak_data.upgrades.drill_alert_radius or 2500)
			timer_gui_ext:set_skill(BaseInteractionExt.SKILL_IDS.none)
			add_bg_icon_func(background_icons, "drillgui_icon_silent", UPGRADE_COLOR_0)
		end
		if auto_repair_level > 0 or new_auto_repair_level > 0 then
			if new_auto_repair_level > auto_repair_level then
				auto_repair_level = new_auto_repair_level
				upgrades.auto_repair_level = auto_repair_level
			end
			self._autorepair_delay = managers.player:upgrade_value_by_level("player","drill_auto_repair_guaranteed",auto_repair_level,false)
			--tweak_data.upgrades.values.player.drill_auto_repair_guaranteed
			
			if auto_repair_level > 1 then
				add_bg_icon_func(background_icons, "drillgui_icon_restarter", UPGRADE_COLOR_2)
			else
				add_bg_icon_func(background_icons, "drillgui_icon_restarter", UPGRADE_COLOR_1)
			end
		else
			self._autorepair_delay = false -- cannot autorepair
			add_bg_icon_func(background_icons, "drillgui_icon_restarter", UPGRADE_COLOR_0)
		end
		if shocktrap_level > 0 or new_shocktrap_level > 0 then
			if new_shocktrap_level > shocktrap_level then
				shocktrap_level = new_shocktrap_level
				upgrades.shocktrap_level = shocktrap_level
				
				local upgrade_data = managers.player:upgrade_value_by_level("player","drill_shock_trap_zap",shocktrap_level,false)
				
				self._shocktrap_cooldown_interval = upgrade_data[1]
				self._shocktrap_aoe_radius = upgrade_data[2]
			end
			
			if shocktrap_level > 1 then
				add_bg_icon_func(background_icons, "drillgui_icon_shocktrap", UPGRADE_COLOR_2)
			else
				add_bg_icon_func(background_icons, "drillgui_icon_shocktrap", UPGRADE_COLOR_1)
			end
		else
			self._shocktrap_cooldown_interval = nil
			self._shocktrap_aoe_radius = nil
			add_bg_icon_func(background_icons, "drillgui_icon_shocktrap", UPGRADE_COLOR_0)
		end
		
		-- no ui element, just the upgrade flag
		if shocktrap_alert or new_shocktrap_alert then
			upgrades.shocktrap_alert = true
			self._shocktrap_alert = true
		end
		
		self._skill_upgrades = table.deep_map_copy(upgrades)
	end
	
	timer_gui_ext:set_background_icons(background_icons)
	timer_gui_ext:update_sound_event()
end)

-- tcd autorepair mechanic
Hooks:OverrideFunction(Drill,"set_jammed",function(self,jammed)
	jammed = jammed and true or false

	if self._jammed == jammed then
		return
	end

	self._jammed = jammed

	if self._jammed then
		self._jammed_count = self._jammed_count + 1

		self:_kill_drill_effect()

		if self._use_effect then
			local params = {
				effect = Idstring("effects/payday2/environment/drill_jammed"),
				parent = self._unit:get_object(Idstring("e_drill_particles"))
			}
			self._jammed_effect = World:effect_manager():spawn(params)
		end
		
		-- TCD autorepair mechanic (guaranteed, but one-time use, and on a fixed delay)
		-- self:_reset_melee_autorepair() -- in tcd, only one melee fix per drill
		if not self._has_done_guaranteed_autorepair then
			if self._autorepair_delay and not self._autorepair_clbk_id then
				self._autorepair_clbk_id = "Drill_autorepair" .. tostring(self._unit:key())

				managers.enemy:add_delayed_clbk(self._autorepair_clbk_id, callback(self, self, "clbk_autorepair"), TimerManager:game():time() + self._autorepair_delay)
			end
		end
		-- end of tcd changes
		
		
	elseif self._jammed_effect then
		self:_kill_jammed_effect()
		self:_start_drill_effect()

		if not self.is_hacking_device and not self.is_saw and not managers.groupai:state():whisper_mode() then
			managers.groupai:state():teammate_comment(nil, "g22", self._unit:position(), true, 500, false)
		end

		if self._autorepair_clbk_id then
			managers.enemy:remove_delayed_clbk(self._autorepair_clbk_id)

			self._autorepair_clbk_id = nil
		end

		if self._bain_report_sabotage_clbk_id then
			managers.enemy:remove_delayed_clbk(self._bain_report_sabotage_clbk_id)

			self._bain_report_sabotage_clbk_id = nil
		end
	end

	self:_change_num_jammed_drills(self._jammed and 1 or -1)

	if Network:is_server() then
		if jammed then
			self:_unregister_sabotage_SO()
		else
			self:_register_sabotage_SO()
		end
	end
end)

Hooks:OverrideFunction(Drill,"clbk_autorepair",function(self)
	self._autorepair_clbk_id = nil

	if alive_g(self._unit) then
		self._has_done_guaranteed_autorepair = true --add flag since this can only happen once
		self._unit:timer_gui():set_jammed(false)
		self._unit:interaction():set_active(false, true)
	end
end)

-- tcd function
function Drill.shock_enemy(unit,from_pos)
	from_pos = from_pos or Vector3()
	
	local mov_ext = unit:movement()
	if mov_ext then
		--log("Shocking",unit)
		local hit_pos = mov_ext:m_com()
		local attack_dir = hit_pos - from_pos:with_z(hit_pos.z)
		attack_dir = attack_dir:normalized()

		local attack_data = {
			damage = 0,
			variant = "melee",
			pos = mvec3_cpy(hit_pos),
			attack_dir = attack_dir,
			result = {
				variant = "melee",
				type = "taser_tased"
			}
		}

		local dmg_ext = unit:character_damage()
		if dmg_ext and dmg_ext._call_listeners then
			dmg_ext._tased_time = tweak_data.upgrades.values.player.drill_shock_tase_time --to be used in huskcopdamage as well

			managers.network:session():send_to_peers_synched("sync_unit_event_id_16", unit, "character_damage", HuskCopDamage._NET_EVENTS.set_drill_shock_tase_time)
			--log("Calling listeners!")
			dmg_ext:_call_listeners(attack_data)
		end
	end
end

Hooks:OverrideFunction(Drill,"on_sabotage_SO_started",function(self,saboteur)
	--asdf = self
	
	local drill_unit = self._unit
	if self._shocktrap_cooldown_interval then
		local objective = saboteur:brain():objective()
		local gametimer = TimerManager:game()
		local t = gametimer:time()
		if self._shocktrap_cooldown_t and self._shocktrap_cooldown_t > t then
			-- still in cooldown, can't trigger shock trap
		else
			-- trigger cooldown
			self._shocktrap_cooldown_t = t + self._shocktrap_cooldown_interval
			
			local static_defense_clbk_id = "static_defense_clbk" .. tostring_g(saboteur:key())
			self._static_defense_clbk_id = static_defense_clbk_id
			
			managers.enemy:add_delayed_clbk(
				static_defense_clbk_id,
				function()
					--log("Sabotime!")
--					fdsa = saboteur
					if not alive_g(drill_unit) or not alive_g(self._saboteur) or not alive_g(saboteur) or self._saboteur:key() ~= saboteur:key() then
						--log("Sabotime exit")
						return
					end
					--log("Sabotime 2")

					local cur_objective = saboteur:brain():objective()

					if cur_objective ~= objective then
						return
					end
					--log("Sabotime 3")
					
					managers.network:session():send_to_peers_synched("sync_unit_event_id_16", drill_unit, "base", Drill.EVENT_IDS.shock_trap_proc)
					
					if self._shocktrap_alert then 
						self:on_shock_trap_alert()
					end
					
					--log("Sabotime 4")

					managers.groupai:state():on_objective_failed(saboteur, objective)
							
					saboteur:brain():action_request({
						type = "idle",
						body_part = 1,
						non_persistent = true
					})
					
					Drill.shock_enemy(saboteur,objective.pos)
					
					--log("Sabotime 5")
					if self._shocktrap_aoe_radius and self._shocktrap_aoe_radius > 0 then
						local nearby_units = World:find_units_quick("sphere", objective.pos, self._shocktrap_aoe_radius, managers.slot:get_mask("enemies"),"ignore_unit",saboteur)
						for _,unit in pairs(nearby_units) do
							Drill.shock_enemy(unit,objective.pos)
						end
					end
					--log("Sabotime end")
					managers.enemy:add_delayed_clbk(remove_icon_clbk_id,function() managers.hud:remove_waypoint(waypoint_id) end,gametimer:time() + tweak_data.upgrades.values.player.drill_shock_tase_time)
				end,
				gametimer:time() + 0.5
			)
			return
		end
	end

	self._saboteur = nil

	drill_unit:timer_gui():set_jammed(true)

	--the voiceline used here only applies to drills, so don't schedule the delayed callback unless the device is indeed a drill
	if self.is_drill and not self._bain_report_sabotage_clbk_id then
		self._bain_report_sabotage_clbk_id = "Drill_bain_report_sabotage" .. tostring_g(drill_unit:key())

		managers.enemy:add_delayed_clbk(self._bain_report_sabotage_clbk_id, callback(self, self, "clbk_bain_report_sabotage"), TimerManager:game():time() + 2 + 4 * math.random())
	end
end)

function Drill:sync_net_event(event_id,peer)
	if event_id == Drill.EVENT_IDS.shock_trap_proc then
		self:on_shock_trap_alert()
	elseif event_id == Drill.EVENT_IDS.autorepair then
		self:on_autorepair()
	elseif event_id == Drill.EVENT_IDS.melee_restart_client then
		self:on_melee_hit(peer:id())
	elseif event_id == Drill.EVENT_IDS.melee_restart_success then
		self:on_melee_hit_success()
	end
end

function Drill:on_shock_trap_alert()
	-- play sound
	self._unit:sound_source():post_event("trip_mine_sensor_alarm")
	
	-- show hud waypoint alert
	if not self._sabotage_align_obj_name then
		return
	end
	
	local drill_unit = self._unit
	local gametimer = TimerManager:game()
	
	local wp_color = Color.yellow
	if self._skill_upgrades.shocktrap_level == 2 then
		wp_color = drill_unit:timer_gui():get_upgrade_icon_color("upgrade_color_2")
	else
		wp_color = drill_unit:timer_gui():get_upgrade_icon_color("upgrade_color_1")
	end

	local align_obj = self._unit:get_object(Idstring(self._sabotage_align_obj_name))
	local objective_pos = align_obj:position()
	
	local str_ukey = tostring(drill_unit:key())
	local remove_icon_clbk_id = "shocktrap_wp_expire_" .. str_ukey
	local waypoint_id = "wp_shocktrap_" .. str_ukey
	managers.hud:add_waypoint(waypoint_id, {
		blend_mode = "add",
		distance = false,
		no_sync = true,
		present_timer = 0,
		state = "sneak_present",
		icon = "wp_shocktrap",
		position = objective_pos,
		color = wp_color
	})
	managers.enemy:add_delayed_clbk(remove_icon_clbk_id,function() managers.hud:remove_waypoint(waypoint_id) end,gametimer:time() + tweak_data.upgrades.values.player.drill_shock_tase_time)
end

function Drill:on_melee_hit(peer_id)
	if self._disable_upgrades or self._has_done_melee_restart or not self._jammed then
		return
	end
	
	self._has_done_melee_restart = true
	self._unit:timer_gui():set_jammed(false)
	local interaction_ext = self._unit:interaction()
	interaction_ext:set_active(false, true)
	interaction_ext:check_for_upgrade()

	if self._kickstarter_success_sequence then
		self._unit:damage():run_sequence_simple(self._kickstarter_success_sequence)
	end
end

-- disabled basegame rng based autorepair mechanic
function Drill:set_autorepair(chance)
end

Hooks:OverrideFunction(Drill,"compare_skill_upgrades",function(self,skill_upgrades)
	if self._disable_upgrades then
		return false
	end
	
	return	(skill_upgrades.shocktrap_level or 0) > (self._skill_upgrades.shocktrap_level or 0)
		or	(skill_upgrades.auto_repair_level or 0) > (self._skill_upgrades.auto_repair_level or 0)
		or	(skill_upgrades.speed_upgrade_level or 0) > (self._skill_upgrades.speed_upgrade_level or 0)
		or	(skill_upgrades.silent_drill and not self._skill_upgrades.silent_drill)
		or	(skill_upgrades.shocktrap_alert and not self._skill_upgrades.shocktrap_alert)
end)

Hooks:PostHook(Drill,"destroy","tcd_drill_destroy",function(self,...)
	local nav_tracker = self._nav_tracker

	if nav_tracker then
		managers.navigation:destroy_nav_tracker(nav_tracker)

		self._nav_tracker = nil
	end

	local static_defense_clbk_id = self._static_defense_clbk_id

	if static_defense_clbk_id then
		managers.enemy:remove_delayed_clbk(static_defense_clbk_id)

		self._static_defense_clbk_id = nil
	end
end)