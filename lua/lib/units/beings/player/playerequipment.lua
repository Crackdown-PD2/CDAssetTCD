-- not used?
function PlayerEquipment:use_trip_mine()
	local ray = self:valid_look_at_placement()

	if ray then
		managers.statistics:use_trip_mine()
		
		local radius_upgrade_level = managers.player:upgrade_level("trip_mine", "stuck_enemy_panic_radius", 0)
		local vulnerability_upgrade_level = managers.player:upgrade_level("trip_mine", "stuck_dozer_damage_vulnerability", 0)
		
		local upgrade_bits = Bitwise:lshift(radius_upgrade_level, TripMineBase.UPGRADE_SHIFT_RADIUS)
			+ Bitwise:lshift(vulnerability_upgrade_level, TripMineBase.UPGRADE_SHIFT_VULN)
			+ 1
		
		local payload_mode = TripmineControlMenu._current_mode
		local specials_only = TripmineControlMenu._current_specials_enabled
		
		if Network:is_client() then
			managers.network:session():send_to_host("place_trip_mine", ray.position, ray.normal, upgrade_bits, payload_mode, specials_only)
		else
			local rot = Rotation(ray.normal, math.UP)
			local unit = TripMineBase.spawn(ray.position, rot, managers.network:session():local_peer():id(), upgrade_bits, payload_mode, specials_only)
			
			unit:base():set_active(true, self._unit)
		end

		return true
	end

	return false
end