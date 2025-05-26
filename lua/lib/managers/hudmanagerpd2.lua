Hooks:PostHook(HUDManager,"_setup_player_info_hud_pd2","deathvox_hudmanager_createhud",function(self)
	local hud = managers.hud:script(PlayerBase.PLAYER_INFO_HUD_PD2)
	local tcd_panel = hud.panel:child("tcd_panel")
	if alive(tcd_panel) then 
		hud.panel:remove(tcd_panel)
	end
	tcd_panel = hud.panel:panel({
		name = "tcd_panel"
	})
	
	local HUDTCDBuff = DeathvoxOverhaulCore:require("lua/classes/hudtcdbuff")
	local HUDTCDSociopath = DeathvoxOverhaulCore:require("lua/classes/hudtcdsociopath")
	
	local hudtcdbuff = HUDTCDBuff:new(tcd_panel)
	local hudtcdsociopath = HUDTCDSociopath:new(tcd_panel)
	
	self._hud_tcdbuff = hudtcdbuff
	self._hud_tcdsociopath = hudtcdsociopath
	
	
end)

