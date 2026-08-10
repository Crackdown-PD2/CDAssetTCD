local mvec3_norm = mvector3.normalize
local mvec3_set = mvector3.set
local mvec3_sz = mvector3.set_z
local mvec3_sub = mvector3.subtract
local mvec3_cross = mvector3.cross
local mvec3_norm = mvector3.normalize
local mvec3_set_static = mvector3.set_static
local mvec3_mul = mvector3.multiply
local tmp_vec1 = Vector3()
local tmp_vec2 = Vector3()
local tmp_vec3 = Vector3()
local bezier3 = require("lib/utils/Bezier3")

PlayerDamage._UPPERS_COOLDOWN = 0 -- no cooldown, go hog wild

Hooks:PostHook(PlayerDamage,"init","tcd_playerdmg_init",function(self)
	self._lives_max = 0 -- tcd var
	self._medic_hot_aura_t = 0 -- cooldown timer counter value for medic's docbag healing aura
	--self._docbag_tether_obj = nil -- visual only
	
	self:recalculate_max_revives()
end)


function PlayerDamage._draw_bezier(brush, source, target, tangent)
	local line_segments = {}
	local v = target - source

	mvec3_sz(v, 0)

	local xmax = mvec3_norm(v)
	local p = source + tangent * xmax / 2
	local x1 = 0
	local y1 = source.z
	local x2 = xmax / 2
	local y2 = p.z
	local x3 = xmax / 2
	local y3 = p.z
	local x4 = xmax
	local y4 = target.z
	local angle_tolerance = 0
	local cusp_limit = 0
	local scale = 1

	table.insert(line_segments, {
		0,
		source.z
	})
	bezier3.interpolate(function (s, x, y)
		table.insert(line_segments, {
			x,
			y
		})
	end, x1, y1, x2, y2, x3, y3, x4, y4, scale, angle_tolerance, cusp_limit)

	local n = #line_segments

	for i = 1, n - 1 do
		local p1 = source + v * line_segments[i][1]

		mvec3_sz(p1, line_segments[i][2])

		local p2 = source + v * line_segments[i + 1][1]

		mvec3_sz(p2, line_segments[i + 1][2])
		brush:cylinder(p1, p2, 0.5)

		line_segments[i] = nil
	end
end

-- Medic's Doctor's Orders (doctor bag healing over time radius)
Hooks:PostHook(PlayerDamage,"_upd_health_regen","tcd_playerdmg_update_health_regen",function(self,t,dt)
	-- check for nearby docbags
	
	local pm = managers.player
		
	local bag,docbag_level,bag_distance = DoctorBagBase.get_best_hot(self._unit:movement():m_pos())
	self._docbag_tether_obj = bag
	if self._medic_hot_aura_t > 0 then
		-- on cooldown
		self._medic_hot_aura_t = self._medic_hot_aura_t - dt
	else
		local hot_missing = 0
		local hot_maximum = managers.player:get_temporary_property("max_health_hot",0)
		local heal_amount = 0 -- total
		
		-- Doctor's Orders (i totally overengineered this)
	
		-- use a variable instead of a cooldown property
		-- so that healing can be properly calculated in case of performance loss,
		-- even if frame loss spans over multiple ticks
		
		--[[
		if bag:
			- reset linger
			- draw tether
		else:
			- calc linger
		
		- add other sources of hot
		--]]
		
		local heal_aura_level,heal_aura_upgrade_data
		if bag then
			docbag_level = bag._healaura_upgrade_level
			local upgrade_data = pm:upgrade_value_by_level("doctor_bag","heal_aura",docbag_level,nil)
			if upgrade_data and upgrade_data ~= 0 and upgrade_data.linger_duration then
				-- set/extend linger duration
				pm:activate_temporary_property("medic_hot_aura_linger",upgrade_data.linger_duration,docbag_level)
				
				-- use this heal aura level
				heal_aura_level = docbag_level
				heal_aura_upgrade_data = upgrade_data
			end
			--[[
			local dir_to_bag = tmp_vec1
			mvec3_set(dir_to_bag,bag._hot_draw_pos)
			local player_pos = tmp_vec2
			mvec3_set(player_pos,self._unit:position()) --self._unit:oobb():center())
			mvec3_sub(dir_to_bag,player_pos)
			
			local bt = math.sin(t * math.pi * 3) * 10
			local tangent = tmp_vec3
			mvec3_cross(tangent,dir_to_bag,math.UP * bt)
			
			self._draw_bezier(bag._hot_brush,bag._unit:position(),player_pos,tangent)
			bag._hot_brush:sphere(player_pos,1,2)
			--]]
			self._docbag_tether_obj = bag
		end
		
		if docbag_level and heal_aura_level and docbag_level < heal_aura_level then
			heal_aura_upgrade_data = pm:upgrade_value_by_level("doctor_bag","heal_aura",heal_aura_level,nil)
		else
			heal_aura_level = pm:get_temporary_property("medic_hot_aura_linger",0)
			if heal_aura_level > 0 then
				heal_aura_upgrade_data = pm:upgrade_value_by_level("doctor_bag","heal_aura",heal_aura_level,nil)
			end
		end
		
		if heal_aura_upgrade_data then
			if heal_aura_upgrade_data.hot_mis_value then
				-- 1% of missing health
				
				-- due to how this frame loss compensation works,
				-- it's actually better healing if you drop excessive frames during the heal period
				hot_missing = hot_missing + heal_aura_upgrade_data.hot_mis_value
			end
			
			if heal_aura_upgrade_data.hot_max_value then
				-- 1% of maximum health
				hot_maximum = hot_maximum + heal_aura_upgrade_data.hot_max_value
			end
		end
		
		if hot_missing > 0 then
			local health_missing = 1 - self:health_ratio()
			heal_amount = heal_amount + (health_missing * hot_missing)
		end
		if hot_maximum > 0 then
			local health_max = self:_max_health()
			heal_amount = heal_amount + (health_max * hot_maximum)
		end
		
		if heal_amount > 0 then
			self:restore_health(heal_amount,true,true)
			
			-- reset cooldown on heal tick
			self._medic_hot_aura_t = self._medic_hot_aura_t + 1
		end
		
	end
	
	-- todo feed status info to buffmanager
	-- visual tether for docbag heal aoe
	if self._docbag_tether_obj then
		local tether_bag = self._docbag_tether_obj
		local dir_to_bag = tmp_vec1
		mvec3_set(dir_to_bag,tether_bag._hot_draw_pos)
		local player_pos = tmp_vec2
		mvec3_set(player_pos,self._unit:position()) --self._unit:oobb():center())
		mvec3_sub(dir_to_bag,player_pos)
		
		local bt = math.sin(t * math.pi * 3) * 10
		local tangent = tmp_vec3
		mvec3_cross(tangent,dir_to_bag,math.UP * bt)
		
		self._draw_bezier(tether_bag._hot_brush,tether_bag._unit:position(),player_pos,tangent)
		tether_bag._hot_brush:sphere(player_pos,1,2)
	end
	
