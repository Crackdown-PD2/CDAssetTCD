Hooks:PostHook(Setup,"init_managers","tcd_setup_initmanagers",function(self,managers)
	managers.tcdbuff = DeathvoxOverhaulCore:require("lua/classes/tcdbuffmanager"):new()
end)