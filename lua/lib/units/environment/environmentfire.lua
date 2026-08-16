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
			base_ext._on_fire_dmg_mul = burn_bonus_dmg_mul

			time_until_destruction = base_ext.get_duration_until_destruction and base_ext:get_duration_until_destruction()
		end
	end

	return unit, time_until_destruction
end
