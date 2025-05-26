-- requires TotalCrackdown (BeardLib ModCore) for GetPath()

-- some core functions and data that needs to be available asap (at entry);
-- beardlib's ModCore init is too late, so here we are
DeathvoxOverhaulCore = DeathvoxOverhaulCore or {}
DeathvoxOverhaulCore.MATCHMAKING_KEY = "totalcrackdown_phoenixv1_pd2_" .. string.gsub(Application:version(),"%.","_")

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

DeathvoxOverhaulCore.TCD_GUI_DATA = {
	weapons = {
		class = {
			class_grenade = "guis/textures/pd2/blackmarket/icons/tcd/class_grenade",
			class_heavy = "guis/textures/pd2/blackmarket/icons/tcd/class_heavy",
			class_melee = "guis/textures/pd2/blackmarket/icons/tcd/class_melee",
			class_precision = "guis/textures/pd2/blackmarket/icons/tcd/class_precision",
			class_rapidfire = "guis/textures/pd2/blackmarket/icons/tcd/class_rapidfire",
			class_saw = "guis/textures/pd2/blackmarket/icons/tcd/class_saw",
			class_shotgun = "guis/textures/pd2/blackmarket/icons/tcd/class_shotgun",
			class_specialist = "guis/textures/pd2/blackmarket/icons/tcd/class_specialist",
			class_throwing = "guis/textures/pd2/blackmarket/icons/tcd/class_throwing"
		},
		subclass = {
			subclass_areadenial = "guis/textures/pd2/blackmarket/icons/tcd/subclass_areadenial",
			subclass_poison = "guis/textures/pd2/blackmarket/icons/tcd/subclass_poison",
			subclass_quiet = "guis/textures/pd2/blackmarket/icons/tcd/subclass_quiet"
		}
	}
}

DeathvoxOverhaulCore.TCD_ICON_CHARS = {
	heavy = {
		character = "─",
		macro = "ICN_HVY",
	},
	grenade = {
		character = "┼",
		macro = "ICN_GRN"
	},
	area_denial = {
		character = "═",
		macro = "ICN_ARD"
	},
	throwing = {
		character = "╤",
		macro = "ICN_THR"
	},
	specialist = {
		character = "╥",
		macro = "ICN_SPC"
	},
	shotgun = {
		character = "╦",
		macro = "ICN_SHO"
	},
	saw = {
		character = "╧",
		macro = "ICN_SAW"
	},
	rapidfire = {
		character = "╨",
		macro = "ICN_RPF"
	},
	quiet = {
		character = "╩",
		macro = "ICN_QUT"
	},
	precision = {
		character = "╪",
		macro = "ICN_PRE"
	},
	poison = {
		character = "╫",
		macro = "ICN_POI"
	},
	melee = {
		character = "╬",
		macro = "ICN_MEL"
	}
}

function DeathvoxOverhaulCore.insert_tcd_macros(macros)
	for _,v in pairs(DeathvoxOverhaulCore.TCD_ICON_CHARS) do  --just adds wpn class/subclass icon macros
		if v.macro and v.character then
			macros[v.macro] = v.character
		end
	end
end
	