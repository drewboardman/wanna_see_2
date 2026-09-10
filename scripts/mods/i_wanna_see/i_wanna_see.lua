local mod = get_mod("i_wanna_see")

local Action = require("scripts/utilities/action/action")
local ChainLightningTarget = require("scripts/utilities/action/chain_lightning_target")

local package_name = "content/levels/training_grounds/missions/mission_tg_basic_combat_01"
local decal_unit_name = "content/levels/training_grounds/fx/decal_aoe_indicator"
local PARTICLES_WALL = {
	stop = "content/fx/particles/abilities/protectorate_forward_shield_fade_wide",
}

-- Settings are cached in locals: the hot paths below run once per frame per flamer
-- and per chain lightning source, and reading a local is cheaper than calling
-- mod:get. mod.on_setting_changed keeps the cache current.
local REMOVE_PURGATUS_EFFECT = false
local REMOVE_FLAMER_EFFECT = false
local REMOVE_SMITE_EFFECT = false
local REMOVE_ELECTRO_EFFECT = false
local REMOVE_SHIELD_EFFECT = false
local REMOVE_SHIELD_SOUND = false
local DISPLAY_SHIELD_RADIUS = false
local DECAL_R = 0
local DECAL_G = 0
local DECAL_B = 4

local function refresh_settings(setting_id)
	if not setting_id or setting_id == "remove_purgatus_effect" then
		REMOVE_PURGATUS_EFFECT = mod:get("remove_purgatus_effect") == true
	end
	if not setting_id or setting_id == "remove_flamer_effect" then
		REMOVE_FLAMER_EFFECT = mod:get("remove_flamer_effect") == true
	end
	if not setting_id or setting_id == "remove_smite_effect" then
		REMOVE_SMITE_EFFECT = mod:get("remove_smite_effect") == true
	end
	if not setting_id or setting_id == "remove_electro_effect" then
		REMOVE_ELECTRO_EFFECT = mod:get("remove_electro_effect") == true
	end
	if not setting_id or setting_id == "remove_shield_effect" then
		REMOVE_SHIELD_EFFECT = mod:get("remove_shield_effect") == true
	end
	if not setting_id or setting_id == "remove_shield_sound" then
		REMOVE_SHIELD_SOUND = mod:get("remove_shield_sound") == true
	end
	if not setting_id or setting_id == "display_shield_radius" then
		DISPLAY_SHIELD_RADIUS = mod:get("display_shield_radius") == true
	end
	if not setting_id or setting_id == "R" then
		DECAL_R = mod:get("R") or 0
	end
	if not setting_id or setting_id == "G" then
		DECAL_G = mod:get("G") or 0
	end
	if not setting_id or setting_id == "B" then
		DECAL_B = mod:get("B") or 0
	end
end

refresh_settings()

mod.on_all_mods_loaded = function()
	refresh_settings()
end

mod.on_setting_changed = function(setting_id)
	refresh_settings(setting_id)
end

-- Shield radius decals are tracked per shield unit and destroyed with it. A plain
-- table is used rather than mod:persistent_table so no dead unit references survive
-- a level change, and the decal is destroyed on death whatever the settings say.
local bubble_decals = {}

local function destroy_aoe_decal(unit)
	local bubble_decal = bubble_decals[unit]

	if bubble_decal then
		World.destroy_unit(Unit.world(unit), bubble_decal)

		bubble_decals[unit] = nil
	end
end

mod.on_game_state_changed = function()
	table.clear(bubble_decals)
end

local function set_decal_color(decal_unit, r, g, b)
	local identity_value = Quaternion.identity()

	Quaternion.set_xyzw(identity_value, r, g, b, 0.5)
	Unit.set_vector4_for_material(decal_unit, "projector", "particle_color", identity_value, true)
	Unit.set_scalar_for_material(decal_unit, "projector", "color_multiplier", 0.05)
end

local function get_decal_unit(unit, r, g, b)
	local world = Unit.world(unit)
	local position = Unit.local_position(unit, 1)
	local decal_unit = World.spawn_unit_ex(world, decal_unit_name, nil, position + Vector3(0, 0, 0.1))
	local diameter = 6 * 2 + 1.5

	Unit.set_local_scale(decal_unit, 1, Vector3(diameter, diameter, 1))
	set_decal_color(decal_unit, r, g, b)

	return decal_unit
