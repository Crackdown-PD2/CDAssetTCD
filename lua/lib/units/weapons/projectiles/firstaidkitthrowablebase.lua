FirstAidKitThrowableBase = FirstAidKitThrowableBase or class(TripmineThrowableBase)

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

function FirstAidKitThrowableBase:init(...)
	FirstAidKitThrowableBase.super.init(self,...)
	self._wall_raycast = 50 -- 50cm; likely to bounce when angle of attack is close to parallel with impact surface
end

function FirstAidKitThrowableBase:_setup_server_data()
	self._slot_mask = managers.slot:get_mask("trip_mine_placeables")
	self._collider_tag_name = Idstring("impact1") -- identifies the body involved in the collision
end

function FirstAidKitThrowableBase:_on_collision(col_ray)
	local success
	--Print("Collision")
	local position = col_ray.position
	local normal = col_ray.normal
	
	
--	Draw:brush(Color(1,0,0.5):with_alpha(0.7),10):cone(position + (normal * 100),position, 3) -- draw normal
--	Draw:brush(Color(1,0,1):with_alpha(0.1),10):cylinder(position, position + col_ray.velocity, 2) -- draw velocity ray

	local revivable_unit = nil
	
	local closest_rev_dis = managers.player:upgrade_value("first_aid_kit", "deploy_auto_recovery",0)

	if closest_rev_dis > 0 then
		local nearby_criminals = world_g:find_units_quick("sphere" , position, closest_rev_dis, managers.slot:get_mask("criminals_no_deployables"))

		for i = 1, #nearby_criminals do
			local criminal = nearby_criminals[i]
			local ext_mov = criminal:movement()

			if ext_mov and ext_mov.downed and ext_mov:downed() then
				local dis = mvec3_dis(position, ext_mov:m_pos())

				if dis < closest_rev_dis then
					closest_rev_dis = dis
					revivable_unit = criminal
				end
			end
		end
	end
	
	Print(mvector3.angle(col_ray.ray,math.DOWN))
	
	if mvector3.angle(normal,math.UP) < 50 and mvector3.angle(col_ray.ray,math.DOWN) < 90 then
		-- must land on a valid, relatively flat surface (no mountain goat faks on sheer vertical surfaces)
		-- cannot land on the underside of a ceiling surface
		-- a bit of a slope is okay
		local session = managers.network:session()
		local player_unit = managers.player:local_player()
		
		if Network:is_server() then
			success = player_unit:equipment():use_first_aid_kit(col_ray,revivable_unit)
		else
			-- send place fak request
			local upgrade_lvl = managers.player:upgrade_level("first_aid_kit", "damage_overshield", 0)
			local auto_recovery = managers.player:upgrade_level("first_aid_kit", "first_aid_kit_auto_recovery", 0)
			local bits = Bitwise:lshift(auto_recovery, FirstAidKitBase.auto_recovery_shift) + Bitwise:lshift(upgrade_lvl, FirstAidKitBase.upgrade_lvl_shift)
			
			mrot_set_look_at(tmp_rot1, normal, math_up)
			mrot_set(tmp_rot2, mrot_yaw(tmp_rot1), 0, 0)
			
			managers.network:session():send_to_host("place_deployable_bag", "FirstAidKitBase", position, tmp_rot1, bits)
			
			-- assume we succeeded; if the 
			success = true
		end
	else
		success = false
	end
	
	if success then
		self:_handle_hiding_and_destroying(true,nil)
	end
	
	return success
end
