local mvec3_dot = mvector3.dot
local mvec3_set = mvector3.set
local mvec3_sub = mvector3.subtract
local mvec3_dis_sq = mvector3.distance_sq
local mvec3_dir = mvector3.direction
local mvec3_l_sq = mvector3.length_sq
local mvec3_set_l = mvector3.set_length
local mvec3_add = mvector3.add
local mvec3_rand_orth = mvector3.random_orthogonal
local mvec3_cpy = mvector3.copy

local math_up = math.UP
local math_ceil = math.ceil
local math_floor = math.floor
local math_random = math.random
local math_pow = math.pow
local math_clamp = math.clamp
local math_lerp = math.lerp
local math_DOWN = math.DOWN

local table_insert = table.insert
local table_remove = table.remove
local table_size = table.size

local pairs_g = pairs
local next_g = next
local tostring_g = tostring
local alive_g = alive

local tmp_vec1 = Vector3()
local tmp_vec2 = Vector3()
function GroupAIStateBase:on_hostage_follow(owner, follower, state)
	local mov_ext = follower:movement()
	mov_ext:set_hostage_speed_modifier(state)

	local follower_key = follower:key()

	if state then
		owner = alive_g(owner) and owner or nil

		if owner then
			local owner_data = self:criminal_record(owner:key())

			if owner_data then
				owner_data.following_hostages = owner_data.following_hostages or {}
				owner_data.following_hostages[follower_key] = follower
			end

			local follower_data = managers.enemy:all_civilians()[follower_key]

			if follower_data then
				follower_data.hostage_following = owner
			end
		end

		if Network:is_server() then
			local peer = owner and managers.network:session():peer_by_unit(owner)

			if peer then
				local peer_id = peer:id()

				if peer_id ~= managers.network:session():local_peer():id() then
					peer:send_queued_sync("sync_unit_event_id_16", follower, "base", 1)

					managers.network:session():send_to_peers_synched_except(peer_id, "sync_unit_event_id_16", follower, "base", 3)
				else
					managers.network:session():send_to_peers_synched("sync_unit_event_id_16", follower, "base", 3)
				end
			else
				managers.network:session():send_to_peers_synched("sync_unit_event_id_16", follower, "base", 3)
			end
			
			-- main change is this tcd upgrade code;
			-- other changes were integrated into base-game in 240.3
			if managers.player:has_team_category_upgrade("player", "civilian_hostage_carry_bags") and mov_ext then
				CarryData._valid_civs[follower_key] = follower

				local was_carrying_data = mov_ext:was_carrying_bag()
				local bag_unit = was_carrying_data and was_carrying_data.unit

				if alive_g(bag_unit) then
					local distance = mvec3_dis_sq(mov_ext:m_pos(), bag_unit:position())
					local max_distance = math_pow(tweak_data.ai_carry.revive_distance_autopickup, 2)

					if distance <= max_distance then
						bag_unit:carry_data():link_to(follower, false)

						if mov_ext.set_carrying_bag then
							mov_ext:set_carrying_bag(bag_unit)
						end
					end
				end
			end
		end
	else
		local follower_data = managers.enemy:all_civilians()[follower_key]

		owner = owner or follower_data and follower_data.hostage_following
		owner = alive_g(owner) and owner or nil

		local owner_data = owner and self:criminal_record(owner:key())

		if owner_data and owner_data.following_hostages then
			owner_data.following_hostages[follower_key] = nil

			if not next_g(owner_data.following_hostages) then
				owner_data.following_hostages = nil
			end
		end

		if follower_data then
			follower_data.hostage_following = nil
		end

		if Network:is_server() then
			if follower:id() ~= 1 then
				local peer = owner and managers.network:session():peer_by_unit(owner)

				if peer then
					local peer_id = peer:id()

					if peer_id ~= managers.network:session():local_peer():id() then
						peer:send_queued_sync("sync_unit_event_id_16", follower, "base", 3)
						managers.network:session():send_to_peers_synched_except(peer_id, "sync_unit_event_id_16", follower, "base", 4)
					else
						managers.network:session():send_to_peers_synched("sync_unit_event_id_16", follower, "base", 4)
					end
				else
					managers.network:session():send_to_peers_synched("sync_unit_event_id_16", follower, "base", 4)
				end
			end
			
			if mov_ext then
				mov_ext:throw_bag()
			end

			if CarryData._valid_civs[follower_key] then
				CarryData._valid_civs[follower_key] = nil

				--reset the table to remove nil entries that still increase its size
				if not next_g(CarryData._valid_civs) then
					CarryData._valid_civs = {}
				end
			end

			if follower:id() ~= 1 then
				managers.network:session():send_to_peers_synched("sync_unit_event_id_16", follower, "base", 2)
			end
		end
	end
	if mov_ext and mov_ext.set_hostage_speed_modifier then
		mov_ext:set_hostage_speed_modifier(state)
	end
end
