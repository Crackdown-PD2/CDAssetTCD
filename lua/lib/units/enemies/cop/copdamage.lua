CopDamage.melee_knockback_tiers = {
	[1] = false,
	[2] = "light_hurt",
	[3] = "hurt",
	[4] = "heavy_hurt",
	[5] = "expl_hurt"
}


-- from Lookout Duty aced; tcd func
function CopDamage:_get_incoming_damage_multiplier(multiplier)
	multiplier = multiplier or 1
	if managers.player:team_upgrade_level("player","civilian_hostage_area_marking") >= 2 then
		local range = tweak_data.upgrades.values.team.player.civilian_hostage_area_marking_distance
		local lookout_aced_bonus = tweak_data.upgrades.values.team.player.civilian_hostage_area_marking_damage_mul
		
		--this applies to damage from all sources, so we don't need to check if the attacker unit is the player
		if range and CivilianBase.get_nearby_civ(self._unit:movement():m_pos(),range,true) then 
			multiplier = multiplier * lookout_aced_bonus
		end
	end
	return multiplier -- + self:get_damage_vulnerability_total()
end

function CopDamage:roll_critical_hit(attack_data,damage)
	if not self:can_be_critical(attack_data) then
		return false, damage
	end

	local critical_hits = self._char_tweak.critical_hits or {}
	local critical_hit = attack_data.critical_hit
	if critical_hit == nil then 
		--if the attack has not had its crit chance rolled already (eg. guaranteed crit from a skill), 
		--then roll crit chance
		local crit_chance = (critical_hits.base_chance or 0) + managers.player:critical_hit_chance() * (critical_hits.player_chance_multiplier or 1)
		
		if crit_chance > 0 then 
			local critical_roll = math.rand(1)
			critical_hit = critical_roll < crit_chance
		end
		
	end	

	if critical_hit then
		local critical_damage_mul = critical_hits.damage_mul or self._char_tweak.headshot_dmg_mul
		
		if critical_damage_mul then 
			critical_damage_mul = critical_damage_mul * managers.player:upgrade_value("player","critical_hit_multiplier",2)
			damage = damage * critical_damage_mul
		else
			damage = self._health * 10
		end
	end

	return critical_hit, damage
end

local mvec3_set = mvector3.set
local mvec3_set_stat = mvector3.set_static
local mvec3_set_z = mvector3.set_z
local mvec3_add = mvector3.add
local mvec3_mul = mvector3.multiply
local mvec3_sub = mvector3.subtract
local mvec3_dot = mvector3.dot
local mvec3_dis = mvector3.distance
local mvec3_norm = mvector3.normalize
local mvec3_cpy = mvector3.copy
local mvec3_neg = mvector3.negate
local mvec3_lerp = mvector3.lerp
local mvec3_spread = mvector3.spread

local mvec_1 = Vector3()
local mvec_2 = Vector3()
local mvec_3 = Vector3()
local mvec_4 = Vector3()

local m_rot_z = mrotation.z

local math_lerp = math.lerp
local math_random = math.random
local math_clamp = math.clamp
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local math_up = math.UP
local math_down = math.DOWN

local table_insert = table.insert
local table_contains = table.contains
local table_size = table.size

local tostring_g = tostring
local alive_g = alive
local world_g = World

local idstr_func = Idstring
local ids_head_obj = idstr_func("Head")
local ids_flesh = idstr_func("flesh")
local ids_char_dmg = idstr_func("character_damage")
local idstr_bullet_hit_blood = idstr_func("effects/payday2/particles/impacts/blood/blood_impact_a")
local ids_bullet_hit_glass_effect = idstr_func("effects/particles/bullet_hit/glass_breakable/bullet_hit_glass_breakable")
local table_contains = table.contains