end

local function shield_spawned(unit, dont_load_package)
	if not unit then
		return
	end
	if not Managers.package:has_loaded(package_name) and not dont_load_package then
		Managers.package:load(package_name, "i_wanna_see", function()
			shield_spawned(unit, true)
		end)
		return
	end

	destroy_aoe_decal(unit)

	bubble_decals[unit] = get_decal_unit(unit, DECAL_R, DECAL_G, DECAL_B)
end

-- The shield extension is allowed to initialise exactly as vanilla does and its
-- unwanted parts are removed afterwards. Reimplementing init instead meant the copy
-- silently drifted from the game (shield point width, deployable shield durations,
-- sphere particles and sounds, the stop flow event) and every option being off still
-- left a reimplementation of vanilla running.
mod:hook(CLASS.PsykerForceFieldUnitExtension, "init", function(func, self, extension_init_context, unit, extension_init_data, game_object_data_or_game_session, unit_spawn_parameter_or_game_object_id)
	func(self, extension_init_context, unit, extension_init_data, game_object_data_or_game_session, unit_spawn_parameter_or_game_object_id)

	if not (REMOVE_SHIELD_SOUND or REMOVE_SHIELD_EFFECT or DISPLAY_SHIELD_RADIUS) then
		return
	end

	if REMOVE_SHIELD_SOUND then
		local wwise_world = self._wwise_world
		local source_id = self._source_id

		if source_id then
			local playing_id = self._playing_id

			if playing_id and WwiseWorld.is_playing(wwise_world, playing_id) then
				WwiseWorld.stop_event(wwise_world, playing_id)
			end

			WwiseWorld.destroy_manual_source(wwise_world, source_id)

			self._playing_id = nil
			self._source_id = nil
		end
	end

	if REMOVE_SHIELD_EFFECT then
		local world = self._world
		local effect_id = self._effect_id

		if effect_id and World.are_particles_playing(world, effect_id) then
			World.destroy_particles(world, effect_id)
		end

		self._effect_id = nil

		Unit.set_unit_visibility(self._unit, false, true)
	end

	if DISPLAY_SHIELD_RADIUS and self._sphere_shield then
		shield_spawned(self._unit)
	end
end)

-- Vanilla's stop sound cannot be silenced after the fact, and it would be triggered
-- with a nil source once remove_shield_sound has dropped it, so that one combination
-- mirrors vanilla without the Wwise calls. Every other combination runs vanilla and
-- then removes the fade particle it created.
mod:hook(CLASS.PsykerForceFieldUnitExtension, "_trigger_death_effects", function(func, self)
	local unit = self._unit

	if not (REMOVE_SHIELD_SOUND or REMOVE_SHIELD_EFFECT) then
		func(self)
	elseif REMOVE_SHIELD_SOUND then
		local world = self._world
		local effect_id = self._effect_id

		if effect_id and World.are_particles_playing(world, effect_id) then
			World.destroy_particles(world, effect_id)
		end

		self._effect_id = nil
		self._source_id = nil
		self._playing_id = nil

		local particles = self._sphere_shield and self._particles_sphere
		local stop_flow_event = particles and particles.stop_flow_event

		if stop_flow_event then
			Unit.flow_event(unit, stop_flow_event)
		end

		if not REMOVE_SHIELD_EFFECT then
			local stop_particle_effect = particles and particles.stop or PARTICLES_WALL.stop

			self._effect_id = World.create_particles(world, stop_particle_effect, self._position:unbox(), self._rotation:unbox())
		end
	else
		func(self)

		local effect_id = self._effect_id

		if effect_id then
			World.destroy_particles(self._world, effect_id)

			self._effect_id = nil
		end
	end

	destroy_aoe_decal(unit)
end)

-- Whether a chain lightning source is the electrokinetic staff or Smite is a
-- property of the source, so it is resolved once per func_context and cached
-- (weakly, so nothing keeps a spent context alive).
local chain_source_is_staff = setmetatable({}, { __mode = "k" })

