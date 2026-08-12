ClusterGrenadeBase = ClusterGrenadeBase or blt_class(FragGrenade)

local tmp_mvec1 = Vector3()
local tmp_mvec2 = Vector3()
local tmp_mvec3 = Vector3()
local tmp_mrot1 = Rotation()

function ClusterGrenadeBase:_setup_from_tweak_data(...)
	local tweak_entry = ClusterGrenadeBase.super._setup_from_tweak_data(self,...)
	self._init_timer = self._init_timer + math.random(0.1)
	self._num_submunitions = tweak_entry.num_submunitions
	
	return tweak_entry
end

function ClusterGrenadeBase:throw(params)
	self._owner = params.owner
	if params.submunitions then
		self:set_num_submunitions(params.submunitions)
	end
	local velocity = params.dir
	local adjust_z = params.adjust_z or 50
	local launch_speed = params.launch_speed or 250
	local push_at_body_index

	if params.projectile_entry and tweak_data.projectiles[params.projectile_entry] then
		adjust_z = tweak_data.projectiles[params.projectile_entry].adjust_z or adjust_z
		launch_speed = tweak_data.projectiles[params.projectile_entry].launch_speed or launch_speed
		push_at_body_index = tweak_data.projectiles[params.projectile_entry].push_at_body_index
	end

	velocity = velocity * launch_speed
	velocity = Vector3(velocity.x, velocity.y, velocity.z + adjust_z)

	local mass_look_up_modifier = self._mass_look_up_modifier or 2
	local mass = math.max(mass_look_up_modifier * (1 + math.min(0, params.dir.z)), 1)

	if self._simulated then
		if push_at_body_index then
			self._unit:push_at(mass, velocity, self._unit:body(push_at_body_index):center_of_mass())
		else
			self._unit:push_at(mass, velocity, self._unit:position())
		end
	else
		self._velocity = velocity
	end

	if params.projectile_entry and tweak_data.blackmarket.projectiles[params.projectile_entry] then
		local tweak_entry = tweak_data.blackmarket.projectiles[params.projectile_entry]
		local physic_effect = tweak_entry.physic_effect

		if physic_effect then
			World:play_physic_effect(physic_effect, self._unit)
		end

		if tweak_entry.add_trail_effect then
			self:add_trail_effect(tweak_entry.add_trail_effect)
		end

		local unit_name = tweak_entry.sprint_unit

		if unit_name then
			local new_dir = Vector3(params.dir.y * -1, params.dir.x, params.dir.z)
			local sprint = World:spawn_unit(Idstring(unit_name), self._unit:position() + new_dir * 50, self._unit:rotation())
			local rot = Rotation(params.dir, math.UP)

			mrotation.x(rot, mvec1)
			mvector3.multiply(mvec1, 0.15)
			mvector3.add(mvec1, new_dir)
			mvector3.add(mvec1, math.UP / 2)
			mvector3.multiply(mvec1, 100)
			sprint:push_at(mass, mvec1, sprint:position())
		end

		self:set_projectile_entry(params.projectile_entry)
	end
end


function ClusterGrenadeBase:set_num_submunitions(n)
	self._num_submunitions = n
end

function ClusterGrenadeBase:_detonate(tag, unit, body, other_unit, other_body, position, normal, collision_velocity, velocity, other_velocity, new_velocity, direction, damage, ...)
	local pos = self._unit:position()
	local normal = math.UP
	local range = self._range
	local slot_mask = managers.slot:get_mask("explosion_targets")

	managers.explosion:give_local_player_dmg(pos, range, self._player_damage)
	managers.explosion:play_sound_and_effects(pos, normal, range, self._custom_params)

	local hit_units, splinters = managers.explosion:detect_and_give_dmg({
		player_damage = 0,
		hit_pos = pos,
		range = range,
		collision_slotmask = slot_mask,
		curve_pow = self._curve_pow,
		damage = self._damage,
		ignore_unit = self._unit,
		alert_radius = self._alert_radius,
		critical_chance = self._critical_chance,
		user = self:thrower_unit() or self._unit,
		owner = self._unit
	})
	
	if self._unit:id() ~= -1 then
		managers.network:session():send_to_peers_synched("sync_unit_event_id_16", self._unit, "base", GrenadeBase.EVENT_IDS.detonate)
	end
	
	local owner_peer_id = self._owner_peer_id
	if owner_peer_id and managers.network:session() then
		local peer = managers.network:session():peer(owner_peer_id)
		local thrower_unit = peer and peer:unit()
	end

-- cloned ProjectileBase.throw
	local projectile_type = self:projectile_entry()
	local tweak_entry = tweak_data.blackmarket.projectiles[projectile_type]
	local unit_name = Idstring(not Network:is_server() and tweak_entry.local_unit or tweak_entry.unit)
	if not ProjectileBase.check_time_cheat(projectile_type, owner_peer_id) then
		return
	end


	if not PackageManager:has(Idstring("unit"), unit_name) then
		Application:error("[ProjectileBase.throw_projectile] Trying to spawn an unloaded projectile:", unit_name)

		return
	end

	local projectile_type_index = tweak_data.blackmarket:get_index_from_projectile_id(projectile_type)

--

	local launch_speed = 100
	local launch_pos = tmp_mvec1
	local launch_dir = tmp_mvec2
	local num_children = self._num_submunitions or 0
	local nf = 1/num_children
	for i=1,num_children,1 do 
		local p = i/num_children
		
		-- spawn children at semi random intervals in a circle around the original, with some slight vertical offset and horizontal offsets
		local distance = 2 + math.random(5)
		mvector3.set_static(launch_dir,0,distance,math.random(3))
		
		-- rotate the spawn position (around the z axis)
		local deg_rand = 360 * (math.random() + i) / num_children
		mrotation.set_axis_angle(tmp_mrot1,math.UP,deg_rand)
		mvector3.rotate_with(launch_dir,tmp_mrot1)
		
		mvector3.set(launch_pos,pos)
		mvector3.add(launch_pos,launch_dir)
		mvector3.normalize(launch_dir)
		--mvector3.multiply(launch_dir,launch_speed)
		
		
		local dir = launch_dir

		local unit = World:spawn_unit(unit_name, pos, Rotation(dir, math.UP))
		
		if alive(thrower_unit) then
			unit:base():set_thrower_unit(thrower_unit, true, false)

			if not tweak_entry.throwable and thrower_unit:movement() and thrower_unit:movement():current_state() then
				unit:base():set_weapon_unit(thrower_unit:movement():current_state()._equipped_unit)
			end
		end

		unit:base():throw({
			dir = dir,
			projectile_entry = projectile_type,
			launch_speed = launch_speed,
			submunitions = 0,
			adjust_z = nil
		})

		if unit:base().set_owner_peer_id then
			unit:base():set_owner_peer_id(owner_peer_id)
		end
		managers.network:session():send_to_peers_synched("sync_throw_projectile", unit:id() ~= -1 and unit or nil, pos, dir, projectile_type_index, owner_peer_id or 0)

		if tweak_entry.impact_detonation then
			unit:damage():add_body_collision_callback(callback(unit:base(), unit:base(), "clbk_impact"))
			unit:base():create_sweep_data()
		end
	end
	
	self:_handle_hiding_and_destroying(true, nil)
end

function ClusterGrenadeBase:set_owner_peer_id(peer_id,...)
	self._owner_peer_id = peer_id
	if ClusterGrenadeBase.super.set_owner_peer_id then
		return super.set_owner_peer_id(self,peer_id,...)
	end
end