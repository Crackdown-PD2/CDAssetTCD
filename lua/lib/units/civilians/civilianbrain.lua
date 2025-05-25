-- Stay Down basic/aced
Hooks:PostHook(CivilianBrain,"init","cd_civilianbrain_init",function(self,unit)
	self._hostage_area_marking_t = Application:time() + math.random() -- add a bit of random delay to balance the load for drop-ins
end)

-- Stay Down basic/aced
Hooks:PostHook(CivilianBrain,"update","cd_civilianbrain_update",function(self,unit, t, dt)
	--marking and damage are both clientside

	if self:is_tied() then --and Network:is_server()
		if managers.player:has_team_category_upgrade("player","civilian_hostage_area_marking") then
			local interval = tweak_data.upgrades.values.team.player.civilian_hostage_area_marking_interval
--			Draw:brush(Color.red:with_alpha(0.1)):sphere(unit:position(),tweak_data.upgrades.values.team.player.civilian_hostage_area_marking_distance)
			if self._hostage_area_marking_t + interval < t then 

				self._hostage_area_marking_t = self._hostage_area_marking_t + interval
				
				local distance = tweak_data.upgrades.values.team.player.civilian_hostage_area_marking_distance
				local pos = unit:movement() and unit:movement():m_pos() or unit:position()
				
				
				for _,enemy_unit in pairs(World:find_units_quick("sphere",pos,distance,managers.slot:get_mask("enemies"))) do
					local ubase = enemy_unit:base()
					if ubase then
						if enemy_unit:contour() then 
							if ubase.sentry_gun then 
								enemy_unit:contour():add("mark_enemy",false)
							else
								if ubase.has_tag and ubase:has_tag("special") and managers.player:team_upgrade_value("player","civilian_hostage_area_marking") > 1 then
									enemy_unit:contour():add("civilian_mark_special",false)
								else
									enemy_unit:contour():add("civilian_mark_standard",false)
								end
							end
						end
					end
				end
			end
		end
	end
end)