local function chain_suppressed(func_context)
	if not REMOVE_SMITE_EFFECT then
		return false
	end

	local is_staff = chain_source_is_staff[func_context]

	if is_staff == nil then
		local action_settings = Action.current_action_settings_from_component(func_context.weapon_action_component, func_context.weapon_actions)
		local chain_settings = action_settings and action_settings.chain_settings

		is_staff = chain_settings and chain_settings.staff and true or false

		chain_source_is_staff[func_context] = is_staff
	end

	if is_staff and not REMOVE_ELECTRO_EFFECT then
		return false
	end

	return true
end

-- Vanilla's add callbacks mark hit_units so the chain does not try to re-add the
-- same target every frame; keep exactly that bookkeeping and skip only the spawn.
local function suppress_spawn(node, context)
	context.hit_units[node:value("unit")] = true
end

-- Every link, including the ones created by ChainLightning.jump, is added through
-- ChainLightningTarget.add_child, so substituting the callback here removes the beams
-- while leaving the node tree, vanilla's own cleanup and its hit_units tracking alone.
mod:hook(ChainLightningTarget, "add_child", function(func, self, on_add_func, func_context, ...)
	if chain_suppressed(func_context) then
		return func(self, suppress_spawn, func_context, ...)
	end

	return func(self, on_add_func, func_context, ...)
end)

-- The arc drawn when the chain has no target is spawned outside add_child.
mod:hook(CLASS.ChainLightningLinkEffects, "_find_no_target", function(func, self, t)
	if chain_suppressed(self._func_context) then
		return
	end

	return func(self, t)
end)

local function damage_type_suppressed(damage_type)
	if damage_type == "warpfire" then
		return REMOVE_PURGATUS_EFFECT
	elseif damage_type == "burning" then
		return REMOVE_FLAMER_EFFECT
	end

	return false
end

-- Mirrors vanilla's handling of both fire configuration shapes (the game reads
-- "fire_configurations or fire_configuration"), so a weapon using either form is
-- treated correctly. A plural weapon is only suppressed when every configuration is
-- one the user asked to remove.
local function fire_configuration_suppressed(action_settings)
	if not action_settings then
		return false
	end

	local configuration = action_settings.fire_configuration

	if configuration then
		return damage_type_suppressed(configuration.damage_type)
	end

	local configurations = action_settings.fire_configurations

	if not configurations then
		return false
	end

	local num_configurations = #configurations

	if num_configurations == 0 then
		return false
	end

	for i = 1, num_configurations do
		if not damage_type_suppressed(configurations[i].damage_type) then
			return false
		end
	end

	return true
end

-- Wrapping rather than replacing _update_effects: when nothing is suppressed vanilla
-- runs untouched (no copied body to drift out of date and no extra work), and when it
-- is suppressed the pose lookup, the particle variable lookups and every Vector3 and
-- Quaternion vanilla builds to place, move and drive the effects are skipped.
mod:hook(CLASS.FlamerGasEffects, "_update_effects", function(func, self, dt, t)
	if not (REMOVE_FLAMER_EFFECT or REMOVE_PURGATUS_EFFECT) then
		return func(self, dt, t)
	end

	local action_settings = Action.current_action_settings_from_component(self._weapon_action_component, self._weapon_actions)

	if not fire_configuration_suppressed(action_settings) then
		self._iws_impacts_cleared = false

		return func(self, dt, t)
	end

	-- Drop anything queued before the suppression so no decal fires afterwards.
	if not self._iws_impacts_cleared then
		local impact_data = self._impact_data

		for i = 1, #impact_data do
			local data = impact_data[i]

			data.time = nil
			data.effect_name = nil
		end

		self._iws_impacts_cleared = true
	end

	if self._stream_effect_id then
		-- Reached at most once per suppression: _destroy_effects only reads the
		-- rotation when a stream still exists, and a fresh one is never created.
		local forward = Quaternion.forward(self._first_person_component.rotation)
		local direction = Vector3.normalize(Vector3.multiply(forward, self._action_flamer_gas_component.range))

		self:_destroy_effects(true, Quaternion.look(direction))
	else
		self:_destroy_effects(true, nil)
	end

	self:_update_moving_lingering_effects(dt, t)
end)

-- Wrapped so the looping pilot light is never resolved, created and linked in the
-- first place rather than being created and then destroyed again.
mod:hook(CLASS.FlamerPilotLightEffects, "_create_effects", function(func, self)
	if REMOVE_FLAMER_EFFECT then
		return
	end

	return func(self)
end)




