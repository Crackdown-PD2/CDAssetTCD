local mvec3_dis = mvector3.distance
local mvec3_set = mvector3.set
local mvec3_set_stat = mvector3.set_static
local mvec3_add = mvector3.add
local mvec3_dot = mvector3.dot
local mvec3_sub = mvector3.subtract
local mvec3_mul = mvector3.multiply
local mvec3_dir = mvector3.direction
local mvec3_rot = mvector3.rotate_with
local mvec3_cpy = mvector3.copy
local tmp_vec1 = Vector3()
local tmp_vec2 = Vector3()
local tmp_vec3 = Vector3()
local tmp_vec4 = Vector3()
local tmp_seg_vec1 = Vector3()
local tmp_seg_vec2 = Vector3()
local tmp_seg_vec3 = Vector3()
local tmp_seg_vec4 = Vector3()
local tmp_seg_vec5 = Vector3()
local tmp_seg_vec6 = Vector3()

local mrot_y = mrotation.y
local mrot_yaw = mrotation.yaw
local mrot_pitch = mrotation.pitch
local mrot_roll = mrotation.roll
local mrot_mul = mrotation.multiply
local mrot_inv = mrotation.invert
local mrot_set = mrotation.set_yaw_pitch_roll
local mrot_set_look_at = mrotation.set_look_at
local tmp_rot1 = Rotation()
local tmp_rot2 = Rotation()

local math_up = math.UP
local math_dot = math.dot
local math_clamp = math.clamp

local alive_g = alive
local world_g = World

local idstr_func = Idstring
local body_idstr = idstr_func("body")

--also changed signature: allow passing the arguments from the raycast check 
function PlayerEquipment:use_trip_mine(ray,stuck_enemy,...)
	if ray == nil and stuck_enemy == nil then
		ray, stuck_enemy = self:valid_look_at_placement(nil, managers.player:has_category_upgrade("trip_mine", "can_place_on_enemies"),...)
	end

	if ray then
		local radius_upgrade_level = managers.player:upgrade_level("trip_mine", "stuck_enemy_panic_radius", 0)
		local vulnerability_upgrade_level = managers.player:upgrade_level("trip_mine", "stuck_dozer_damage_vulnerability", 0)
		
		local upgrade_bits = Bitwise:lshift(radius_upgrade_level, TripMineBase.UPGRADE_SHIFT_RADIUS)
			+ Bitwise:lshift(vulnerability_upgrade_level, TripMineBase.UPGRADE_SHIFT_VULN)
			+ 1
		
		local payload_mode = TripmineControlMenu._current_mode
		local specials_only = TripmineControlMenu._current_specials_enabled
	
		managers.statistics:use_trip_mine()

		local session = managers.network:session()

		if Network:is_client() then
			if stuck_enemy then
				local body = ray.body
				local normal = ray.normal
				local parent_obj = body:root_object()
				local global_pos, local_pos, local_rot_vec = tmp_vec1
				mvec3_set(global_pos, ray.position)

				self:_check_unit_attach_segment(stuck_enemy, global_pos)

				if parent_obj then
					local_pos, local_rot_vec = tmp_vec2, tmp_vec3
					local parent_pos, inv_parent_rot = tmp_vec4, tmp_rot1

					parent_obj:m_position(parent_pos)
					parent_obj:m_rotation(inv_parent_rot)
					mrot_inv(inv_parent_rot)

					mvec3_set(local_pos, global_pos)
					mvec3_sub(local_pos, parent_pos)
					mvec3_rot(local_pos, inv_parent_rot)

					local normal_rot = tmp_rot2
					mrot_set_look_at(normal_rot, normal, math_up)
					mrot_mul(inv_parent_rot, normal_rot)
					mvec3_set_stat(local_rot_vec, mrot_yaw(inv_parent_rot), mrot_pitch(inv_parent_rot), mrot_roll(inv_parent_rot))

					local_pos = mvec3_cpy(local_pos)
					local_rot_vec = mvec3_cpy(local_rot_vec)
				end
				
				session:send_to_host("request_spawn_attach_trip_mine", stuck_enemy, body or nil, parent_obj or nil, local_pos or global_pos, local_rot_vec or normal, upgrade_bits, payload_mode, specials_only)
			else
				session:send_to_host("place_trip_mine", ray.position, ray.normal, upgrade_bits, payload_mode, specials_only)
			end
		else

			local peer_id = session:local_peer():id()
			
			if stuck_enemy then
				local body = ray.body
				local normal = ray.normal
				local parent_obj = body:root_object()
				local global_pos, local_pos, local_rot_vec = tmp_vec1
				mvec3_set(global_pos, ray.position)

				self:_check_unit_attach_segment(stuck_enemy, global_pos)

				local global_rot = tmp_rot1
				mrot_set_look_at(global_rot, normal, math_up)

				if parent_obj then
					local_pos, local_rot_vec = tmp_vec2, tmp_vec3
					local parent_pos, inv_parent_rot = tmp_vec4, tmp_rot2

					parent_obj:m_position(parent_pos)
					parent_obj:m_rotation(inv_parent_rot)
					mrot_inv(inv_parent_rot)

					mvec3_set(local_pos, global_pos)
					mvec3_sub(local_pos, parent_pos)
					mvec3_rot(local_pos, inv_parent_rot)

					mrot_mul(inv_parent_rot, global_rot)
					mvec3_set_stat(local_rot_vec, mrot_yaw(inv_parent_rot), mrot_pitch(inv_parent_rot), mrot_roll(inv_parent_rot))

					local_pos = mvec3_cpy(local_pos)
					local_rot_vec = mvec3_cpy(local_rot_vec)
				end

				local unit = TripMineBase.spawn(global_pos, global_rot, peer_id, upgrade_bits, payload_mode,specials_only)
				unit:base():set_active(true, self._unit, true)
				
				unit:base():attach_to_enemy(stuck_enemy, local_pos, local_rot_vec, parent_obj, radius_upgrade_level, vulnerability_upgrade_level)


				session:send_to_peers_synched("sync_spawn_attach_trip_mine", unit, stuck_enemy, body or nil, parent_obj or nil, local_pos or global_pos, local_rot_vec or normal, peer_id, upgrade_bits, payload_mode, specials_only)
			else
				local rot = tmp_rot1
				mrot_set_look_at(rot, ray.normal, math_up)

				local unit = TripMineBase.spawn(ray.position, rot, peer_id, upgrade_bits, payload_mode, specials_only)
				unit:base():set_active(true, self._unit)
			end
		end
		return true
	end

	return false
