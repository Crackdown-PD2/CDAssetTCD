function EnvEffectTweakData:trip_mine_fire()
	local params = {
		alert_radius = 15000,
		burn_duration = 15, -- was 10
		burn_tick_period = 0.5,
		curve_pow = 3,
		damage = 25, -- was 1 (10)
		dot_data_name = "equipment_tripmine_groundfire",
		hexes = 0, -- was nil
		effect_name = "effects/payday2/particles/explosions/molotov_grenade",
		fire_alert_radius = 15000,
		player_damage = 1.5, -- was 2
		range = 75,
		sound_event = "no_sound",
		sound_event_burning = "burn_loop_gen",
		sound_event_burning_stop = "burn_loop_gen_stop_fade",
		sound_event_impact_duration = 0
	}

	return params
end