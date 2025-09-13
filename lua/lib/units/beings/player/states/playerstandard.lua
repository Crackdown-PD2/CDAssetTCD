local mvec3_dis_sq = mvector3.distance_sq
local mvec3_set = mvector3.set
local mvec3_set_z = mvector3.set_z
local mvec3_sub = mvector3.subtract
local mvec3_add = mvector3.add
local mvec3_mul = mvector3.multiply
local mvec3_norm = mvector3.normalize
local mvec3_cpy = mvector3.copy
local mvec3_dir = mvector3.direction	
local up_offset_vec = math.UP * 30
local down_offset_vec = math.UP * -40

-- temp vectors
-- allocated for optimization
local mvec_pos_new = Vector3()
local mvec_achieved_walk_vel = Vector3()
local mvec_move_dir_normalized = Vector3()
local tmp_vec = Vector3()
local lunge_vec1 = Vector3()
local lunge_vec2 = Vector3()
local tmp_ground_from_vec = Vector3()
local tmp_ground_to_vec = Vector3()

local world_g = World
local alive_g = alive

local ai_vision_ids = Idstring("ai_vision")

local melee_vars = {
	"player_melee",
	"player_melee_var2"
}

-- init some vars
-- [Runner] Float Like a Butterfly
-- [Runner] Wave Dash
Hooks:PostHook(PlayerStandard,"init","tcd_playerstandard_init",function(self,unit)
	
	-- Float like a Butterfly
	if managers.player:has_category_upgrade("player", "bungielungie") then
		-- (tbl) cache upgrade vars for melee lunge
		self._tcd_bungielungie_data = table.deep_map_copy(managers.player:upgrade_value("player", "bungielungie"))
		
		-- (bool) this flag is updated every frame when melee lunge target is evaluated (in fwd_ray)
		self._has_lunge_target = nil
		
		-- (tbl) holds temporary data about the lunge that is currently being attempted
		self._lunge_data = nil
	else
		self._tcd_bungielungie_data = nil
		self._has_lunge_target = nil
	end
	
	-- Wave Dash
	if managers.player:has_category_upgrade("player", "wave_dash_basic") then
		-- (some of these "declarations" are more for organization than function)
		self._has_wave_dashed = nil
	end
	
end)

-- Zip It Aced- AOE intimidation shout
Hooks:OverrideFunction(PlayerStandard,"_get_intimidation_action",function(self, prime_target, char_table, amount, primary_only, detect_only, secondary)
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
end)

-- general melee rework
--not to be confused with _do_action_melee()
Hooks:OverrideFunction(PlayerStandard,"_do_melee_damage",function(self, t, bayonet_melee, melee_hit_ray, melee_entry, hand_id, force_max_charge,skip_shaker)
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
		local trade_unit = col_ray.unit
		if managers.trade:is_tradable_civilian(trade_unit) then
			if col_ray.unit:brain().is_tied and col_ray.unit:brain():is_tied() then
				local player_char_dmg = self._unit:character_damage()
				local current_revives = player_char_damage:get_revives()
				local max_revives = player_char_dmg._lives_init + managers.player:upgrade_value("player", "additional_lives", 0)
				if false and current_revives < max_revives then
					if is_host then
						if unit_is_tradable(unit) then
							send_to_peers("make_unit_escape")
							-- if necessary, manually mark civilian as untradable
							
							player_char_dmg._revives = Application:digest_value(current_revives + 1,true)
							player_char_dmg:_send_set_revives(current_revives + 1 >= max_revives)
						end
					else
						if not local_pending_req and unit_is_tradable(unit) then
							-- todo waypoint? "bain is negotiating" or something
							send_to_host("request_trade_replenish_down",unit)
							
							
							local function callback_receive_request_replenish_trade()
								-- as host
								if unit_is_tradable(unit) and not unit_has_pending_req(unit) then
									--nts check if mission critical
									-- use default trademanager check?
								end
							end
							
							local function callback_receive_response_replenish_trade(success)
								-- clear pending req
								if success then
									local player = managers.player:local_player()
									if alive(player) then
										local _player_char_dmg = player:character_damage()
										local _max_revives = _player_char_dmg._lives_init + managers.player:upgrade_value("player", "additional_lives", 0)
										local new_revives = math.min(_player_char_dmg:get_revives() + 1,_max_revives)
										_player_char_dmg._revives = Application:digest_value(new_revives,true)
										_player_char_dmg:_send_set_revives(new_revives >= _max_revives)
									end
								end
							end
							
						end
					end
					
					
				end
				
			end
		end
		
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
end)

-- Runner's Float Like a Butterfly (melee-and-sprint check)

