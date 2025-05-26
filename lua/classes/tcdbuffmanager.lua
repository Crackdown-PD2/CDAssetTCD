-- feed buff data to hudbuff

local TCDBuffManager = blt_class()

function TCDBuffManager:init()
	self._listeners = {}
end

function TCDBuffManager:add_listener(event,listener_id,cb,priority)
	self._listeners[event] = self._listeners[event] or {}
	self._listeners[event][listener_id] = cb
end

function TCDBuffManager:remove_listener(event,listener_id)
	self._listeners[event][listener_id] = nil
end

function TCDBuffManager:call_listeners(event,...)
	for _,cb in pairs(self._listeners[event]) do 
		cb(...)
	end
end

function TCDBuffManager:pre_destroy()
	self._listeners = nil
end


return TCDBuffManager