local unit_id = Idstring("units/payday2/environment/environment_fire_1/environment_fire_1")

function EnvironmentFire.spawn(position, rotation, data, normal, user_unit, weapon_unit, added_time, range_multiplier)
	local unit = World:spawn_unit(unit_id, position, rotation)
	local time_until_destruction

	if unit then
		local burn_bonus_dmg_mul = nil
		
		local user_base_ext = user_unit and alive(user_unit) and user_unit:base()
		if user_base_ext then
			local bonus_duration_mul,tmp_dmg_mul
			
			if user_base_ext.is_local_player then
				-- dot puddle from local player
				bonus_duration_mul = managers.player:upgrade_value("subclass_areadenial", "effect_duration_increase_mul", 0)
				
				-- save bonus puddle damage to burning enemies
				tmp_dmg_mul = managers.player:upgrade_value("subclass_areadenial", "effect_doubleroasting_damage_increase_mul", 0)
			else
				-- dot puddle from teammate
				bonus_duration_mul = user_base_ext:upgrade_value("subclass_areadenial", "effect_duration_increase_mul",0)
				tmp_dmg_mul = user_base_ext:upgrade_value("subclass_areadenial", "effect_doubleroasting_damage_increase_mul",0)
			end
		
			-- calculate extra burn time
			added_time = added_time + (data.burn_duration * bonus_duration_mul)
			
			if tmp_dmg_mul > 0 then
				burn_bonus_dmg_mul = tmp_dmg_mul
			end
		end
		
		local base_ext = unit:base()
		if base_ext then
			if base_ext.on_spawn then
				base_ext:on_spawn(data, normal, user_unit, weapon_unit, added_time, range_multiplier)
			end
			--base_ext._on_fire_dmg_mul = burn_bonus_dmg_mul -- not needed

			time_until_destruction = base_ext.get_duration_until_destruction and base_ext:get_duration_until_destruction()
		end
	end

	return unit, time_until_destruction
end

--[[ in case of mp damage buff not applying, break glass
function EnvironmentFire:_do_damage()
	local pos = self._unit:position()
	local normal = math.UP
	local range = self._range
	local slot_mask = self._damage_slotmask
	local player_in_range = false
	local player_in_range_count = 0

	if self._molotov_damage_effect_table then
		local collision_safety_distance = Vector3(0, 0, 5)
		local effect_position
		local player_damage_range = range

		for _, damage_effect_entry in pairs(self._molotov_damage_effect_table) do
			if damage_effect_entry.body ~= nil then
				effect_position = damage_effect_entry.effect_current_position + collision_safety_distance

				local damage_range = range

				if _ == 1 then
					damage_range = range * 1.5
				end

				if managers.player:player_unit() then
					local player_distance = mvector3.distance(damage_effect_entry.effect_current_position, managers.player:player_unit():position())

					if player_distance <= damage_range and player_in_range == false then
						local raycast = World:raycast("ray", effect_position, managers.player:player_unit():position() + Vector3(0, 0, 30), "slot_mask", slot_mask)
						local raycast2 = World:raycast("ray", effect_position, managers.player:player_unit():position() + Vector3(0, 0, 0), "slot_mask", slot_mask)

						if raycast == nil or raycast2 == nil then
							player_in_range = true
							player_in_range_count = player_in_range_count + 1
							pos = damage_effect_entry.effect_current_position
							player_damage_range = damage_range
						end
					end
				end

				if Network:is_server() then
					local user = self._user_unit
					local weapon = self._weapon_unit

					user = alive(user) and user or nil
					weapon = alive(weapon) and weapon or nil

					local hit_units, splinters = managers.fire:detect_and_give_dmg({
						player_damage = 0,
						push_units = false,
						hit_pos = effect_position,
						range = damage_range,
						collision_slotmask = slot_mask,
						curve_pow = self._curve_pow,
						damage = self._damage,
						ignore_unit = user or self._unit,
						user = user,
						owner = weapon or self._unit,
						alert_radius = self._fire_alert_radius,
						no_alert = self._no_fire_alert,
						dot_data = self._dot_data,
						is_molotov = self._is_molotov
					})
				end
			end
		end

		if player_in_range == true then
			managers.fire:give_local_player_dmg(pos, player_damage_range, self._player_damage)
		end
	end

	self._burn_tick_counter = 0
end

--]]