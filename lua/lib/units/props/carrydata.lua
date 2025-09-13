CarryData._valid_civs = {}
CarryData._carrying_units = {}

local mvec3_dis = mvector3.distance
local alive_g = alive
local pairs_g = pairs
local ids_char_g_body = Idstring("g_body")
local ids_char_g_body_lod0 = Idstring("g_body_lod0")
local ids_char_s_body = Idstring("s_body")

function CarryData:_update_throw_link(unit, t, dt)
	if self._linked_to or not self._spawn_time or t > self._spawn_time + 1 or not self._link_obj or not self._link_obj:visibility() then
		return false
	end

	local carrying_units = CarryData.carry_links
	
	local bag_center = self._link_obj:oobb():center()
	local links = CarryData.carry_links
	local oobb_mod = self._oobb_mod

	for u_key, entry in pairs_g(managers.groupai:state():all_AI_criminals()) do
		if not links[u_key] then
			local mov_ext = entry.unit:movement()

			if not mov_ext.vehicle_unit and not mov_ext:cool() and not mov_ext:downed() then
				local body_oobb = entry.unit:oobb()

				body_oobb:grow(oobb_mod)

				if body_oobb:point_inside(bag_center) then
					body_oobb:shrink(oobb_mod)
					entry.unit:sound():say("r03x_sin", true)
					self:link_to(entry.unit)

					return false
				end

				body_oobb:shrink(oobb_mod)
			end
		end
	end


	for key, civ in pairs_g(CarryData._valid_civs) do
		if not links[key] then
			
			local get_obj_f = civ.get_object
			local body = get_obj_f(civ, ids_char_g_body) or get_obj_f(civ, ids_char_g_body_lod0) or get_obj_f(civ, ids_char_s_body)

			if body then
				local body_oobb = body:oobb()
				--body_oobb:debug_draw(1, 1, 1)
				body_oobb:grow(oobb_mod)
				--body_oobb:debug_draw(1, 1, 1)

				if body_oobb:point_inside(bag_center) then
					body_oobb:shrink(oobb_mod)

					self:link_to(civ, false)

					break
				end
				
				body_oobb:shrink(oobb_mod)
			else
				local mov_ext = civ:movement()
				local sphere_size = 75 + oobb_mod
				local m_com = mov_ext:m_com()

				--draw_sphere_f(app, m_com, sphere_size, 1, 1, 1)

				if mvec3_dis(m_com, bag_center) < sphere_size then
					self:link_to(civ, false)

					break
				end
			end
		end
	end

	return true
end
