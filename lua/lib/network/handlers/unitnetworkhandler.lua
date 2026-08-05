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
	--Print("place_trip_mine",pos, normal, upgrade_bits, payload_mode, specials_only, rpc)
	local peer = self._verify_sender(rpc)

	if not self._verify_gamestate(self._gamestate_filter.any_ingame) or not peer then
		return
	end

--	if not managers.player:verify_grenade(peer:id()) then
--		return
--	end

	local rot = Rotation(normal, math.UP)
	local peer = self._verify_sender(rpc)
	local unit = TripMineBase.spawn(pos, rot, peer:id(), upgrade_bits, payload_mode, specials_only)

	unit:base():set_server_information(peer:id())
	rpc:activate_trip_mine(unit)
end

function UnitNetworkHandler:sync_trip_mine_setup(unit, peer_id, upgrade_bits, payload_mode, specials_only)
--	Print("sync_trip_mine_setup", unit, peer_id, upgrade_bits, payload_mode, specials_only)
	if not alive(unit) or not self._verify_gamestate(self._gamestate_filter.any_ingame) then
		return
	end
	

	--managers.player:verify_grenade(peer_id)
	unit:base():sync_setup(upgrade_bits, payload_mode, specials_only)
end

-- as host, receive from client: request spawning and attaching a tripmine to the given enemy
function UnitNetworkHandler:request_spawn_attach_trip_mine(parent_unit, parent_body, synced_parent_object, local_pos, normal, upgrade_bits, payload_mode, specials_only, sender)
--	Print("incoming client request_spawn_attach_trip_mine:",parent_unit, parent_body, synced_parent_object, local_pos, normal, upgrade_bits, payload_mode, specials_only, sender)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) then
		return
	end
	local peer = self._verify_sender(sender)
	if not peer then
		return
	end
	
	local peer_id = peer:id()
	
	
	-- anticheat
--	if not managers.player:verify_grenade(peer_id) then
--		return
--	end
	
	local parent_is_alive = alive(parent_unit)
	local parent_object = nil
	
	if parent_is_alive then
		if alive(parent_body) then
			parent_object = parent_body:root_object()
		else
			parent_object = alive(synced_parent_object) and synced_parent_object
		end
	end
	
	local world_position, world_rotation = nil

	if parent_object then
		local obj_rot = parent_object:rotation()

		world_position = local_pos:rotate_with(obj_rot) + parent_object:position()
		world_rotation = Rotation(normal.x, normal.y, normal.z) * obj_rot
	else
		world_position = Vector3()
		world_rotation = Rotation()
	end


local local_rot_vec = nil -- not sure what to do with that

	local tripmine_unit = TripMineBase.spawn(world_position, world_rotation, peer_id, upgrade_bits, payload_mode, specials_only)
	local tripmine_base = tripmine_unit:base()
	tripmine_base:set_active(true, peer:unit(), true) -- note: in vanilla this is always the local player; revert if problematic
	tripmine_base:set_server_information(peer_id)
	tripmine_base:attach_to_enemy(parent_unit, local_pos, normal, parent_object, radius_upgrade_level, vulnerability_upgrade_level)
	
	if parent_is_alive and parent_unit:id() ~= -1 then
		managers.network:session():send_to_peers_synched("sync_spawn_attach_trip_mine", tripmine_unit, parent_unit, parent_body or nil, synced_parent_object or nil, local_pos or world_position, local_rot_vec or normal, peer_id, upgrade_bits, payload_mode, specials_only)
	else
		-- probably needs to send a refund message to the owner
	end
end

-- as client, receive from host: sync enemy-stuck tripmine setup details to clients
function UnitNetworkHandler:sync_spawn_attach_trip_mine(tripmine_unit, parent_unit, parent_body, synced_parent_object, local_pos, normal, owner_peer_id, upgrade_bits, payload_mode, specials_only, sender)
--	Print("incoming server sync_spawn_attach_trip_mine",tripmine_unit, "parent",parent_unit, "body",parent_body, "obj",synced_parent_object, "pos",local_pos, "normal",normal, "peerid",owner_peer_id, "bits",upgrade_bits, "payload",payload_mode, "specials",specials_only, sender)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) and not self._verify_gamestate(self._gamestate_filter.any_end_game) or not self._verify_sender(sender) then
		return
	end
	
	
	local tripmine_base = tripmine_unit:base()
	
	tripmine_base:sync_setup(upgrade_bits,payload_mode,specials_only)
	tripmine_base:attach_to_enemy(parent_unit, local_pos, normal, synced_parent_object, nil,nil)
	
end



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

--]]