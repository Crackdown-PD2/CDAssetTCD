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
	return multiplier + self:get_damage_vulnerability_total()
end