-- mostly vanilla (atm)
-- minor optimizations (non gameplay changing)
-- allow custom headshot mul per weapon class, for Grand Brachial (shotgunner)
Hooks:OverrideFunction(CopDamage,"damage_bullet",function(self,attack_data)
	if self._dead or self._invulnerable then
		return
	end

	local player_unit = managers.player:player_unit()
	local attacker_is_main_player = attack_data.attacker_unit == player_unit
	
	if self:is_friendly_fire(attack_data.attacker_unit) then
		return "friendly_fire"
	end

	if self:chk_immune_to_attacker(attack_data.attacker_unit) then
		return
	end
	
	if self._char_tweak.bullet_damage_only_from_front then
		mvector3.set(mvec_1, attack_data.col_ray.ray)
		mvector3.set_z(mvec_1, 0)
		mrotation.y(self._unit:rotation(), mvec_2)
		mvector3.set_z(mvec_2, 0)

		local not_from_the_front = mvector3.dot(mvec_1, mvec_2) > 0.3

		if not_from_the_front then
			return
		end
	end

	local is_civilian = CopDamage.is_civilian(self._unit:base()._tweak_table)

	if self._has_plate and attack_data.col_ray.body and attack_data.col_ray.body:name() == self._ids_plate_name and not attack_data.armor_piercing then
		local armor_pierce_roll = math.rand(1)
		local armor_pierce_value = 0

		if attacker_is_main_player and not attack_data.weapon_unit:base().thrower_unit then
			armor_pierce_value = armor_pierce_value + attack_data.weapon_unit:base():armor_piercing_chance()
			armor_pierce_value = armor_pierce_value + managers.player:upgrade_value("player", "armor_piercing_chance", 0)
			armor_pierce_value = armor_pierce_value + managers.player:upgrade_value("weapon", "armor_piercing_chance", 0)
			armor_pierce_value = armor_pierce_value + managers.player:upgrade_value("weapon", "armor_piercing_chance_2", 0)

			if attack_data.weapon_unit:base():got_silencer() then
				armor_pierce_value = armor_pierce_value + managers.player:upgrade_value("weapon", "armor_piercing_chance_silencer", 0)
			end

			if attack_data.weapon_unit:base():is_category("saw") then
				armor_pierce_value = armor_pierce_value + managers.player:upgrade_value("saw", "armor_piercing_chance", 0)
			end
		elseif attack_data.attacker_unit:base() and attack_data.attacker_unit:base().sentry_gun then
			local owner = attack_data.attacker_unit:base():get_owner()

			if alive(owner) then
				if owner == player_unit then
					armor_pierce_value = armor_pierce_value + managers.player:upgrade_value("sentry_gun", "armor_piercing_chance", 0)
					armor_pierce_value = armor_pierce_value + managers.player:upgrade_value("sentry_gun", "armor_piercing_chance_2", 0)
				else
					armor_pierce_value = armor_pierce_value + (owner:base():upgrade_value("sentry_gun", "armor_piercing_chance") or 0)
					armor_pierce_value = armor_pierce_value + (owner:base():upgrade_value("sentry_gun", "armor_piercing_chance_2") or 0)
				end
			end
		end

		if armor_pierce_roll >= armor_pierce_value then
			return
		end
	end

	local result = nil
	local body_index = self._unit:get_body_index(attack_data.col_ray.body:name())
	local head = self._head_body_name and attack_data.col_ray.body and attack_data.col_ray.body:name() == self._ids_head_body_name
	local damage = attack_data.damage

	if self._unit:base():char_tweak().DAMAGE_CLAMP_BULLET then
		damage = math.min(damage, self._unit:base():char_tweak().DAMAGE_CLAMP_BULLET)
	end

	damage = damage * (self._marked_dmg_mul or 1)

	if self._marked_dmg_dist_mul then
		local spott_dst = tweak_data.upgrades.values.player.marked_inc_dmg_distance[self._marked_dmg_dist_mul]

		if spott_dst then
			local dst = mvector3.distance(attack_data.origin, self._unit:position())

			if spott_dst[1] < dst then
				damage = damage * spott_dst[2]
			end
		end
	end

	if self._unit:movement():cool() then
		damage = self._HEALTH_INIT
	end

	local headshot = false
	local headshot_multiplier = 1

	if attacker_is_main_player then
	
		-- tcd weapon class/subclasses
		local weap_base = alive(attack_data.weapon_unit) and attack_data.weapon_unit:base()
		local weapon_class = weap_base and weap_base.get_weapon_class and weap_base:get_weapon_class() or "NO_WEAPON_CLASS"
		local subclasses = weap_base and weap_base.get_weapon_subclasses and weap_base:get_weapon_subclasses() or {}
		
		local damage_scale = nil

		if alive(attack_data.weapon_unit) and attack_data.weapon_unit:base() and attack_data.weapon_unit:base().is_weak_hit then
			damage_scale = attack_data.weapon_unit:base():is_weak_hit(attack_data.col_ray and attack_data.col_ray.distance, attack_data.attacker_unit) or 1
		end

		local critical_hit, crit_damage = self:roll_critical_hit(attack_data, damage)

		if critical_hit then
			managers.hud:on_crit_confirmed(damage_scale)

			damage = crit_damage
			attack_data.critical_hit = true
		else
			managers.hud:on_hit_confirmed(damage_scale)
		end

		-- headshot_mul_addend is from tcd
		headshot_multiplier = managers.player:upgrade_value("weapon", "passive_headshot_damage_multiplier", 1) + managers.player:upgrade_value(weapon_class, "headshot_mul_addend", 0)

		if managers.groupai:state():is_enemy_special(self._unit) then
			damage = damage * managers.player:upgrade_value("weapon", "special_damage_taken_multiplier", 1)

			if attack_data.weapon_unit:base().weapon_tweak_data then
				damage = damage * (attack_data.weapon_unit:base():weapon_tweak_data().special_damage_multiplier or 1)
			end
		end

		if head then
			managers.player:on_headshot_dealt()

			headshot = true
		end
		
		--------------------------
		-- TCD: apply fire damage mul from Third Degree aced here
		-- (deal +25% more damage to enemies on fire)
		if managers.fire:is_set_on_fire(self._unit) then
			-- if attack_data.is_molotov then 
			damage = damage * managers.player:upgrade_value("subclass_areadenial", "effect_doubleroasting_damage_increase_mul", 1)
		end
		--------------------------
	end

	if not self._char_tweak.ignore_headshot and not self._damage_reduction_multiplier and head then
		if self._char_tweak.headshot_dmg_mul then
			damage = damage * self._char_tweak.headshot_dmg_mul * headshot_multiplier
		else
			damage = self._health * 10
		end
	end

	if not head and not self._char_tweak.no_headshot_add_mul and attack_data.weapon_unit:base().get_add_head_shot_mul then
		local add_head_shot_mul = attack_data.weapon_unit:base():get_add_head_shot_mul()

		if add_head_shot_mul then
			if self._char_tweak.headshot_dmg_mul then
				local tweak_headshot_mul = math.max(0, self._char_tweak.headshot_dmg_mul - 1)
				local mul = tweak_headshot_mul * add_head_shot_mul + 1
				damage = damage * mul
			else
				damage = self._health * 10
			end
		end
	end

	damage = self:_apply_damage_reduction(damage)
	attack_data.raw_damage = damage
	attack_data.headshot = head
	local damage_percent = math.ceil(math.clamp(damage / self._HEALTH_INIT_PRECENT, 1, self._HEALTH_GRANULARITY))
	damage = damage_percent * self._HEALTH_INIT_PRECENT
	damage, damage_percent = self:_apply_min_health_limit(damage, damage_percent)

	if self._immortal then
		damage = math.min(damage, self._health - 1)
	end

	if self._health <= damage then
		if self:check_medic_heal() then
			result = {
				type = "healed",
				variant = attack_data.variant
			}
		else
			if head then
				managers.player:on_lethal_headshot_dealt(attack_data.attacker_unit, attack_data)
				self:_spawn_head_gadget({
					position = attack_data.col_ray.body:position(),
					rotation = attack_data.col_ray.body:rotation(),
					dir = attack_data.col_ray.ray
				})
			end

			attack_data.damage = self._health
			result = {
				type = "death",
				variant = attack_data.variant
			}

			self:die(attack_data)
			self:chk_killshot(attack_data.attacker_unit, "bullet", headshot, attack_data.weapon_unit:base():get_name_id())
		end
	else
		attack_data.damage = damage
		local result_type = not self._char_tweak.immune_to_knock_down and (attack_data.knock_down and "knock_down" or attack_data.stagger and not self._has_been_staggered and "stagger") or self:get_damage_type(damage_percent, "bullet")
		result = {
			type = result_type,
			variant = attack_data.variant
		}

		self:_apply_damage_to_health(damage)
	end

	attack_data.result = result
	attack_data.pos = attack_data.col_ray.position

	if result.type == "death" then
		local data = {
			name = self._unit:base()._tweak_table,
			stats_name = self._unit:base()._stats_name,
			head_shot = head,
			weapon_unit = attack_data.weapon_unit,
			variant = attack_data.variant
		}

		if managers.groupai:state():all_criminals()[attack_data.attacker_unit:key()] then
			managers.statistics:killed_by_anyone(data)
		end

		if attacker_is_main_player then
			local special_comment = self:_check_special_death_conditions(attack_data.variant, attack_data.col_ray.body, attack_data.attacker_unit, attack_data.weapon_unit)

			self:_comment_death(attack_data.attacker_unit, self._unit, special_comment)
			self:_show_death_hint(self._unit:base()._tweak_table)

			local attacker_state = managers.player:current_state()
			data.attacker_state = attacker_state

			managers.statistics:killed(data)
			self:_check_damage_achievements(attack_data, head)

			if not is_civilian and managers.player:has_category_upgrade("temporary", "overkill_damage_multiplier") and not attack_data.weapon_unit:base().thrower_unit and attack_data.weapon_unit:base():is_category("shotgun", "saw") then
				managers.player:activate_temporary_upgrade("temporary", "overkill_damage_multiplier")
			end

			if is_civilian then
				managers.money:civilian_killed()
			end
		elseif managers.groupai:state():is_unit_team_AI(attack_data.attacker_unit) then
			local special_comment = self:_check_special_death_conditions(attack_data.variant, attack_data.col_ray.body, attack_data.attacker_unit, attack_data.weapon_unit)

			self:_comment_death(attack_data.attacker_unit, self._unit, special_comment)
		elseif attack_data.attacker_unit:base().sentry_gun then
			if Network:is_server() then
				local server_info = attack_data.weapon_unit:base():server_information()

				if server_info and server_info.owner_peer_id ~= managers.network:session():local_peer():id() then
					local owner_peer = managers.network:session():peer(server_info.owner_peer_id)

					if owner_peer then
						owner_peer:send_queued_sync("sync_player_kill_statistic", data.name, data.head_shot and true or false, data.weapon_unit, data.variant, data.stats_name)
					end
				else
					data.attacker_state = managers.player:current_state()

					managers.statistics:killed(data)
				end
			end

			local sentry_attack_data = deep_clone(attack_data)
			sentry_attack_data.attacker_unit = attack_data.attacker_unit:base():get_owner()

			if sentry_attack_data.attacker_unit == managers.player:player_unit() then
				self:_check_damage_achievements(sentry_attack_data, head)
			else
				self._unit:network():send("sync_damage_achievements", sentry_attack_data.weapon_unit, sentry_attack_data.attacker_unit, sentry_attack_data.damage, sentry_attack_data.col_ray and sentry_attack_data.col_ray.distance, head)
			end
		end
	end

	local hit_offset_height = math.clamp(attack_data.col_ray.position.z - self._unit:movement():m_pos().z, 0, 300)
	local attacker = attack_data.attacker_unit

	if attacker:id() == -1 then
		attacker = self._unit
	end

	local weapon_unit = attack_data.weapon_unit

	if alive(weapon_unit) and weapon_unit:base() and weapon_unit:base().add_damage_result then
		weapon_unit:base():add_damage_result(self._unit, result.type == "death", attacker, damage_percent)
	end

	local variant = nil

	if result.type == "knock_down" then
		variant = 1
	elseif result.type == "stagger" then
		variant = 2
		self._has_been_staggered = true
	elseif result.type == "healed" then
		variant = 3
	else
		variant = 0
	end

	self:_send_bullet_attack_result(attack_data, attacker, damage_percent, body_index, hit_offset_height, variant)
	self:_on_damage_received(attack_data)

	if not is_civilian then
		managers.player:send_message(Message.OnEnemyShot, nil, self._unit, attack_data)
	end

	result.attack_data = attack_data

	return result
end)

