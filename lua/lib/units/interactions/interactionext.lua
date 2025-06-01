-- changed one line for Zip It Basic (prevent tied civs from fleeing)
function IntimitateInteractionExt:interact(player)
	if not self:can_interact(player) then
		return
	end

	local player_manager = managers.player
	local has_equipment = managers.player:has_special_equipment(self._tweak_data.special_equipment)

	if self._tweak_data.equipment_consume and has_equipment then
		managers.player:remove_special(self._tweak_data.special_equipment)
	end

	if self._tweak_data.sound_event then
		player:sound():play(self._tweak_data.sound_event)
	end

	if self._unit:damage() and self._unit:damage():has_sequence("interact") then
		self._unit:damage():run_sequence_simple("interact")
	end

	if self.tweak_data == "corpse_alarm_pager" then
		if Network:is_server() then
			self._nbr_interactions = 0

			if self._unit:character_damage():dead() then
				local u_id = managers.enemy:get_corpse_unit_data_from_key(self._unit:key()).u_id

				managers.network:session():send_to_peers_synched("alarm_pager_interaction", u_id, self.tweak_data, 3)
			else
				managers.network:session():send_to_peers_synched("sync_interacted", self._unit, self._unit:id(), self.tweak_data, 3)
			end

			self._unit:brain():on_alarm_pager_interaction("complete", player)

			if managers.interaction:active_unit() == self._unit then
				self:set_text_dirty(true)
			end
		else
			managers.groupai:state():sync_alarm_pager_bluff()

			if managers.enemy:get_corpse_unit_data_from_key(self._unit:key()) then
				local u_id = managers.enemy:get_corpse_unit_data_from_key(self._unit:key()).u_id

				managers.network:session():send_to_host("alarm_pager_interaction", u_id, self.tweak_data, 3)
			else
				managers.network:session():send_to_host("sync_interacted", self._unit, self._unit:id(), self.tweak_data, 3)
			end
		end

		if tweak_data.achievement.nothing_to_see_here and managers.player:local_player() == player then
			local achievement_data = tweak_data.achievement.nothing_to_see_here
			local achievement = "nothing_to_see_here"
			local memory = managers.job:get_memory(achievement, true)
			local t = Application:time()
			local new_memory = {
				value = 1,
				time = t
			}

			if memory then
				table.insert(memory, new_memory)

				for i = #memory, 1, -1 do
					if achievement_data.timer <= t - memory[i].time then
						table.remove(memory, i)
					end
				end
			else
				memory = {
					new_memory
				}
			end

			managers.job:set_memory(achievement, memory, true)

			local total_memory_value = 0

			for _, m_data in ipairs(memory) do
				total_memory_value = total_memory_value + m_data.value
			end

			if achievement_data.total_value <= total_memory_value then
				managers.achievment:award(achievement_data.award)
			end
		end

		self:remove_interact()
	elseif self.tweak_data == "corpse_dispose" then
		managers.player:set_carry("person", 0)
		managers.player:on_used_body_bag()

		local u_id = managers.enemy:get_corpse_unit_data_from_key(self._unit:key()).u_id

		if Network:is_server() then
			self:remove_interact()
			self:set_active(false, true)
			self._unit:set_slot(0)
			managers.network:session():send_to_peers_synched("remove_corpse_by_id", u_id, true, managers.network:session():local_peer():id())
			managers.player:register_carry(managers.network:session():local_peer(), "person")
		else
			managers.network:session():send_to_host("sync_interacted_by_id", u_id, self.tweak_data)
			player:movement():set_carry_restriction(true)
		end

		managers.mission:call_global_event("player_pickup_bodybag")
		managers.custom_safehouse:award("corpse_dispose")
	elseif self._tweak_data.dont_need_equipment and not has_equipment then
		self:set_active(false)
		self._unit:brain():on_tied(player, true)
	elseif self.tweak_data == "hostage_trade" then
		self._unit:brain():on_trade(player:position(), player:rotation(), true)

		if managers.blackmarket:equipped_mask().mask_id == tweak_data.achievement.relation_with_bulldozer.mask then
			managers.achievment:award_progress(tweak_data.achievement.relation_with_bulldozer.stat)
		end

		managers.statistics:trade({
			name = self._unit:base()._tweak_table
		})
	elseif self.tweak_data == "hostage_convert" then
		if Network:is_server() then
			self:remove_interact()
			self:set_active(false, true)
			managers.groupai:state():convert_hostage_to_criminal(self._unit)
		else
			managers.network:session():send_to_host("sync_interacted", self._unit, self._unit:id(), self.tweak_data, 1)
		end
	elseif self.tweak_data == "hostage_move" then
		if Network:is_server() then
			if self._unit:brain():on_hostage_move_interaction(player, "move") then
				self:remove_interact()
			end
		else
			managers.network:session():send_to_host("sync_interacted", self._unit, self._unit:id(), self.tweak_data, 1)
		end
	elseif self.tweak_data == "hostage_stay" then
		if Network:is_server() then
			if self._unit:brain():on_hostage_move_interaction(player, "stay") then
				self:remove_interact()
			end
		else
			managers.network:session():send_to_host("sync_interacted", self._unit, self._unit:id(), self.tweak_data, 1)
		end
	else
		self:remove_interact()
		self:set_active(false)
		player:sound():play("cable_tie_apply")
		self._unit:brain():on_tied(player, false, not managers.player:has_team_category_upgrade("player","civilian_hostage_no_fleeing"))
	end
