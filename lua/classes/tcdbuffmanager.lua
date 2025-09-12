-- feed buff data to hudbuff

local TCDBuffManager = blt_class()

function TCDBuffManager:init()
	self._listeners = {}
	self._updaters = {}
end

function TCDBuffManager:update(t,dt)
	for id,cb in pairs(self._updaters) do 
		cb(t,dt)
	end
end

function TCDBuffManager:add_updater(id,cb)
	self._updaters[id] = cb
end

function TCDBuffManager:has_updater(id)
	return self._updaters[id] and true or false
end

function TCDBuffManager:remove_updater(id)
	self._updaters[id] = nil
end

function TCDBuffManager:add_listener(event,listener_id,cb)
	self._listeners[event] = self._listeners[event] or {}
	self._listeners[event][listener_id] = cb
end

function TCDBuffManager:remove_listener(event,listener_id)
	if self._listeners[event] then
		self._listeners[event][listener_id] = nil
	end
end

function TCDBuffManager:call_listeners(event,...)
	if self._listeners[event] then
		for _,cb in pairs(self._listeners[event]) do 
			cb(...)
		end
	end
end

function TCDBuffManager:pre_destroy()
	self._listeners = nil
end


return TCDBuffManager