Hooks:OverrideFunction(CopDamage,"damage_melee",function(self,attack_data)
	if self._dead or self._invulnerable then
		return
	end
	
	local attacker_unit = attack_data.attacker_unit
	
	if PlayerDamage.is_friendly_fire(self, attacker_unit) then
		return "friendly_fire"
	end
	
	if self:chk_immune_to_attacker(attacker_unit) then
		return
	end

	if alive(attacker_unit) and attacker_unit:in_slot(16) then
		local has_surrendered = self._unit:brain().surrendered and self._unit:brain():surrendered() or self._unit:anim_data().surrender or self._unit:anim_data().hands_back or self._unit:anim_data().hands_tied

		if has_surrendered then
			return
		end
	end

	local result = nil
	local is_civilian, is_gangster, is_cop = nil
	local attacker_is_main_player = attacker_unit == managers.player:player_unit()

	if CopDamage.is_civilian(self._unit:base()._tweak_table) then
		is_civilian = true
	elseif CopDamage.is_gangster(self._unit:base()._tweak_table) then
		is_gangster = true
	else
		is_cop = true
	end

	local head = self._head_body_name and not self._unit:in_slot(16) and not self._char_tweak.ignore_headshot and attack_data.col_ray.body and attack_data.col_ray.body:name() == self._ids_head_body_name
	local damage = attack_data.damage
	local damage_effect = attack_data.damage_effect
	
	--[[
			elseif managers.player:has_active_temporary_property("biker_guaranteed_stagger") then
				local stagger_id = managers.player:get_temporary_property("biker_guaranteed_stagger")
				if stagger_id ~= self._biker_proc_stagger then
					self._biker_proc_stagger = stagger_id
					result_type = "stagger"
				end
				--]]
	
	local damage_multiplier = 1
	local headshot_multiplier = 1

	local can_headshot = false
	if attacker_is_main_player then
		can_headshot = managers.player:has_category_upgrade("class_melee","can_headshot") and not self._char_tweak.ignore_headshot
		local critical_hit, crit_damage = self:roll_critical_hit(attack_data,damage)

		if critical_hit then
			damage = crit_damage

			local critical_hits = self._char_tweak.critical_hits or {}
			local critical_damage_mul = critical_hits.damage_mul or self._char_tweak.headshot_dmg_mul

			if critical_damage_mul then
				damage_effect = damage_effect * critical_damage_mul
			else
				damage_effect = self._health * 10
			end

			attack_data.critical_hit = true

			if damage > 0 then
				managers.hud:on_crit_confirmed()
			end
		elseif damage > 0 then
			managers.hud:on_hit_confirmed()
		end

		if not is_civilian and tweak_data.achievement.cavity.melee_type == attack_data.name_id then
			managers.achievment:award(tweak_data.achievement.cavity.award)
		end
		if head and can_headshot then 
			attack_data.headshot = head
				
			if not self._damage_reduction_multiplier then
				if self._char_tweak.headshot_dmg_mul then
					headshot_multiplier = headshot_multiplier * self._char_tweak.headshot_dmg_mul
				end
			end
		
			managers.player:on_headshot_dealt()
			headshot_multiplier = headshot_multiplier * managers.player:upgrade_value("weapon", "passive_headshot_damage_multiplier", 1)
		end


		--------------------------
		-- TCD: apply fire damage mul from Third Degree aced here
		-- (deal +25% more damage to enemies on fire)
		if managers.fire:is_set_on_fire(self._unit) then
			-- if attack_data.is_molotov then 
			damage = damage * managers.player:upgrade_value("subclass_areadenial", "effect_doubleroasting_damage_increase_mul", 1)
		end
		--------------------------
		
	end

	if self._marked_dmg_mul then
		damage = damage * self._marked_dmg_mul
		damage_effect = damage_effect * self._marked_dmg_mul
		
		if alive(attacker_unit) then
			local attacker_dmg_ext = attacker_unit:character_damage()
			local joker_dmg_bonus = attacker_dmg_ext and attacker_dmg_ext._joker_mark_dmg_bonus

			if joker_dmg_bonus then
				damage = damage * joker_dmg_bonus
			end
		end
	end
	
	damage_multiplier = self:_get_incoming_damage_multiplier(damage_multiplier)
	damage_multiplier = damage_multiplier * headshot_multiplier
	damage = damage * damage_multiplier 

	damage = self:_apply_damage_reduction(damage)
	damage_effect = self:_apply_damage_reduction(damage_effect)

	if self._unit:movement():cool() then
		damage = self._HEALTH_INIT
		damage_effect = self._HEALTH_INIT
	elseif self._char_tweak.DAMAGE_CLAMP_MELEE then --adding it while I'm at it in case it's needed for some reason
		damage = math_min(damage, self._char_tweak.DAMAGE_CLAMP_MELEE)
		damage_effect = math_min(damage_effect, self._char_tweak.DAMAGE_CLAMP_MELEE)
	end

	attack_data.raw_damage = damage

	damage = math_clamp(damage, 0, self._HEALTH_INIT)
	damage_effect = math_clamp(damage_effect, 0, self._HEALTH_INIT)

	local damage_percent = math_ceil(damage / self._HEALTH_INIT_PRECENT)
	local damage_effect_percent = math_ceil(damage_effect / self._HEALTH_INIT_PRECENT)

	damage = damage_percent * self._HEALTH_INIT_PRECENT
	damage_effect = damage_effect_percent * self._HEALTH_INIT_PRECENT

	damage, damage_percent = self:_apply_min_health_limit(damage, damage_percent)
	damage_effect, damage_effect_percent = self:_apply_min_health_limit(damage_effect, damage_effect_percent)

	if self._immortal then
		damage = math_min(damage, self._health - 1)
		damage_effect = math_min(damage_effect, self._health - 1)
	end

	if self._health <= damage then
		damage_effect_percent = 1
		attack_data.damage = self._health
		attack_data.damage_effect = self._health

		if self:check_medic_heal() then
			result = {
				type = "healed",
				variant = "melee"
			}
		else
			result = {
				type = "death",
				variant = "melee"
			}

			self:die(attack_data)
			self:chk_killshot(attacker_unit, "melee")
		end
	else
		attack_data.damage = damage
		attack_data.damage_effect = damage_effect

		local result_type = nil
		local is_tank = self._unit:base():has_tag("tank")
		if attack_data.shield_knock and self._char_tweak.damage.shield_knocked and not self:is_immune_to_shield_knockback() then
			result_type = "shield_knock"
		elseif attack_data.variant == "counter_tased" then
			result_type = "counter_tased"
		elseif attack_data.variant == "taser_tased" then
			if self._char_tweak.can_be_tased == nil or self._char_tweak.can_be_tased then
				result_type = "taser_tased"

				if attack_data.charge_lerp_value then
					local charge_power = math_lerp(0, 1, attack_data.charge_lerp_value)

					--damage_effect_percent here is used to sync how much the tase was charged (0-100%)
					damage_effect_percent = charge_power
					self._tased_time = math_lerp(1, 5, charge_power)
					self._tased_down_time = self._tased_time * 2
				else
					damage_effect_percent = 0.4
					self._tased_time = 2
					self._tased_down_time = self._tased_time * 2
				end
			end
		elseif attack_data.variant == "counter_spooc" and not is_tank and not self._unit:base():has_tag("boss") then
			result_type = "expl_hurt"
		elseif not self._char_tweak.immune_to_knock_down then
			if attacker_is_main_player and managers.player:has_active_temporary_property("biker_guaranteed_stagger") then
				local do_stagger = false
				if self._unit:base():has_tag("tank") then
					--stagger not allowed
				elseif self._unit:base():has_tag("special") then
					if managers.player:has_team_category_upgrade("player","biker_can_stagger_special_enemies") then
						do_stagger = true
					end
				elseif self._unit:base():has_tag("heavy") then
					if managers.player:has_team_category_upgrade("player","biker_can_stagger_heavy_enemies") then
						do_stagger = true
					end
				else --assume light enemy
					do_stagger = true
				end
				if do_stagger then
					local stagger_id = managers.player:get_temporary_property("biker_guaranteed_stagger")
					if stagger_id ~= self._biker_proc_stagger then
						self._biker_proc_stagger = stagger_id
						result_type = "stagger"
					end
				end
			end
		end

		if not result_type then
			if attack_data.knockback_tier then 
				result_type = attack_data.knockback_tier and self.melee_knockback_tiers[math.min(#self.melee_knockback_tiers,attack_data.knockback_tier)]
				if result_type == "expl_hurt" and is_tank then 
					-- expl_hurt is listed as a tier above hurt_heavy, but is not as severe an animation for bulldozers as hurt_heavy,
					-- so don't punish the player for being TOO GOOD at punching things
					result_type = self.melee_knockback_tiers[4]
				end
			end
			if result_type == nil then 
				result_type = self:get_damage_type(damage_effect_percent, "melee")
			end
		end

		result = {
			type = result_type,
			variant = "melee"
		}

		self:_apply_damage_to_health(damage)
	end

	attack_data.variant = "melee"
	attack_data.result = result
	attack_data.pos = attack_data.col_ray.position

	local snatch_pager, from_behind = nil

	if result.type == "death" then
		local data = {
			name = self._unit:base()._tweak_table,
			stats_name = self._unit:base()._stats_name,
			name_id = attack_data.name_id,
			variant = "melee"
		}

		managers.statistics:killed_by_anyone(data)

		if head then
			if can_headshot then 
				managers.player:on_lethal_headshot_dealt(attacker_unit,attack_data)
			end
			if data.name == "deathvox_grenadier" then
				self._unit:damage():run_sequence_simple("grenadier_glass_break")
			else
				self:_spawn_head_gadget({
					position = attack_data.col_ray.body:position(),
					rotation = attack_data.col_ray.body:rotation(),
					dir = attack_data.col_ray.ray
				})
			end
		end

		if attacker_is_main_player then
			local special_comment = self:_check_special_death_conditions("melee", attack_data.col_ray.body, attacker_unit, attack_data.name_id)

			self:_comment_death(attacker_unit, self._unit, special_comment)
			self:_show_death_hint(self._unit:base()._tweak_table)
			managers.statistics:killed(data)

			if is_civilian then
				managers.money:civilian_killed()
			else
				if managers.groupai:state():whisper_mode() and managers.blackmarket:equipped_mask().mask_id == tweak_data.achievement.cant_hear_you_scream.mask then
					managers.achievment:award_progress(tweak_data.achievement.cant_hear_you_scream.stat)
				end

				if is_cop and attack_data.name_id and attack_data.name_id == "fists" and Global.game_settings.level_id == "nightclub" then
					managers.achievment:award_progress(tweak_data.achievement.final_rule.stat)
				end

				mvec3_set(mvec_1, self._unit:position())
				mvec3_sub(mvec_1, attacker_unit:position())
				mvec3_norm(mvec_1)
				mvec3_set(mvec_2, self._unit:rotation():y())

				from_behind = mvec3_dot(mvec_1, mvec_2) >= 0

				if math_random() < managers.player:upgrade_value("player", "melee_kill_snatch_pager_chance", 0) then
					snatch_pager = true
					self._unit:unit_data().has_alarm_pager = false
				end
			end
		end
	end

	--only check for achievements if the attacker is the local player and they're alive (to be more specific, if their unit still exists)
	if attacker_is_main_player and tweak_data.blackmarket.melee_weapons[attack_data.name_id] then
		local achievements = tweak_data.achievement.enemy_melee_hit_achievements or {}
		local melee_type = tweak_data.blackmarket.melee_weapons[attack_data.name_id].type
		local enemy_base = self._unit:base()
		local enemy_movement = self._unit:movement()
		local enemy_type = enemy_base._tweak_table
		local unit_weapon = enemy_base._default_weapon_id
		local health_ratio = managers.player:player_unit():character_damage():health_ratio() * 100
		local melee_pass, melee_weapons_pass, type_pass, enemy_pass, enemy_weapon_pass, diff_pass, health_pass, level_pass, job_pass, jobs_pass, enemy_count_pass, tags_all_pass, tags_any_pass, all_pass, cop_pass, gangster_pass, civilian_pass, stealth_pass, on_fire_pass, behind_pass, result_pass, mutators_pass, critical_pass, action_pass, is_dropin_pass = nil

		for achievement, achievement_data in pairs(achievements) do
			melee_pass = not achievement_data.melee_id or achievement_data.melee_id == attack_data.name_id
			melee_weapons_pass = not achievement_data.melee_weapons or table_contains(achievement_data.melee_weapons, attack_data.name_id)
			type_pass = not achievement_data.melee_type or melee_type == achievement_data.melee_type
			result_pass = not achievement_data.result or attack_data.result.type == achievement_data.result
			enemy_pass = not achievement_data.enemy or enemy_type == achievement_data.enemy
			enemy_weapon_pass = not achievement_data.enemy_weapon or unit_weapon == achievement_data.enemy_weapon
			behind_pass = not achievement_data.from_behind or from_behind
			diff_pass = not achievement_data.difficulty or table_contains(achievement_data.difficulty, Global.game_settings.difficulty)
			health_pass = not achievement_data.health or health_ratio <= achievement_data.health
			level_pass = not achievement_data.level_id or (managers.job:current_level_id() or "") == achievement_data.level_id
			job_pass = not achievement_data.job or managers.job:current_real_job_id() == achievement_data.job
			jobs_pass = not achievement_data.jobs or table_contains(achievement_data.jobs, managers.job:current_real_job_id())
			enemy_count_pass = not achievement_data.enemy_kills or achievement_data.enemy_kills.count <= managers.statistics:session_enemy_killed_by_type(achievement_data.enemy_kills.enemy, "melee")
			tags_all_pass = not achievement_data.enemy_tags_all or enemy_base:has_all_tags(achievement_data.enemy_tags_all)
			tags_any_pass = not achievement_data.enemy_tags_any or enemy_base:has_any_tag(achievement_data.enemy_tags_any)
			cop_pass = not achievement_data.is_cop or is_cop
			gangster_pass = not achievement_data.is_gangster or is_gangster
			civilian_pass = not achievement_data.is_not_civilian or not is_civilian
			stealth_pass = not achievement_data.is_stealth or managers.groupai:state():whisper_mode()
			on_fire_pass = not achievement_data.is_on_fire or managers.fire:is_set_on_fire(self._unit)
			is_dropin_pass = achievement_data.is_dropin == nil or achievement_data.is_dropin == managers.statistics:is_dropin()

			if achievement_data.enemies then
				enemy_pass = false

				for _, enemy in pairs(achievement_data.enemies) do
					if enemy == enemy_type then
						enemy_pass = true

						break
					end
				end
			end

			mutators_pass = managers.mutators:check_achievements(achievement_data)
			critical_pass = not achievement_data.critical

			if achievement_data.critical then
				critical_pass = attack_data.critical_hit
			end

			action_pass = true

			if achievement_data.action then
				local action = enemy_movement:get_action(achievement_data.action.body_part)
				local action_type = action and action:type()
				action_pass = action_type == achievement_data.action.type
			end

			all_pass = melee_pass and melee_weapons_pass and type_pass and enemy_pass and enemy_weapon_pass and behind_pass and diff_pass and health_pass and level_pass and job_pass and jobs_pass and cop_pass and gangster_pass and civilian_pass and stealth_pass and on_fire_pass and enemy_count_pass and tags_all_pass and tags_any_pass and result_pass and mutators_pass and critical_pass and action_pass and is_dropin_pass

			if all_pass then
				if achievement_data.stat then
					managers.achievment:award_progress(achievement_data.stat)
				elseif achievement_data.award then
					managers.achievment:award(achievement_data.award)
				elseif achievement_data.challenge_stat then
					managers.challenge:award_progress(achievement_data.challenge_stat)
				elseif achievement_data.trophy_stat then
					managers.custom_safehouse:award(achievement_data.trophy_stat)
				elseif achievement_data.challenge_award then
					managers.challenge:award(achievement_data.challenge_award)
				end
			end
		end
	end
	
	if not attacker_unit or not alive(attacker_unit) or attacker_unit:id() == -1 then
		attack_data.attacker_unit = self._unit
	end

	local hit_offset_height = math_clamp(attack_data.col_ray.position.z - self._unit:position().z, 0, 300)
	local i_result = 0

	if snatch_pager then
		i_result = 3
	elseif result.type == "taser_tased" then
		i_result = 2
	elseif result.type == "healed" then
		i_result = 1
	end

	local body_index = self._unit:get_body_index(attack_data.col_ray.body:name())

	self:_send_melee_attack_result(attack_data, damage_percent, damage_effect_percent, hit_offset_height, i_result, body_index)
	self:_on_damage_received(attack_data)

	return result
end)

Hooks:OverrideFunction(CopDamage,"damage_fire",function(self,attack_data)
	if self._dead or self._invulnerable then
		return
	end
	local player_unit = managers.player:player_unit()
	local attacker_is_main_player = attack_data.attacker_unit == player_unit

	if self:is_friendly_fire(attack_data.attacker_unit) then
		return "friendly_fire"
	end

	if self:chk_immune_to_attacker(attack_data.attacker_unit) then
		return
	end

	local result
	local damage = attack_data.damage * (self._char_tweak.damage.fire_damage_mul or 1)
	local is_civilian = CopDamage.is_civilian(self._unit:base()._tweak_table)
	local head = self._head_body_name and attack_data.col_ray.body and attack_data.col_ray.body:name() == self._ids_head_body_name
	local headshot_multiplier = 1
	
	if attacker_is_main_player then
		local damage_scale

		if alive(attack_data.weapon_unit) and attack_data.weapon_unit:base() and attack_data.weapon_unit:base().is_weak_hit then
			damage_scale = attack_data.weapon_unit:base():is_weak_hit(attack_data.col_ray and attack_data.col_ray.distance, attack_data.attacker_unit) or 1
		end

		local critical_hit, crit_damage = self:roll_critical_hit(attack_data, damage)

		if critical_hit then
			damage = crit_damage
			attack_data.critical_hit = true
		end

		if attack_data.weapon_unit and attack_data.variant ~= "stun" then
			if critical_hit then
				managers.hud:on_crit_confirmed(damage_scale)
			else
				managers.hud:on_hit_confirmed(damage_scale)
			end
		end

		headshot_multiplier = managers.player:upgrade_value("weapon", "passive_headshot_damage_multiplier", 1)

		if managers.groupai:state():is_enemy_special(self._unit) then
			damage = damage * managers.player:upgrade_value("weapon", "special_damage_taken_multiplier", 1)
		end

		if head then
			managers.player:on_headshot_dealt()
		end
			
		
		--------------------------
		-- TCD: apply fire damage mul from Third Degree aced here
		-- (deal +25% more damage to enemies on fire)
		if managers.fire:is_set_on_fire(self._unit) then
			-- if attack_data.is_molotov then 
			damage = damage * managers.player:upgrade_value("subclass_areadenial", "effect_doubleroasting_damage_increase_mul", 1)
		end
		--------------------------
		
		
	end

	if not self._damage_reduction_multiplier and head then
		if self._char_tweak.headshot_dmg_mul then
			damage = damage * self._char_tweak.headshot_dmg_mul * headshot_multiplier
		else
			damage = self._health * 10
		end
	end
	
	damage = self:_apply_damage_reduction(damage)
	damage = math.clamp(damage, 0, self._HEALTH_INIT)

	local damage_percent = math.ceil(damage / self._HEALTH_INIT_PRECENT)

	damage = damage_percent * self._HEALTH_INIT_PRECENT
	damage, damage_percent = self:_apply_min_health_limit(damage, damage_percent)

	if self._immortal then
		damage = math.min(damage, self._health - 1)
	end

	if damage >= self._health then
		if self:check_medic_heal() then
			result = {
				type = "healed",
				variant = attack_data.variant
			}
		else
			attack_data.damage = self._health
			result = {
				type = "death",
				variant = attack_data.variant
			}

			self:die(attack_data)
			self:chk_killshot(attack_data.attacker_unit, "fire", head, attack_data.weapon_unit and attack_data.weapon_unit:base():get_name_id())
		end
	else
		attack_data.damage = damage

		local result_type = "dmg_rcv"

		result = {
			type = result_type,
			variant = attack_data.variant
		}

		self:_apply_damage_to_health(damage)
	end

	attack_data.result = result
	attack_data.pos = attack_data.col_ray.position

	local attacker = attack_data.attacker_unit

	if not alive(attacker) or attacker:id() == -1 then
		attacker = self._unit
	end

	local attacker_unit = attack_data.attacker_unit

	if result.type == "death" then
		local data = {
			name = self._unit:base()._tweak_table,
			stats_name = self._unit:base()._stats_name,
			owner = attack_data.owner,
			weapon_unit = attack_data.weapon_unit,
			variant = attack_data.variant,
			head_shot = head,
			is_molotov = attack_data.is_molotov
		}

		managers.statistics:killed_by_anyone(data)

		if not is_civilian and managers.player:has_category_upgrade("temporary", "overkill_damage_multiplier") and attacker_unit == managers.player:player_unit() and alive(attack_data.weapon_unit) and not attack_data.weapon_unit:base().thrower_unit and attack_data.weapon_unit:base().is_category and attack_data.weapon_unit:base():is_category("shotgun", "saw") then
			managers.player:activate_temporary_upgrade("temporary", "overkill_damage_multiplier")
		end

		if attacker_unit and alive(attacker_unit) and attacker_unit:base() and attacker_unit:base().thrower_unit then
			attacker_unit = attacker_unit:base():thrower_unit()
			data.weapon_unit = attack_data.attacker_unit
		end

		if attacker_unit == managers.player:player_unit() then
			if alive(attacker_unit) then
				self:_comment_death(attacker_unit, self._unit)
			end

			self:_show_death_hint(self._unit:base()._tweak_table)
			managers.statistics:killed(data)

			if is_civilian then
				managers.money:civilian_killed()
			end

			self:_check_damage_achievements(attack_data, false)
		end
	end

	local weapon_unit = attack_data.weapon_unit or attacker

	if alive(weapon_unit) and weapon_unit:base() and weapon_unit:base().add_damage_result then
		weapon_unit:base():add_damage_result(self._unit, result.type == "death", damage_percent)
	end

	local i_result = self._result_type_to_idx.fire[result.type] or 0

	self:_send_fire_attack_result(attack_data, attacker, damage_percent, attack_data.col_ray.ray, i_result)
	self:_on_damage_received(attack_data)

	if not is_civilian and attack_data.attacker_unit and alive(attack_data.attacker_unit) then
		managers.player:send_message(Message.OnEnemyShot, nil, self._unit, attack_data)
	end

	result.attack_data = attack_data

	return result
end)

Hooks:OverrideFunction(CopDamage,"damage_tase",function(self,attack_data)
	if self._dead or self._invulnerable then
		return
	end

	local attacker_unit = attack_data.attacker_unit
	
	if PlayerDamage.is_friendly_fire(self, attacker_unit) then
		return "friendly_fire"
	end

	if self:chk_immune_to_attacker(attacker_unit) then
		return
	end
	
	local weap_unit = attack_data.weapon_unit
	local damage = attack_data.damage
	local player_unit = managers.player:local_player()
	local attacker_is_player = alive(player_unit) and attacker_unit == player_unit
	
	if attacker_is_player then
		local critical_hit, crit_damage = self:roll_critical_hit(attack_data, damage)

		if critical_hit then
			damage = crit_damage
		end

		if attack_data.weapon_unit then
			if critical_hit then
				managers.hud:on_crit_confirmed()
			else
				managers.hud:on_hit_confirmed()
			end
		end
	end
	
	damage = damage * self:_get_incoming_damage_multiplier(1)

	if managers.fire:is_set_on_fire(self._unit) then
		local third_degree_dmg_mul = 1
		local attacker_base_ext = alive(attacker_unit) and attacker_unit:base()

		if attacker_base_ext then
			if attacker_base_ext.is_local_player then
				third_degree_dmg_mul = managers.player:upgrade_value("subclass_areadenial", "effect_doubleroasting_damage_increase_mul", 1)
			elseif attacker_base_ext.is_husk_player then
				third_degree_dmg_mul = attacker_base_ext:upgrade_value("subclass_areadenial", "effect_doubleroasting_damage_increase_mul") or 1
			end
		end

		if third_degree_dmg_mul > 1 then
			damage = damage * third_degree_dmg_mul
		end
	end

	damage = self:_apply_damage_reduction(damage)

	attack_data.raw_damage = damage

	damage = math_clamp(damage, 0, self._HEALTH_INIT)
	local damage_percent = math_ceil(damage / self._HEALTH_INIT_PRECENT)
	damage = damage_percent * self._HEALTH_INIT_PRECENT
	damage, damage_percent = self:_apply_min_health_limit(damage, damage_percent)

	if self._immortal then
		damage = math_min(damage, self._health - 1)
	end

	local result, tase_variant = nil
	local is_civilian = CopDamage.is_civilian(self._unit:base()._tweak_table)
	local is_gangster = CopDamage.is_gangster(self._unit:base()._tweak_table)
	local is_cop = not is_civilian and not is_gangster
	local head = self._head_body_name and attack_data.col_ray.body and attack_data.col_ray.body:name() == self._ids_head_body_name

	if self._health <= damage then
		attack_data.damage = self._health
		attack_data.variant = "bullet"

		if self:check_medic_heal() then
			result = {
				type = "healed",
				variant = attack_data.variant
			}
		else
			result = {
				variant = "bullet",
				type = "death"
			}

			self:die(attack_data)
			self:chk_killshot(attacker_unit, "tase", false, attack_data.name_id)
		end
	else
		attack_data.damage = damage

		local result_type = "dmg_rcv"

		if not alive(managers.groupai:state():phalanx_vip()) then
			if self._char_tweak.damage.hurt_severity.tase == nil or self._char_tweak.damage.hurt_severity.tase then
				if weap_unit and attacker_is_player then
					managers.hud:on_hit_confirmed()
				end

				result_type = "taser_tased"

				self._tased_time = 5
				self._tased_down_time = 10

				local tased_response = self._char_tweak.damage.tased_response

				if tased_response then
					if attack_data.variant == "heavy" and tased_response.heavy then
						self._tased_time = tased_response.heavy.tased_time
						self._tased_down_time = tased_response.heavy.down_time
						tase_variant = "heavy"
					elseif tased_response.light then
						self._tased_time = tased_response.light.tased_time
						self._tased_down_time = tased_response.light.down_time
						tase_variant = "light"
					end
				end
			end
		end

		attack_data.variant = "bullet"

		result = {
			type = result_type,
			variant = attack_data.variant
		}

		self:_apply_damage_to_health(damage)
	end

	attack_data.result = result
	attack_data.pos = attack_data.col_ray.position

	if result.type == "death" then
		local head = nil

		if self._head_body_name then
			head = attack_data.col_ray and attack_data.col_ray.body and self._head_body_key and attack_data.col_ray.body:key() == self._head_body_key
			local body = self._unit:body(self._head_body_name)
			local dir_vec = head and attack_data.col_ray.ray or body:rotation():y()

			self:_spawn_head_gadget({
				position = body:position(),
				rotation = body:rotation(),
				skip_push = not head,
				dir = dir_vec
			})
		end
	
		local data = {
			name = self._unit:base()._tweak_table,
			stats_name = self._unit:base()._stats_name,
			head_shot = head,
			weapon_unit = weap_unit,
			owner = attack_data.owner,
			name_id = attack_data.name_id,
			variant = "bullet" -- attack_data.variant
		}

		managers.statistics:killed_by_anyone(data)

		if attacker_is_player then
			if alive(attacker_unit) then
				self:_comment_death(attacker_unit, self._unit)
			end

			self:_show_death_hint(self._unit:base()._tweak_table)
			managers.statistics:killed(data)

			if not is_civlian and managers.groupai:state():whisper_mode() and managers.blackmarket:equipped_mask().mask_id == tweak_data.achievement.cant_hear_you_scream.mask then
				managers.achievment:award_progress(tweak_data.achievement.cant_hear_you_scream.stat)
			end
			
			mvector3.set(mvec_1, self._unit:position())
			mvector3.subtract(mvec_1, attack_data.attacker_unit:position())
			mvector3.normalize(mvec_1)
			mvector3.set(mvec_2, self._unit:rotation():y())

			local from_behind = mvector3.dot(mvec_1, mvec_2) >= 0

			if is_cop and Global.game_settings.level_id == "nightclub" and attack_data.name_id and attack_data.name_id == "fists" then
				managers.achievment:award_progress(tweak_data.achievement.final_rule.stat)
			end
			
			if is_civlian then
				managers.money:civilian_killed()
			end
			-- removed unused snatch pager chance code

			self:_check_damage_achievements(attack_data, false)
		elseif alive(attacker_unit) and managers.groupai:state():is_unit_team_AI(attacker_unit) then
			self:_comment_death(attacker_unit, self._unit)
		end
	end
	
	--self:_check_melee_achievements(attack_data)

	if not attacker_unit or not alive(attacker_unit) or attacker_unit:id() == -1 then
		attack_data.attacker_unit = self._unit
	end

	local i_result = nil

	if result.type == "taser_tased" then
		if tase_variant == "heavy" then
			i_result = 1
		elseif tase_variant == "light" then
			i_result = 2
		else
			i_result = 3
		end
	elseif result.type == "healed" then
		i_result = 4
	else
		i_result = 0
	end

	self:_send_tase_attack_result(attack_data, damage_percent, i_result)
	self:_on_damage_received(attack_data)
	
	result.attack_data = attack_data
	
	return result
end)

Hooks:OverrideFunction(CopDamage,"damage_explosion",function(self,attack_data)
	if self._dead or self._invulnerable then
		return
	end

	if self:chk_immune_to_attacker(attack_data.attacker_unit) then
		return
	end

	local is_civilian = CopDamage.is_civilian(self._unit:base()._tweak_table)
	local result
	local damage = attack_data.damage

	damage = managers.modifiers:modify_value("CopDamage:DamageExplosion", damage, self._unit)

	if self._unit:base():char_tweak().DAMAGE_CLAMP_EXPLOSION then
		damage = math.min(damage, self._unit:base():char_tweak().DAMAGE_CLAMP_EXPLOSION)
	end

	damage = damage * (self._char_tweak.damage.explosion_damage_mul or 1)
	damage = damage * (self._marked_dmg_mul or 1)

	if attack_data.attacker_unit == managers.player:player_unit() then
		local critical_hit, crit_damage = self:roll_critical_hit(attack_data, damage)

		if critical_hit then
			damage = crit_damage
		end

		if attack_data.weapon_unit and attack_data.variant ~= "stun" then
			if critical_hit then
				managers.hud:on_crit_confirmed()
			else
				managers.hud:on_hit_confirmed()
			end
		end
		
		--------------------------
		-- TCD: apply fire damage mul from Third Degree aced here
		-- (deal +25% more damage to enemies on fire)
		if managers.fire:is_set_on_fire(self._unit) then
			-- if attack_data.is_molotov then 
			damage = damage * managers.player:upgrade_value("subclass_areadenial", "effect_doubleroasting_damage_increase_mul", 1)
		end
		--------------------------
	end

	damage = self:_apply_damage_reduction(damage)
	damage = math.clamp(damage, 0, self._HEALTH_INIT)

	local damage_percent = math.ceil(damage / self._HEALTH_INIT_PRECENT)

	damage = damage_percent * self._HEALTH_INIT_PRECENT
	damage, damage_percent = self:_apply_min_health_limit(damage, damage_percent)

	if self._immortal then
		damage = math.min(damage, self._health - 1)
	end

	if damage >= self._health then
		if self:check_medic_heal() then
			attack_data.variant = "healed"
			result = {
				type = "healed",
				variant = attack_data.variant
			}
		else
			attack_data.damage = self._health
			result = {
				type = "death",
				variant = attack_data.variant
			}

			self:die(attack_data)
		end
	else
		attack_data.damage = damage

		local result_type = attack_data.variant == "stun" and "hurt_sick" or self:get_damage_type(damage_percent, "explosion")

		result = {
			type = result_type,
			variant = attack_data.variant
		}

		self:_apply_damage_to_health(damage)
	end

	attack_data.result = result
	attack_data.pos = attack_data.col_ray.position

	local head

	if result.type == "death" and self._head_body_name and attack_data.variant ~= "stun" then
		head = attack_data.col_ray.body and self._head_body_key and attack_data.col_ray.body:key() == self._head_body_key

		local body = self._unit:body(self._head_body_name)

		self:_spawn_head_gadget({
			position = body:position(),
			rotation = body:rotation(),
			dir = -attack_data.col_ray.ray
		})
	end

	local attacker = attack_data.attacker_unit

	if not attacker or attacker:id() == -1 then
		attacker = self._unit
	end

	if result.type == "death" then
		local data = {
			name = self._unit:base()._tweak_table,
			stats_name = self._unit:base()._stats_name,
			owner = attack_data.owner,
			weapon_unit = attack_data.weapon_unit,
			variant = attack_data.variant,
			head_shot = head
		}

		managers.statistics:killed_by_anyone(data)

		local attacker_unit = attack_data.attacker_unit

		if attacker_unit and attacker_unit:base() and attacker_unit:base().thrower_unit then
			attacker_unit = attacker_unit:base():thrower_unit()
			data.weapon_unit = attack_data.attacker_unit
		end

		if not is_civilian and managers.player:has_category_upgrade("temporary", "overkill_damage_multiplier") and attacker_unit == managers.player:player_unit() and attack_data.weapon_unit and attack_data.weapon_unit:base().weapon_tweak_data and not attack_data.weapon_unit:base().thrower_unit and attack_data.weapon_unit:base():is_category("shotgun", "saw") then
			managers.player:activate_temporary_upgrade("temporary", "overkill_damage_multiplier")
		end

		self:chk_killshot(attacker_unit, "explosion", false, attack_data.weapon_unit and attack_data.weapon_unit:base():get_name_id())

		if attacker_unit == managers.player:player_unit() then
			if alive(attacker_unit) then
				self:_comment_death(attacker_unit, self._unit)
			end

			self:_show_death_hint(self._unit:base()._tweak_table)
			managers.statistics:killed(data)

			if is_civilian then
				managers.money:civilian_killed()
			end

			self:_check_damage_achievements(attack_data, false)
		end
	end

	local weapon_unit = attack_data.weapon_unit

	if alive(weapon_unit) and weapon_unit:base() and weapon_unit:base().add_damage_result then
		weapon_unit:base():add_damage_result(self._unit, result.type == "death", attacker, damage_percent)
	end

	if not self._no_blood then
		managers.game_play_central:sync_play_impact_flesh(attack_data.pos, attack_data.col_ray.ray)
	end

	self:_send_explosion_attack_result(attack_data, attacker, damage_percent, self:_get_attack_variant_index(attack_data.result.variant), attack_data.col_ray.ray)
	self:_on_damage_received(attack_data)

	if not is_civilian and attack_data.attacker_unit and alive(attack_data.attacker_unit) then
		managers.player:send_message(Message.OnEnemyShot, nil, self._unit, attack_data)
	end

	return result
end)

Hooks:OverrideFunction(CopDamage,"damage_dot",function(self,attack_data)
	if self._dead or self._invulnerable then
		return
	end

	if self:chk_immune_to_attacker(attack_data.attacker_unit) then
		return
	end

	local result
	local damage = attack_data.damage

	--------------------------
	-- TCD: apply fire damage mul from Third Degree aced here
	-- (deal +25% more damage to enemies on fire)
	if managers.fire:is_set_on_fire(self._unit) then
		-- if attack_data.is_molotov then 
		damage = damage * managers.player:upgrade_value("subclass_areadenial", "effect_doubleroasting_damage_increase_mul", 1)
	end
	--------------------------
	
	damage = self:_apply_damage_reduction(damage)
	damage = math.clamp(damage, 0, self._HEALTH_INIT)

	local damage_percent = math.ceil(damage / self._HEALTH_INIT_PRECENT)

	damage = damage_percent * self._HEALTH_INIT_PRECENT
	damage, damage_percent = self:_apply_min_health_limit(damage, damage_percent)

	if self._immortal then
		damage = math.min(damage, self._health - 1)
	end

	if damage >= self._health then
		if self:check_medic_heal() then
			result = {
				type = "healed",
				variant = attack_data.variant
			}
		else
			attack_data.damage = self._health
			result = {
				type = "death",
				variant = attack_data.variant
			}

			self:die(attack_data)
			self:chk_killshot(attack_data.attacker_unit, attack_data.variant or "poison", nil, attack_data.weapon_id)
		end
	else
		attack_data.damage = damage

		local result_type = attack_data.hurt_animation and self:get_damage_type(damage_percent, attack_data.variant) or "dmg_rcv"

		result = {
			type = result_type,
			variant = attack_data.variant
		}

		self:_apply_damage_to_health(damage)
	end

	attack_data.result = result
	attack_data.pos = attack_data.col_ray.position

	local head = self._head_body_name and attack_data.col_ray.body and attack_data.col_ray.body:name() == self._ids_head_body_name
	local attacker = attack_data.attacker_unit

	if not attacker or attacker:id() == -1 then
		attacker = self._unit
	end

	local attacker_unit = attack_data.attacker_unit

	if result.type == "death" then
		local variant = attack_data.weapon_id and tweak_data.blackmarket and tweak_data.blackmarket.melee_weapons and tweak_data.blackmarket.melee_weapons[attack_data.weapon_id] and "melee" or attack_data.variant
		local data = {
			name = self._unit:base()._tweak_table,
			stats_name = self._unit:base()._stats_name,
			owner = attack_data.owner,
			weapon_unit = attack_data.weapon_unit,
			variant = variant,
			head_shot = head,
			weapon_id = attack_data.weapon_id,
			is_molotov = attack_data.is_molotov
		}

		managers.statistics:killed_by_anyone(data)

		if attacker_unit == managers.player:player_unit() then
			if alive(attacker_unit) then
				self:_comment_death(attacker_unit, self._unit)
			end

			self:_show_death_hint(self._unit:base()._tweak_table)
			managers.statistics:killed(data)

			local is_civilian = CopDamage.is_civilian(self._unit:base()._tweak_table)

			if is_civilian then
				managers.money:civilian_killed()
			end

			if attack_data and attack_data.weapon_id and not attack_data.weapon_unit then
				attack_data.name_id = attack_data.weapon_id

				self:_check_melee_achievements(attack_data)
			else
				self:_check_damage_achievements(attack_data, false)

				if not is_civilian and managers.player:has_category_upgrade("temporary", "overkill_damage_multiplier") and not attack_data.weapon_unit:base().thrower_unit and attack_data.weapon_unit:base():is_category("shotgun", "saw") then
					managers.player:activate_temporary_upgrade("temporary", "overkill_damage_multiplier")
				end
			end
		end
	end

	local i_dot_variant = self._variant_to_idx.dot[attack_data.variant] or 0
	local i_result = self._result_type_to_idx.dot[result.type] or 0

	self:_send_dot_attack_result(attack_data, attacker, damage_percent, i_dot_variant, i_result)
	self:_on_damage_received(attack_data)

	result.attack_data = attack_data
	result.damage_percent = damage_percent
	result.damage = damage

	return result
end)


-- sig diff; network sync change is in damagesyncing.xml -offy
Hooks:OverrideFunction(CopDamage,"sync_damage_tase",function(self, attacker_unit, damage_percent, i_result, death)
	if self._dead then
		return
	end

	local attack_data = {
		attacker_unit = attacker_unit,
		variant = "bullet"
	}

	local hit_pos = mvec3_cpy(self._unit:position())
	mvec3_set_z(hit_pos, hit_pos.z + 100)

	local attack_dir, result = nil

	if attacker_unit then
		local from_pos = nil

		if attacker_unit:movement() and attacker_unit:movement().m_head_pos then
			from_pos = attacker_unit:movement():m_head_pos()
		else
			from_pos = attacker_unit:position()
		end

		attack_dir = hit_pos - from_pos
		mvec3_norm(attack_dir)
	else
		attack_dir = -self._unit:rotation():y()
	end

	attack_data.attack_dir = attack_dir
	hit_pos = hit_pos - attack_dir * 5
	attack_data.pos = hit_pos

	local damage = damage_percent * self._HEALTH_INIT_PRECENT
	attack_data.damage = damage

	if death then
		attack_data.damage = self._health

		result = {
			variant = "bullet",
			type = "death"
		}

		self:die(attack_data)
		self:chk_killshot(attacker_unit, "tase")

		local data = {
			variant = "bullet",
			name = self._unit:base()._tweak_table,
			stats_name = self._unit:base()._stats_name,
			weapon_unit = attacker_unit and attacker_unit:inventory() and attacker_unit:inventory():equipped_unit(),
		}

		managers.statistics:killed_by_anyone(data)
	else
		local result_type = "dmg_rcv"

		if i_result == 4 then
			attack_data.damage = self._health
			result_type = "healed"
		else
			self:_apply_damage_to_health(damage)

			if i_result == 1 then
				result_type = "taser_tased"
				self._tased_time = self._char_tweak.damage.tased_response.heavy.tased_time
				self._tased_down_time = self._char_tweak.damage.tased_response.heavy.down_time
			elseif i_result == 2 then
				result_type = "taser_tased"
				self._tased_time = self._char_tweak.damage.tased_response.light.tased_time
				self._tased_down_time = self._char_tweak.damage.tased_response.light.down_time
			elseif i_result == 3 then
				result_type = "taser_tased"
				self._tased_time = 5
				self._tased_down_time = 10
			end
		end

		result = {
			type = result_type,
			variant = "bullet"
		}

		self:_apply_damage_to_health(damage)
	end

	attack_data.result = result
	attack_data.is_synced = true

	self:_on_damage_received(attack_data)
end)


-- allow overriding explosive damage resistance through Demolitions tree's Tankbuster
Hooks:OverrideFunction(CopDamage,"damage_explosion",function(self, attack_data)
	if self._dead or self._invulnerable then
		return
	end

	if self:chk_immune_to_attacker(attack_data.attacker_unit) then
		return
	end

	local is_civilian = CopDamage.is_civilian(self._unit:base()._tweak_table)
	local result
	local damage = attack_data.damage

	damage = managers.modifiers:modify_value("CopDamage:DamageExplosion", damage, self._unit)
	
	-- CD changes below
	local chartweak_damage_mul = self._char_tweak.damage.explosion_damage_mul or 1
	if attack_data.attacker_unit == managers.player:player_unit() then
		-- override damage from Demolition tree's Tankbuster
		if chartweak_damage_mul < 1 then
			chartweak_damage_mul = managers.player:upgrade_value("class_specialist","negate_enemy_explosive_resistance",chartweak_damage_mul)
		end
	end
--	if attack_data.vuln_override and chartweak_damage_mul < 1 then
--		chartweak_damage_mul = managers.player:upgrade_value_by_level("class_specialist","negate_enemy_explosive_resistance",attack_data.vuln_override,chartweak_damage_mul)
--	end
	damage = damage * chartweak_damage_mul
	-- CD changes above
	
	if self._unit:base():char_tweak().DAMAGE_CLAMP_EXPLOSION then
		damage = math.min(damage, self._unit:base():char_tweak().DAMAGE_CLAMP_EXPLOSION)
	end
	
	
	damage = damage * (self._marked_dmg_mul or 1)

	if attack_data.attacker_unit == managers.player:player_unit() then
		local critical_hit, crit_damage = self:roll_critical_hit(attack_data, damage)

		if critical_hit then
			damage = crit_damage
		end

		if attack_data.weapon_unit and attack_data.variant ~= "stun" then
			if critical_hit then
				managers.hud:on_crit_confirmed()
			else
				managers.hud:on_hit_confirmed()
			end
		end
	end

	damage = self:_apply_damage_reduction(damage)
	damage = math.clamp(damage, 0, self._HEALTH_INIT)

	local damage_percent = math.ceil(damage / self._HEALTH_INIT_PRECENT)

	damage = damage_percent * self._HEALTH_INIT_PRECENT
	damage, damage_percent = self:_apply_min_health_limit(damage, damage_percent)

	if self._immortal then
		damage = math.min(damage, self._health - 1)
	end

	if damage >= self._health then
		if self:check_medic_heal() then
			attack_data.variant = "healed"
			result = {
				type = "healed",
				variant = attack_data.variant
			}
		else
			attack_data.damage = self._health
			result = {
				type = "death",
				variant = attack_data.variant
			}

			self:die(attack_data)
		end
	else
		attack_data.damage = damage

		local result_type = attack_data.variant == "stun" and "hurt_sick" or self:get_damage_type(damage_percent, "explosion")

		result = {
			type = result_type,
			variant = attack_data.variant
		}

		self:_apply_damage_to_health(damage)
	end

	attack_data.result = result
	attack_data.pos = attack_data.col_ray.position

	local head

	if result.type == "death" and self._head_body_name and attack_data.variant ~= "stun" then
		head = attack_data.col_ray.body and self._head_body_key and attack_data.col_ray.body:key() == self._head_body_key

		local body = self._unit:body(self._head_body_name)

		self:_spawn_head_gadget({
			position = body:position(),
			rotation = body:rotation(),
			dir = -attack_data.col_ray.ray
		})
	end

	local attacker = attack_data.attacker_unit

	if not attacker or attacker:id() == -1 then
		attacker = self._unit
	end

	if result.type == "death" then
		local data = {
			name = self._unit:base()._tweak_table,
			stats_name = self._unit:base()._stats_name,
			owner = attack_data.owner,
			weapon_unit = attack_data.weapon_unit,
			variant = attack_data.variant,
			head_shot = head
		}

		managers.statistics:killed_by_anyone(data)

		local attacker_unit = attack_data.attacker_unit

		if attacker_unit and attacker_unit:base() and attacker_unit:base().thrower_unit then
			attacker_unit = attacker_unit:base():thrower_unit()
			data.weapon_unit = attack_data.attacker_unit
		end

		if not is_civilian and managers.player:has_category_upgrade("temporary", "overkill_damage_multiplier") and attacker_unit == managers.player:player_unit() and attack_data.weapon_unit and attack_data.weapon_unit:base().weapon_tweak_data and not attack_data.weapon_unit:base().thrower_unit and attack_data.weapon_unit:base():is_category("shotgun", "saw") then
			managers.player:activate_temporary_upgrade("temporary", "overkill_damage_multiplier")
		end

		self:chk_killshot(attacker_unit, "explosion", false, attack_data.weapon_unit and attack_data.weapon_unit:base():get_name_id())

		if attacker_unit == managers.player:player_unit() then
			if alive(attacker_unit) then
				self:_comment_death(attacker_unit, self._unit)
			end

			self:_show_death_hint(self._unit:base()._tweak_table)
			managers.statistics:killed(data)

			if is_civilian then
				managers.money:civilian_killed()
			end

			self:_check_damage_achievements(attack_data, false)
		end
	end

	local weapon_unit = attack_data.weapon_unit

	if alive(weapon_unit) and weapon_unit:base() and weapon_unit:base().add_damage_result then
		weapon_unit:base():add_damage_result(self._unit, result.type == "death", attacker, damage_percent)
	end

	if not self._no_blood then
		managers.game_play_central:sync_play_impact_flesh(attack_data.pos, attack_data.col_ray.ray)
	end

	self:_send_explosion_attack_result(attack_data, attacker, damage_percent, self:_get_attack_variant_index(attack_data.result.variant), attack_data.col_ray.ray)
	self:_on_damage_received(attack_data)

	if not is_civilian and attack_data.attacker_unit and alive(attack_data.attacker_unit) then
		managers.player:send_message(Message.OnEnemyShot, nil, self._unit, attack_data)
	end

	return result
end)


