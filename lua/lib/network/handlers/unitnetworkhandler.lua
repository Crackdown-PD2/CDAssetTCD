function UnitNetworkHandler:sync_drill_upgrades(unit, shocktrap_level, auto_repair_level, speed_upgrade_level, silent_drill, shocktrap_alert, sender_rpc)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) or not self._verify_sender(sender_rpc) then
		return
	end
	log("Incoming sync drill upgrades: shocktrap",shocktrap_level,"autorepair",auto_repair_level,"speed",speed_upgrade_level, "silent",silent_drill,"shockalert",shocktrap_alert)

	local base_ext = alive(unit) and unit:base()

	if base_ext and base_ext.set_skill_upgrades then
		base_ext:set_skill_upgrades(Drill.create_upgrades(shocktrap_level, auto_repair_level, speed_upgrade_level, silent_drill, shocktrap_alert))
	end
end

-- tcd function
-- as client, received from host
function UnitNetworkHandler:from_server_early_hostage_trade_response(unit,success,reason,sender)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) then
		return
	end
	local peer = self._verify_sender(sender)
	if not peer then
		return
	end
	local peer_id = peer:id()
	--log("Received from_server_early_hostage_trade_response",tostring(unit),"success",success,"reason",reason,"peer_id",tostring(peer_id))
	managers.trade:receive_trade_response(unit,success,reason,peer_id)
end

-- tcd function
-- as host, received from client
function UnitNetworkHandler:request_early_hostage_trade(unit,sender)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) then
		return
	end
	local peer = self._verify_sender(sender)
	if not peer then
		return
	end
	local peer_id = peer:id()
	--log("Received request_early_hostage_trade",tostring(unit),"peer_id",tostring(peer_id))
	managers.trade:receive_early_trade_request(unit,peer_id)
end




-- ==================================== TRIPMINES
function UnitNetworkHandler:place_trip_mine(pos, normal, upgrade_bits, payload_mode, specials_only, rpc)
	local peer = self._verify_sender(rpc)

	if not self._verify_gamestate(self._gamestate_filter.any_ingame) or not peer then
		return
	end

	if not managers.player:verify_equipment(peer:id(), "trip_mine") then
		return
	end

	local rot = Rotation(normal, math.UP)
	local peer = self._verify_sender(rpc)
	local unit = TripMineBase.spawn(pos, rot, peer:id(), upgrade_bits, payload_mode, specials_only)

	unit:base():set_server_information(peer:id())
	rpc:activate_trip_mine(unit)
end

function UnitNetworkHandler:sync_trip_mine_setup(unit, peer_id, upgrade_bits, payload_mode, specials_only)
	if not alive(unit) or not self._verify_gamestate(self._gamestate_filter.any_ingame) then
		return
	end

	managers.player:verify_equipment(peer_id, "trip_mine")
	unit:base():sync_setup(upgrade_bits, payload_mode, specials_only)
end

--used for tripmine syncing when attached to an enemy
local orig_sync_attach_projectile = UnitNetworkHandler.sync_attach_projectile
function UnitNetworkHandler:sync_attach_projectile(unit, instant_dynamic_pickup, parent_unit, parent_body, synced_parent_object, synced_pos, dir, projectile_type_index, peer_id, sender)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) then
		return
	end

	local peer = self._verify_sender(sender)

	if not peer then
		return
	end

	if alive(unit) then
		local base_ext = unit:base()

		if base_ext and base_ext.NAME == "TripMineBase" then -- alt. can check getmetatable()
			local is_server = Network:is_server()

			--since this is a tripmine, and it works as a throwable/grenade, use the throwable anticheat check
			if is_server and not managers.player:verify_grenade(peer_id) then
				return
			end

			local bits = projectile_type_index - 1
			local radius_upgrade_level = Bitwise:rshift(bits, TripMineBase.UPGRADE_SHIFT_RADIUS)
			local vulnerability_upgrade_level = Bitwise:rshift(bits, TripMineBase.UPGRADE_SHIFT_VULN) % 2^TripMineBase.UPGRADE_SHIFT_VULN
			local parent_is_alive = alive(parent_unit)
			local local_pos = mvector3.copy(synced_pos)
			local parent_object = nil

			if parent_is_alive then
				if alive(parent_body) then
					parent_object = parent_body:root_object()
				else
					parent_object = alive(synced_parent_object) and synced_parent_object
				end
			end

			if Network:is_server() then
				local world_position, world_rotation = nil

				if parent_object then
					local obj_rot = parent_object:rotation()

					world_position = local_pos:rotate_with(obj_rot) + parent_object:position()
					world_rotation = Rotation(dir.x, dir.y, dir.z) * obj_rot
				else
					world_position = Vector3()
					world_rotation = Rotation()
				end

				local tripmine_unit = TripMineBase.spawn(world_position, world_rotation, false, peer_id)

				tripmine_unit:base():set_server_information(peer_id)

				if parent_is_alive and parent_unit:id() ~= -1 then
					managers.network:session():send_to_peers_synched("sync_attach_projectile", tripmine_unit, false, parent_unit, parent_body or nil, synced_parent_object or nil, synced_pos, dir, projectile_type_index, peer_id)
				else
					managers.network:session():send_to_peers_synched("sync_attach_projectile", tripmine_unit, false, nil, nil, nil, synced_pos, dir, projectile_type_index, peer_id)
				end

				tripmine_unit:base():attach_to_enemy(parent_unit, local_pos, dir, parent_object, radius_upgrade_level, vulnerability_upgrade_level)
			elseif base_ext.get_name_id and base_ext:get_name_id() == "trip_mine" then
				if managers.network:session():local_peer():id() == peer_id then
					base_ext:set_active(true, managers.player:player_unit(), true)
				end

				base_ext:attach_to_enemy(parent_unit, local_pos, dir, parent_object, radius_upgrade_level, vulnerability_upgrade_level)
			end

			return
		end
	end

	--assume that this is the spoofed function
	return orig_sync_attach_projectile(self, unit, instant_dynamic_pickup, parent_unit, parent_body, synced_parent_object, synced_pos, dir, projectile_type_index, peer_id, sender)