Hooks:OverrideFunction(PlayerStandard,"_start_action_melee",function(self, t, input, instant)
	self._equipped_unit:base():tweak_data_anim_stop("fire")
	self:_interupt_action_reload(t)
	self:_interupt_action_steelsight(t)
	
	if not managers.player:has_category_upgrade("player","can_melee_and_sprint") then
		self:_interupt_action_running(t)
	end
	self:_interupt_action_charging_weapon(t)

	self._state_data.melee_charge_wanted = nil
	self._state_data.meleeing = true
	self._state_data.melee_start_t = nil
	local melee_entry = managers.blackmarket:equipped_melee_weapon()
	local primary = managers.blackmarket:equipped_primary()
	local primary_id = primary.weapon_id
	local bayonet_id = managers.blackmarket:equipped_bayonet(primary_id)
	local bayonet_melee = false

	if bayonet_id and melee_entry == "weapon" and self._equipped_unit:base():selection_index() == 2 then
		bayonet_melee = true
	end

	if instant then
		self:_do_action_melee(t, input)

		return
	end

	self:_stance_entered()

	if self._state_data.melee_global_value then
		self._camera_unit:anim_state_machine():set_global(self._state_data.melee_global_value, 0)
	end

	local melee_entry = managers.blackmarket:equipped_melee_weapon()
	self._state_data.melee_global_value = tweak_data.blackmarket.melee_weapons[melee_entry].anim_global_param

	self._camera_unit:anim_state_machine():set_global(self._state_data.melee_global_value, 1)

	local current_state_name = self._camera_unit:anim_state_machine():segment_state(self:get_animation("base"))
	local attack_allowed_expire_t = tweak_data.blackmarket.melee_weapons[melee_entry].attack_allowed_expire_t or 0.15
	self._state_data.melee_attack_allowed_t = t + (current_state_name ~= self:get_animation("melee_attack_state") and attack_allowed_expire_t or 0)
	local instant_hit = tweak_data.blackmarket.melee_weapons[melee_entry].instant

	if not instant_hit then
		self._ext_network:send("sync_melee_start", 0)
	end

	if current_state_name == self:get_animation("melee_attack_state") then
		self._ext_camera:play_redirect(self:get_animation("melee_charge"))

		return
	end

	local offset = nil

	if current_state_name == self:get_animation("melee_exit_state") then
		local segment_relative_time = self._camera_unit:anim_state_machine():segment_relative_time(self:get_animation("base"))
		offset = (1 - segment_relative_time) * 0.9
	end

	offset = math.max(offset or 0, attack_allowed_expire_t)

	self._ext_camera:play_redirect(self:get_animation("melee_enter"), nil, offset)
end)

-- Runner's Float Like a Butterfly (melee-and-sprint check)
Hooks:OverrideFunction(PlayerStandard,"_start_action_running",function(self, t)
	if self._slowdown_run_prevent then
		self._running_wanted = false

		return
	end

	if not self._move_dir then
		self._running_wanted = true

		return
	end

	if self:on_ladder() or self:_on_zipline() then
		return
	end
	
	local is_meleeing = self:_is_meleeing()
	if is_meleeing and not managers.player:has_category_upgrade("player","can_melee_and_sprint") then
		return
	end
	
	if self._shooting and not self._equipped_unit:base():run_and_shoot_allowed() or self:_changing_weapon() or self._use_item_expire_t or self._state_data.in_air or self:_is_throwing_projectile() or self:_is_charging_weapon() then
		self._running_wanted = true

		return
	end

	if self._state_data.ducking and not self:_can_stand() then
		self._running_wanted = true

		return
	end

	if not self:_can_run_directional() then
		return
	end

	self._running_wanted = false

	if managers.player:get_player_rule("no_run") then
		return
	end

	if not self._unit:movement():is_above_stamina_threshold() then
		return
	end

	if (not self._state_data.shake_player_start_running or not self._ext_camera:shaker():is_playing(self._state_data.shake_player_start_running)) and self._setting_use_headbob then
		self._state_data.shake_player_start_running = self._ext_camera:play_shaker("player_start_running", 0.75)
	end

	self:set_running(true)

	self._end_running_expire_t = nil
	self._start_running_t = t
	self._play_stop_running_anim = nil
	
	-- don't play fp redirect if meleeing
	if not is_meleeing and (not self:_is_reloading() or not self.RUN_AND_RELOAD) then
		if not self._equipped_unit:base():run_and_shoot_allowed() then
			self._ext_camera:play_redirect(self:get_animation("start_running"))
		else
			self._ext_camera:play_redirect(self:get_animation("idle"))
		end
	end

	if not self.RUN_AND_RELOAD then
		self:_interupt_action_reload(t)
	end

	self:_interupt_action_steelsight(t)
	self:_interupt_action_ducking(t)
end)


