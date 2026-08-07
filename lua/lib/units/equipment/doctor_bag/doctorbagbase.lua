--DoctorBagBase.DRAW_HOT_CYLINDER_Z_OFFSET = Vector3(0,0,-10)
--DoctorBagBase.DRAW_HOT_CYLINDER_Z_HEIGHT = Vector3(0,0,400)
DoctorBagBase._HOT_DRAW_ALPHA_BY_TIER = {
	0.25,
	0.5,
	1
}
DoctorBagBase._HOT_DRAW_COLOR = Color(1,1,0)
DoctorBagBase._HOT_TETHER_DRAW_COLOR = Color(1,1,0)
DoctorBagBase.UPGRADE_SHIFT_HEALAURA = 2
DoctorBagBase.UPGRADE_SHIFT_OVERSHIELD = 4


local mvec3_dis = mvector3.distance
local mvec3_set = mvector3.set
-- list of objects with Healing-Over-Time auras
DoctorBagBase.hot_list = {}

-- CD func
function DoctorBagBase._register_hot(obj, pos, min_distance, upgrade_lvl)
	table.insert(DoctorBagBase.hot_list,{
		obj = obj,
		pos = pos,
		min_distance = min_distance,
		upgrade_lvl = upgrade_lvl
	})
end

-- CD func
function DoctorBagBase._unregister_hot(obj)
	for i, o in pairs(DoctorBagBase.hot_list) do
		if obj == o.obj then
			table.remove(DoctorBagBase.hot_list,i)
			return
		end
	end
end

--since this includes a raycast LoS check, it is not recommended to call this every frame
function DoctorBagBase.get_best_hot(pos)
	local best_bag,best_distance
	local max_upgrade_lvl = 0
	for i=#DoctorBagBase.hot_list,1,-1 do 
		local o = DoctorBagBase.hot_list[i]
		local dst = mvec3_dis(pos, o.pos)
--		local t = managers.player:player_timer():time()
		if alive(o.obj._unit) then 
			if dst <= o.min_distance and o.upgrade_lvl > max_upgrade_lvl then
				local raycast = World:raycast("ray",o.pos,pos,"slot_mask",managers.slot:get_mask("world_geometry"),"ignore_unit",o.obj._unit)
				if not raycast then 
					best_distance = dist
					best_bag = o.obj
					max_upgrade_lvl = o.upgrade_lvl
				end
			end
		else
			DoctorBagBase._unregister_hot(obj)
		end
	end
	return best_bag,max_upgrade_lvl,best_distance
end

Hooks:OverrideFunction(DoctorBagBase,"_get_upgrade_levels",function(self, bits)
	local upgrade_lvl_overshield = Bitwise:rshift(bits, DoctorBagBase.UPGRADE_SHIFT_OVERSHIELD)
	local upgrade_lvl_healaura = Bitwise:rshift(bits, DoctorBagBase.UPGRADE_SHIFT_HEALAURA) % 2^DoctorBagBase.UPGRADE_SHIFT_HEALAURA

	return upgrade_lvl_healaura, upgrade_lvl_overshield
end)

Hooks:OverrideFunction(DoctorBagBase,"setup",function(self, bits)
	local amount_upgrade_lvl = 0
	local dmg_reduction_lvl = 0
	self._damage_reduction_upgrade = dmg_reduction_lvl ~= 0
	local doctor_bag_amount_increase = managers.player:upgrade_value_by_level("doctor_bag", "amount_increase", amount_upgrade_lvl)
	
	-- add upgrade value change from bits
	
	local upgrade_lvl_healaura,upgrade_lvl_overshield = self:_get_upgrade_levels(bits)
	
--	Print("bits",bits,"Heal level",upgrade_lvl_healaura,"overshield level",upgrade_lvl_overshield)
	
	if upgrade_lvl_healaura > 0 then
		local upgrade_data = managers.player:upgrade_value_by_level("doctor_bag", "heal_aura", upgrade_lvl_healaura,nil)
		if upgrade_data ~= 0 then
			self._should_upd_hot = true
			self._hot_radius = upgrade_data.radius
			self._hot_brush = Draw:brush(DoctorBagBase._HOT_DRAW_COLOR:with_alpha(DoctorBagBase._HOT_DRAW_ALPHA_BY_TIER[upgrade_lvl_healaura] or 1))
			
			local vec3_center_pos = self._unit:oobb():center()
			
			self._hot_draw_pos = vec3_center_pos
			
			-- use oobb instead of root position,
			-- so it's lifted off the floor a bit and doesn't collide with the floor it's sitting on
			DoctorBagBase._register_hot(self,vec3_center_pos,self._hot_radius,upgrade_lvl_healaura)
		end
		
	else
		self._should_upd_hot = nil
	end
	
	self._healaura_upgrade_level = upgrade_lvl_healaura
	
	self._overshield_upgrade_level = upgrade_lvl_overshield
	
	self._amount = tweak_data.upgrades.doctor_bag_base + doctor_bag_amount_increase

	self:_set_visual_stage()

	if Network:is_server() and self._is_attachable then
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
			
			-- set flag to update body if valid;
			-- this is separate from other update checks
			self._should_upd_body = true
			
--			self._unit:set_extension_update_enabled(Idstring("base"), true)
		end
	end
	
	-- main change: set updater enabled regardless of server/client status,
	-- so that heal over time can always be calculated on the clientside
	if self._should_upd_body or self._should_upd_hot then
		self._unit:set_extension_update_enabled(Idstring("base"), true)
	end
end)

function DoctorBagBase:take(unit)
	if self._empty then
		return
	end

	if self._damage_reduction_upgrade then
		managers.player:activate_temporary_upgrade("temporary", "first_aid_damage_reduction")
	end
	
	if self._overshield_upgrade_level then
		-- add overshield
		unit:character_damage():_activate_preventative_care(self._overshield_upgrade_level)
	end
	
	local taken = self:_take(unit)

	if taken > 0 then
		unit:sound():play("pickup_ammo")
		managers.network:session():send_to_peers_synched("sync_doctor_bag_taken", self._unit, taken)
		managers.mission:call_global_event("player_refill_doctorbag")
	end

	if self._amount <= 0 then
		self:_set_empty()
	else
		self:_set_visual_stage()
	end

	return taken > 0
end


Hooks:OverrideFunction(DoctorBagBase,"update",function(self, unit, t, dt)
	if self._should_upd_body then
		self:_check_body()
	end
	if self._should_upd_hot then
		self:_upd_hot(unit,t,dt)
	end
end)

-- CD function- NOTE: this is the visual only! for the HOT calculation, check playerdamage
function DoctorBagBase:_upd_hot(unit,t,dt)
	if self._is_dynamic then
		mvec3_set(self._hot_draw_pos,self._unit:oobb():center())
	end
	self._hot_brush:circle(self._hot_draw_pos,self._hot_radius,5)
end

Hooks:PostHook(DoctorBagBase,"_set_empty","cd_docbag_set_empty",function(self)
	DoctorBagBase._unregister_hot(self)
end)

Hooks:PreHook(DoctorBagBase,"destroy","cd_docbag_set_empty",function(self)
	DoctorBagBase._unregister_hot(self)
end)