--no longer using SecurityCamera.active_tape_loop_unit; instead tracking all looped cameras in the below table (keyed by peer id)
SecurityCamera.all_active_tape_loop_cameras = {}
SecurityCamera._LOOP_RESTART_T = 5 -- grace period after a loop expires when the camera is still not active but is about to be (blinking contour)

-- tcd specific cam checking
-- caution: some of these are static and some are not

--- return int or nil
function SecurityCamera.get_tape_loop_camera_by_peer_id(peer_id)
	return peer_id and SecurityCamera.all_active_tape_loop_cameras[peer_id]
end
function SecurityCamera:register_tape_loop_camera(peer_id)
	SecurityCamera.all_active_tape_loop_cameras[peer_id] = self
end
--- return bool success
function SecurityCamera:unregister_tape_loop_by_peer_id(peer_id)
	local cam = SecurityCamera.all_active_tape_loop_cameras[peer_id]
	SecurityCamera.all_active_tape_loop_cameras[peer_id] = nil
	if cam then
		cam:_unregister_tape_loop()
		return true
	end
	return false
end
--- return bool success
function SecurityCamera.unregister_tape_loop_by_ext(ext)
	for peer_id,cam in pairs(SecurityCamera.all_active_tape_loop_cameras) do 
		if cam == ext then
			SecurityCamera.all_active_tape_loop_cameras[peer_id] = nil
			ext:_unregister_tape_loop()
			return true
		end
	end
	return false
end
function SecurityCamera:_unregister_tape_loop()
	if alive(self._unit) then
		--[[
		-- actually it should be fine, contour removal should be handled by other functions
		
		--need to check the extension exists in case this was called upon destruction
		local contour_ext = self._unit:contour()
		if contour_ext then
			contour_ext:remove("mark_unit_friendly")
		end
		--]]
	end
end
--- return int peer_id or nil
function SecurityCamera.get_loop_owner_peer_id(ext)
	for peer_id,cam in pairs(SecurityCamera.all_active_tape_loop_cameras) do 
		if cam == ext then
			return peer_id
		end
	end
end

-- add peer arg, pass peer_id arg
-- (peer was already passed from the caller, just not used in the sig)
function SecurityCamera:sync_net_event(event_id,peer,...)
	local net_events = self._NET_EVENTS
	local peer_id = peer:id()

	if net_events.suspicion_1 <= event_id and event_id <= net_events.suspicion_6 then
		local suspicion_lvl = (event_id - net_events.suspicion_1 + 1) / 6

		self:_set_suspicion_sound(suspicion_lvl)
	elseif event_id == net_events.sound_off then
		self:_stop_all_sounds()
	elseif event_id == net_events.alarm_start then
		self:_sound_the_alarm()
	elseif event_id == net_events.start_tape_loop_1 then
		self:_start_tape_loop_by_upgrade_level(1,peer_id)
	elseif event_id == net_events.start_tape_loop_2 then
		self:_start_tape_loop_by_upgrade_level(2,peer_id)
	elseif event_id == net_events.request_start_tape_loop_1 then
		self:_request_start_tape_loop_by_upgrade_level(1,peer_id)
	elseif event_id == net_events.request_start_tape_loop_2 then
		self:_request_start_tape_loop_by_upgrade_level(2,peer_id)
	elseif event_id == net_events.deactivate_tape_loop then
		self:_deactivate_tape_loop()
	end
end



-- tweak looped cam count check, added peer_id arg
-- this is the entry point for the whole camera behavior tree
Hooks:OverrideFunction(SecurityCamera,"start_tape_loop",function(self,peer_id)
--	if alive(SecurityCamera.active_tape_loop_unit) then
--		return
--	end

	local time_upgrade_level = managers.player:upgrade_level("player", "tape_loop_duration", 0)

	if Network:is_server() then
		self:_start_tape_loop_by_upgrade_level(time_upgrade_level,peer_id)

		if time_upgrade_level == 1 then
			self:_send_net_event(self._NET_EVENTS.start_tape_loop_1)
		elseif time_upgrade_level == 2 then
			self:_send_net_event(self._NET_EVENTS.start_tape_loop_2)
		end
	elseif time_upgrade_level == 1 then
		self:_send_net_event(self._NET_EVENTS.request_start_tape_loop_1)
	elseif time_upgrade_level == 2 then
		self:_send_net_event(self._NET_EVENTS.request_start_tape_loop_2)
	end
end)

-- tweak looped cam count check, added peer_id arg
Hooks:OverrideFunction(SecurityCamera,"_request_start_tape_loop_by_upgrade_level",function(self,time_upgrade_level,peer_id)
	if not peer_id then
		return
	end
	
	if not Network:is_server() then
		return
	end
--[[
	local looped_cam = SecurityCamera.all_active_tape_loop_cameras[peer_id]
	if looped_cam and looped_cam ~= self._unit then
		-- if this peer has already looped a different cam, abort
		return
	end
--]]

	self:_start_tape_loop_by_upgrade_level(time_upgrade_level,peer_id)

	if time_upgrade_level == 1 then
		self:_send_net_event(self._NET_EVENTS.start_tape_loop_1)
	elseif time_upgrade_level == 2 then
		self:_send_net_event(self._NET_EVENTS.start_tape_loop_2)
	end
end)

