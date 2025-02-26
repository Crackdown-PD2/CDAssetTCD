-- requires TotalCrackdown (BeardLib ModCore) for GetPath()

-- some core functions and data that needs to be available asap (at entry);
-- beardlib's ModCore init is too late, so here we are
DeathvoxOverhaulCore = DeathvoxOverhaulCore or {}

DeathvoxOverhaulCore._require_libs = DeathvoxOverhaulCore._require_libs or {}
function DeathvoxOverhaulCore:require(_path)
	local path = TotalCrackdown:GetPath() .. _path .. ".lua"
	if DeathvoxOverhaulCore._require_libs[_path] then
		return DeathvoxOverhaulCore._require_libs[_path]
	elseif io.file_is_readable(path) then
		local result = blt.vm.dofile(path)
		DeathvoxOverhaulCore._require_libs[_path] = result
		return result
	else
		error("CoreDeathvoxOverhaul:require() File could not be read: " .. tostring(path))
	end
end