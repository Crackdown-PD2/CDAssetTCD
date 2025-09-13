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

--]]