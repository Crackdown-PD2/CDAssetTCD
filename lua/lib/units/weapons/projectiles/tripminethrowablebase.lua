TripmineThrowableBase = TripmineThrowableBase or class(ProjectileBase)

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
local mvec3_nrm = mvector3.normalize
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

function TripmineThrowableBase:_handle_hiding_and_destroying(...)
	if self._timeout_clbk_id then
		managers.enemy:remove_delayed_clbk(self._timeout_clbk_id)
		self._timeout_clbk_id = nil
	end
	if not self._destroyed then
		TripmineThrowableBase.super._handle_hiding_and_destroying(self,...)
	end
	self:set_active(false)
	self._destroyed = true -- allow this to be called from multiple places, but only executed once
	self._collided = true
end

function TripmineThrowableBase:refund_throwable()
	if self._owner_peer_id and self._owner_peer_id == managers.network:session():local_peer():id() then
		-- placement failed, so destroy it and refund the use
		managers.player:add_grenade_amount(1, true)
	end
	self:_handle_hiding_and_destroying(true,nil)
end

function TripmineThrowableBase:init(unit,...)
	TripmineThrowableBase.super.init(self,unit,...)
	--self._draw_debug_trail = true
	self._orient_to_vel = false
	self._timeout_invalid_timer = 5 -- this many seconds after being thrown, if no valid target hit, refund the use and destroy the object
	
	self._wall_raycast = true
	--asdf = self
end

function TripmineThrowableBase:_setup_server_data()
	self._slot_mask = managers.slot:get_mask("trip_mine_targets") + managers.slot:get_mask("enemies") + managers.slot:get_mask("trip_mine_placeables")
	self._collider_tag_name = Idstring("impact2")
end

function TripmineThrowableBase:throw(params,...)
--	Print("Throwing a projectile",params.projectile_entry)

	self._timeout_clbk_id = "projectile_refund_" .. tostring(self._unit:key())

	managers.enemy:add_delayed_clbk(self._timeout_clbk_id,callback(self,self,"refund_throwable"), TimerManager:game():time() + self._timeout_invalid_timer)
	
	if tweak_data.blackmarket.projectiles[params.projectile_entry].impact_detonation and self._owner_peer_id and self._owner_peer_id ~= managers.network:session():local_peer():id() then
		self._unit:damage():add_body_collision_callback(callback(self,self,"_husk_on_collision"))
	end
	
	self._ignore_units = self._ignore_units or {self._unit}
	-- self:add_ignore_unit(self._unit)
	
	TripmineThrowableBase.super.throw(self,params,...)

	if params.projectile_entry and tweak_data.projectiles[params.projectile_entry] then
		local push_at_body_index = tweak_data.projectiles[params.projectile_entry].push_at_body_index
		local body = self._unit:body(push_at_body_index)
		if body then
			self._rotatey_body = body
		end
	end
end


function TripmineThrowableBase:_on_collision(col_ray)
	
	local body = col_ray.body
	local position = col_ray.position
	local hit_unit = col_ray.unit
	local normal = col_ray.normal
	
--	Print("Collided with ",col_ray.unit)
	
	
	
	local payload_mode = TripmineControlMenu._current_mode
	local specials_only = TripmineControlMenu._current_specials_enabled
	
	local bits = TripMineBase.get_local_upgrade_bits()
	
	local global_pos, local_pos, local_rot_vec = tmp_vec1
	mvec3_set(global_pos, position)
	
	--PlayerEquipment._check_unit_attach_segment(hit_unit, global_pos)
	
	local session = managers.network:session()

	local player_unit = managers.player:local_player()

	if body and hit_unit:in_slot(managers.slot:get_mask("enemies")) then
	
		local parent_obj = body:root_object()
	
		if Network:is_client() then
			-- stuck as client
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
			
			session:send_to_host("request_spawn_attach_trip_mine", hit_unit, body or nil, parent_obj or nil, local_pos or global_pos, local_rot_vec or normal, bits, payload_mode, specials_only)
		else
			-- stuck as host
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

			local peer_id = session:local_peer():id()
			local tripmine_unit = TripMineBase.spawn(global_pos, global_rot, peer_id, bits, payload_mode, specials_only)
			local tripmine_base = tripmine_unit:base()
			tripmine_base:set_active(true, player_unit, true)
			
			tripmine_base:attach_to_enemy(hit_unit, local_pos, local_rot_vec, parent_obj)
			
			managers.network:session():send_to_peers_synched("sync_spawn_attach_trip_mine", tripmine_unit, hit_unit, body or nil, parent_obj or nil, local_pos or global_pos, local_rot_vec or normal, peer_id, bits, payload_mode, specials_only)
		end
		
		--self:_handle_hiding_and_destroying(true,nil)
	else
		
		-- place tripmine on geometry surface
		if Network:is_client() then
			session:send_to_host("place_trip_mine", position, normal, bits, payload_mode, specials_only)
		else	
			local rot = tmp_rot1
			mrot_set_look_at(rot, normal, math_up)

			local tripmine_unit = TripMineBase.spawn(position, rot, session:local_peer():id(), bits, payload_mode, specials_only)
			tripmine_unit:base():set_active(true, player_unit)
			
		end
	end
	
	self:_handle_hiding_and_destroying(true,nil)
	
	return true