-- Runner's Float Like a Butterfly Aced (melee lunge)
-- only real difference between tcd's and vanilla's (aside from the tcd skill check) is that the raycast is performed from the player unit in tcd, rather than the world in vanilla
Hooks:OverrideFunction(PlayerStandard,"_update_fwd_ray",function(self)
	local my_unit = self._unit
	local from = my_unit:movement():m_head_pos()
	local my_cam_fwd = self._cam_fwd
	local equipped_unit = alive_g(self._equipped_unit) and self._equipped_unit or nil

	local weap_base = equipped_unit and equipped_unit:base()
	local range = weap_base and weap_base.needs_extended_fwd_ray_range and weap_base:needs_extended_fwd_ray_range(self._state_data.in_steelsight) and 20000 or 4000

	local to = tmp_vec
	mvec3_set(to, my_cam_fwd)
	mvec3_mul(to, range)
	mvec3_add(to, from)

	local fwd_ray_slotmask = self._slotmask_fwd_ray
	local fwd_ray = my_unit.raycast(my_unit, "ray", from, to, "slot_mask", fwd_ray_slotmask)
	self._fwd_ray = fwd_ray

	if self._tcd_bungielungie_data and fwd_ray then
		if not managers.player:has_active_temporary_property("runner_bungielungie_cooldown") and not self._state_data.on_zipline then
			if fwd_ray.distance <= self._tcd_bungielungie_data.range then
				self._has_lunge_target = fwd_ray.unit:in_slot(managers.slot:get_mask("enemies"))
			else
				self._has_lunge_target = nil
			end
		else
			self._has_lunge_target = nil
		end
	else
		self._has_lunge_target = nil
	end

	managers.environment_controller:set_dof_distance(math.max(0, math.min(fwd_ray and fwd_ray.distance or 4000, 4000) - 200), self._state_data.in_steelsight)
	
	if weap_base then
		if fwd_ray and self._state_data.in_steelsight and weap_base.check_highlight_unit then
			weap_base:check_highlight_unit(fwd_ray.unit)
		end

		if weap_base.set_unit_health_display then
			weap_base:set_unit_health_display(fwd_ray and fwd_ray.unit or nil)
		end

		if weap_base.set_scope_range_distance then
			weap_base:set_scope_range_distance(fwd_ray and fwd_ray.distance / 100 or false)
		end
	end
end)

