-- used for Lookout Duty basic/aced, to allow the updater in civilianbrain to run and detect enemies
Hooks:PostHook(CivilianLogicSurrender,"enter","tcd_civ_onlogicsurrender",function(data, new_logic_name, enter_params, can_flee)
	data.unit:brain():set_update_enabled_state(true)
end)