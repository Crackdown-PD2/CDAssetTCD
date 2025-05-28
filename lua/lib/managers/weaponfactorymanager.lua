
-- these three are tcd functions; don't call them every frame, call them once and cache the result
-- DEAR OFFY PLEASE LEARN FROM YOUR PAST MISTAKES OFFY
-- love, offy
function WeaponFactoryManager:get_primary_weapon_class_from_blueprint(weapon_id,blueprint,fallback)
	if fallback == nil then 
		fallback = "NO_WEAPON_CLASS"
	end
	local wpntd = tweak_data.weapon
	local primary_class
	local weapondata = weapon_id and wpntd[weapon_id]
	if weapondata and weapondata.primary_class then
		primary_class = weapondata.primary_class
	end
	
	local factory_id = self:get_factory_id_by_weapon_id(weapon_id)
	
	if type(blueprint) == "table" then 
		for _,part_id in pairs(blueprint) do 
			local part_data = self:get_part_data_by_part_id_from_weapon(part_id,factory_id,blueprint)
			if part_data then 
				if part_data.class_modifier then 
					primary_class = part_data.class_modifier
				end
			end
		end
	end
	return primary_class or fallback
end

function WeaponFactoryManager:get_weapon_subclasses_from_blueprint(weapon_id,blueprint)
	local wpntd = tweak_data.weapon
	local subclasses = {}
	local weapondata = weapon_id and wpntd[weapon_id]
	if weapondata and weapondata.subclasses then
		subclasses = table.deep_map_copy(weapondata.subclasses)
	end
	local factory_id = self:get_factory_id_by_weapon_id(weapon_id)
	
	if type(blueprint) == "table" then 
		for _,part_id in pairs(blueprint) do 
			local part_data = self:get_part_data_by_part_id_from_weapon(part_id,factory_id,blueprint)
			if part_data then 
				if part_data.subclass_modifiers then 
					for _,subclass in pairs(part_data.subclass_modifiers) do 
						table.insert(subclasses,subclass)
					end
				end
			end
		end
	end
	return subclasses
end

function WeaponFactoryManager:get_weapon_class_subclasses_from_blueprint(weapon_id,blueprint,fallback)
	if fallback == nil then 
		fallback = "NO_WEAPON_CLASS"
	end
	local wpntd = tweak_data.weapon
	local primary_class = fallback
	local subclasses = {}
	local weapondata = weapon_id and wpntd[weapon_id]
	if weapondata then
		if weapondata.primary_class then
			primary_class = weapondata.primary_class
		end
		if weapondata.subclasses then
			subclasses = table.deep_map_copy(weapondata.subclasses)
		end
	end
	
	local factory_id = self:get_factory_id_by_weapon_id(weapon_id)
	if type(blueprint) == "table" then 
		for _,part_id in pairs(blueprint) do 
			local part_data = self:get_part_data_by_part_id_from_weapon(part_id,factory_id,blueprint)
			if part_data then 
				if part_data.class_modifier then 
					primary_class = part_data.class_modifier
				end
				if part_data.subclass_modifiers then 
					for _,subclass in pairs(part_data.subclass_modifiers) do 
						table.insert(subclasses,subclass)
					end
				end
			end
		end
	end
	return primary_class,subclasses
end

--not very efficient; try not to call this too much
--it is suggested to call once on weapon assembled and cache whatever you need to into the weapon base instance
-- (also goes for the above functions)
function WeaponFactoryManager:_part_data(part_id, factory_id, override)
	local factory = tweak_data.weapon.factory

	if not self:is_part_valid(part_id) then
		--Print("[WeaponFactoryManager:_part_data] Part do not exist!", part_id, "factory_id", factory_id)
		return {}
	end

	local part = deep_clone(factory.parts[part_id])

	--offy wuz hear
	if part.tcd_stats then 
		local weapon_override = part.tcd_stats[factory_id]
		if weapon_override then 
			if weapon_override.class_modifier then
				part.class_modifier = weapon_override.class_modifier
			end
			if weapon_override.subclass_modifiers then
				part.subclass_modifiers = deep_clone(weapon_override.subclass_modifiers)
			end
			if weapon_override.stats then
				part.stats = deep_clone(weapon_override.stats)
			end
			if weapon_override.custom_stats then 
				part.custom_stats = deep_clone(weapon_override.custom_stats)
			end
		end
	end
	--^

	if factory[factory_id].override and factory[factory_id].override[part_id] then
		for d, v in pairs(factory[factory_id].override[part_id]) do
			part[d] = type(v) == "table" and deep_clone(v) or v
		end
	end
	
	if override then
		if override[part_id] then
			for d, v in pairs(override[part_id]) do
				part[d] = type(v) == "table" and deep_clone(v) or v
			end
		end

		if override[factory_id] then
			for d, v in pairs(override[factory_id]) do
				part[d] = type(v) == "table" and deep_clone(v) or v
			end
		end
	end
	
	return part
end