end

-- tcd function
-- only called as host when another player's tripmine is removed
function TripmineThrowableBase:_husk_on_collision(...)
	if not self._collided then
		self._collided = true
		self:_handle_hiding_and_destroying(true,nil)
	end
end

-- diesel physics collision callback
-- todo maybe a cylinder cast would work?
function TripmineThrowableBase:clbk_impact(tag, unit, body, other_unit, other_body, position, normal, collision_velocity, velocity, other_velocity, new_velocity, direction, damage, ...)
	--TripmineThrowableBase.super.clbk_impact(self, tag, unit, body, other_unit, other_body, position, normal, collision_velocity, velocity, other_velocity, new_velocity, direction, damage, ...)
	--Print("Impact",tag,collision_velocity, velocity, other_velocity, new_velocity)
	--Print("clbk_impact",tag, unit, body, other_unit, other_body, position, normal, collision_velocity, velocity, other_velocity, new_velocity, direction, damage)
	
	if self._sweep_data and not self._collided then
		mvec3_set(mvec2, self._sweep_data.last_pos)
		if self._wall_raycast then
			if self._wall_raycast == true then
				mvec3_add(mvec2, velocity)
			else
				-- alt. set length of wall raycast; falls apart at unit velocities higher than specified, of course
				local raycast_vel = tmp_vec1
				mvec3_set(raycast_vel,velocity)
				mvec3_nrm(raycast_vel)
				mvec3_mul(raycast_vel,self._wall_raycast)
				mvec3_set(mvec2, self._sweep_data.last_pos)
				mvec3_add(mvec2, raycast_vel)
			end
			-- larger, velocity-based cast to make sure the normal is set properly;
			-- may result in weird snapping to a point past the actual collision, 
			-- in cases where diesel finds that the projectile strikes a corner, but the wall raycast finds a surface past the corner instead;
			-- use for tripmines (since those stick to walls, and we need the accurate position and normal)
			-- do not use for first aid kits (since those do not stick to walls, diesel physics sim is sufficient)
			
			
		else
			-- basegame ray calculation
			mvec3_sub(mvec2, self._sweep_data.last_pos)
			mvec3_mul(mvec2, 2)
			mvec3_add(mvec2, self._sweep_data.last_pos)
		end
		
		--Draw:brush(Color(1,0,1):with_alpha(0.1),10):cylinder(self._sweep_data.last_pos, mvec2, 2) -- draw forward cast
		--Draw:brush(Color(1,0,0.5):with_alpha(0.7),10):cone(self._sweep_data.last_pos, mvec2, 3) -- draw trail
		--Draw:brush(Color.yellow:with_alpha(0.3)):sphere(self._sweep_data.last_pos,50,3)  -- draw impact pos

		local ig_units = self._ignore_units
		local col_ray = unit:raycast("ray", self._sweep_data.last_pos, mvec2, "slot_mask", self._sweep_data.slot_mask, ig_units and "ignore_unit" or nil, ig_units or nil)

		if col_ray then
			if self._draw_debug_impact then
				Draw:brush(Color(0.5, 0, 0, 1), nil, 10):sphere(col_ray.position, 4)
				Draw:brush(Color(0.5, 1, 0, 0), nil, 10):sphere(self._unit:position(), 3)
			end

			mvec3_dir(mvec1, self._sweep_data.last_pos, col_ray.position)
			mvec3_add(mvec1, col_ray.position)
			self._unit:set_position(mvec1)
			self._unit:set_position(mvec1)

			col_ray.velocity = velocity

			if self:_on_collision(col_ray) then
				self._collided = true
			end
		end
	end
end

