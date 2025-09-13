-- todo clear request of peer if peer disconnects

TradeManager._EARLY_TRADE_TIMEOUT = 10 -- after this many seconds, the request will "timeout" allowing the client's timeout check to pass and the client to make another early trade request
TradeManager._EARLY_TRADE_RESULTS = {
	[0] = "hud_tcd_early_trade_success",
	[1] = "hud_tcd_early_trade_fail_reason_invalidunit",
	[2] = "hud_tcd_early_trade_fail_reason_unitpendingtrade",
	[3] = "hud_tcd_early_trade_fail_reason_playerpendingtrade", -- local check only
	[4] = "hud_tcd_early_trade_fail_reason_playermaxlives", -- local check only
	[5] = "hud_tcd_early_trade_pending" -- local check only
}

Hooks:PostHook(TradeManager,"init","tcd_trademanager_init",function(self)
	-- tcd var;
	-- holds list of civilians being used for trades;
	-- this list is not synced, so clients will only populate this with their own trades,
	-- while hosts will track all clients' requests
	self._pending_trades = {
	--[[
		[Idstring d34db33f] = { -- example
			peer_id = peer_id,
			timeout_callback_id = "timeout_d3adb33f"
		}
	--]]
	}
end)

-- tcd function
-- externally visible/universal entry point to early trades, from client or host
function TradeManager:attempt_early_trade(unit)
	-- check if unit is valid
	if not self:is_tradable_civilian(trade_unit) then
		return false,TradeManager._EARLY_TRADE_RESULTS[1]
	elseif not self:is_unit_pending_trade(trade_unit) then
		return false,TradeManager._EARLY_TRADE_RESULTS[2]
	else
		local player = managers.player:local_player()
		local player_char_dmg = player:character_damage()
		local current_revives = player_char_dmg:get_revives()
		local max_revives = player_char_dmg:get_max_revives()
		if current_revives < max_revives then
			local session = managers.network:session()
			local local_peer_id = session:local_peer():id()
			if self:peer_has_pending_trade(local_peer_id) then
				-- already has pending trade
				return false,TradeManager._EARLY_TRADE_RESULTS[3]
			end
			
			if Network:is_server() then
				managers.trade:start_early_trade(unit)
				player_char_dmg:change_revives(1,false)
				return true,TradeManager._EARLY_TRADE_RESULTS[0]
			else
				self:send_early_trade_request()
				return true,TradeManager._EARLY_TRADE_RESULTS[5]
			end
		else
			return false,TradeManager._EARLY_TRADE_RESULTS[4]
		end
	end
end

-- tcd function
-- used as client and host
-- can be used for both down-restore trades and for custody-release trades
-- note: does not check whether unit is already in a pending trade req, since that is managed by host
function TradeManager:is_tradable_civilian(unit)
	-- must be extant, not deleted
	if not alive(unit) then
		return false
	end
	
	-- must have a character damage extension
	local dmg_ext = unit:character_damage()
	if not dmg_ext then
		return false
	end
	
	-- must be alive
	if dmg_ext:dead() then
		return false
	end
	
	-- must not have a pickup
	if dmg_ext:pickup() then
		-- don't allow trading civilians with key items
		return false
	end
	
	-- must be civilian
	if not managers.enemy:is_civilian(unit) then
		return false
	end

	-- must be tied
	if not (unit:brain().is_tied and unit:brain():is_tied()) then
		return false
	end
	
	return true
end

-- tcd function
-- used as host
-- if the unit is being used in a pending trade, return the peer id of the criminal instigator
function TradeManager:get_peer_id_for_unit_pending_trade(unit)
	local data = self._pending_trades[unit:key()]
	if data then
		return data.peer_id
	end
end

-- tcd function
-- used as host and client
function TradeManager:peer_has_pending_trade(peer_id)
	for u_key,data in pairs(self._pending_trades) do 
		if peer_id == data.peer_id then
			return true
		end
	end
	return false
end

-- tcd function
-- used as host
-- called when a peer disconnects, to clear their pending trade requests from any units
function TradeManager:clear_peer_trade_requests(peer_id)
	for u_key,data in pairs(self._pending_trades) do 
		if peer_id == data.peer_id then
			self._pending_trades[u_key] = nil
		end
	end
end

-- tcd function
-- used as client and host
-- returns whether or not the unit is part of a pending trade already
function TradeManager:is_unit_pending_trade(unit)
	return self._pending_trades[unit:key()] and true or false
end

-- tcd function
--- used by clients when meleeing a prospective trade target;
--- prevents further trade requests from being produced locally
--- until a "decline" response is received (from server), or the request times out (locally enforced)
--- also used by hosts to track requests from all clients
function TradeManager:register_pending_request(unit,peer_id)
	local u_key = unit:key()
	
	local clbk_id
	if not Network:is_server() then
		clbk_id = "trademanager_early_trade_timeout_" .. tostring(u_key)
		
		managers.enemy:add_delayed_clbk(
			clbk_id,
			callback(self,self,"_unregister_pending_request",u_key),
			TimerManager:game():time() + TradeManager._EARLY_TRADE_TIMEOUT
		)
	end
	
	self._pending_trades[u_key] = {
		peer_id = peer_id,
		timeout_callback_id = clbk_id
	}
