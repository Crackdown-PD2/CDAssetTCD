Hooks:PostHook(WeaponTweakData,"init","tcd_weapontd_init",function(self,tweak_data)
--Player Sentry stats here
	local function rpm(n) --converts rounds per minute to seconds per round
		local rounds_per_second = n / 60
		return 1 / rounds_per_second
	end
	
	--BASIC
--	self.sentry_gun.KEEP_FIRE_ANGLE = 0.1
	self.sentry_gun.auto.fire_rate = rpm(400)
	self.sentry_gun.DAMAGE = 5
	self.sentry_gun.FIRE_RANGE = 2000
	self.sentry_gun.SPREAD = 10
	self.sentry_gun.DETECTION_RANGE = 2000
	self.sentry_gun.WEAPON_HEAT_INIT = 0
	self.sentry_gun.WEAPON_HEAT_GAIN_RATE = 1 --heat gained per kill
	self.sentry_gun.WEAPON_HEAT_MAX = 75 
	self.sentry_gun.WEAPON_HEAT_DAMAGE_PENALTY = -0.01 -- -1% damage penalty per heat point
	
	self.sentry_gun.WEAPON_HEAT_OVERHEAT_THRESHOLD = 50 --threshold at which the heat value causes the sentry gun to overheat and shut down (not used) 
	
	--AP
	self.sentry_ap = table.deep_map_copy(self.sentry_gun)
	self.sentry_ap.DAMAGE = 10
	self.sentry_ap.auto.fire_rate = rpm(100)
	self.sentry_ap.can_shoot_through_enemy = true
	self.sentry_ap.can_shoot_through_shield = true
	self.sentry_ap.can_shoot_through_wall = false
	self.sentry_ap.muzzleflash = "effects/particles/weapons/mp5/scene_m_muzzle"
	
	--HE
	self.sentry_he = table.deep_map_copy(self.sentry_gun)
	self.sentry_he.DAMAGE = 5
	self.sentry_he.auto.fire_rate = rpm(100)
	self.sentry_he.muzzleflash = "effects/particles/weapons/shotgun/muzzleflash"
	
	--TASER
	self.sentry_taser = table.deep_map_copy(self.sentry_gun)
	self.sentry_taser.DAMAGE = 1.5
	self.sentry_taser.auto.fire_rate = rpm(400)
	self.sentry_taser.SUPPRESSION = 0
	self.sentry_taser.muzzleflash = "effects/particles/weapons/silenced/muzzleflash"
--	self.sentry_gun.SPREAD = 5 -- NOTE discuss removal
--	self.sentry_gun.FIRE_RANGE = 5000
end)

Hooks:PostHook(WeaponTweakData, "_init_stats", "tcd_weapontd_extrammostattweak", function(self) --total crackdown overhaul stat modifications
	self.stats.extra_ammo = {}

	for i = -100, 100, 1 do --overwrite extra_ammo so that it accepts odds
		table.insert(self.stats.extra_ammo, i)
	end
end)

