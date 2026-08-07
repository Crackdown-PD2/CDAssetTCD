FirstAidKitThrowableBase = class(TripmineThrowableBase)

local mvec1 = Vector3()
local mvec2 = Vector3()
local mvec3 = Vector3()
local mrot1 = Rotation()

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

function FirstAidKitThrowableBase:_setup_server_data()
	self._slot_mask = managers.slot:get_mask("trip_mine_placeables")
end

function FirstAidKitThrowableBase:_on_collision(col_ray)
	--Print("Collision")
end

function FirstAidKitThrowableBase:clbk_impact(tag, unit, body, other_unit, other_body, position, normal, collision_velocity, velocity, other_velocity, new_velocity, direction, damage, ...)
	--TripmineThrowableBase.super.clbk_impact(self, tag, unit, body, other_unit, other_body, position, normal, collision_velocity, velocity, other_velocity, new_velocity, direction, damage, ...)
	--Print("clbk_impact",tag, unit, body, other_unit, other_body, position, normal, collision_velocity, velocity, other_velocity, new_velocity, direction, damage)
	local ray
	if tag == Idstring("impact1") and not self._is_detonated then
		-- stuck to world
		
		-- do custom raycast to check placement;
		-- diesel physics collision is not to be trusted here
		if self._sweep_data then
			local from_pos = self._sweep_data.last_pos -- position is current position after collision, but last_pos is the position from prev frame
			-- since we don't trust the results of the physics engine collision,
			-- we're going to pretend it didn't happen and just calculate a collision detection from the previous frame's position
			local to_pos = tmp_vec1
			mvec3_set(to_pos,position)
			mvec3_add(to_pos,velocity)
			
--			Draw:brush(Color(1,0,1):with_alpha(0.1),10):cylinder(from_pos, to_pos, 2) -- draw forward cast
--			Draw:brush(Color(1,0,0.5):with_alpha(0.7),10):cone(from_pos, to_pos, 3) -- draw trail
--			Draw:brush(Color.yellow:with_alpha(0.3),3):sphere(from_pos,50,3)  -- draw current pos
			
			ray = self._unit:raycast("ray", from_pos, to_pos, "slot_mask", self._sweep_data.slot_mask, "ignore_unit", self._ignore_units, "ray_type", "equipment_placement")
			if ray then
--				normal = ray.normal
--				position = ray.position
			end
		end
		
--		if normal then
--			Draw:brush(Color.red:with_alpha(0.3),5):cone(position,position + normal * 100,25)
--		end
--		if direction then
--			Draw:brush(Color.blue:with_alpha(0.3),5):cone(position,position + direction * 100,25)
--		end
		
		self:_handle_hiding_and_destroying(true,nil)
		self._is_detonated = true
		
		local revivable_unit = nil
		
		local autorevive_level = 0
		local closest_rev_dis = managers.player:upgrade_value_by_level("first_aid_kit", "auto_revive", autorevive_level,0)

		if closest_rev_dis > 0 then
			local nearby_criminals = world_g:find_units_quick(unit, "sphere" , position, closest_rev_dis, managers.slot:get_mask("criminals_no_deployables"))

			for i = 1, #nearby_criminals do
				local criminal = nearby_criminals[i]
				local ext_mov = criminal:movement()

				if ext_mov and ext_mov.downed and ext_mov:downed() then
					local dis = mvec3_dis(dummy_pos, ext_mov:m_pos())

					if dis < closest_rev_dis then
						closest_rev_dis = dis
						revivable_unit = criminal
					end
				end
			end
		end
		
		
		local session = managers.network:session()
		local player_unit = managers.player:local_player()
		
		if Network:is_server() then
			player_unit:equipment():use_first_aid_kit(ray,revivable_unit)
		else
			-- send place fak request
			local upgrade_lvl = managers.player:upgrade_level("first_aid_kit", "damage_overshield", 0)
			local auto_recovery = managers.player:upgrade_level("first_aid_kit", "first_aid_kit_auto_recovery", 0)
			local bits = Bitwise:lshift(auto_recovery, FirstAidKitBase.auto_recovery_shift) + Bitwise:lshift(upgrade_lvl, FirstAidKitBase.upgrade_lvl_shift)
			
			mrot_set_look_at(tmp_rot1, ray.normal, math_up)
			mrot_set(tmp_rot2, mrot_yaw(tmp_rot1), 0, 0)
			
			managers.network:session():send_to_host("place_deployable_bag", "FirstAidKitBase", position, tmp_rot1, bits)
		end
		
	end
	
	if self._sweep_data and not self._collided then
		mvector3.set(mvec2, position)
		mvector3.subtract(mvec2, self._sweep_data.last_pos)
		mvector3.multiply(mvec2, 2)
		mvector3.add(mvec2, self._sweep_data.last_pos)

		local ig_units = self._ignore_units
		local col_ray = World:raycast("ray", self._sweep_data.last_pos, mvec2, "slot_mask", self._sweep_data.slot_mask, ig_units and "ignore_unit" or nil, ig_units or nil)

		if col_ray and col_ray.unit then
			if self._draw_debug_impact then
				Draw:brush(Color(0.5, 0, 0, 1), nil, 10):sphere(col_ray.position, 4)
				Draw:brush(Color(0.5, 1, 0, 0), nil, 10):sphere(self._unit:position(), 3)
			end

			mvector3.direction(mvec1, self._sweep_data.last_pos, col_ray.position)
			mvector3.add(mvec1, col_ray.position)
			self._unit:set_position(mvec1)
			self._unit:set_position(mvec1)

			col_ray.velocity = velocity
			self._collided = true

			self:_on_collision(col_ray)
		end
	end
end