end

-- tcd function
-- used as client and host
-- remove this unit from the "pending trade" list
function TradeManager:unregister_pending_request(unit)
	local u_key = unit:key()
	local data = self._pending_trades[u_key]
	if data.timeout_callback_id then
		managers.enemy:remove_delayed_clbk(data.timeout_callback_id)
	end
	self:_unregister_pending_request(u_key)
end
function TradeManager:_unregister_pending_request(unit_key)
	self._pending_trades[unit_key] = nil
end

-- tcd function
-- used as client only
function TradeManager:send_early_trade_request(unit)
	if Network:is_server() then
		-- shouldn't ever be used as host
		log("TradeManager:send_early_trade_request() Can't send trade request as host!",tostring(unit))
		return
	end
	log("Sending message","request_early_hostage_trade",unit)
	managers.network:session():send_to_host("request_early_hostage_trade",unit)
end

-- tcd function
-- Unit unit (traded civ unit), Int sender (peer_id)
function TradeManager:receive_early_trade_request(unit,sender)
	local success = nil
	local reason = 0
	
	if self:is_tradable_civilian(unit) then
		if self:is_unit_pending_trade(unit) then
			success = false
			reason = 2
		else
			self:register_pending_request(unit,sender) -- this is only reset when the civilian escapes
			success = true
		end
		
	else
		success = false
		reason = 1
	end
	
	self:start_early_trade(unit)
	
	
	-- if you want a delay, put it here before the response
	self:send_early_trade_response(unit,success,reason)
end

-- tcd function
-- used as host only
function TradeManager:send_early_trade_response(unit,success,reason)
	local peer_id = self:get_peer_id_for_unit_pending_trade(unit)
	local session = managers.network:session()
	local peer = session:peer(peer_id)
	if peer then
		log("Sending message","from_server_early_hostage_trade_response",unit,success,reason)
		-- reason is only applicable if success is false
--		session:send_to_peer(peer,"from_server_early_hostage_trade_response",unit,success,reason)
	end
end

-- tcd function
-- used as client only
function TradeManager:receive_trade_response(unit,success,reason)
	--[[
	reason: (int)
	0: success
	1: unit is not a civilian hostage
	2: unit is already being traded
	--]]
	
	local skip_hint = false
	
	if not self:peer_has_pending_trade(managers.network:session():local_peer():id()) then
		skip_hint = true
		log("TradeManager:receive_trade_response() Received trade response from server but client has no pending trades (???)")
	end
	
	if success then
		log("TradeManager:receive_trade_response() Successful trade response:",tostring(unit),success,reason)
		local player = managers.player:local_player()
		if alive(player) then
			if managers.player:has_category_upgrade("player","civilian_early_trade_restores_down") then
				local downs_restored = managers.player:upgrade_value("player","civilian_early_trade_restores_down",0)
				player:character_damage():change_revives(downs_restored,false)
				self:unregister_pending_request(unit)
			end
		end
	else
		log("TradeManager:receive_trade_response() Unsuccessful trade response:",tostring(unit),success,reason)
	end
	
	if not skip_hint then
		local reason_text = reason and TradeManager._EARLY_TRADE_RESULTS[reason]
		if reason_text then
			managers.hud:show_hint({text = managers.localization:text(reason_text)})
		end
	end
end

-- tcd function
-- host only
-- called on successful early trade
-- tell the unit to get up and escape,
-- set the contour, sync the result to clients etc.
function TradeManager:start_early_trade(unit)
	if not Network:is_server() then
		return
	end
	if not alive(unit) then
		log("TradeManager:start_early_trade() Dead unit!",tostring(unit))
	end
	
--	local contour_ext = unit:contour()
--	if contour_ext then
--	end
	
	local brain = unit:brain()
	brain:set_logic("trade", {
		skip_hint = true
	})
	
	if Network:is_server() then
		local u_key = unit:key()
		local destroyed_clbk_key = "trademanager_early_trade_on_destroyed_" .. tostring(u_key)
		local death_clbk_key = "trademanager_early_trade_on_death_" .. tostring(u_key)
		self:register_pending_request(unit,managers.network:session():local_peer():id())
		unit:base():add_destroy_listener(destroyed_clbk_key, callback(self, self, "_unregister_pending_request",u_key))
		unit:character_damage():add_listener(death_clbk_key, {
			"death"
		}, callback(self, self, "_unregister_pending_request",u_key))
	end
	brain:on_trade(unit:position(), unit:rotation(), false)
end