local mvec3_dis_sq = mvector3.distance_sq
local mvec3_set = mvector3.set
local mvec3_set_z = mvector3.set_z
local mvec3_sub = mvector3.subtract
local mvec3_add = mvector3.add
local mvec3_mul = mvector3.multiply
local mvec3_norm = mvector3.normalize
local mvec3_cpy = mvector3.copy
local mvec3_dir = mvector3.direction	
local tmp_ground_from_vec = Vector3()
local tmp_ground_to_vec = Vector3()
local up_offset_vec = math.UP * 30
local down_offset_vec = math.UP * -40

local mvec_pos_new = Vector3()
local mvec_achieved_walk_vel = Vector3()
local mvec_move_dir_normalized = Vector3()

local tmp_vec = Vector3()

local world_g = World
local alive_g = alive

local ai_vision_ids = Idstring("ai_vision")

local melee_vars = {
	"player_melee",
	"player_melee_var2"
}

-- Zip It Aced- AOE intimidation shout
function PlayerStandard:_get_intimidation_action(prime_target, char_table, amount, primary_only, detect_only, secondary)
	local voice_type, new_action, plural = nil
	local unit_type_enemy = 0
	local unit_type_civilian = 1
	local unit_type_teammate = 2
	local unit_type_camera = 3
	local unit_type_turret = 4
	local is_whisper_mode = managers.groupai:state():whisper_mode()

	if prime_target then
		if prime_target.unit_type == unit_type_teammate then
			local is_human_player, record = nil

			if not detect_only then
				record = managers.groupai:state():all_criminals()[prime_target.unit:key()]

				if record.ai then
					if not prime_target.unit:brain():player_ignore() then
						prime_target.unit:movement():set_cool(false)
						prime_target.unit:brain():on_long_dis_interacted(0, self._unit, secondary)
					end
				else
					is_human_player = true
				end
			end

			local amount = 0

			if not secondary then
				local current_state_name = self._unit:movement():current_state_name()

				if current_state_name ~= "arrested" and current_state_name ~= "bleed_out" and current_state_name ~= "fatal" and current_state_name ~= "incapacitated" then
					local rally_skill_data = self._ext_movement:rally_skill_data()

					if rally_skill_data and mvec3_dis_sq(self._pos, record.m_pos) < rally_skill_data.range_sq then
						local needs_revive, is_arrested = nil

						if prime_target.unit:base().is_husk_player then
							is_arrested = prime_target.unit:movement():current_state_name() == "arrested"
							needs_revive = prime_target.unit:interaction():active() and prime_target.unit:movement():need_revive() and not is_arrested
						else
							is_arrested = prime_target.unit:character_damage():arrested()
							needs_revive = prime_target.unit:character_damage():need_revive()
						end

						if needs_revive and managers.player:has_enabled_cooldown_upgrade("cooldown", "long_dis_revive") then
							voice_type = "revive"

							managers.player:disable_cooldown_upgrade("cooldown", "long_dis_revive")
						elseif is_human_player and not is_arrested and not needs_revive and rally_skill_data.morale_boost_delay_t and rally_skill_data.morale_boost_delay_t < managers.player:player_timer():time() then
							voice_type = "boost"
							amount = 1
						end
					end
				end
			end

			if is_human_player then
				prime_target.unit:network():send_to_unit({
					"long_dis_interaction",
					prime_target.unit,
					amount,
					self._unit,
					secondary or false
				})
			end

			voice_type = voice_type or secondary and "ai_stay" or "come"
			plural = false
		else
			local prime_target_key = prime_target.unit:key()

			if prime_target.unit_type == unit_type_enemy then
				plural = false

				if prime_target.unit:anim_data().hands_back then
					voice_type = "cuff_cop"
				elseif prime_target.unit:anim_data().surrender then
					voice_type = "down_cop"
				elseif is_whisper_mode and prime_target.unit:movement():cool() and prime_target.unit:base():char_tweak().silent_priority_shout then
					voice_type = "mark_cop_quiet"
				elseif prime_target.unit:base():char_tweak().priority_shout then
					voice_type = "mark_cop"
				else
					voice_type = "stop_cop"
				end
			elseif prime_target.unit_type == unit_type_camera then
				plural = false
				voice_type = "mark_camera"
			elseif prime_target.unit_type == unit_type_turret then
				plural = false
				voice_type = "mark_turret"
			elseif prime_target.unit:base():char_tweak().is_escort then
				plural = false
				local e_guy = prime_target.unit

				if e_guy:anim_data().move or e_guy:anim_data().standing_hesitant then
					voice_type = "escort_keep"
				elseif e_guy:anim_data().panic then
					voice_type = "escort_go"
				else
					voice_type = prime_target.unit:base():char_tweak().speech_escort or "escort"
				end
			else
				if prime_target.unit:anim_data().drop then
					voice_type = "down_stay"
				elseif prime_target.unit:anim_data().tied or prime_target.unit:movement():stance_name() == "cbt" then
					voice_type = "come"
				elseif prime_target.unit:anim_data().move then
					voice_type = "stop"
				else
					voice_type = "down"
				end

				local num_affected = 0

				if voice_type ~= "come" then
					for _, char in pairs(char_table) do
						if char.unit_type == unit_type_civilian then
							if voice_type == "stop" and char.unit:anim_data().move then
								num_affected = num_affected + 1
							elseif voice_type == "down_stay" and char.unit:anim_data().drop then
								num_affected = num_affected + 1
							elseif voice_type == "down" and not char.unit:anim_data().move and not char.unit:anim_data().drop then
								num_affected = num_affected + 1
							end

							if num_affected > 1 then
								break
							end
						end
					end
				end

				if num_affected > 1 then
					plural = true
				else
					plural = false
				end
			end

			if detect_only then
				voice_type = "come"
			else
				local max_inv_wgt = 0

				for _, char in pairs(char_table) do
					if max_inv_wgt < char.inv_wgt then
						max_inv_wgt = char.inv_wgt
					end
				end

				if max_inv_wgt < 1 then
					max_inv_wgt = 1
				end

				amount = amount or tweak_data.player.long_dis_interaction.intimidate_strength
				local amount_civ = amount * managers.player:upgrade_value("player", "civ_intimidation_mul", 1) * managers.player:team_upgrade_value("player", "civ_intimidation_mul", 1)

				for _, char in pairs(char_table) do
					if char.unit_type ~= unit_type_camera and char.unit_type ~= unit_type_teammate and (not is_whisper_mode or not char.unit:movement():cool()) then
						local int_amount = char.unit_type == unit_type_civilian and amount_civ or amount

						if prime_target_key == char.unit:key() then
							voice_type = char.unit:brain():on_intimidated(int_amount, self._unit) or voice_type
						elseif not primary_only and char.unit_type ~= unit_type_enemy then
							char.unit:brain():on_intimidated(int_amount * char.inv_wgt / max_inv_wgt, self._unit)
						end
					end
				end
				
				-- tcd intimidate aoe
				-- (this chunk is the only change)
				local aoe_intimidation_radius = managers.player:upgrade_value("player", "shout_intimidation_aoe", 0)

				if aoe_intimidation_radius > 0 then
					local target_unit = prime_target.unit
					--target unit will be ignored by the search
					local aoe_civs = target_unit:find_units_quick("sphere", target_unit:position(), aoe_intimidation_radius, managers.slot:get_mask("civilians"))

					for i = 1, #aoe_civs do
						local aoe_civ = aoe_civs[i]

						if not is_whisper_mode or not aoe_civ:movement():cool() then
							if not aoe_civ:anim_data().long_dis_interact_disabled then
								aoe_civ:brain():on_intimidated(amount_civ, self._unit)
							end
						end
					end
				end
				--
				
			end
		end
	end

	return voice_type, plural, prime_target
