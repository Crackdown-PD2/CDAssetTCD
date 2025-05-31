Hooks:PostHook(HintManager,"init","tcd_hintmanager_init",function(self)
	self:_parse_hint({
		id = "camera_already_looping",
		text_id = "hud_hint_camera_already_looped",
		event = "stinger_feedback_negative",
		sync = false
	})
end)