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

FirstAidKitThrowableBase.MAX_DEPLOY_ANGLE_NORMAL = 55 -- cannot land on a slope steeper than this many degrees
FirstAidKitThrowableBase.MAX_DEPLOY_ANGLE_DIRECTION = 90 -- cannot land if it is currently moving upward (aka if its azimuth is greater than 0)

function FirstAidKitThrowableBase:init(...)
	FirstAidKitThrowableBase.super.init(self,...)
	self._wall_raycast = 50 -- 50cm; likely to bounce when angle of attack is close to parallel with impact surface
	
	self._slot_mask = managers.slot:get_mask("trip_mine_placeables")
	self._collider_tag_name = Idstring("impact1") -- identifies the body involved in the collision
end

function FirstAidKitThrowableBase:_on_collision(col_ray)
	
	local success = false
	
	if col_ray then
	
		-- this check only applies to thrown FAKs;
		-- regularly deployed FAKs should only need to follow the same restrictions of the preview placement in PlayerEquipment
		if mvector3.angle(col_ray.normal,math.UP) < FirstAidKitThrowableBase.MAX_DEPLOY_ANGLE_NORMAL and mvector3.angle(col_ray.ray,math.DOWN) < FirstAidKitThrowableBase.MAX_DEPLOY_ANGLE_DIRECTION then
			-- must land on a valid, relatively flat surface (no mountain goat faks on sheer vertical surfaces)
			-- cannot land on the underside of a ceiling surface
			-- a bit of a slope is okay
			
			local position = col_ray.position
			local revivable_unit
			
			local player = managers.player:local_player()
			local eq_ext = player:equipment()
			
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
			
			success = eq_ext:use_first_aid_kit(col_ray,revivable_unit)
		end
	end
	
	if success then
		self:_handle_hiding_and_destroying(true,nil)
	end
	
	return success
end
