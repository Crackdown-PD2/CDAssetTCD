Hooks:OverrideFunction(PlayerCarry,"_check_action_run",function(self,...)
	if tweak_data.carry.types[self._tweak_data_name].can_run or managers.player:has_category_upgrade("carry", "can_sprint_with_bag") then
		return PlayerCarry.super._check_action_run(self, ...)
	end
end)

Hooks:OverrideFunction(PlayerCarry,"_get_max_walk_speed",function(self,...)
	local multiplier = tweak_data.carry.types[self._tweak_data_name].move_speed_modifier
	multiplier = managers.player:has_category_upgrade("carry", "can_sprint_with_bag") and 1 or math.clamp(multiplier * managers.player:upgrade_value("carry", "movement_speed_multiplier", 1), 0, 1)
	multiplier = math.clamp(multiplier + managers.player:upgrade_value("player","heave_ho",0),0,1)

	if managers.player:has_category_upgrade("player", "armor_carry_bonus") then
		local armor_init = managers.player:player_unit():character_damage()._ARMOR_INIT
		local base_max_armor = armor_init + managers.player:body_armor_value("armor") + managers.player:body_armor_skill_addend()
		local mul = managers.player:upgrade_value("player", "armor_carry_bonus", 1)

		for i = 1, base_max_armor do
			multiplier = multiplier * mul
		end

		multiplier = math.clamp(multiplier, 0, 1)
	end

	return PlayerCarry.super._get_max_walk_speed(self, ...) * multiplier
end)