end)

function PlayerDamage:damage_melee(attack_data)
	if not self:_chk_can_take_dmg() then
		return
	end

	local pm = managers.player
	local can_counter_strike = pm:has_category_upgrade("player", "counter_strike_melee")

	if can_counter_strike and self._unit:movement():current_state().in_melee and self._unit:movement():current_state():in_melee() then
		if attack_data.attacker_unit and alive(attack_data.attacker_unit) and attack_data.attacker_unit:base() then
			local comeback_strike = pm:has_category_upgrade("player", "infiltrator_comeback_strike")
			local is_dozer = not comeback_strike and attack_data.attacker_unit:base().has_tag and attack_data.attacker_unit:base():has_tag("tank")

			--prevent the player from countering Dozers or other players through FF, for obvious reasons
			if not attack_data.attacker_unit:base().is_husk_player and not is_dozer then
			
				if comeback_strike then
					local ray = self._unit:raycast("ray", self._unit:movement():m_head_pos(), attack_data.attacker_unit:movement():m_head_pos(), "slot_mask", managers.slot:get_mask("bullet_impact_targets"), "sphere_cast_radius", 20, "ray_type", "body melee")
					
					self._unit:movement():current_state():_do_melee_damage(pm:player_timer():time(), nil, ray, nil, nil, true)
				end	
				
				self._unit:movement():current_state():discharge_melee()

				return "countered"
			end
		end
	end

	local damage_info = {
		result = {
			variant = "melee",
			type = "hurt"
		},
		attacker_unit = attack_data.attacker_unit
	}

	if self:is_friendly_fire(attack_data.attacker_unit) then
		return
	elseif self._bleed_out and managers.player:has_category_upgrade("player", "hitman_bleedout_invuln") then
		return
	elseif self._god_mode then
		if attack_data.damage > 0 then
			self:_send_damage_drama(attack_data, attack_data.damage)
		end

		self:_call_listeners(damage_info)

		return
	elseif self._invulnerable or self._mission_damage_blockers.invulnerable then
		self:_call_listeners(damage_info)

		return
	elseif self:incapacitated() then
		return
	elseif self._unit:movement():current_state().immortal then
		return
	elseif self:_chk_dmg_too_soon(attack_data.damage) then
		return
	end

	self:_hit_direction(attack_data.attacker_unit:position())

	self._last_received_dmg = attack_data.damage
	self._next_allowed_dmg_t = Application:digest_value(pm:player_timer():time() + self._dmg_interval, true)
	
	if pm:has_category_upgrade("player", "wcard_thorns") then
		self:do_thorns(attack_data.damage)
	end
	
	local allow_melee_dodge = self._next_melee_dodge_t and self._next_melee_dodge_t < pm:player_timer():time() --manual toggle, to be later replaced with a Rogue melee dodge perk check

	if allow_melee_dodge and pm:current_state() ~= "bleed_out" and pm:current_state() ~= "bipod" and pm:current_state() ~= "tased" then --self._bleed_out and current_state() ~= "bleed_out" aren't the same thing
		self._unit:movement():push(attack_data.push_vel * 0.25)
		self._unit:camera():play_shaker("melee_hit", 0.1)
			
		self._unit:sound():play("clk_baton_swing", nil, false)
		self._unit:sound():play("clk_baton_swing", nil, false)
		
		self._next_melee_dodge_t = pm:player_timer():time() + 10
		pm:send_message(Message.OnPlayerDodge)

		return
	end
	
	if not pm:has_category_upgrade("player", "sociopath_mode") then
		local dmg_mul = pm:damage_reduction_skill_multiplier("melee") --the vanilla function has this line, but it also uses bullet damage reduction skills due to it redirecting to damage_bullet to get results
		attack_data.damage = attack_data.damage * dmg_mul
		attack_data.damage = pm:modify_value("damage_taken", attack_data.damage, attack_data) --apply damage resistances before checking for bleedout and other things

		local damage_absorption = pm:damage_absorption()

		if damage_absorption > 0 then
			attack_data.damage = math.max(0, attack_data.damage - damage_absorption)
		end
	else
		attack_data.damage = 1
	end
	
	pm:_deduct_local_cocaine_stacks()
	
	attack_data.damage = pm:consume_damage_overshield(attack_data.damage)

	if attack_data.tase_player then
		if pm:current_state() == "standard" or pm:current_state() == "carry" or pm:current_state() == "bipod" then
			if pm:current_state() == "bipod" then
				self._unit:movement()._current_state:exit(nil, "tased")
			end

			self._unit:movement():on_non_lethal_electrocution()
			pm:set_player_state("tased")

			--no pushing and camera shaking for melee tase attacks
		end
	else
		if pm:current_state() == "bipod" then
			self._unit:movement()._current_state:exit(nil, "standard")
			pm:set_player_state("standard")
		end

		local vars = {
			"melee_hit",
			"melee_hit_var2"
		}

		self._unit:camera():play_shaker(vars[math.random(#vars)], 0.5)

		--no pushing when in bleedout, looks silly in third-person
		if pm:current_state() ~= "bleed_out" then
			self._unit:movement():push(attack_data.push_vel)
		end
	end

	if self._bleed_out then
		self:_bleed_out_damage(attack_data)

		--bleed_out = always taking health damage, so use the appropiate sound and cause a blood effect if the weapon isn't tase capable
		local hit_sound = "hit_body"

		--unless damage is completely negated
		if attack_data.damage == 0 then
			hit_sound = "hit_gen"
		end

		self:play_melee_hit_sound_and_effects(attack_data, hit_sound, not attack_data.tase_player)

		return
	end
	
	self:_check_chico_heal(attack_data)

	local go_through_armor = false --manual toggle
	local health_subtracted = nil
	local armor_broken = false

	if go_through_armor then
		health_subtracted = self:_calc_armor_damage(attack_data)

		attack_data.damage = attack_data.damage - health_subtracted

		health_subtracted = health_subtracted + self:_calc_health_damage(attack_data)

		armor_broken = self:_max_armor() == 0 or self:_max_armor() > 0 and self:get_real_armor() <= 0 --works when armor is broken and health damage is taken by the same hit
	else
		local armor_reduction_multiplier = 0

		if self:get_real_armor() <= 0 then --if armor is already broken, don't negate health damage
			armor_reduction_multiplier = 1
			armor_broken = true --checked before actually taking damage
		end

		health_subtracted = self:_calc_armor_damage(attack_data)

		if attack_data.melee_armor_piercing then --for specific cases, like say, making headless Dozers able to go through armor with melee when other enemies can't
			attack_data.damage = attack_data.damage - health_subtracted
		else
			attack_data.damage = attack_data.damage * armor_reduction_multiplier
		end

		health_subtracted = health_subtracted + self:_calc_health_damage(attack_data)
	end

	local hit_sound_type = "hit_gen"
	local blood_effect = false

	if armor_broken then
		hit_sound_type = "hit_body"
		blood_effect = not attack_data.tase_player
	end

	self:play_melee_hit_sound_and_effects(attack_data, hit_sound_type, blood_effect)

	if not self._bleed_out then
		if health_subtracted > 0 then
			self:_send_damage_drama(attack_data, health_subtracted)
		end
	else
		local attacker = attack_data.attacker_unit

		if attacker:character_damage() and attacker:character_damage().dead and not attacker:character_damage():dead() then
			if attacker:base().has_tag then
				if attacker:base():has_tag("tank") then
					self._kill_taunt_clbk_id = "kill_taunt" .. tostring(self._unit:key())
					managers.enemy:add_delayed_clbk(self._kill_taunt_clbk_id, callback(self, self, "clbk_kill_taunt", attack_data), TimerManager:game():time() + 0.5)
				elseif attacker:base():has_tag("taser") then
					self._kill_taunt_clbk_id = "kill_taunt" .. tostring(self._unit:key())
					managers.enemy:add_delayed_clbk(self._kill_taunt_clbk_id, callback(self, self, "clbk_kill_taunt_tase", attack_data), TimerManager:game():time() + 0.5)
				elseif attacker:base():has_tag("law") and not attacker:base():has_tag("special") then
					self._kill_taunt_clbk_id = "kill_taunt" .. tostring(self._unit:key())
					managers.enemy:add_delayed_clbk(self._kill_taunt_clbk_id, callback(self, self, "clbk_kill_taunt_common", attack_data), TimerManager:game():time() + 0.5)
				end
			end
		end
	end

	pm:send_message(Message.OnPlayerDamage, nil, attack_data)
	self:_call_listeners(damage_info)

	return
end

function PlayerDamage:damage_bullet(attack_data)
	if not self:_chk_can_take_dmg() then
		return
	end

	local damage_info = {
		result = {
			variant = "bullet",
			type = "hurt"
		},
		attacker_unit = attack_data.attacker_unit
	}

	if self:is_friendly_fire(attack_data.attacker_unit) then
		return
	elseif self._bleed_out and managers.player:has_category_upgrade("player", "hitman_bleedout_invuln") then
		return
	elseif self._god_mode then
		if attack_data.damage > 0 then
			self:_send_damage_drama(attack_data, attack_data.damage)
		end

		self:_call_listeners(damage_info)

		return
	elseif self._invulnerable or self._mission_damage_blockers.invulnerable then
		self:_call_listeners(damage_info)

		return
	elseif self:incapacitated() then
		return
	elseif self._unit:movement():current_state().immortal then
		return
	elseif self._revive_miss and math.random() < self._revive_miss then
		self:play_whizby(attack_data.col_ray.position)

		return
	elseif self:_chk_dmg_too_soon(attack_data.damage) then
		return
	end

	self:_hit_direction(attack_data.attacker_unit:position())

	local pm = managers.player
	self._last_received_dmg = attack_data.damage
	
	self._next_allowed_dmg_t = Application:digest_value(pm:player_timer():time() + self._dmg_interval, true)
	
	if pm:has_category_upgrade("player", "wcard_thorns") then
		self:do_thorns(attack_data.damage)
	end
	
	if managers.player:has_category_upgrade("player", "sociopath_mode") then
		attack_data.damage = 1
	end
	local dodge_roll = math.random()
	local dodge_value = tweak_data.player.damage.DODGE_INIT or 0
	local armor_dodge_chance = pm:body_armor_value("dodge")
	local skill_dodge_chance = pm:skill_dodge_chance(self._unit:movement():running(), self._unit:movement():crouching(), self._unit:movement():zipline_unit())
	dodge_value = dodge_value + armor_dodge_chance + skill_dodge_chance

	if self._temporary_dodge_t and TimerManager:game():time() < self._temporary_dodge_t then
		dodge_value = dodge_value + self._temporary_dodge
	end

	local smoke_dodge = 0

	for _, smoke_screen in ipairs(pm._smoke_screen_effects or {}) do
		if smoke_screen:is_in_smoke(self._unit) then
			smoke_dodge = tweak_data.projectiles.smoke_screen_grenade.dodge_chance

			break
		end
	end

	dodge_value = 1 - (1 - dodge_value) * (1 - smoke_dodge)

	if dodge_roll < dodge_value then
		self:play_whizby(attack_data.col_ray.position)
		pm:send_message(Message.OnPlayerDodge)

		return
	end

	local dmg_mul = pm:damage_reduction_skill_multiplier("bullet")
	attack_data.damage = attack_data.damage * dmg_mul
	attack_data.damage = pm:modify_value("damage_taken", attack_data.damage, attack_data)
	attack_data.damage = managers.mutators:modify_value("PlayerDamage:TakeDamageBullet", attack_data.damage)
	attack_data.damage = managers.modifiers:modify_value("PlayerDamage:TakeDamageBullet", attack_data.damage)
	
	if _G.IS_VR then
		local distance = mvector3.distance(self._unit:position(), attack_data.attacker_unit:position())

		if tweak_data.vr.long_range_damage_reduction_distance[1] < distance then
			local step = math.clamp(distance / tweak_data.vr.long_range_damage_reduction_distance[2], 0, 1)
			local mul = 1 - math.step(tweak_data.vr.long_range_damage_reduction[1], tweak_data.vr.long_range_damage_reduction[2], step)
			attack_data.damage = attack_data.damage * mul
		end
	end
	
	local damage_absorption = pm:damage_absorption()
	
	if damage_absorption > 0 then
		attack_data.damage = math.max(0, attack_data.damage - damage_absorption)
	end
	
	pm:_deduct_local_cocaine_stacks()
	
	attack_data.damage = pm:consume_damage_overshield(attack_data.damage)

	local shake_armor_multiplier = pm:body_armor_value("damage_shake") * pm:upgrade_value("player", "damage_shake_multiplier", 1)
	local gui_shake_number = tweak_data.gui.armor_damage_shake_base / shake_armor_multiplier
	gui_shake_number = gui_shake_number + pm:upgrade_value("player", "damage_shake_addend", 0)
	shake_armor_multiplier = tweak_data.gui.armor_damage_shake_base / gui_shake_number
	local shake_multiplier = math.clamp(attack_data.damage, 0.2, 2) * shake_armor_multiplier

	self._unit:camera():play_shaker("player_bullet_damage", 1 * shake_multiplier)

	if not _G.IS_VR then
		managers.rumble:play("damage_bullet")
	end

	pm:check_damage_carry(attack_data)

	if self._bleed_out then
		if attack_data.damage == 0 then
			self._unit:sound():play("player_hit")
		else
			self._unit:sound():play("player_hit_permadamage")
		end

		self:_bleed_out_damage(attack_data)

		return
	else
		if self:get_real_armor() > 0 or attack_data.damage == 0 then
			self._unit:sound():play("player_hit")
		else
			self._unit:sound():play("player_hit_permadamage")
		end
	end
	
	self:_check_chico_heal(attack_data)

	local armor_reduction_multiplier = 0

	if self:get_real_armor() <= 0 then
		armor_reduction_multiplier = 1
	end

	local health_subtracted = self:_calc_armor_damage(attack_data)

	if attack_data.armor_piercing then
		attack_data.damage = attack_data.damage - health_subtracted
	else
		attack_data.damage = attack_data.damage * armor_reduction_multiplier
	end

	health_subtracted = health_subtracted + self:_calc_health_damage(attack_data)

	if not self._bleed_out then
		if health_subtracted > 0 then
			self:_send_damage_drama(attack_data, health_subtracted)
		end
	else
		self:chk_queue_taunt_line(attack_data)
	end

	pm:send_message(Message.OnPlayerDamage, nil, attack_data)
	self:_call_listeners(damage_info)

	return true
end

function PlayerDamage:damage_melee(attack_data)
	if not self:_chk_can_take_dmg() then
		return
	end

	local pm = managers.player
	local can_counter_strike = pm:has_category_upgrade("player", "counter_strike_melee")

	if can_counter_strike and self._unit:movement():current_state().in_melee and self._unit:movement():current_state():in_melee() then
		if attack_data.attacker_unit and alive(attack_data.attacker_unit) and attack_data.attacker_unit:base() then
			local comeback_strike = pm:has_category_upgrade("player", "infiltrator_comeback_strike")
			local is_dozer = not comeback_strike and attack_data.attacker_unit:base().has_tag and attack_data.attacker_unit:base():has_tag("tank")

			--prevent the player from countering Dozers or other players through FF, for obvious reasons
			if not attack_data.attacker_unit:base().is_husk_player and not is_dozer then
			
				if comeback_strike then
					local ray = self._unit:raycast("ray", self._unit:movement():m_head_pos(), attack_data.attacker_unit:movement():m_head_pos(), "slot_mask", managers.slot:get_mask("bullet_impact_targets"), "sphere_cast_radius", 20, "ray_type", "body melee")
					
					self._unit:movement():current_state():_do_melee_damage(pm:player_timer():time(), nil, ray, nil, nil, true)
				end	
				
				self._unit:movement():current_state():discharge_melee()

				return "countered"
			end
		end
	end

	local damage_info = {
		result = {
			variant = "melee",
			type = "hurt"
		},
		attacker_unit = attack_data.attacker_unit
	}

	if self:is_friendly_fire(attack_data.attacker_unit) then
		return
	elseif self._bleed_out and managers.player:has_category_upgrade("player", "hitman_bleedout_invuln") then
		return
	elseif self._god_mode then
		if attack_data.damage > 0 then
			self:_send_damage_drama(attack_data, attack_data.damage)
		end

		self:_call_listeners(damage_info)

		return
	elseif self._invulnerable or self._mission_damage_blockers.invulnerable then
		self:_call_listeners(damage_info)

		return
	elseif self:incapacitated() then
		return
	elseif self._unit:movement():current_state().immortal then
		return
	elseif self:_chk_dmg_too_soon(attack_data.damage) then
		return
	end

	self:_hit_direction(attack_data.attacker_unit:position())

	self._last_received_dmg = attack_data.damage
	self._next_allowed_dmg_t = Application:digest_value(pm:player_timer():time() + self._dmg_interval, true)
	
	if pm:has_category_upgrade("player", "wcard_thorns") then
		self:do_thorns(attack_data.damage)
	end
	
	local allow_melee_dodge = self._next_melee_dodge_t and self._next_melee_dodge_t < pm:player_timer():time() --manual toggle, to be later replaced with a Rogue melee dodge perk check

	if allow_melee_dodge and pm:current_state() ~= "bleed_out" and pm:current_state() ~= "bipod" and pm:current_state() ~= "tased" then --self._bleed_out and current_state() ~= "bleed_out" aren't the same thing
		self._unit:movement():push(attack_data.push_vel * 0.25)
		self._unit:camera():play_shaker("melee_hit", 0.1)
			
		self._unit:sound():play("clk_baton_swing", nil, false)
		self._unit:sound():play("clk_baton_swing", nil, false)
		
		self._next_melee_dodge_t = pm:player_timer():time() + 10
		pm:send_message(Message.OnPlayerDodge)

		return
	end
	
	if not pm:has_category_upgrade("player", "sociopath_mode") then
		local dmg_mul = pm:damage_reduction_skill_multiplier("melee") --the vanilla function has this line, but it also uses bullet damage reduction skills due to it redirecting to damage_bullet to get results
		attack_data.damage = attack_data.damage * dmg_mul
		attack_data.damage = pm:modify_value("damage_taken", attack_data.damage, attack_data) --apply damage resistances before checking for bleedout and other things

		local damage_absorption = pm:damage_absorption()

		if damage_absorption > 0 then
			attack_data.damage = math.max(0, attack_data.damage - damage_absorption)
		end
	else
		attack_data.damage = 1
	end
	
	pm:_deduct_local_cocaine_stacks()
	
	attack_data.damage = pm:consume_damage_overshield(attack_data.damage)

	if attack_data.tase_player then
		if pm:current_state() == "standard" or pm:current_state() == "carry" or pm:current_state() == "bipod" then
			if pm:current_state() == "bipod" then
				self._unit:movement()._current_state:exit(nil, "tased")
			end

			self._unit:movement():on_non_lethal_electrocution()
			pm:set_player_state("tased")

			--no pushing and camera shaking for melee tase attacks
		end
	else
		if pm:current_state() == "bipod" then
			self._unit:movement()._current_state:exit(nil, "standard")
			pm:set_player_state("standard")
		end

		local vars = {
			"melee_hit",
			"melee_hit_var2"
		}

		self._unit:camera():play_shaker(vars[math.random(#vars)], 0.5)

		--no pushing when in bleedout, looks silly in third-person
		if pm:current_state() ~= "bleed_out" then
			self._unit:movement():push(attack_data.push_vel)
		end
	end

	if self._bleed_out then
		self:_bleed_out_damage(attack_data)

		--bleed_out = always taking health damage, so use the appropiate sound and cause a blood effect if the weapon isn't tase capable
		local hit_sound = "hit_body"

		--unless damage is completely negated
		if attack_data.damage == 0 then
			hit_sound = "hit_gen"
		end

		self:play_melee_hit_sound_and_effects(attack_data, hit_sound, not attack_data.tase_player)

		return
	end
	
	self:_check_chico_heal(attack_data)

	local go_through_armor = false --manual toggle
	local health_subtracted = nil
	local armor_broken = false

	if go_through_armor then
		health_subtracted = self:_calc_armor_damage(attack_data)

		attack_data.damage = attack_data.damage - health_subtracted

		health_subtracted = health_subtracted + self:_calc_health_damage(attack_data)

		armor_broken = self:_max_armor() == 0 or self:_max_armor() > 0 and self:get_real_armor() <= 0 --works when armor is broken and health damage is taken by the same hit
	else
		local armor_reduction_multiplier = 0

		if self:get_real_armor() <= 0 then --if armor is already broken, don't negate health damage
			armor_reduction_multiplier = 1
			armor_broken = true --checked before actually taking damage
		end

		health_subtracted = self:_calc_armor_damage(attack_data)

		if attack_data.melee_armor_piercing then --for specific cases, like say, making headless Dozers able to go through armor with melee when other enemies can't
			attack_data.damage = attack_data.damage - health_subtracted
		else
			attack_data.damage = attack_data.damage * armor_reduction_multiplier
		end

		health_subtracted = health_subtracted + self:_calc_health_damage(attack_data)
	end

	local hit_sound_type = "hit_gen"
	local blood_effect = false

	if armor_broken then
		hit_sound_type = "hit_body"
		blood_effect = not attack_data.tase_player
	end

	self:play_melee_hit_sound_and_effects(attack_data, hit_sound_type, blood_effect)

	if not self._bleed_out then
		if health_subtracted > 0 then
			self:_send_damage_drama(attack_data, health_subtracted)
		end
	else
		local attacker = attack_data.attacker_unit

		if attacker:character_damage() and attacker:character_damage().dead and not attacker:character_damage():dead() then
			if attacker:base().has_tag then
				if attacker:base():has_tag("tank") then
					self._kill_taunt_clbk_id = "kill_taunt" .. tostring(self._unit:key())
					managers.enemy:add_delayed_clbk(self._kill_taunt_clbk_id, callback(self, self, "clbk_kill_taunt", attack_data), TimerManager:game():time() + 0.5)
				elseif attacker:base():has_tag("taser") then
					self._kill_taunt_clbk_id = "kill_taunt" .. tostring(self._unit:key())
					managers.enemy:add_delayed_clbk(self._kill_taunt_clbk_id, callback(self, self, "clbk_kill_taunt_tase", attack_data), TimerManager:game():time() + 0.5)
				elseif attacker:base():has_tag("law") and not attacker:base():has_tag("special") then
					self._kill_taunt_clbk_id = "kill_taunt" .. tostring(self._unit:key())
					managers.enemy:add_delayed_clbk(self._kill_taunt_clbk_id, callback(self, self, "clbk_kill_taunt_common", attack_data), TimerManager:game():time() + 0.5)
				end
			end
		end
	end

	pm:send_message(Message.OnPlayerDamage, nil, attack_data)
	self:_call_listeners(damage_info)

	return
end

--tcd function
--- directly sets the amount of lives for the local player
function PlayerDamage:set_revives(amount,ignore_max)
	amount = math.max(amount,0)
	local max_revives = self:get_max_revives()
	if not ignore_max then
		amount = math.min(amount,max_revives)
	end
	self._revives = Application:digest_value(amount,true)
	self:_send_set_revives(amount >= max_revives)
end

--tcd function
--- adds or removes lives for the local player
function PlayerDamage:change_revives(amount,ignore_max)
	return self:set_revives(amount + Application:digest_value(self._revives,false),ignore_max)
end

--- returns the maximum number of lives for the local player
function PlayerDamage:get_max_revives()
	return self._lives_max,self._lives_init 
	-- _lives_max is separate from _lives_init; the latter is vanilla and does not account for player bonuses such as nine lives
end

--tcd function
--- 
function PlayerDamage:recalculate_max_revives(chk_lives_init)
	if chk_lives_init then
		self._lives_init = tweak_data.player.damage.LIVES_INIT

		if Global.game_settings.one_down then
			self._lives_init = 2
		end

		self._lives_init = managers.modifiers:modify_value("PlayerDamage:GetMaximumLives", self._lives_init)
	end
	self._lives_max = self._lives_init + managers.player:upgrade_value("player", "additional_lives", 0)
	return self._lives_max,self._lives_init
end

--tcd function
function PlayerDamage:clbk_kill_taunt(taunt_data)
	local attacker = taunt_data.attacker_unit

	if not alive(attacker) or attacker:character_damage():dead() then
		return
	end
	
	if taunt_data.taunt_line then
		attacker:sound():say(taunt_data.taunt_line, true)
	end
end

--tcd function
function PlayerDamage:clbk_kill_taunt_common(attack_data)
	local attacker = attack_data.attacker_unit

	if attacker and alive(attacker) and attacker:character_damage() and attacker:character_damage().dead and not attacker:character_damage():dead() then
		attacker:sound():say("i03")
	end

	self._kill_taunt_clbk_id = nil
end

--tcd function
function PlayerDamage:clbk_kill_taunt_tase(attack_data)
--[[
	local attacker = attack_data.attacker_unit

	if attacker and alive(attacker) and attacker:character_damage() and attacker:character_damage().dead and not attacker:character_damage():dead() then
		attacker:sound():say("tsr_post_tasing_taunt")
	end
--]]
	self._kill_taunt_clbk_id = nil
end


--tcd function
function PlayerDamage:do_thorns(damage)
	local pm = managers.player
	
	local aced = pm:has_category_upgrade("player", "wcard_thorns_stagger")
	
	local m_head_pos = pm:local_player():movement():m_head_pos()
	local weap_unit = pm:get_current_state()._equipped_unit
	local enemies = World:find_units_quick(self._unit, "sphere", self._unit:position(), 200, managers.slot:get_mask("enemies"))
	
	for i = 1, #enemies do
		local enemy = enemies[i]
		local dmg_ext = enemy:character_damage()

		if dmg_ext and dmg_ext.damage_simple then
			local center_of_mass = enemy:movement():m_com()
			local attack_dir = center_of_mass - m_head_pos
			mvec3_norm(attack_dir)

			local attack_data = {
				damage = damage,
				attacker_unit = self._unit,
				no_weapon_stats = true,
				stagger = aced,
				pos = center_of_mass,
				attack_dir = attack_dir,
				weapon_unit = weap_unit
			}

			dmg_ext:damage_simple(attack_data)
		end
	end
end

--tcd function
function PlayerDamage:play_melee_hit_sound_and_effects(attack_data, sound_type, play_blood_effect)
	if play_blood_effect then
		--make sure the weapon is supposed to cause a blood splatter
		local blood_effect = attack_data.melee_weapon and attack_data.melee_weapon == "weapon"
		blood_effect = blood_effect or attack_data.melee_weapon and tweak_data.weapon.npc_melee[attack_data.melee_weapon] and tweak_data.weapon.npc_melee[attack_data.melee_weapon].player_blood_effect or false

		if blood_effect then --spawn a blood splatter in front of the player
			local pos = mvec1

			mvector3.set(pos, self._unit:camera():forward())
			mvector3.multiply(pos, 20)
			mvector3.add(pos, self._unit:camera():position())

			local rot = self._unit:camera():rotation():z()

			World:effect_manager():spawn({
				effect = Idstring("effects/payday2/particles/impacts/blood/blood_impact_a"),
				position = pos,
				normal = rot
			})
		end
	end

	local melee_name_id = nil
	local attacker_unit = attack_data.attacker_unit
	local valid_attacker = attacker_unit and alive(attacker_unit) and attacker_unit:base()

	if valid_attacker then
		--get melee weapon id
		if attacker_unit:base().is_husk_player then
			local peer_id = managers.network:session():peer_by_unit(attacker_unit):id()
			local peer = managers.network:session():peer(peer_id)

			melee_name_id = peer:melee_id()
		else
			melee_name_id = attacker_unit:base().melee_weapon and attacker_unit:base():melee_weapon()
		end

		if melee_name_id then
			if melee_name_id == "knife_1" then --knife used by NPCs
				melee_name_id = "kabar"
			elseif melee_name_id == "helloween" then --titan staff used by headless Dozers
				melee_name_id = "brass_knuckles"
			elseif not attacker_unit:base().is_husk_player and melee_name_id == "baton" then --cop baton (otherwise the ballistic baton's sounds are used)
				melee_name_id = "weapon"
			end

			local tweak_data = tweak_data.blackmarket.melee_weapons[melee_name_id]

			if tweak_data and tweak_data.sounds and tweak_data.sounds[sound_type] then
				local post_event = tweak_data.sounds[sound_type]
				local anim_attack_vars = tweak_data.anim_attack_vars
				local variation = anim_attack_vars and math.random(#anim_attack_vars)

				if type(post_event) == "table" then
					if variation then
						post_event = post_event[variation]
					else
						post_event = post_event[1]
					end
				end
				
				--some sounds are too low to hear, playing them twice helps and or accentuates a hit even more)
				self._unit:sound():play(post_event, nil, false)
				self._unit:sound():play(post_event, nil, false)
			end
		end
	end
end


function PlayerDamage:_activate_preventative_care(upgrade_level)
	if upgrade_level and upgrade_level > 0 then

		local pm = managers.player
		local ehp = nil
		local mul = nil
		local upgrade_data = pm:upgrade_value_by_level("first_aid_kit","damage_overshield",upgrade_level,{0,0})
		
		if managers.player:has_category_upgrade("player", "sociopath_mode") then
			ehp = 1
			mul = 1
		else
			ehp = self:_max_health() + self:_max_armor()
			mul = upgrade_data[1]
		end
		
		local amount = ehp * mul
		
		local duration = upgrade_data[2]
		pm:set_damage_overshield("preventative_care_absorption",amount,
			{
				depleted_callback = function(damage_before_overshield,damage_blocked_by_overshield)
					if duration > 0 then 
						pm:activate_temporary_property("preventative_care_invuln_active",duration,true)
						
						return 0 -- nullify remaining damage for this attack
					end
				end
			}
		)
	end
end

function PlayerDamage:_on_use_first_aid_kit(preventative_care_level)
	local heal_values = tweak_data.upgrades.values.first_aid_kit.base_values[1]
	
	-- restore 50% of missing health
	local max_hp = self:_max_health()
	local health_ratio = self:get_real_health() / max_hp -- self:health_ratio()
	local health_missing_ratio = 1 - health_ratio
	
	local hot_mis_value = heal_values.hot_mis_value
	local duration = heal_values.hot_duration
	local hot_max_value = heal_values.hot_max_value -- 10% maximum health regen'd total
	
	-- instant health restore
	local health_restored = hot_mis_value * health_missing_ratio
	self:restore_health(health_restored,false,true)
	local missing_restore_percent_per_tick = hot_max_value / duration
	
	-- restore total 10% of maximum health over 10s
	managers.player:activate_temporary_property("max_health_hot",duration,missing_restore_percent_per_tick)
	
	self:_activate_preventative_care(preventative_care_level)
end

-- temporary invuln from Medic's Preventative Care
local orig_chk_invuln = PlayerDamage._chk_can_take_dmg
function PlayerDamage:_chk_can_take_dmg(...)
	return orig_chk_invuln(self,...) and not managers.player:has_active_temporary_property("preventative_care_invuln_active") and not managers.player:has_active_temporary_property("armorer_perfect_defense_invuln")
end
