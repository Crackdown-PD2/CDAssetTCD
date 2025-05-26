
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
	
	
end)











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