-- Runner's Float Like a Butterfly Aced (melee lunge)
Hooks:OverrideFunction(PlayerStandard,"_do_action_melee",function(self, t, input, skip_damage, ignore_lunge)
	self._state_data.meleeing = nil
	local melee_entry = managers.blackmarket:equipped_melee_weapon()
	local mtd = tweak_data.blackmarket.melee_weapons[melee_entry]
	local instant_hit = mtd.instant
	local pre_calc_hit_ray = mtd.hit_pre_calculation
	local melee_damage_delay = mtd.melee_damage_delay or 0
	melee_damage_delay = math.min(melee_damage_delay, mtd.repeat_expire_t)
	local primary = managers.blackmarket:equipped_primary()
	local primary_id = primary.weapon_id
	local bayonet_id = managers.blackmarket:equipped_bayonet(primary_id)
	local bayonet_melee = false

	if bayonet_id and self._equipped_unit:base():selection_index() == 2 then
		bayonet_melee = true
	end
	self._state_data.melee_hit_while_charging_t = nil
	self._state_data.melee_expire_t = t + mtd.expire_t
	self._state_data.melee_repeat_expire_t = t + math.min(mtd.repeat_expire_t, tweak_data.blackmarket.melee_weapons[melee_entry].expire_t)
	
	local anim_speed = 1

	if not instant_hit and not skip_damage then
		if self._has_lunge_target and not self._lunge_data then
			local range = mtd.stats.range or 175
			local fwd_ray = self._fwd_ray
			local travel_dis = fwd_ray.distance
			
			if travel_dis <= 0 then
				--nothing
			else
				local travel_t = math.lerp(0.01, 0.15, travel_dis / 500)
				local fwd_ray_unit = fwd_ray.unit
				local player_pos = mvec3_cpy(self._unit:movement():m_pos())
				local target_pos = mvec3_cpy(fwd_ray_unit:movement():m_pos())

				mvec3_dir(lunge_vec1, player_pos, target_pos)
				mvec3_dir(lunge_vec2, self._unit:movement():m_head_pos(), fwd_ray_unit:body("head"):position())
				
				self._lunge_data = {
					travel_t = travel_t,
					traveled_dis = 0,
					travel_dir = mvec3_cpy(lunge_vec1),
					achieved_vel = mvec3_cpy(lunge_vec1),
					travel_dis = travel_dis,
					target_unit = fwd_ray_unit,
					positions = {
						player_pos = player_pos,
						target_pos = target_pos
					},
					camera_dir = mvec3_cpy(lunge_vec2),
					instant_hit = nil
				}
				managers.player:activate_temporary_property("runner_bungielungie_cooldown",self._tcd_bungielungie_data.cooldown,true)
				managers.player._can_lunge = nil
				self._state_data.in_air = true
				self._state_data.enter_air_pos_z = player_pos.z
				
				anim_speed = melee_damage_delay / travel_t
				
				melee_damage_delay = travel_t
				
				self._unit:set_driving("script")
			end
		end
	
		self._state_data.melee_damage_delay_t = t + melee_damage_delay

		if pre_calc_hit_ray then
			self._state_data.melee_hit_ray = self:_calc_melee_hit_ray(t, 20) or true
		else
			self._state_data.melee_hit_ray = nil
		end
	elseif not skip_damage and not ignore_lunge then
		if self._has_lunge_target and not self._lunge_data then
			local range = mtd.stats.range or 175
			local fwd_ray = self._fwd_ray
			local travel_dis = fwd_ray.distance
			
			if travel_dis <= 0 then
				--nothing
			else
				local travel_t = math.lerp(0.01, 0.15, travel_dis / 500)
				local fwd_ray_unit = fwd_ray.unit
				local player_pos = mvec3_cpy(self._unit:movement():m_pos())
				local target_pos = mvec3_cpy(fwd_ray_unit:movement():m_pos())

				mvec3_dir(lunge_vec1, player_pos, target_pos)
				mvec3_dir(lunge_vec2, self._unit:movement():m_head_pos(), fwd_ray_unit:body("head"):position())
				
				self._lunge_data = {
					travel_t = travel_t,
					traveled_dis = 0,
					travel_dir = mvec3_cpy(lunge_vec1),
					achieved_vel = mvec3_cpy(lunge_vec1),
					travel_dis = travel_dis,
					target_unit = fwd_ray_unit,
					positions = {
						player_pos = player_pos,
						target_pos = target_pos
					},
					camera_dir = mvec3_cpy(lunge_vec2),
					instant_hit = true
				}
				
				managers.player:activate_temporary_property("runner_bungielungie_cooldown",self._tcd_bungielungie_data.cooldown,true)
				self._state_data.in_air = true
				self._state_data.enter_air_pos_z = player_pos.z
				self._unit:set_driving("script")
				
				return
			end
		end
	end

	local send_redirect = instant_hit and (bayonet_melee and "melee_bayonet" or "melee") or "melee_item"

	if instant_hit then
		managers.network:session():send_to_peers_synched("play_distance_interact_redirect", self._unit, send_redirect)
	else
		self._ext_network:send("sync_melee_discharge")
	end

	if self._state_data.melee_charge_shake then
		self._ext_camera:shaker():stop(self._state_data.melee_charge_shake)

		self._state_data.melee_charge_shake = nil
	end

	self._melee_attack_var = 0

	if instant_hit then
		local hit = skip_damage or self:_do_melee_damage(t, bayonet_melee)

		if hit then
			self._ext_camera:play_redirect(bayonet_melee and self:get_animation("melee_bayonet") or self:get_animation("melee"))
		else
			self._ext_camera:play_redirect(bayonet_melee and self:get_animation("melee_miss_bayonet") or self:get_animation("melee_miss"))
		end
	else
		local state = self._ext_camera:play_redirect(self:get_animation("melee_attack"), anim_speed)
		local anim_attack_vars = tweak_data.blackmarket.melee_weapons[melee_entry].anim_attack_vars
		self._melee_attack_var = anim_attack_vars and math.random(#anim_attack_vars)

		self:_play_melee_sound(melee_entry, "hit_air", self._melee_attack_var)

		local melee_item_tweak_anim = "attack"
		local melee_item_prefix = ""
		local melee_item_suffix = ""
		local anim_attack_param = anim_attack_vars and anim_attack_vars[self._melee_attack_var]

		if anim_attack_param then
			self._camera_unit:anim_state_machine():set_parameter(state, anim_attack_param, 1)

			melee_item_prefix = anim_attack_param .. "_"
		end

		if self._state_data.melee_hit_ray and self._state_data.melee_hit_ray ~= true then
			self._camera_unit:anim_state_machine():set_parameter(state, "hit", 1)

			melee_item_suffix = "_hit"
		end

		melee_item_tweak_anim = melee_item_prefix .. melee_item_tweak_anim .. melee_item_suffix

		self._camera_unit:base():play_anim_melee_item(melee_item_tweak_anim)
	end
end)

-- Runner's Float Like a Butterfly Aced (melee lunge)
Hooks:OverrideFunction(PlayerStandard,"_update_ground_ray",function(self)
	if self._lunge_data then
		self._gnd_ray = nil
		return
	end
	
	local vel_z = 1

	if self._unit:mover() then
		vel_z = math.clamp(math.abs(self._unit:mover():velocity().z + 100), 0.01, 1)
	end
	
	if vel_z < 0.2 and not self._is_jumping then
		self._gnd_ray = true
	else
		local hips_pos = tmp_ground_from_vec
		local down_pos = tmp_ground_to_vec

		mvector3.set(hips_pos, self._pos)
		mvector3.add(hips_pos, up_offset_vec)
		mvector3.set(down_pos, hips_pos)
		mvector3.add(down_pos, down_offset_vec)

		if self._unit:movement():ladder_unit() then
			self._gnd_ray = World:raycast("ray", hips_pos, down_pos, "slot_mask", self._slotmask_gnd_ray, "ignore_unit", self._unit:movement():ladder_unit(), "ray_type", "body mover", "sphere_cast_radius", 29, "report")
		else
			self._gnd_ray = World:raycast("ray", hips_pos, down_pos, "slot_mask", self._slotmask_gnd_ray, "ray_type", "body mover", "sphere_cast_radius", 29, "report")
		end
	end

	self._gnd_ray_chk = true
end)

-- Runner's Float Like a Butterfly Aced (melee lunge)
Hooks:OverrideFunction(PlayerStandard,"_chk_floor_moving_pos",function(self,pos)
	
	-- this block is the only change
	if self._lunge_data then
		return
	end
	-- ^

	local hips_pos = tmp_ground_from_vec
	local down_pos = tmp_ground_to_vec

	mvec3_set(hips_pos, self._pos)
	mvec3_add(hips_pos, up_offset_vec)
	mvec3_set(down_pos, hips_pos)
	mvec3_add(down_pos, down_offset_vec)

	local ground_ray = self._unit:raycast("ray", hips_pos, down_pos, "slot_mask", self._slotmask_gnd_ray, "ray_type", "body mover", "sphere_cast_radius", 29, "bundle", 9)

	if ground_ray and ground_ray.body and math.abs(ground_ray.body:velocity().z) > 0 then
		return ground_ray.body:position().z
	end
end)

-- Runner's Float Like a Butterfly Aced (melee lunge)
Hooks:OverrideFunction(PlayerStandard,"_update_movement",function(self,t,dt)
	local anim_data = self._unit:anim_data()
	local weapon_id = alive(self._equipped_unit) and self._equipped_unit:base() and self._equipped_unit:base():get_name_id()
	local weapon_tweak_data = weapon_id and tweak_data.weapon[weapon_id]
	local pos_new = nil
	self._target_headbob = self._target_headbob or 0
	self._headbob = self._headbob or 0
	
	-- this section is the only change
	if self._lunge_data then
		local lunge_data = self._lunge_data
		
		self._unit:camera():camera_unit():base():clbk_aim_assist({
			ray = lunge_data.camera_dir
		})
		
		local speed = 500 / lunge_data.travel_t
		local traveled_dis = speed * dt
		local achieved_vel = lunge_data.achieved_vel
		
		mvector3.set(achieved_vel, lunge_data.travel_dir)
		mvector3.multiply(achieved_vel, speed)
	
		pos_new = mvec_pos_new

		mvector3.set(pos_new, achieved_vel)
		mvector3.multiply(pos_new, dt)
		mvector3.add(pos_new, self._pos)
		
		lunge_data.traveled_dis = lunge_data.traveled_dis + traveled_dis
		
		if lunge_data.traveled_dis >= lunge_data.travel_dis then
			if lunge_data.instant_hit then
				self:_do_action_melee(t, input, nil, true)
				
				self._lunge_data = nil
			end
		
			pos_new = nil
		end
	-- ^
	elseif self._state_data.on_zipline and self._state_data.zipline_data.position then
		local speed = mvector3.length(self._state_data.zipline_data.position - self._pos) / dt / 500
		pos_new = mvec_pos_new

		mvector3.set(pos_new, self._state_data.zipline_data.position)

		if self._state_data.zipline_data.camera_shake then
			self._ext_camera:shaker():set_parameter(self._state_data.zipline_data.camera_shake, "amplitude", speed)
		end

		if alive(self._state_data.zipline_data.zipline_unit) then
			local dot = mvector3.dot(self._ext_camera:rotation():x(), self._state_data.zipline_data.zipline_unit:zipline():current_direction())

			self._ext_camera:camera_unit():base():set_target_tilt(dot * 10 * speed)
		end

		self._target_headbob = 0
	elseif self._move_dir then
		local enter_moving = not self._moving
		self._moving = true

		if enter_moving then
			self._last_sent_pos_t = t

			self:_update_crosshair_offset()
		end

		local WALK_SPEED_MAX = self:_get_max_walk_speed(t)

		mvector3.set(mvec_move_dir_normalized, self._move_dir)
		mvector3.normalize(mvec_move_dir_normalized)

		local wanted_walk_speed = WALK_SPEED_MAX * math.min(1, self._move_dir:length())
		local acceleration = self._state_data.in_air and 700 or self._running and 5000 or 3000
		local achieved_walk_vel = mvec_achieved_walk_vel

		if self._jump_vel_xy and self._state_data.in_air and mvector3.dot(self._jump_vel_xy, self._last_velocity_xy) > 0 then
			local input_move_vec = wanted_walk_speed * self._move_dir
			local jump_dir = mvector3.copy(self._last_velocity_xy)
			local jump_vel = mvector3.normalize(jump_dir)
			local fwd_dot = jump_dir:dot(input_move_vec)

			if fwd_dot < jump_vel then
				local sustain_dot = (input_move_vec:normalized() * jump_vel):dot(jump_dir)
				local new_move_vec = input_move_vec + jump_dir * (sustain_dot - fwd_dot)

				mvector3.step(achieved_walk_vel, self._last_velocity_xy, new_move_vec, 700 * dt)
			else
				mvector3.multiply(mvec_move_dir_normalized, wanted_walk_speed)
				mvector3.step(achieved_walk_vel, self._last_velocity_xy, wanted_walk_speed * self._move_dir:normalized(), acceleration * dt)
			end

			local fwd_component = nil
		else
			mvector3.multiply(mvec_move_dir_normalized, wanted_walk_speed)
			mvector3.step(achieved_walk_vel, self._last_velocity_xy, mvec_move_dir_normalized, acceleration * dt)
		end

		if mvector3.is_zero(self._last_velocity_xy) then
			mvector3.set_length(achieved_walk_vel, math.max(achieved_walk_vel:length(), 100))
		end

		pos_new = mvec_pos_new

		mvector3.set(pos_new, achieved_walk_vel)
		mvector3.multiply(pos_new, dt)
		mvector3.add(pos_new, self._pos)

		self._target_headbob = self:_get_walk_headbob()
		self._target_headbob = self._target_headbob * self._move_dir:length()

		if weapon_tweak_data and weapon_tweak_data.headbob and weapon_tweak_data.headbob.multiplier then
			self._target_headbob = self._target_headbob * weapon_tweak_data.headbob.multiplier
		end
	elseif not mvector3.is_zero(self._last_velocity_xy) then
		local decceleration = self._state_data.in_air and 250 or math.lerp(2000, 1500, math.min(self._last_velocity_xy:length() / tweak_data.player.movement_state.standard.movement.speed.RUNNING_MAX, 1))
		local achieved_walk_vel = math.step(self._last_velocity_xy, Vector3(), decceleration * dt)
		pos_new = mvec_pos_new

		mvector3.set(pos_new, achieved_walk_vel)
		mvector3.multiply(pos_new, dt)
		mvector3.add(pos_new, self._pos)

		self._target_headbob = 0
	elseif self._moving then
		self._target_headbob = 0
		self._moving = false

		self:_update_crosshair_offset()
	end

	if self._headbob ~= self._target_headbob then
		local ratio = 4

		if weapon_tweak_data and weapon_tweak_data.headbob and weapon_tweak_data.headbob.speed_ratio then
			ratio = weapon_tweak_data.headbob.speed_ratio
		end

		self._headbob = math.step(self._headbob, self._target_headbob, dt / ratio)

		self._ext_camera:set_shaker_parameter("headbob", "amplitude", self._headbob)
	end

	local ground_z = self:_chk_floor_moving_pos()

	if ground_z and not self._is_jumping then
		if not pos_new then
			pos_new = mvec_pos_new

			mvector3.set(pos_new, self._pos)
		end

		mvector3.set_z(pos_new, ground_z)
	end

	if pos_new then
		self._unit:movement():set_position(pos_new)
		mvector3.set(self._last_velocity_xy, pos_new)
		mvector3.subtract(self._last_velocity_xy, self._pos)

		if not self._state_data.on_ladder and not self._state_data.on_zipline then
			mvector3.set_z(self._last_velocity_xy, 0)
		end

		mvector3.divide(self._last_velocity_xy, dt)
	else
		mvector3.set_static(self._last_velocity_xy, 0, 0, 0)
	end

	local cur_pos = pos_new or self._pos

	self:_update_network_jump(cur_pos, false)
	self:_update_network_position(t, dt, cur_pos, pos_new)
end)

-- Runner's Float Like a Butterfly Aced (melee lunge)
Hooks:OverrideFunction(PlayerStandard,"_check_action_melee",function(self,t,input)
	if self._lunge_data then
		return
	end
	
	if self._state_data.melee_attack_wanted then
		if not self._state_data.melee_attack_allowed_t then
			self._state_data.melee_attack_wanted = nil
			
			self:_do_action_melee(t, input)
		end

		return
	end

	local action_wanted = input.btn_melee_press or input.btn_melee_release or self._state_data.melee_charge_wanted

	if not action_wanted then
		return
	end

	if input.btn_melee_release then
		if self._state_data.meleeing then
			if self._state_data.melee_attack_allowed_t then
				self._state_data.melee_attack_wanted = true

				return
			end

			self:_do_action_melee(t, input)
		end

		return
	end

	local action_forbidden = not self:_melee_repeat_allowed() or self._use_item_expire_t or self:_changing_weapon() or self:_interacting() or self:_is_throwing_projectile() or self:_is_using_bipod() or self._melee_stunned

	if action_forbidden then
		return
	end

	local melee_entry = managers.blackmarket:equipped_melee_weapon()
	local mtd = tweak_data.blackmarket.melee_weapons[melee_entry]
	local instant = mtd.instant
	
	self:_start_action_melee(t, input, instant)

	return true
end)

-- Runner's Float Like a Butterfly Aced (melee lunge)
Hooks:OverrideFunction(PlayerStandard,"_calc_melee_hit_ray",function(self,t,sphere_cast_radius)
	local melee_entry = managers.blackmarket:equipped_melee_weapon()
	local mtd = tweak_data.blackmarket.melee_weapons[melee_entry]
	local range = mtd.stats.range or 175
	local from, to = nil
	
	if self._lunge_data then
		from = self._unit:movement():m_head_pos()
		to = self._lunge_data.target_unit:body("head"):position()
		mvec3_dir(to, from, to)
		mvec3_mul(to, range + 50)
		mvec3_add(to, from)

	else
		from = self._unit:movement():m_head_pos()
		to = from + self._unit:movement():m_head_rot():y() * range
	end
	local slot_mask = self._slotmask_bullet_impact_targets
	if mtd.pierce_shields then
		slot_mask = slot_mask - managers.slot:get_mask("enemy_shield_check")
	end
	return self._unit:raycast("ray", from, to, "slot_mask", slot_mask, "sphere_cast_radius", sphere_cast_radius, "ray_type", "body melee")
end)

-- Runner's Wave Dash (dolphin dive)
Hooks:OverrideFunction(PlayerStandard,"_check_action_duck",function(self,t, input)
	if self:_is_using_bipod() then
		return
	end
	
	if input.btn_duck_release then
		self._t_holding_duck = nil
	elseif input.btn_duck_press then
		self._t_holding_duck = t + tweak_data.upgrades.WAVE_DASH_INPUT_HOLD_THRESHOLD
	end

	if self._setting_hold_to_duck and input.btn_duck_release then
		if self._state_data.ducking then
			self:_end_action_ducking(t)
		end
	elseif input.btn_duck_press and not self._unit:base():stats_screen_visible() then
		if not self._state_data.ducking then
			self:_start_action_ducking(t)
		elseif self._state_data.ducking then
			self:_end_action_ducking(t)
		end
	end
	
	if self._state_data.in_air then
		-- wave dash check
		if managers.player:has_category_upgrade("player", "wave_dash_basic") then
			if self._t_holding_duck and t > self._t_holding_duck then
				local mov_ext = self._unit:movement()
				local stamina_cost = managers.player:upgrade_value("player","wave_dash_basic",math.huge) * mov_ext:_max_stamina()
				if mov_ext._stamina >= stamina_cost then
					self._unit:mover():set_velocity(Vector3(0, 0, -1400))
					mvector3.set_static(self._last_velocity_xy, 0, 0, 0)
					self._state_data.diving = true
					
					mov_ext:subtract_stamina(stamina_cost, true)
				end
			end
		end
	end
end)

-- Runner's Wave Dash (dolphin dive)
Hooks:OverrideFunction(PlayerStandard,"_check_action_jump",function(self,t, input)
	local new_action = nil
	local action_wanted = input.btn_jump_press

	if action_wanted then
		local action_forbidden = self._jump_t and t < self._jump_t + 0.55
		
		-- wave dash changes 
		local cant_mid_air_jump = nil
		local wave_dashing = nil
		local skill = managers.player:has_category_upgrade("player", "wave_dash_basic")
		local skill2 = managers.player:has_category_upgrade("player", "wave_dash_aced")
		
		if self._state_data.in_air then
			cant_mid_air_jump = true
			
			if skill and self._unit:movement():is_above_stamina_threshold() then			
				if not self._has_wave_dashed then
					cant_mid_air_jump = nil
					action_forbidden = nil
					self._has_wave_dashed = true
					wave_dashing = true
				end
			end
		end
		-- ^ changes
			
		
		action_forbidden = action_forbidden or self._unit:base():stats_screen_visible() or cant_mid_air_jump or self:_interacting() or self:_on_zipline() or self:_does_deploying_limit_movement() or self:_is_using_bipod()

		if not action_forbidden then
			if self._state_data.ducking then
				self:_interupt_action_ducking(t)
			else
				if self._state_data.on_ladder then
					self:_interupt_action_ladder(t)
				end

				local action_start_data = {}
				local jump_vel_z = tweak_data.player.movement_state.standard.movement.jump_velocity.z
				
				if wave_dashing then
					if not self._move_dir or not skill2 then
						if not self._move_dir then
							self._move_dir = Vector3()
						end
						
						if skill2 or not self._jump_vel_xy then
							mvec3_set(self._move_dir, self._unit:movement()._m_head_rot:y())
						else
							mvec3_set(self._move_dir, self._jump_vel_xy)
						end
					end	
					
					jump_vel_z = 200
				end
				
				action_start_data.jump_vel_z = jump_vel_z
				
				if self._move_dir then
					local is_running = self._running and self._unit:movement():is_above_stamina_threshold() and t - self._start_running_t > 0.4
					local jump_vel_xy = wave_dashing and 1000 or tweak_data.player.movement_state.standard.movement.jump_velocity.xy[is_running and "run" or "walk"]
					
					action_start_data.jump_vel_xy = jump_vel_xy

					if is_running then
						self._unit:movement():subtract_stamina(tweak_data.player.movement_state.stamina.JUMP_STAMINA_DRAIN)
					end
					
					if wave_dashing then
						self._unit:movement():subtract_stamina(0.05, true) --5% of stamina consumed on dash
					end
				end

				new_action = self:_start_action_jump(t, action_start_data)
			end
		end
	end

	return new_action
end)

-- Runner's Wave Dash (dolphin dive)
Hooks:OverrideFunction(PlayerStandard,"_update_foley",function(self,t, input)
	if self._state_data.on_zipline or self._lunge_data then
		return
	end

	if not self._gnd_ray and not self._state_data.on_ladder then
		if not self._state_data.in_air then
			self._state_data.in_air = true
			self._state_data.enter_air_pos_z = self._pos.z

			self:_interupt_action_running(t)
			self._unit:set_driving("orientation_object")
		end
	elseif self._state_data.in_air then
		self._unit:set_driving("script")

		self._state_data.in_air = false
		self._has_wave_dashed = nil
		
		local from = self._pos + math.UP * 10
		local to = self._pos - math.UP * 60
		local material_name, pos, norm = World:pick_decal_material(from, to, self._slotmask_foley_ray)

		self._unit:sound():play_land(material_name)
		
		local check_fall_damage = not self._state_data.diving
		local height = self._state_data.enter_air_pos_z - self._pos.z
		
		if not check_fall_damage and height > 631 then
			check_fall_damage = true
		end
		
		if check_fall_damage and self._unit:character_damage():damage_fall({
			height = height
		}) then
			self._running_wanted = false

			managers.rumble:play("hard_land")
			self._ext_camera:play_shaker("player_fall_damage")
			self:_start_action_ducking(t)
		else
			if self._state_data.diving then					
				--self._fall_damage_slow_t = t + 0.4
				managers.rumble:play("hard_land")
				self._ext_camera:play_shaker("player_fall_damage", 1)
				self._ext_camera:play_shaker("player_land", 1)
				
				self._state_data.diving = nil
			end
			
			if input.btn_run_state then
				self._running_wanted = true
			end
		end

		self._jump_t = nil
		self._jump_vel_xy = nil

		self._ext_camera:play_shaker("player_land", 0.5)
		managers.rumble:play("land")
	elseif self._jump_vel_xy and t - self._jump_t > 0.3 then
		self._jump_vel_xy = nil

		if input.btn_run_state then
			self._running_wanted = true
		end
	end

	self:_check_step(t)
end)


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