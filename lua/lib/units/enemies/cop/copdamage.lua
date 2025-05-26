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