end

function PlayerEquipment:valid_look_at_placement(equipment_data, can_place_on_enemies)
	local unit = self._unit
	local mov_ext = unit:movement()
	local from = mov_ext:m_head_pos()
	local to, ray, stuck_enemy = tmp_vec1

	mrot_y(self:_m_deploy_rot(), to)
	mvec3_mul(to, 220)
	mvec3_add(to, from)

	if can_place_on_enemies then
		local raycast_f = unit.raycast
		local slot_manager = managers.slot

		ray = raycast_f(unit, "ray", from, to, "slot_mask", slot_manager:get_mask("enemies"))

		local ray_pos = ray and ray.position

		if ray_pos and not raycast_f(unit, "ray", from, ray_pos, "slot_mask", slot_manager:get_mask("enemy_shield_check"), "report") then
			local obstructed_ray = raycast_f(unit, "ray", from, ray_pos, "slot_mask", slot_manager:get_mask("trip_mine_placeables"), "ray_type", "equipment_placement")

			if obstructed_ray then
				ray = obstructed_ray
			else
				stuck_enemy = ray.unit
			end
		else
			ray = raycast_f(unit, "ray", from, to, "slot_mask", slot_manager:get_mask("trip_mine_placeables"), "ray_type", "equipment_placement")
		end
	else
		ray = unit:raycast("ray", from, to, "slot_mask", managers.slot:get_mask("trip_mine_placeables"), "ray_type", "equipment_placement")
	end

	local dummy_unit = self._dummy_unit

	if ray then
		local equipment_dummy = equipment_data and equipment_data.dummy_unit

		if equipment_dummy then
			local dummy_pos = tmp_vec2
			mvec3_set(dummy_pos, ray.position)

			if stuck_enemy then
				self:_check_unit_attach_segment(stuck_enemy, dummy_pos)
			end

			local dummy_rot = tmp_rot1
			mrot_set_look_at(dummy_rot, ray.normal, math_up)

			if alive_g(dummy_unit) then
				dummy_unit:set_position(dummy_pos)
				dummy_unit:set_rotation(dummy_rot)
			else
				dummy_unit = world_g:spawn_unit(idstr_func(equipment_dummy), dummy_pos, dummy_rot)
				self._dummy_unit = dummy_unit

				self:_disable_contour(dummy_unit)
			end
		end
	end

	if alive_g(dummy_unit) then
		local state = ray and true or false

		dummy_unit:set_enabled(state)
	end

	return ray, stuck_enemy
end

function PlayerEquipment:_check_unit_attach_segment(hit_unit, m_global_pos)
	local damage_ext = hit_unit:character_damage()

	if not damage_ext or not damage_ext.get_impact_segment then
		return
	end

	local parent_obj, child_obj = damage_ext:get_impact_segment(m_global_pos)

	if not parent_obj or not child_obj then
		return
	end

	local parent_pos, child_pos, parent_col_vec, seg_dir, proj_pos, dir_from_seg = tmp_seg_vec1, tmp_seg_vec2, tmp_seg_vec3, tmp_seg_vec4, tmp_seg_vec5, tmp_seg_vec6

	parent_obj:m_position(parent_pos)
	child_obj:m_position(child_pos)

	mvec3_set(parent_col_vec, m_global_pos)
	mvec3_sub(parent_col_vec, parent_pos)

	local segment_len = mvec3_dir(seg_dir, parent_pos, child_pos)
	local proj_len = mvec3_dot(parent_col_vec, seg_dir)
	proj_len = math_clamp(proj_len, 0, segment_len)

	mvec3_set(proj_pos, seg_dir)
	mvec3_mul(proj_pos, proj_len)
	mvec3_add(proj_pos, parent_pos)

	local max_dis_from_seg = 10
	local dis_from_seg = mvec3_dir(dir_from_seg, proj_pos, m_global_pos)

	if max_dis_from_seg < dis_from_seg then
		mvec3_set(m_global_pos, dir_from_seg)
		mvec3_mul(m_global_pos, max_dis_from_seg)
		mvec3_add(m_global_pos, proj_pos)
	end

	return true
end

--[[
function PlayerEquipment:use_trip_mine(...)
	local ray = self:valid_look_at_placement(...)

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
--]]
