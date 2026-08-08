function FirstAidKitBase:_get_upgrade_levels(bits)
	local auto_recovery = Bitwise:rshift(bits, FirstAidKitBase.auto_recovery_shift)
	local overshield_lvl = Bitwise:rshift(bits, FirstAidKitBase.upgrade_lvl_shift) % 2^FirstAidKitBase.upgrade_lvl_shift

	return overshield_lvl, auto_recovery
end

function FirstAidKitBase:setup(bits)
	local overshield_lvl, auto_recovery = self:_get_upgrade_levels(bits)

	self._damage_reduction_upgrade = false 
	self._preventative_care_upgrade_lvl = overshield_lvl

	if Network:is_server() then
		local from_pos = self._unit:position() + self._unit:rotation():z() * 10
		local to_pos = self._unit:position() + self._unit:rotation():z() * -10
		local ray = self._unit:raycast("ray", from_pos, to_pos, "slot_mask", managers.slot:get_mask("world_geometry"))

		if ray then
			self._attached_data = {}
			self._attached_data.body = ray.body
			self._attached_data.position = ray.body:position()
			self._attached_data.rotation = ray.body:rotation()
			self._attached_data.index = 1
			self._attached_data.max_index = 3

			self._unit:set_extension_update_enabled(Idstring("base"), true)
		end
	end

	if auto_recovery ~= 0 then
		self._min_distance = tweak_data.upgrades.values.first_aid_kit.first_aid_kit_auto_recovery[1]

		--print("min distance ", self._min_distance)
		FirstAidKitBase.Add(self, self._unit:position(), self._min_distance)
	end
	foo = self
end


function FirstAidKitBase:take(unit)
	if self._empty then
		return
	end
	
	-- heal 50% missing health
	-- heal 10% of max health over 10 seconds, or 2hp, whichever is larger
	unit:character_damage():_on_use_first_aid_kit(self._preventative_care_upgrade_lvl)

	if self._damage_reduction_upgrade then -- not active in cd
		managers.player:activate_temporary_upgrade("temporary", "first_aid_damage_reduction")
	end

	if managers.network:session() then
		managers.network:session():send_to_peers_synched("sync_unit_event_id_16", self._unit, "base", 2)
	end

	self:_set_empty()
end
