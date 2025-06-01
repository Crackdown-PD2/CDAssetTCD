function UnitNetworkHandler:sync_drill_upgrades(unit, shocktrap_level, auto_repair_level, speed_upgrade_level, silent_drill, shocktrap_alert, sender_rpc)
	if not self._verify_gamestate(self._gamestate_filter.any_ingame) or not self._verify_sender(sender_rpc) then
		return
	end
	--log("Incoming sync drill upgrades: shocktrap",shocktrap_level,"autorepair",auto_repair_level,"speed",speed_upgrade_level, "silent",silent_drill,"shockalert",shocktrap_alert)

	local base_ext = alive(unit) and unit:base()

	if base_ext and base_ext.set_skill_upgrades then
		base_ext:set_skill_upgrades(Drill.create_upgrades(shocktrap_level, auto_repair_level, speed_upgrade_level, silent_drill, shocktrap_alert))
	end
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