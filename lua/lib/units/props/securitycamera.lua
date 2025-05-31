--no longer using SecurityCamera.active_tape_loop_unit; instead tracking all looped cameras in the below table (keyed by peer id)
SecurityCamera.all_active_tape_loop_cameras = {}

-- tcd specific cam checking
-- caution: some of these are static and some are not
function SecurityCamera.get_tape_loop_camera_by_peer_id(peer_id)
	return peer_id and SecurityCamera.all_active_tape_loop_cameras[peer_id]
end
function SecurityCamera:register_tape_loop_camera(peer_id)
	SecurityCamera.all_active_tape_loop_cameras[peer_id] = self
end
function SecurityCamera:unregister_tape_loop_by_peer_id(peer_id)
	local cam = SecurityCamera.all_active_tape_loop_cameras[peer_id]
	if cam then
		cam:_unregister_tape_loop()
	end
	SecurityCamera.all_active_tape_loop_cameras[peer_id] = nil
end
function SecurityCamera.unregister_tape_loop_by_ext(ext)
	for peer_id,cam in pairs(SecurityCamera.all_active_tape_loop_cameras) do 
		if cam == ext then
			SecurityCamera.all_active_tape_loop_cameras[peer_id] = nil
			ext:_unregister_tape_loop()
			return true
		end
	end
end
function SecurityCamera:_unregister_tape_loop()
	if alive(self._unit) then
		--[[
		--need to check the extension exists in case this was called upon destruction
		local contour_ext = self._unit:contour()
		if contour_ext then
			contour_ext:remove("mark_unit_friendly")
		end
		--]]
	end
end

function SecurityCamera:sync_net_event(event_id,peer,...)
	local net_events = self._NET_EVENTS
	local peer_id = peer:id()
	--local peer_id = 1

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
function SecurityCamera:start_tape_loop(peer_id)
	local looped_cam = SecurityCamera.all_active_tape_loop_cameras[peer_id]
	if looped_cam and looped_cam ~= self._unit then
		-- if this peer has already looped a different cam, abort
		return
	end
	
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
end

-- tweak looped cam count check, added peer_id arg
function SecurityCamera:_request_start_tape_loop_by_upgrade_level(time_upgrade_level,peer_id)
	if not peer_id then
		return
	end
	
	if not Network:is_server() then
		return
	end

	local looped_cam = SecurityCamera.all_active_tape_loop_cameras[peer_id]
	if looped_cam and looped_cam ~= self._unit then
		-- if this peer has already looped a different cam, abort
		return
	end

	self:_start_tape_loop_by_upgrade_level(time_upgrade_level,peer_id)

	if time_upgrade_level == 1 then
		self:_send_net_event(self._NET_EVENTS.start_tape_loop_1)
	elseif time_upgrade_level == 2 then
		self:_send_net_event(self._NET_EVENTS.start_tape_loop_2)
	end
end

function SecurityCamera:_start_tape_loop_by_upgrade_level(time_upgrade_level,peer_id)
	local tape_loop_t = managers.player:upgrade_value_by_level("player", "tape_loop_duration", time_upgrade_level)

	self:_start_tape_loop(tape_loop_t,peer_id)
end

function SecurityCamera:_start_tape_loop(tape_loop_t,peer_id)
	self:_deactivate_tape_loop_restart()

	self._tape_loop_end_t = Application:time() + tape_loop_t
	--SecurityCamera.active_tape_loop_unit = self._unit
	self:register_tape_loop_camera(peer_id)

	self._unit:contour():add("mark_unit_friendly")

	if self._unit:interaction() then
		self._unit:interaction():set_active(false)
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
end

-- allow reapplying tape loop regardless of current loop timer;
-- other restrictions still apply
function SecurityCamera:can_apply_tape_loop()
	return true
end

-- unregister tape loop on loop stop

function SecurityCamera:_deactivate_tape_loop()
	if Network:is_server() then
		self:_send_net_event(self._NET_EVENTS.deactivate_tape_loop)
	end
--[[
	if SecurityCamera.active_tape_loop_unit and SecurityCamera.active_tape_loop_unit == self._unit then
		SecurityCamera.active_tape_loop_unit = nil
		self._unit:contour():remove("mark_unit_friendly")
	end
--]]
	if self:unregister_tape_loop_by_ext() then
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
end

-- unregister tape loop on expire
Hooks:PreHook(SecurityCamera,"_clbk_tape_loop_expired","tcd_ssecuritycamera_loop_done",function(self,...)
	self:unregister_tape_loop_by_ext()
end)

-- unregister tape loop on destruction
Hooks:PreHook(SecurityCamera,"destroy","tcd_securitycamera_destroy",function(self)
	self:unregister_tape_loop_by_ext()
end)