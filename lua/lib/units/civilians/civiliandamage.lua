local orig_damage_bullet = CivilianDamage.damage_bullet
function CivilianDamage:damage_bullet(attack_data,...)
	local brain = self._unit:brain()
	if brain and brain:is_tied() and managers.player:has_team_category_upgrade("player","civilian_hostage_stationary_invuln") then 
		return
	end
	
	return orig_damage_bullet(self,attack_data,...)
end

local orig_damage_expl = CivilianDamage.damage_explosion
function CivilianDamage:damage_explosion(attack_data,...)
	local brain = self._unit:brain()
	if brain and brain:is_tied() and managers.player:has_team_category_upgrade("player","civilian_hostage_stationary_invuln") then 
		return
	end
	
	return orig_damage_expl(self,attack_data,...)
end

local orig_damage_fire = CivilianDamage.damage_fire
function CivilianDamage:damage_fire(attack_data,...)
	local brain = self._unit:brain()
	if brain and brain:is_tied() and managers.player:has_team_category_upgrade("player","civilian_hostage_stationary_invuln") then 
		return
	end
	
	return orig_damage_fire(self,attack_data,...)
end

local orig_damage_melee = CivilianDamage.damage_melee
function CivilianDamage:damage_melee(attack_data,...)
	local brain = self._unit:brain()
	if brain and brain:is_tied() and managers.player:has_team_category_upgrade("player","civilian_hostage_stationary_invuln") then 
		return
	end
	
	return orig_damage_melee(self,attack_data,...)
end

local orig_damage_tase = CivilianDamage.damage_tase
function CivilianDamage:damage_tase(attack_data,...)
	local brain = self._unit:brain()
	if brain and brain:is_tied() and managers.player:has_team_category_upgrade("player","civilian_hostage_stationary_invuln") then 
		return
	end
	
	return orig_damage_tase(self,attack_data,...)
end