end

-- removed looped cam count check,
-- check camera loop duration against your own loop duration skill
function SecurityCameraInteractionExt:_interact_blocked(player)
	local cam_base = self._unit:base()
	--local peer_id = cam_base:get_loop_owner_peer_id()
	--if peer_id and peer_id ~= managers.network:session():local_peer():id() then -- prevent you from overwriting other players' tape loops
		local loop_duration = managers.player:upgrade_value("player", "tape_loop_duration", 0)
		if cam_base._tape_loop_end_t and cam_base._tape_loop_end_t >= loop_duration then
			-- don't allow looping if the camera's remaining duration is greater than your max
			-- (incl. infinite)
			return true,nil,"camera_already_looping"
		end
	--end
	
	-- allowed regardless;
	-- if attempting to loop a second cam, send the first one into restart time and unregister it, then loop the second
	return false
end

function SecurityCameraInteractionExt:interact(player)
	SecurityCameraInteractionExt.super.super.interact(self, player)
	local peer_id = managers.network:session():local_peer():id()
	self._unit:base():start_tape_loop(peer_id)
end

function MissionDoorDeviceInteractionExt:server_place_mission_door_device(player, sender)
	local can_place = not self._unit:mission_door_device() or self._unit:mission_door_device():can_place()

	if sender then
		sender:result_place_mission_door_device(self._unit, can_place)
	else
		self:result_place_mission_door_device(can_place)
	end

	local network_session = managers.network:session()

	self:remove_interact()

	local is_saw = self._unit:base() and self._unit:base().is_saw
	local is_drill = self._unit:base() and self._unit:base().is_drill

	if is_saw or is_drill then
		local user_unit = nil

		if player and player:base() and not player:base().is_local_player then
			user_unit = player
		end
		
		local upgrades = Drill.get_upgrades(self._unit, user_unit)

		self._unit:base():set_skill_upgrades(upgrades)
		
		network_session:send_to_peers_synched("sync_drill_upgrades", self._unit, upgrades.shocktrap_level, upgrades.auto_repair_level, upgrades.speed_upgrade_level, upgrades.silent_drill, upgrades.shocktrap_alert)
	end

	if self._unit:damage() then
		self._unit:damage():run_sequence_simple("interact", {
			unit = player
		})
	end

	network_session:send_to_peers_synched("sync_interacted", self._unit, -2, self.tweak_data, 1)
	self:set_active(false)
	self:check_for_upgrade()

	if self._unit:mission_door_device() then
		self._unit:mission_door_device():placed()
	end

	if self._tweak_data.sound_event then
		player:sound():play(self._tweak_data.sound_event)
	end

	return can_place
end
