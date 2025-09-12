
local mvec3_dis = mvector3.distance
local mvec3_dis_sq = mvector3_distance_sq
local mvec3_copy = mvector3.copy
local pairs_g = pairs
local alive_g = alive
local world_g = World

Hooks:PostHook(PlayerManager,"check_skills","tcd_playermanager_checkskills",function(self)
	
	-- Point and Click related skill checks
	do
		if self:has_category_upgrade("player","point_and_click_stacks") then 
			self:set_property("current_point_and_click_stacks",0)
			self:set_property("point_and_click_deadshot_kills",0) -- kills without missing
			
			-- visually update stacks
			managers.tcdbuff:add_listener("pointclick_stacks_changed","upd_pointclick_stacks",function(prev_stacks,new_stacks)
				local hudbuff = managers.hud._hud_tcdbuff
				if prev_stacks ~= new_stacks then
					if new_stacks == 0 then
						hudbuff:remove_buff("pointclick")
					else
						if not hudbuff:has_buff("pointclick") then
							hudbuff:add_buff("pointclick",new_stacks)
						end
						
						--hudbuff:set_tag_text(string.format("%i",new_stacks))
						
						hudbuff:set_label_text("pointclick",string.format("%i",new_stacks))
					end
				end
			end)
			
			
			-- Potential Exponential Aced miss detection
			local has_potential_exponential = self:has_category_upgrade("player", "point_and_click_deadshot_mul")
			if has_potential_exponential then
				self._message_system:register(Message.OnWeaponFired, "point_and_click_on_miss",
					function(weapon_unit, result)
						if result and result.hit_enemy then
							return
						end
						local player = self:local_player()
						if not alive(player) then 
							return
						end
						local weapon_base = weapon_unit and weapon_unit:base()
						if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
							if weapon_base._setup.user_unit ~= player then 
								return
							end
						else
							return
						end
						
						self:set_property("point_and_click_deadshot_kills", 0)
					end
				)
			end
			
			-- Point and Click basic - add 1 stack
			local amount = self:upgrade_value("player","point_and_click_stacks",0) -- base stack gain per kill
			self._message_system:register(Message.OnEnemyKilled, "point_and_click_stack_on_kill",
				function(weapon_unit, variant, killed_unit)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					
					local add_amount = amount
					if has_potential_exponential then
						-- add kill count to stack bonus
						add_amount = add_amount + self:get_property("point_and_click_deadshot_kills",0)
						
						--increment kill counter afterward
						self:add_to_property("point_and_click_deadshot_kills",1)
					end
					
					-- grant point+click stacks
					
					local prev_stacks = self:get_property("current_point_and_click_stacks",0)
					self:add_to_property("current_point_and_click_stacks",add_amount)
					managers.tcdbuff:call_listeners("pointclick_stacks_changed",prev_stacks,self:get_property("current_point_and_click_stacks",0))
				end
			)
		else
			self._message_system:unregister(Message.OnEnemyShot,"point_and_click_stack_on_kill")
			managers.tcdbuff:remove_listener("pointclick_stacks_changed","upd_pointclick_stacks")
		end
		
		-- Investment Returns basic (headshots grant 1 additional pointclick stack)
		if self:has_category_upgrade("player", "point_and_click_stack_from_headshot_kill") then
			local pointclick_headshot_bonus_stacks = self:upgrade_value("player","point_and_click_stack_from_headshot_kill",0)
			self._message_system:register(Message.OnLethalHeadShot, "pointclick_onheadshotkill",
				-- must be a separate message hook since OnEnemyKilled can't check for headshots
				-- unfortunately that causes an issue where the killcount label appears to flicker for one frame, since it's updated twice in a single frame
				function(attack_data)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = attack_data and attack_data.weapon_unit and attack_data.weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					
					local prev_stacks = self:get_property("current_point_and_click_stacks",0)
					self:add_to_property("current_point_and_click_stacks",pointclick_headshot_bonus_stacks)
					managers.tcdbuff:call_listeners("pointclick_stacks_changed",prev_stacks,self:get_property("current_point_and_click_stacks",0))
				end
			)
		else
			self._message_system:unregister(Message.OnLethalHeadShot,"pointclick_onheadshotkill")
		end
		
	end
	
	-- Shot Grouping
	if self:has_category_upgrade("class_rapidfire","critical_hit_chance_on_headshot") then 
		local skill_data = self:upgrade_value("class_rapidfire","critical_hit_chance_on_headshot")
	
		local duration = skill_data[2]
		local max_stacks = skill_data[3]
		
		self._message_system:register(Message.OnHeadShot,"proc_shotgrouping_aced",
			function()
				local player = self:local_player()
				if not alive(player) then 
					return
				end
				local weapon = player:inventory():equipped_unit():base()
				if not weapon:is_weapon_class("class_rapidfire") then 
					return
				end
				
				local stacks = math.min(self:get_temporary_property("shotgrouping_aced_stacks",0) + 1,max_stacks)
				self:activate_temporary_property("shotgrouping_aced_stacks",duration,stacks)
			end
		)
	else
		self._message_system:unregister(Message.OnHeadShot,"proc_shotgrouping_aced")
	end
	
	-- Lead Farmer
	if self:has_category_upgrade("class_heavy","lead_farmer_basic") then 
		local upgrade_data = self:upgrade_value("class_heavy","lead_farmer_basic")
		self._leadfarmer_alh_percent = upgrade_data[1]
		self._leadfarmer_alh_interval = upgrade_data[2]
		self._leadfarmer_alh_timer = 0
	else
		self._leadfarmer_alh_percent = nil
		self._leadfarmer_alh_interval = nil
		self._leadfarmer_alh_timer = nil
	end
	
	-- Death Grips
	if self:has_category_upgrade("class_heavy","death_grips_stacks") then
		local death_grips_data = self:upgrade_value("class_heavy","death_grips_stacks",{0,0})
		local death_grips_stack_reset_timer = death_grips_data[1]
		local death_grips_max_stacks = death_grips_data[2]
		
		managers.tcdbuff:add_listener("deathgrips_stacks_changed","on_deathgrips_stacks_changed",function(prev_stacks,new_stacks)
			-- temporary values have their own timer so just check it every frame
			managers.tcdbuff:add_updater("upd_deathgrips_stacks",function(t,dt)
				local hudbuff = managers.hud._hud_tcdbuff
				
				if not hudbuff:has_buff("deathgrips") then
					hudbuff:add_buff("deathgrips")
				end
				
				-- this check is actually technically destructive, temp property timers aren't checked until observed by a caller
				if self._temporary_properties:has_active_property("current_death_grips_stacks") then
					local property = self._temporary_properties._properties.current_death_grips_stacks
					local rem = property[2] - Application:time()
					local value = property[1]
					
					--hudbuff:set_tag_text("deathgrips",string.format("%i",new_stacks))
					hudbuff:set_label_text("deathgrips",string.format("%i",value))
					hudbuff:set_progress("deathgrips",rem,death_grips_stack_reset_timer)
				else
					hudbuff:remove_buff("deathgrips")
					managers.tcdbuff:remove_updater("upd_deathgrips_stacks")
				end
				
				
			end)
		end)
		
		self._message_system:register(Message.OnEnemyKilled,"proc_death_grips",
			function(weapon_unit,variant,killed_unit)
				local player = self:local_player()
				if not alive(player) then 
					return
				end
				local weapon_base = alive(weapon_unit) and weapon_unit:base()
				if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_heavy") then 
					if weapon_base._setup.user_unit ~= player then 
						return
					end
				else
					return
				end
				
				local prev_stacks = self:get_temporary_property("current_death_grips_stacks",0)
				local death_grips_stacks = math.min(prev_stacks + 1,death_grips_max_stacks)
				self:activate_temporary_property("current_death_grips_stacks",death_grips_stack_reset_timer,death_grips_stacks)
				
				managers.tcdbuff:call_listeners("deathgrips_stacks_changed",prev_stacks,death_grips_stacks)
			end
		)
	else
		self._message_system:unregister(Message.OnEnemyKilled,"proc_death_grips")
		managers.tcdbuff:remove_listener("deathgrips_stacks_changed","on_deathgrips_stacks_changed")
		managers.tcdbuff:remove_updater("upd_deathgrips_stacks")
	end
	
	-- Collateral Damage
	if self:has_category_upgrade("class_heavy","collateral_damage") then 
		local slot_mask = managers.slot:get_mask("enemies")
		
		local collateral_damage_data = self:upgrade_value("class_heavy","collateral_damage",{0,0})
		local damage_mul = collateral_damage_data[1]
		local radius = collateral_damage_data[2]
		
		self._message_system:register(Message.OnWeaponFired,"proc_collateral_damage",
			function(weapon_unit,result)
				local player = self:local_player()
				if not alive(player) then 
					return
				end
				local weapon_base = weapon_unit and weapon_unit:base()
				if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_heavy") then 
					if weapon_base._setup.user_unit ~= player then 
						return
					end
				else
					return
				end
				if #result.rays == 0 then 
					return
				end
				
				local first_ray = result.rays[1] 
				local from = player:movement():current_state():get_fire_weapon_position()
				--sort of cheating here by assuming the origin of the ray is the current fire position
				local dir = mvec3_copy(first_ray.ray)
				local to
				local hits = {}
				for n,ray in ipairs(result.rays) do 
					local damage = weapon_base:_get_current_damage()
					local dir = ray.ray or Vector3()
					if ray.damage_result then 
						local attack_data = ray.damage_result.attack_data or {}
						damage = attack_data and attack_data.damage_raw or damage
					end
					damage = damage * damage_mul
					if ray.unit then
						hits[ray.unit:key()] = {
							disabled = true
						}
					end
					to = mvec3_copy(ray.hit_position or ray.position or Vector3())
--						Draw:brush(Color.red:with_alpha(0.1),5):sphere(from,50)
--						Draw:brush(Color.blue:with_alpha(0.1),5):sphere(to,50)
--						Draw:brush(Color(1,n / #result.rays,1):with_alpha(0.1),5):cylinder(from,to,radius)
					local grazed_enemies = world_g:raycast_all("ray", from, to, "sphere_cast_radius", radius, "disable_inner_ray", "slot_mask", slot_mask)
					for _,hit in pairs(grazed_enemies) do 
						local hit_data = hits[hit.unit:key()]
						local add_hit = not (hit_data and hit_data.disabled)
						if add_hit and hit_data and hit_data.damage < damage then 
							add_hit = false
						end
						if add_hit and hit.unit then 
							hits[hit.unit:key()] = {
								unit = hit.unit,
								damage = damage,
								attacker_unit = player,
								pos = mvec3_copy(to),
								attack_dir = mvec3_copy(dir)
							}
						end
						--collect hits here to prevent the same enemy from being hit by multiple rays, in the case of penetrating or ricochet shots
					end
					
					from = mvec3_copy(to)
				end

				
				for _,hit_data in pairs(hits) do 
					if not hit_data.disabled then 
						local enemy = hit_data.unit
						if enemy and enemy.character_damage and enemy:character_damage() then 
							enemy:character_damage():damage_simple({
								variant = "graze",
								damage = hit_data.damage,
								attacker_unit = hit_data.attacker_unit,
								pos = hit_data.pos,
								attack_dir = hit_data.attack_dir
							})
						end
					end
				end
				
			end
		)
	else
		self._message_system:unregister(Message.OnWeaponFired,"proc_collateral_damage")
	end
	
	-- Shuffle and Cut (buff checker only)
	do
		if self:has_category_upgrade("class_melee","melee_boosts_throwing_loop") then
			managers.tcdbuff:add_listener("shufflecut_throwing_stacks_changed","on_shufflecut_throwing_stacks_changed",function(prev_stacks,new_stacks)
				local hudbuff = managers.hud._hud_tcdbuff
				if prev_stacks ~= new_stacks then
					if new_stacks == 0 then
						hudbuff:remove_buff("shufflecut_throwing")
					else
						if not hudbuff:has_buff("shufflecut_throwing") then
							hudbuff:add_buff("shufflecut_throwing",new_stacks)
						end
						hudbuff:set_label_text("shufflecut_throwing",string.format("x%i",new_stacks))
					end
				end
			end)
		else
			managers.tcdbuff:remove_listener("shufflecut_throwing_stacks_changed","on_shufflecut_throwing_stacks_changed")
		end	
		
		if self:has_category_upgrade("class_throwing","throwing_boosts_melee_loop") then
			managers.tcdbuff:add_listener("shufflecut_melee_stacks_changed","on_shufflecut_melee_stacks_changed",function(prev_stacks,new_stacks)
				local hudbuff = managers.hud._hud_tcdbuff
				if prev_stacks ~= new_stacks then
					if new_stacks == 0 then
						hudbuff:remove_buff("shufflecut_melee")
					else
						if not hudbuff:has_buff("shufflecut_melee") then
							hudbuff:add_buff("shufflecut_melee",new_stacks)
						end
						hudbuff:set_label_text("shufflecut_melee",string.format("x%i",new_stacks))
					end
				end
			end)
		else
			managers.tcdbuff:remove_listener("shufflecut_melee_stacks_changed","on_shufflecut_melee_stacks_changed")
		end
	end
	
	-- Rolling Cutter (buff checker only)
	if self:has_category_upgrade("saw","consecutive_damage_bonus") then
		local upgrade_data = self:upgrade_value("saw","consecutive_damage_bonus")
		local max_stacks = upgrade_data[2]
		
		managers.tcdbuff:add_listener("rollingcutter_stacks_changed","on_rollingcutter_stacks_changed",function(prev_stacks,new_stacks)
			local hudbuff = managers.hud._hud_tcdbuff
			if prev_stacks ~= new_stacks then
				if new_stacks == 0 then
					hudbuff:remove_buff("rollingcutter")
				else
					if not hudbuff:has_buff("rollingcutter") then
						hudbuff:add_buff("rollingcutter",new_stacks)
					end
					if new_stacks >= max_stacks then
						hudbuff:set_label_color("rollingcutter",Color.yellow)
					end
					hudbuff:set_label_text("rollingcutter",string.format("x%i",new_stacks))
				end
			end
		end)
	else
		managers.tcdbuff:remove_listener("rollingcutter_stacks_changed","on_rollingcutter_stacks_changed")
	end
	
	if self:has_category_upgrade("player","bungielungie") then
		self:remove_temporary_property("runner_bungielungie_cooldown")
		self:register_message(Message.OnEnemyKilled, "runner_float_butterfly_meleekill_refund", function(weapon_unit, variant, killed_unit)
			if variant == "melee" then
				-- on melee kill, remove cooldown for "float like a butterfly" melee lunge
				self:remove_temporary_property("runner_bungielungie_cooldown")
			end
		end)
	else
		self:remove_temporary_property("runner_bungielungie_cooldown")
		self._message_system:unregister(Message.OnEnemyKilled,"runner_float_butterfly_meleekill_refund")
	end
	
end)

Hooks:PostHook(PlayerManager,"update","tcd_playermanager_update",function(self,t,dt)
	
	managers.tcdbuff:update(t,dt)
	
	local player = self:local_player()
	if player then
		local current_state = self:get_current_state()
		local inventory_ext = player:inventory()
		if inventory_ext then
			if self._leadfarmer_alh_timer then
				self._leadfarmer_alh_timer = self._leadfarmer_alh_timer - dt
				if self._leadfarmer_alh_timer < 0 then
					self._leadfarmer_alh_timer = self._leadfarmer_alh_timer + self._leadfarmer_alh_interval
					local current_equipped_selection = inventory_ext._equipped_selection
					local can_reload_from_bipod = current_state == "bipod" and self:has_category_upgrade("class_heavy", "lead_farmer_aced")
					
					local available_selections = inventory_ext:available_selections()
					local done_reload
					for selection_index, selection_data in pairs(available_selections) do
						if selection_index ~= current_equipped_selection or can_reload_from_bipod then
							local weapon_base = selection_data.unit and selection_data.unit:base()
							if weapon_base and weapon_base:is_weapon_class("class_heavy") then
								local ammo_total = weapon_base:get_ammo_total()
								local ammo_in_clip = weapon_base:get_ammo_remaining_in_clip()
								if ammo_total > ammo_in_clip then
									local ammo_max_per_clip = weapon_base:get_ammo_max_per_clip()
									if ammo_in_clip < ammo_max_per_clip then
										local add_ammo = math.floor(self._leadfarmer_alh_percent * ammo_max_per_clip)
										local new_amount = math.min(math.min(ammo_max_per_clip, ammo_in_clip + add_ammo), ammo_total)
										weapon_base:set_ammo_remaining_in_clip(new_amount)
										done_reload = true
									end
								
								end
							end
						end
					end
					if done_reload then
						for id, weapon in pairs(available_selections) do
							local weapon_base = weapon.unit:base()
							managers.hud:set_ammo_amount(id, weapon_base:ammo_info())
						end
					end
				end
			end
		end
	end
	
	
end)


function PlayerManager:_deduct_local_cocaine_stacks()
	-- todo!
end


function PlayerManager:consume_damage_overshield(damage)
	-- todo!
	return damage
end







--function written for cd, not vanilla
function PlayerManager:team_upgrade_value_by_level(category, upgrade, level, default)
	local cat = tweak_data.upgrades.values.team[category]
	local upg = cat and cat[upgrade]
	return upg and upg[level] or default
end

--function written for cd, not vanilla
--- returns upgrade level of the given team upgrade 
function PlayerManager:team_upgrade_level(category, upgrade, default)
	for peer_id, categories in pairs(self._global.synced_team_upgrades) do
		if categories[category] and categories[category][upgrade] then
			return categories[category][upgrade]
		end
	end

	if not self._global.team_upgrades[category] then
		return default or 0
	end

	if not self._global.team_upgrades[category][upgrade] then
		return default or 0
	end

	return self._global.team_upgrades[category][upgrade]
end

Hooks:OverrideFunction(PlayerManager,"damage_reduction_skill_multiplier",function(self,damage_type)
	local multiplier = 1
	multiplier = multiplier * self:temporary_upgrade_value("temporary", "dmg_dampener_outnumbered", 1)
	multiplier = multiplier * self:temporary_upgrade_value("temporary", "dmg_dampener_outnumbered_strong", 1)
	multiplier = multiplier * self:temporary_upgrade_value("temporary", "dmg_dampener_close_contact", 1)
	multiplier = multiplier * self:temporary_upgrade_value("temporary", "revived_damage_resist", 1)
	multiplier = multiplier * self:upgrade_value("player", "damage_dampener", 1)
	multiplier = multiplier * self:upgrade_value("player", "health_damage_reduction", 1)
	multiplier = multiplier * self:temporary_upgrade_value("temporary", "first_aid_damage_reduction", 1)
	multiplier = multiplier * self:temporary_upgrade_value("temporary", "revive_damage_reduction", 1)
	multiplier = multiplier * self:get_hostage_bonus_multiplier("damage_dampener")
	multiplier = multiplier * self._properties:get_property("revive_damage_reduction", 1)
	multiplier = multiplier * self._temporary_properties:get_property("revived_damage_reduction", 1)
	local dmg_red_mul = self:team_upgrade_value("damage_dampener", "team_damage_reduction", 1)
	
	-- general vars for tcd since many of them are playerstate dependent
	local player = self:local_player()
	local is_alive = alive_g(player)
	
	--damage resist for being near a civilian with the Stay Down basic skill
	if is_alive and self:team_upgrade_level("player","civilian_hostage_aoe_damage_resistance") > 0 then 
		local player_pos = player:movement():m_pos()
		local upgrade_data = self:team_upgrade_value("player","civilian_hostage_aoe_damage_resistance")
		
		local range = upgrade_data[1]
		local civ_near_dmg_resist_bonus = upgrade_data[2]
		
		if CivilianBase.get_nearby_civ(player_pos,range,true) then
			multiplier = multiplier * civ_near_dmg_resist_bonus
		end
	end
	--
	
	if self:has_category_upgrade("player", "passive_damage_reduction") then
		local health_ratio = self:player_unit():character_damage():health_ratio()
		local min_ratio = self:upgrade_value("player", "passive_damage_reduction")

		if health_ratio < min_ratio then
			dmg_red_mul = dmg_red_mul - (1 - dmg_red_mul)
		end
	end

	multiplier = multiplier * dmg_red_mul

	if damage_type == "melee" then
		multiplier = multiplier * managers.player:upgrade_value("player", "melee_damage_dampener", 1)
	end

	local current_state = self:get_current_state()

	if current_state and current_state:_interacting() then
		multiplier = multiplier * managers.player:upgrade_value("player", "interacting_damage_multiplier", 1)
	end

	return multiplier
end)