-- rotating the body, 
-- manual collision raycast (success conditional on callback determination in _on_collision())
-- TODO visual rotating stuff should be handled in a different way
-- note: look into rotating body params in object file
function TripmineThrowableBase:update(unit, t, dt)
	if not self._simulated and not self._collided then
		self._unit:m_position(mvec1)
		mvector3.set(mvec2, self._velocity * dt)
		mvector3.add(mvec1, mvec2)
		self._unit:set_position(mvec1)

		if self._orient_to_vel then
			mrotation.set_look_at(mrot1, mvec2, math.UP)
			self._unit:set_rotation(mrot1)
		end

		self._velocity = Vector3(self._velocity.x, self._velocity.y, self._velocity.z - 980 * dt)
	end
	
	if self._rotatey_body then
		local _body = self._rotatey_body
		local rotation = _body:rotation()
		local yaw = rotation:yaw()
		local pitch = rotation:pitch() - (dt * 360)
		local roll = rotation:roll()
		_body:set_rotation(Rotation(yaw,pitch,roll + (dt * 30)))
	end

	if self._sweep_data and not self._collided then
		self._unit:m_position(self._sweep_data.current_pos)

		local raycast_params = {
			"ray",
			self._sweep_data.last_pos,
			self._sweep_data.current_pos,
			"slot_mask",
			self._sweep_data.slot_mask
		}

		if self._ignore_units then
			table.list_append(raycast_params, {
				"ignore_unit",
				self._ignore_units
			})
		end

		if self._sphere_cast_radius then
			table.list_append(raycast_params, {
				"sphere_cast_radius",
				self._sphere_cast_radius,
				"bundle",
				4
			})
		end
		--[[
		local to_pos = self._sweep_data.current_pos
		local dir = (self._sweep_data.last_pos - to_pos)
		local length = mvector3.normalize(dir)
		dir = dir * (length + 100)
		to_pos = to_pos + dir
		
--		Draw:brush(Color(1,0,1):with_alpha(0.1),10):cylinder(self._sweep_data.last_pos, self._sweep_data.current_pos, 2)
--		Draw:brush(Color(1,0,0.5):with_alpha(0.7),10):cone(self._sweep_data.last_pos, to_pos, 3)
--		Draw:brush(Color.yellow:with_alpha(0.3)):sphere(self._sweep_data.current_pos,50,3)
		local ray = false and self._unit:raycast("ray", self._sweep_data.last_pos, to_pos, "slot_mask", managers.slot:get_mask("trip_mine_placeables"), "ignore_unit", self._ignore_units, "ray_type", "equipment_placement")
		if ray and ray.unit then
			Print("Update ray hit")
--			mvector3.direction(mvec1, self._sweep_data.last_pos, self._sweep_data.current_pos)
--			mvector3.add(mvec1, ray.position)
--			self._unit:set_position(mvec1)
--			self._unit:set_position(mvec1)

			if self._draw_debug_impact then
				Draw:brush(Color(0.5, 0, 0, 1), nil, 10):sphere(ray.position, 4)
				Draw:brush(Color(0.5, 1, 0, 0), nil, 10):sphere(self._unit:position(), 3)
			end
			
			-- todo visualize 
			
			if ray.normal then
				Draw:brush(Color.red:with_alpha(0.3),5):cone(ray.position,ray.position + ray.normal * 100,25)
			end
			if ray.direction then
				Draw:brush(Color.blue:with_alpha(0.3),5):cone(ray.position,ray.position + ray.direction * 100,25)
			end
			
			ray.velocity = self._unit:velocity()
			self._collided = true

			self:_on_collision(ray)
			
			
			--self._unit:m_position(self._sweep_data.last_pos)

			if self._warning_fx_vfx_data then
				self:_warning_fx_vfx_upd(unit, t, dt, self._warning_fx_vfx_data)
			end
			
			return
		end
		--]]
		local col_ray = World:raycast(unpack(raycast_params))

		if self._draw_debug_trail then
			if self._sphere_cast_radius then
				Draw:brush(Color(0.25, 0, 0, 1), nil, 3):cylinder(self._sweep_data.last_pos, self._sweep_data.current_pos, self._sphere_cast_radius, 4)
			else
				Draw:brush(Color(0.25, 0, 0, 1), nil, 3):line(self._sweep_data.last_pos, self._sweep_data.current_pos)
			end
		end

		if col_ray and col_ray.unit then
			mvector3.direction(mvec1, self._sweep_data.last_pos, self._sweep_data.current_pos)
			mvector3.add(mvec1, col_ray.position)
			self._unit:set_position(mvec1)
			self._unit:set_position(mvec1)

			if self._draw_debug_impact then
				Draw:brush(Color(0.5, 0, 0, 1), nil, 10):sphere(col_ray.position, 4)
				Draw:brush(Color(0.5, 1, 0, 0), nil, 10):sphere(self._unit:position(), 3)
			end

			col_ray.velocity = self._unit:velocity()

			if self:_on_collision(col_ray) then
				self._collided = true
			end
		end

		self._unit:m_position(self._sweep_data.last_pos)
	end

	if self._warning_fx_vfx_data then
		self:_warning_fx_vfx_upd(unit, t, dt, self._warning_fx_vfx_data)
	end
end

function TripmineThrowableBase:set_owner_peer_id(peer_id)
	self._owner_peer_id = peer_id 
end

function TripmineThrowableBase:outside_worlds_bounding_box(...)
	self:refund_throwable()
	return TripmineThrowableBase.super.outside_worlds_bounding_box(self,...)
end