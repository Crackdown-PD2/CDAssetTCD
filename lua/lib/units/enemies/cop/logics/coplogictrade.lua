-- Stay Down aced (double trade)
function CopLogicTrade.on_trade(data, pos, rotation, free_criminal)
	if not data.internal_data._trade_enabled then
		return
	end

	if free_criminal then
		managers.trade:on_hostage_traded(pos, rotation)
	end

	data.internal_data._trade_enabled = false

	data.unit:network():send("hostage_trade", false, true, false)
	CopLogicTrade.hostage_trade(data.unit, false, true)
	managers.groupai:state():on_hostage_state(false, data.key, managers.enemy:all_enemies()[data.key] and true or false)
	
	if managers.enemy:is_civilian(data.unit) and managers.player:has_team_category_upgrade("player", "civilian_hostage_fakeout_trade") then
		local brain = data.unit:brain()
		if brain and not brain._fakeout_trade_done then
			brain._fakeout_trade_done = true
			brain:set_logic("surrender")
			data.unit:contour():remove("hostage_trade", true, nil)
			return
		end
	end
	
	if data.is_converted then
		managers.groupai:state():remove_minion(data.key, nil)
	end

	local ignore_segments = {}
	
	
	local flee_pos = managers.groupai:state():flee_point(data.unit:movement():nav_tracker():nav_segment(), ignore_segments)

	if not flee_pos then
		data.unit:set_slot(0)

		return
	end

	local iterations = 1
	local coarse_path = nil
	local my_data = data.internal_data
	local search_params = {
		from_tracker = data.unit:movement():nav_tracker(),
		id = "CopLogicTrade._get_coarse_flee_path" .. tostring(data.key),
		access_pos = data.char_tweak.access
	}
	local max_attempts = 8

	while iterations < max_attempts do
		local nav_seg = managers.navigation:get_nav_seg_from_pos(flee_pos)
		search_params.to_seg = nav_seg
		coarse_path = managers.navigation:search_coarse(search_params)

		if not coarse_path then
			coarse_path = nil

			table.insert(ignore_segments, nav_seg)
		else
			break
		end

		iterations = iterations + 1

		if max_attempts > iterations then
			flee_pos = managers.groupai:state():flee_point(data.unit:movement():nav_tracker():nav_segment(), ignore_segments)

			if not flee_pos then
				break
			end
		end
	end

	if flee_pos then
		data.internal_data.fleeing = true
		data.internal_data.flee_pos = flee_pos

		if data.unit:anim_data().hands_tied or data.unit:anim_data().tied then
			local new_action = nil

			if data.unit:anim_data().stand and data.is_tied then
				new_action = {
					variant = "panic",
					body_part = 1,
					type = "act"
				}
				data.is_tied = nil

				data.unit:movement():set_stance("hos")
			else
				new_action = {
					variant = "stand",
					body_part = 1,
					type = "act"
				}
			end

			data.unit:brain():action_request(new_action)
		end

		data.unit:contour():add("hostage_trade", true, nil)
	else
		data.unit:set_slot(0)
	end
end
