HuskCopDamage._NET_EVENTS = {
	set_drill_shock_tase_time = 1,
	set_joker_no_hurts = 2,
	joker_regen = 3
}
function HuskCopDamage:sync_net_event(event_id)
	local net_events = HuskCopDamage._NET_EVENTS

	if event_id == net_events.set_drill_shock_tase_time then
		self._tased_time = tweak_data.upgrades.values.player.drill_shock_tase_time
	end
	--[[
	elseif event_id == net_events.set_joker_no_hurts then
		local char_tweaks = deep_clone(self._unit:base()._char_tweak)

		char_tweaks.damage.hurt_severity = tweak_data.character.presets.hurt_severities.no_hurts_no_tase
		char_tweaks.can_be_tased = false
		char_tweaks.use_animation_on_fire_damage = false
		char_tweaks.immune_to_knock_down = true
		char_tweaks.immune_to_concussion = true

		self._unit:base()._char_tweak = char_tweaks
		self._unit:character_damage()._char_tweak = char_tweaks
		self._unit:movement()._tweak_data = char_tweaks
		self._unit:movement()._action_common_data.char_tweak = char_tweaks
	elseif event_id == net_events.joker_regen then
		local regen_percent = 0.025 --placerholder, tweakdata upgrade value here
		local init_health = self._HEALTH_INIT
		local new_health = init_health * regen_percent + self._health

		if new_health >= init_health then
			self._health = init_health
			self._health_ratio = 1
		else
			self._health = new_health
			self._health_ratio = new_health / init_health
		end

		self:_update_debug_ws()
	end
	--]]
end