end


--not to be confused with _do_action_melee()
function PlayerStandard:_do_melee_damage(t, bayonet_melee, melee_hit_ray, melee_entry, hand_id, force_max_charge,skip_shaker)
	melee_entry = melee_entry or managers.blackmarket:equipped_melee_weapon()
	local melee_td = tweak_data.blackmarket.melee_weapons[melee_entry]
	local instant_hit = melee_td.instant
	local melee_damage_delay = melee_td.melee_damage_delay or 0
	local charge_lerp_value = instant_hit and 0 or force_max_charge and 1 or self:_get_melee_charge_lerp_value(t, melee_damage_delay)
	if not skip_shaker then
		self._ext_camera:play_shaker(melee_vars[math.random(#melee_vars)], math.max(0.3, charge_lerp_value))
	end
	local sphere_cast_radius = 20
	local col_ray = nil

	if melee_hit_ray and not self._lunge_data then
		col_ray = melee_hit_ray ~= true and melee_hit_ray or nil
	else
		col_ray = self:_calc_melee_hit_ray(t, sphere_cast_radius)
	end
	
	self._lunge_data = nil
	
	if col_ray and alive(col_ray.unit) then
		local damage, damage_effect = managers.blackmarket:equipped_melee_weapon_damage_info(charge_lerp_value)
		local damage_effect_mul = math.max(managers.player:upgrade_value("player", "melee_knockdown_mul", 1), managers.player:upgrade_value(self._equipped_unit:base():weapon_tweak_data().categories and self._equipped_unit:base():weapon_tweak_data().categories[1], "melee_knockdown_mul", 1))
		damage = damage * managers.player:get_melee_dmg_multiplier()
--		if mark_enemy_on_hit then 
		if melee_td.random_damage_mul then 
			--because the above function is probably meant to be a constant, 
			--calculate random damage multiplier here (currently only used by jackpot lever)
			damage = damage * melee_td.random_damage_mul[#melee_td.random_damage_mul]
		end
		
		damage_effect = damage_effect * damage_effect_mul
		col_ray.sphere_cast_radius = sphere_cast_radius
		local hit_unit = col_ray.unit

		if hit_unit:character_damage() then
			if bayonet_melee then
				self._unit:sound():play("fairbairn_hit_body", nil, false)
			else
				local hit_sfx = "hit_body"

				if hit_unit:character_damage() and hit_unit:character_damage().melee_hit_sfx then
					hit_sfx = hit_unit:character_damage():melee_hit_sfx()
				end

				self:_play_melee_sound(melee_entry, hit_sfx, self._melee_attack_var)
			end

			if not hit_unit:character_damage()._no_blood then
				managers.game_play_central:play_impact_flesh({
					col_ray = col_ray
				})
				managers.game_play_central:play_impact_sound_and_effects({
					no_decal = true,
					no_sound = true,
					col_ray = col_ray
				})
			end

			self._camera_unit:base():play_anim_melee_item("hit_body")
		elseif self._on_melee_restart_drill and hit_unit:base() and (hit_unit:base().is_drill or hit_unit:base().is_saw) then
			hit_unit:base():on_melee_hit(managers.network:session():local_peer():id())
		else
			if bayonet_melee then
				self._unit:sound():play("knife_hit_gen", nil, false)
			else
				self:_play_melee_sound(melee_entry, "hit_gen", self._melee_attack_var)
			end

			self._camera_unit:base():play_anim_melee_item("hit_gen")
			managers.game_play_central:play_impact_sound_and_effects({
				no_decal = true,
				no_sound = true,
				col_ray = col_ray,
				effect = Idstring("effects/payday2/particles/impacts/fallback_impact_pd2")
			})
		end

		local custom_data = nil

		if _G.IS_VR and hand_id then
			custom_data = {
				engine = hand_id == 1 and "right" or "left"
			}
		end

		managers.rumble:play("melee_hit", nil, nil, custom_data)
		managers.game_play_central:physics_push(col_ray)
		local character_unit, shield_knock = nil
		local can_shield_knock = managers.player:has_category_upgrade("player", "shield_knock")

		if can_shield_knock and hit_unit:in_slot(8) and alive(hit_unit:parent()) and not hit_unit:parent():character_damage():is_immune_to_shield_knockback() then
			shield_knock = true
			character_unit = hit_unit:parent()
		end

		character_unit = character_unit or hit_unit
		local target_is_civilian = managers.enemy:is_civilian(character_unit)

		if character_unit:character_damage() and character_unit:character_damage().damage_melee then
			local shuffle_cut_stacks = 0
			
			local dmg_multiplier = 1

			dmg_multiplier = dmg_multiplier + managers.player:upgrade_value("class_melee","weapon_class_damage_mul",0)
			
			if managers.player:has_category_upgrade("class_throwing","throwing_boosts_melee_loop") then 
				shuffle_cut_stacks = managers.player:get_property("shuffle_cut_melee_bonus_damage",0)
				if shuffle_cut_stacks > 0 then 
					local shuffle_cut_data = managers.player:upgrade_value("class_throwing","throwing_boosts_melee_loop")
					local shuffle_cut_bonus = shuffle_cut_data[2]
					dmg_multiplier = dmg_multiplier + shuffle_cut_bonus
				end
			end
			
			if not target_is_civilian and not managers.groupai:state():is_enemy_special(character_unit) then
				dmg_multiplier = dmg_multiplier * managers.player:upgrade_value("player", "non_special_melee_multiplier", 1)
			else
				dmg_multiplier = dmg_multiplier * managers.player:upgrade_value("player", "melee_damage_multiplier", 1)
			end

			dmg_multiplier = dmg_multiplier * managers.player:upgrade_value("player", "melee_" .. tostring(melee_td.stats.weapon_type) .. "_damage_multiplier", 1)
			
			if character_unit:base():char_tweak().priority_shout then
				dmg_multiplier = dmg_multiplier * (melee_td.stats.special_damage_multiplier or 1)
			end
			
			if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
				self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
				self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {
					nil,
					0
				}
				local stack = self._state_data.stacking_dmg_mul.melee

				if stack[1] and t < stack[1] then
					dmg_multiplier = dmg_multiplier * (1 + managers.player:upgrade_value("melee", "stacking_hit_damage_multiplier", 0) * stack[2])
				else
					stack[2] = 0
				end
			end

			local health_ratio = self._ext_damage:health_ratio()
			local damage_health_ratio = managers.player:get_damage_health_ratio(health_ratio, "melee")

			if damage_health_ratio > 0 then
				dmg_multiplier = dmg_multiplier * (1 + self._damage_health_ratio_mul_melee * damage_health_ratio)
			end

			dmg_multiplier = dmg_multiplier * managers.player:temporary_upgrade_value("temporary", "berserker_damage_multiplier", 1)
			local target_alive = character_unit:character_damage().dead and not character_unit:character_damage():dead()
			local target_hostile = managers.enemy:is_enemy(character_unit) and not tweak_data.character[character_unit:base()._tweak_table].is_escort and character_unit:brain():is_hostile()
			local life_leach_available = managers.player:has_category_upgrade("temporary", "melee_life_leech") and not managers.player:has_activate_temporary_upgrade("temporary", "melee_life_leech")

			if target_alive and target_hostile and life_leach_available then
				managers.player:activate_temporary_upgrade("temporary", "melee_life_leech")
				self._unit:character_damage():restore_health(managers.player:temporary_upgrade_value("temporary", "melee_life_leech", 1))
			end

			local special_weapon = melee_td.special_weapon
			local action_data = {
				variant = "melee"
			}
			if melee_td.stats.knockback_tier then 
				local knockback_tier = melee_td.stats.knockback_tier
				if melee_td.random_knockback_tier then 
					knockback_tier = CopDamage.melee_knockback_tiers[math.random(#CopDamage.melee_knockback_tiers)]
				end
				action_data.knockback_tier = knockback_tier + math.floor(charge_lerp_value) + managers.player:upgrade_value("class_melee","knockdown_tier_increase",0) --only used in tcd
			end
			
			if special_weapon == "taser" then
				action_data.variant = "taser_tased"
			end

			if _G.IS_VR and melee_entry == "weapon" and not bayonet_melee then
				dmg_multiplier = 0.1
			end

			action_data.damage = shield_knock and 0 or damage * dmg_multiplier
			action_data.damage_effect = damage_effect
			action_data.attacker_unit = self._unit
			action_data.col_ray = col_ray
			action_data.critical_hit = self:calculate_melee_crit(melee_entry)

			if shield_knock then
				action_data.shield_knock = can_shield_knock
			end

			action_data.name_id = melee_entry
			action_data.charge_lerp_value = charge_lerp_value
			
			local char_base = character_unit:base()
			if char_base and char_base.char_tweak and char_base:char_tweak().priority_shout then
				dmg_multiplier = dmg_multiplier * (melee_td.stats.special_damage_multiplier or 1)
			end
			
			if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
				self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
				self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {
					nil,
					0
				}
				local stack = self._state_data.stacking_dmg_mul.melee

				if target_alive then
					stack[1] = t + managers.player:upgrade_value("melee", "stacking_hit_expire_t", 1)
					stack[2] = math.min(stack[2] + 1, tweak_data.upgrades.max_melee_weapon_dmg_mul_stacks or 5)
				else
					stack[1] = nil
					stack[2] = 0
				end
			end
			
			local defense_data = character_unit:character_damage():damage_melee(action_data)
			if defense_data then 
				local lethal_hit = target_alive and defense_data.type == "dead"
				if shuffle_cut_stacks ~= 0 then 
					if lethal_hit and managers.player:has_category_upgrade("class_melee","throwing_loop_refund") then 
						-- on melee kill with shuffle and cut aced, don't consume a shuffle cut throwing weapon bonus stack
					else
						-- else, consume one stack
						local new_stacks = math.max(shuffle_cut_stacks - 1,0)
						managers.player:set_property("shuffle_cut_melee_bonus_damage",new_stacks)
						managers.tcdbuff:call_listeners("shufflecut_melee_stacks_changed",shuffle_cut_stacks,new_stacks)
					end
				end
				
				-- on melee hit, grant throwing bonus
				if managers.player:has_category_upgrade("class_melee","melee_boosts_throwing_loop") then 
					local max_stacks = managers.player:upgrade_value("class_melee","melee_boosts_throwing_loop")[1]

					local stacks = managers.player:get_property("shuffle_cut_throwing_bonus_damage",0)
					local new_stacks = math.min(stacks+1,max_stacks)
					managers.tcdbuff:call_listeners("shufflecut_throwing_stacks_changed",stacks,new_stacks)
					
					managers.player:set_property("shuffle_cut_throwing_bonus_damage",new_stacks)
				end
			end
			
			action_data.armor_piercing = melee_td.pierce_body_armor

			self:_check_melee_special_damage(col_ray, character_unit, defense_data, melee_entry)
			self:_perform_sync_melee_damage(hit_unit, col_ray, action_data.damage)
			
			
			return defense_data
		else
			self:_perform_sync_melee_damage(hit_unit, col_ray, damage)
		end
	end
	
	if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
		self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
		self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {
			nil,
			0
		}
		local stack = self._state_data.stacking_dmg_mul.melee
		stack[1] = nil
		stack[2] = 0
	end
	
	
	
	return col_ray
end

-- tcd function
function PlayerStandard:calculate_melee_crit(melee_entry)
	local crit_value = managers.player:critical_hit_chance()
	
	if tweak_data.blackmarket.melee_weapons[melee_entry].base_crit then
		crit_value = crit_value + tweak_data.blackmarket.melee_weapons[melee_entry].base_crit --a little bonus if we ever want this.
	end
	
	local critical_roll = math.rand(1)
	critical_hit = critical_roll < crit_value
	
	return critical_hit
end