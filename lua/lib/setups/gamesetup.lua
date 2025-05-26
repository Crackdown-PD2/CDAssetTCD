Hooks:PostHook(GameSetup,"init_managers","tcd_gamesetup_initmanagers",function(self,managers)
	managers.tcdbuff = DeathvoxOverhaulCore:require("lua/classes/tcdbuffmanager"):new()
end)