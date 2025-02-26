DeathvoxOverhaul._require_libs = {}
function DeathvoxOverhaul:require(path)
	if DeathvoxOverhaul._require_libs[path] then
		return DeathvoxOverhaul._require_libs[path]
	elseif io.file_is_readable(path) then
		local result = blt.vm.dofile(path)
		DeathvoxOverhaul._require_libs[path] = result
		return result
	else
		error("DeathvoxOverhaul:require() File could not be read: " .. tostring(path))
	end
end