Hooks:PostHook(WeaponTweakData, "_init_data_player_weapons", "tcd_weapontd_load_player_weapon_stats", function(self, tweak_data) --total crackdown overhaul weapons
-- NOTE: the below notes are from a time when each weapon's balance stats were entered manually in weapontweakdata.
-- The structure of weapon stats in the game data is still the same,
-- but now, TCD weapon stats are entered in a spreadsheet, downloaded as csvs, and parsed into game data. See below for the link:
-- https://docs.google.com/spreadsheets/d/1zZlGRYfnp6kHd6Vzm_pbJUCiLhY5pU-sWg_pYs-IQOU/edit#gid=0
---------------
-- ********************************************************************************************************************************
---------------





--In-game name/Internal name.
	
--Fire Rate/Fire Rate: In-game number is rounds per minute, in code, it's a division of that value in order to achieve proper firerates.
--480 rounds per minute = 8 rounds per second, divide a second by 8 and you get the Chimano 88's firerate, beware of decimal hell.
	
--Category: Not shown in-game, category is more of a "tag" kind of thing, this is important for allowing weapon skills to work appropriately, refer to the Total Crackdown weapon rebalance document for easy data-entry: https://docs.google.com/document/d/1UvE_RL1hncNjAvg6pZsvIfT__appMF8N58eOoAEtYFg/edit
	
--I have provided an example with the new_m4/CAR-4, asval/Valkyria Rifle, and the contraband/Little Friend, refer to the original game's weapontweakdata, and do as I did, preserve the original tags just in case.
	
--rapidfire
--quiet
--precision
--shotgun (already set on most shotguns, keep that in mind.)
--heavy
--specialist
--saw		
--tagging grenades and throwing weapons isnt done here, but in blackmarkettweakdata instead

--Ammo Pickup: Acquire two values, the first value is the ammo pickup minimum, the second value is the pickup max, don't forget to calculate for walk-in closet if that's going to be in the overhaul.
	
--Piercing: All kinds can be defined with armor_piercing_chance being set to 1, can_shoot_through_enemy being set to true, can_shoot_through_shield being set to true and can_shoot_through_wall being set to true, I'm not sure what the effects of having some of the more extreme ones being set to true, while smaller ones being set to nil would be, be careful.
	
--Stability/Recoil: 1 point = 3, to get a weapon with 44 stability, the number you'd enter would end up being 12, the decimal is rounded down to 3, which results in the weapon having "44" stability in the weapon stat screen.

--Accuracy/Spread, Spread_Moving: Same as above, 1 = 3.

--Threat/Suppression: Instead of counting upwards, this one counts downwards, 1 = -3 from max Threat that can be achieved in-game (I assume), so for a weapon to have 28 threat, it's suppression would be "5", for a weapon to have 37 threat, it's suppression would be "2". Also, Suppression appears to be used as an index (probably in a lookup table), so it must be an integer.

--Damage/Damage: Consistent, 1 = 1, don't forget to calculate for Fast and Furious, if that's going to be in the overhaul, due to limitations, in order to achieve 200+ numbers, it needs to use a multiplier in a separate table, which will be included for every weapon, for consistency reasons, for example, in order to achieve 480 damage in a weapon, you cannot simply set it to deal 480 damage, you need to set damage to 48, and then multiply it by 10 on the multiplier table.

--Concealment/Concealment: Consistent, 1 = 1.

--Value: a lookup table. Just copy the stat from the comment.
	
--First gun of every category will have notes on the stats some of the unexplained stats if they weren't explained already by a previous category or this sheet, after that, it's all listening to music, drinking coffee at 2 in the morning while typing all the stuff out.

--Comment info template:			
--Weapon
--ID: self.NAME
--Class:
--Value: 
--Magazine: 
--Ammo: 
--Fire Rate: 
--Damage:
--Acc: 
--Stab: 
--Conc: 
--Threat: 
--Pickup: X, Y
--Notes:
--Active Mods: Reflects mods affecting the gun. 
--Other mods related to the gun (that are not shared/common mods, eg suppressors) should be cosmetic only, retaining only their value.)

--BE AWARE all info in template above, other than value, reflects OUTPUT ingame, not code stats. See guidance above for conversion, entry.
	
	-- pickup for the tcd specialist skill is balanced on a per-weapon basis below
	-- (give small ammo pickup rates for weapons that normally have a pickup rate of 0)
	self.tcd_specialist_pickup_amounts = {
		kacchainsaw_flamethrower = {1,1},
		flamethrower_mk2 = {1,1},
		slap = {0.05,0.1},
		china = {0.05,0.1},
		ms3gl = {0.05,0.1},
		arbiter = {0.05,0.1},
		system = {0.05,0.1},
		rpg7 = {0.005,0.005},
		ray = {0.005,0.005}
	}
	
	
	
	--[[
	do 
		local csv_parser = DeathvoxOverhaul:require("lua/classes/csvstats.lua")
		
		
		
		
		local file_util = _G.FileIO
		local path_util = BeardLib.Utils.Path
		
		for _,filename in pairs(file_util:GetFiles(path)) do
			
			local extension = utf8.to_lower(path_util:GetFileExtension(filename))
			if extension == "csv" then 
			else
				olog("Error! Bad file type: " .. tostring(extension),SEVERITY.FATAL)
			end
		
			olog("Stat reading complete.")
		end
		CSVStatReader:read_files("weapon",self)
	end
	--]]
	
--saw but again (secondary saw is cloned directly from saw stats as a special case)
	self.saw_secondary = deep_clone(self.saw)
	self.saw_secondary.parent_weapon_id = "saw"
	self.saw_secondary.use_data.selection_index = 1
	self.saw_secondary.animations.reload_name_id = "saw"
	self.saw_secondary.use_stance = "saw"
	self.saw_secondary.texture_name = "saw"
	self.saw_secondary.weapon_hold = "saw"
	

	
	
--trip mine deployable (special special boy since it's considered a weapon by the game)
	self.trip_mines.damage = 150
--		self.trip_mines.damage_size = 300 --3m, default
end)