-- add peer_id arg
Hooks:OverrideFunction(SecurityCamera,"_start_tape_loop_by_upgrade_level",function(self,time_upgrade_level,peer_id)
	local tape_loop_t = managers.player:upgrade_value_by_level("player", "tape_loop_duration", time_upgrade_level)
	self:_start_tape_loop(tape_loop_t,peer_id)
end)

Hooks:OverrideFunction(SecurityCamera,"_start_tape_loop",function(self,tape_loop_t,peer_id)
	local prev_cam = SecurityCamera.get_tape_loop_camera_by_peer_id(peer_id)
	if prev_cam and prev_cam ~= self and not prev_cam:destroyed() then
		if prev_cam._tape_loop_expired_clbk_id and not prev_cam._tape_loop_restarting_t then
			managers.enemy:remove_delayed_clbk(prev_cam._tape_loop_expired_clbk_id)
			
			prev_cam._tape_loop_end_t = nil
			prev_cam._tape_loop_expired_clbk_id = nil
			
			-- start the grace period on the previous cam
			-- and unregister it from the "looped cams" list
			prev_cam:_clbk_tape_loop_expired()
		end
	end
	
	self:_deactivate_tape_loop_restart()

	self._tape_loop_end_t = Application:time() + tape_loop_t
	--SecurityCamera.active_tape_loop_unit = self._unit
	self:register_tape_loop_camera(peer_id)

	self._unit:contour():add("mark_unit_friendly")

	if self._unit:interaction() then
		-- allow refreshing the tape loop duration if already active
		self._unit:interaction():set_active(true) -- was false
	end

	if self._camera_wrong_image_sound then
		self._camera_wrong_image_sound:stop()
	end

	self._camera_wrong_image_sound = self._unit:sound_source():post_event("camera_wrong_image")

	if self._tape_loop_expired_clbk_id then
		managers.enemy:remove_delayed_clbk(self._tape_loop_expired_clbk_id)

		self._tape_loop_expired_clbk_id = nil
	end

	self._tape_loop_expired_clbk_id = "tape_loop_expired" .. tostring(self._unit:key())

	managers.enemy:add_delayed_clbk(self._tape_loop_expired_clbk_id, callback(self, self, "_clbk_tape_loop_expired"), self._tape_loop_end_t)
end)

-- allow reapplying tape loop regardless of current loop timer;
-- other restrictions still apply
Hooks:OverrideFunction(SecurityCamera,"can_apply_tape_loop",function(self)
	return true
end)

-- unregister tape loop on loop stop
Hooks:OverrideFunction(SecurityCamera,"_deactivate_tape_loop",function(self)
	if Network:is_server() then
		self:_send_net_event(self._NET_EVENTS.deactivate_tape_loop)
	end
--[[
	if SecurityCamera.active_tape_loop_unit and SecurityCamera.active_tape_loop_unit == self._unit then
		SecurityCamera.active_tape_loop_unit = nil
		self._unit:contour():remove("mark_unit_friendly")
	end
--]]
	if self:unregister_tape_loop_by_ext() then -- changed check to unregister the prev cam
		self._unit:contour():remove("mark_unit_friendly")
	end

	if self._tape_loop_expired_clbk_id then
		managers.enemy:remove_delayed_clbk(self._tape_loop_expired_clbk_id)

		self._tape_loop_end_t = nil
		self._tape_loop_expired_clbk_id = nil
	end

	if self._camera_wrong_image_sound then
		self._camera_wrong_image_sound:stop()

		self._camera_wrong_image_sound = nil
	end

	if self._tape_loop_restarting_t then
		self:_deactivate_tape_loop_restart()
	end

	if self._unit:interaction() then
		self._unit:interaction():set_active(false)
	end
end)

-- unregister tape loop on expire
Hooks:OverrideFunction(SecurityCamera,"_clbk_tape_loop_expired",function(self,...)
	self._tape_loop_expired_clbk_id = nil
	self._tape_loop_end_t = nil

	self._unit:contour():remove("mark_unit_friendly")

	if self._unit:interaction() then
		self._unit:interaction():set_active(true)
	end

	if self._destroyed then
		return
	end
	
	-- only two changes are changing the restart duration magic number to the const _LOOP_RESTART_T,
	-- and changing the security camera unregister method 
	self:_activate_tape_loop_restart(self._LOOP_RESTART_T)
	self:unregister_tape_loop_by_ext()
--	SecurityCamera.active_tape_loop_unit = nil
end)
-- unregister tape loop on destruction
Hooks:PreHook(SecurityCamera,"destroy","tcd_securitycamera_destroy",function(self)
	self:unregister_tape_loop_by_ext()
end)