end


-- test these
function UnitNetworkHandler:request_spawn_attach_trip_mine(parent_unit, parent_body, synced_parent_object, local_pos, normal, upgrade_bits, payload_mode, specials_only, rpc)
	Print("incoming client request_spawn_attach_trip_mine:",parent_unit, parent_body, synced_parent_object, local_pos, normal, upgrade_bits, payload_mode, specials_only, rpc)
end
		
function UnitNetworkHandler:sync_spawn_attach_trip_mine(parent_unit, parent_body, synced_parent_object, local_pos, normal, owner_peer_id, upgrade_bits, payload_mode, specials_only, rpc)
	Print("incoming server sync_spawn_attach_trip_mine",parent_unit, parent_body, synced_parent_object, local_pos, normal, owner_peer_id, upgrade_bits, payload_mode, specials_only, rpc)
end


--function UnitNetworkHandler:sync_attach_throwable_tripmine(unit, parent_unit, parent_body, parent_object, local_pos, dir, projectile_type_index, peer_id, sender, upgrade_bits, payload_mode, specials_only)	
--end

		
--[[
function UnitNetworkHandler:sync_attach_projectile(unit, instant_dynamic_pickup, parent_unit, parent_body, parent_object, local_pos, dir, projectile_type_index, peer_id, sender)
	local peer = self._verify_sender(sender)

	if not self._verify_gamestate(self._gamestate_filter.any_ingame) or not peer then
		print("_verify failed!!!")

		return
	end

	local projectile_type = tweak_data.blackmarket:get_projectile_name_from_index(projectile_type_index)

	if not projectile_type then
		return
	end
	
	local world_position = parent_object and local_pos:rotate_with(parent_object:rotation()) + parent_object:position() or local_pos

	if Network:is_server() then
		local tweak_entry = tweak_data.blackmarket.projectiles[projectile_type]
		local unit_name = Idstring(tweak_entry.unit)
		local synced_unit = World:spawn_unit(unit_name, world_position, Rotation(dir, math.UP))

		managers.network:session():send_to_peers_synched("sync_attach_projectile", synced_unit, instant_dynamic_pickup, alive(parent_unit) and parent_unit:id() ~= -1 and parent_unit or nil, alive(parent_unit) and parent_unit:id() ~= -1 and parent_body or nil, alive(parent_unit) and parent_unit:id() ~= -1 and parent_object or nil, local_pos, dir, projectile_type_index, peer_id)
		synced_unit:base():set_thrower_unit_by_peer_id(peer_id)
		synced_unit:base():set_projectile_entry(projectile_type)
		synced_unit:base():sync_attach_to_unit(instant_dynamic_pickup, parent_unit, parent_body, parent_object, local_pos, dir)
	elseif unit then
		unit:set_position(world_position)
		unit:base():set_thrower_unit_by_peer_id(peer_id)
		unit:base():set_projectile_entry(projectile_type)
		unit:base():sync_attach_to_unit(instant_dynamic_pickup, parent_unit, parent_body, parent_object, local_pos, dir)
	end

	if peer_id ~= 1 then
		local dummy_unit = ArrowBase.find_nearest_arrow(peer_id, world_position)

		if dummy_unit then
			dummy_unit:set_slot(0)
		end
	end
end
--]]









--[[
-- from owner peer
-- todo replace UnitNetworkHandler:picked_up_sentry_gun()
function UnitNetworkHandler:sync_tcdsentry_pickup(unit,sender)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) or not self._verify_character_and_sender(unit, sender) then
		return
	end
	
	if unit:base():owner() ~= sender then
		return
	end
	
	Print("Picking up unit",unit,"sender",sender)
	--
	--unit:set_slot(0)
end

-- from owner peer
-- todo replace UnitNetworkHandler:sentrygun_ammo()
function UnitNetworkHandler:sync_tcdsentry_state(unit,ammo_index,mode_index,sender)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) or not self._verify_character_and_sender(unit, sender) then
		return
	end
	
	if unit:base():owner() ~= sender then
		return
	end
	
	local ammo_type = SentryControlMenu.ammo_string_to_index(ammo_index)
	local fire_mode = SentryControlMenu.mode_string_to_index(mode_index)
	
	local sentry_ext = unit:base()
	sentry_ext:set_state(ammo_type,fire_mode)
end

-- [[

function UnitNetworkHandler:sync_tcdtripmine_state(unit,sender,ammo_type,fire_mode)

end

function UnitNetworkHandler:sync_tcdtripmine_pickup(unit,sender)
	
end


-- tcd function
-- similar to request_throw_projectile, except this is a purely visual physics simulation
-- clientside projectile disappears on contact with surface,
-- actual result is client-authoritative from projectile owner and synced independently
function UnitNetworkHandler:sync_projectile_husk(proj_id,pos,direction,sender)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) then
		return
	end

	local peer = self._verify_sender(rpc)
	if not peer then
		return
	end
	local peer_id = peer:id()
	local td = proj_id and tweak_data.blackmarket.projectiles[id]
	
	
	
	
end


--]]