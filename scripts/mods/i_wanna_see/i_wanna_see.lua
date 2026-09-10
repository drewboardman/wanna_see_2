local mod = get_mod("i_wanna_see")

local Action = require("scripts/utilities/action/action")
local ChainLightningTarget = require("scripts/utilities/action/chain_lightning_target")
local Flamer = require("scripts/utilities/flamer")

local package_name = "content/levels/training_grounds/missions/mission_tg_basic_combat_01"
local decal_unit_name = "content/levels/training_grounds/fx/decal_aoe_indicator"
local PARTICLES_WALL = {
	stop = "content/fx/particles/abilities/protectorate_forward_shield_fade_wide",
}

-- Settings are cached in locals: the hot paths below run once per frame per flamer
-- and per chain lightning source, and reading a local is cheaper than calling
-- mod:get. mod.on_setting_changed keeps the cache current.
--
-- The effect intensities are percentages: 0 removes the effect, 100 leaves vanilla
-- alone, and anything in between scales how much of it is drawn.
local PURGATUS_INTENSITY = 0
local FLAMER_INTENSITY = 0
local SMITE_INTENSITY = 0
local ELECTRO_INTENSITY = 0
local ENEMY_FLAME_INTENSITY = 100
local REMOVE_SHIELD_EFFECT = false
local REMOVE_SHIELD_SOUND = false
local DISPLAY_SHIELD_RADIUS = false
local DEBUG_INTENSITY = false
local DECAL_R = 0
local DECAL_G = 0
local DECAL_B = 4

local function intensity_of(setting_id)
	local value = mod:get(setting_id)

	if type(value) ~= "number" then
		return 0
	end
	if value <= 0 then
		return 0
	end
	if value >= 100 then
		return 100
	end

	return math.floor(value)
end

local function refresh_settings(setting_id)
	if not setting_id or setting_id == "purgatus_intensity" then
		PURGATUS_INTENSITY = intensity_of("purgatus_intensity")
	end
	if not setting_id or setting_id == "flamer_intensity" then
		FLAMER_INTENSITY = intensity_of("flamer_intensity")
	end
	if not setting_id or setting_id == "smite_intensity" then
		SMITE_INTENSITY = intensity_of("smite_intensity")
	end
	if not setting_id or setting_id == "electro_intensity" then
		ELECTRO_INTENSITY = intensity_of("electro_intensity")
	end
	if not setting_id or setting_id == "enemy_flame_intensity" then
		ENEMY_FLAME_INTENSITY = intensity_of("enemy_flame_intensity")
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
	if not setting_id or setting_id == "debug_intensity" then
		DEBUG_INTENSITY = mod:get("debug_intensity") == true
	end
	if not setting_id or setting_id == "shield_radius_color" then
		local color = mod:get("shield_radius_color")

		if type(color) == "table" then
			-- DMF stores and returns colors as an array-like { A, R, G, B }.
			DECAL_R = color[2] or 0
			DECAL_G = color[3] or 0
			DECAL_B = color[4] or 4
		end
	end
end

refresh_settings()

mod.on_all_mods_loaded = function()
	refresh_settings()
end

mod.on_setting_changed = function(setting_id)
	refresh_settings(setting_id)
end

-- Diagnostic aid for the partial intensities. DMF echoes to the log and the chat,
-- so the output has to be strictly bounded: a message is echoed once per key, and
-- the total is capped. A per-frame value (distance, for instance) must never end up
-- in the key, or every frame would echo and flood the chat.
local debug_reported = {}
local debug_reports_sent = 0
local MAX_DEBUG_REPORTS = 60

local function report(message, key)
	if not DEBUG_INTENSITY then
		return
	end

	if debug_reported[key or message] or debug_reports_sent >= MAX_DEBUG_REPORTS then
		return
	end

	debug_reported[key or message] = true
	debug_reports_sent = debug_reports_sent + 1

	-- Passed as an argument so a percent sign inside the message is harmless.
	mod:echo("[i_wanna_see] %s", message)
end

-- Particle variables worth looking for, so the report can say which knobs an effect
-- actually exposes rather than only the one vanilla tries to set. The names are the
-- ones the game itself uses elsewhere: "life" for the flamers, "size" and "radius"
-- for areas, "length" for beams, "intensity" for looping player particles, "velocity"
-- for the AI flamers, and "1".."4" for the control points a code driven jet is built
-- from.
local PROBE_VARIABLES = {
	"life",
	"life_random",
	"size",
	"scale",
	"intensity",
	"length",
	"radius",
	"hit_distance",
	"velocity",
	"speed",
	"spawn_rate",
	"emission_rate",
	"amount",
	"1",
	"2",
	"3",
	"4",
}

local function probe_variables(world, effect_name)
	local found = {}

	for i = 1, #PROBE_VARIABLES do
		local name = PROBE_VARIABLES[i]

		if World.find_particles_variable(world, effect_name, name) then
			found[#found + 1] = name
		end
	end

	return #found > 0 and table.concat(found, ", ") or "none of the probed names"
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
-- (weakly, so nothing keeps a spent context alive). The two have separate settings.
local chain_source_is_staff = setmetatable({}, { __mode = "k" })

-- Links spawned so far per source, so a partial intensity keeps every other link
-- rather than flipping a coin per link, which would pop in and out frame to frame.
local chain_link_counts = setmetatable({}, { __mode = "k" })

local function chain_intensity(func_context)
	if SMITE_INTENSITY >= 100 and ELECTRO_INTENSITY >= 100 then
		return 100
	end

	local is_staff = chain_source_is_staff[func_context]

	if is_staff == nil then
		local action_settings = Action.current_action_settings_from_component(func_context.weapon_action_component, func_context.weapon_actions)
		local chain_settings = action_settings and action_settings.chain_settings

		is_staff = chain_settings and chain_settings.staff and true or false

		chain_source_is_staff[func_context] = is_staff

		if DEBUG_INTENSITY then
			report(string.format("chain lightning: source classified as %s", is_staff and "the electrokinetic staff" or "smite"))
		end
	end

	local intensity = is_staff and ELECTRO_INTENSITY or SMITE_INTENSITY

	if DEBUG_INTENSITY then
		report(string.format("chain lightning: %s intensity -> %d%%", is_staff and "staff" or "smite", intensity))
	end

	return intensity
end

-- Vanilla's add callbacks mark hit_units so the chain does not try to re-add the
-- same target every frame; keep exactly that bookkeeping and skip only the spawn.
local function suppress_spawn(node, context)
	local hit_units = context and context.hit_units
	local unit = node:value("unit")

	if hit_units and unit then
		hit_units[unit] = true
	end
end

-- Whether this tree is the visual link effects, which is the only chain lightning tree
-- the mod may thin out. Chain lightning trees are also built by the electrokinetic
-- staff's weapon action and by the arc ability templates, and their callbacks apply
-- buffs to every target they touch: substituting those breaks the ability. Their
-- contexts carry action_settings or buff_extension and no FX data table pool, so the
-- pool is what tells the two apart.
local function is_link_effects_context(func_context)
	return type(func_context) == "table" and type(func_context.fx_data_tables) == "table" and type(func_context.hit_units) == "table"
end

-- Returns the callback to spawn with, or nil to leave vanilla's in place.
local function chain_spawn_substitute(func_context)
	local intensity = chain_intensity(func_context)

	if intensity >= 100 then
		return nil
	end

	if intensity > 0 then
		local count = (chain_link_counts[func_context] or 0) + 1

		chain_link_counts[func_context] = count

		local keep_every = math.max(1, math.floor(100 / intensity + 0.5))

		if count % keep_every == 0 then
			return nil
		end
	end

	return suppress_spawn
end

-- Every link, including the ones created by ChainLightning.jump, is added through
-- ChainLightningTarget.add_child, so substituting the callback here thins or removes
-- the beams while leaving the node tree, vanilla's own cleanup and its hit_units
-- tracking alone. This hook is deliberately fail open: any context that is not
-- recognisably the link effects, and any error while deciding, leaves vanilla's own
-- callback untouched rather than taking the tree it belongs to down with it.
mod:hook(ChainLightningTarget, "add_child", function(func, self, on_add_func, func_context, ...)
	if (SMITE_INTENSITY < 100 or ELECTRO_INTENSITY < 100) and is_link_effects_context(func_context) then
		local ok, substitute = pcall(chain_spawn_substitute, func_context)

		if ok and substitute then
			return func(self, substitute, func_context, ...)
		end
	end

	return func(self, on_add_func, func_context, ...)
end)

-- The arc drawn when the chain has no target is spawned outside add_child. It is a
-- single small effect, so it only goes away with the chain itself.
mod:hook(CLASS.ChainLightningLinkEffects, "_find_no_target", function(func, self, t)
	if SMITE_INTENSITY < 100 or ELECTRO_INTENSITY < 100 then
		local context = self._func_context

		if is_link_effects_context(context) then
			local ok, intensity = pcall(chain_intensity, context)

			if ok and intensity <= 0 then
				return
			end
		end
	end

	return func(self, t)
end)

-- Whether a unit is on a side that the local player's side counts as an enemy. The
-- game decides who may shoot whom this way, and anything it does not know about
-- returns false, so the player's own unit and their allies are never touched.
local function unit_is_enemy_of_local_player(unit)
	local side_system = Managers.state.extension and Managers.state.extension:system("side_system")

	if not side_system or not unit then
		return false
	end

	local side = side_system.side_by_unit[unit]

	if not side then
		return false
	end

	local local_player = Managers.player and Managers.player:local_player()
	local local_unit = local_player and local_player.player_unit
	local local_side = local_unit and side_system.side_by_unit[local_unit]

	if not local_side then
		return false
	end

	local enemy_side_names = local_side:relation_side_names("enemy")
	local side_name = side:name()

	for i = 1, #enemy_side_names do
		if enemy_side_names[i] == side_name then
			return true
		end
	end

	return false
end

-- Decided once per enemy, so a flame that is dropped stays dropped instead of
-- flickering in and out from frame to frame.
local hidden_flame_units = setmetatable({}, { __mode = "k" })

local function enemy_flames_hidden(unit)
	if ENEMY_FLAME_INTENSITY >= 100 or not unit_is_enemy_of_local_player(unit) then
		return false
	end

	if ENEMY_FLAME_INTENSITY <= 0 then
		return true
	end

	local hidden = hidden_flame_units[unit]

	if hidden == nil then
		hidden = math.random() > ENEMY_FLAME_INTENSITY / 100

		hidden_flame_units[unit] = hidden
	end

	return hidden
end

-- Every enemy flame effect goes through this driver: the AI's effect templates call
-- it for the flamer, the beast of nurgle's vomit and the linked beams. The jet is
-- created by start_shooting_fx and the hit sparks and ground fire by
-- update_shooting_fx, which creates them itself, so both need the same guard. The
-- player's own flamer is a different path (FlamerGasEffects) and is untouched.
mod:hook(Flamer, "start_shooting_fx", function(func, t, unit, vfx, sfx, wwise_world, world, data, ...)
	if enemy_flames_hidden(unit) then
		return
	end

	return func(t, unit, vfx, sfx, wwise_world, world, data, ...)
end)

mod:hook(Flamer, "update_shooting_fx", function(func, t, unit, vfx, sfx, wwise_world, world, physics_world, aim_position, control_point_1, control_point_2, data, ...)
	if enemy_flames_hidden(unit) then
		return
	end

	return func(t, unit, vfx, sfx, wwise_world, world, physics_world, aim_position, control_point_1, control_point_2, data, ...)
end)

local function damage_type_intensity(damage_type)
	if damage_type == "warpfire" then
		return PURGATUS_INTENSITY
	elseif damage_type == "burning" then
		return FLAMER_INTENSITY
	end

	return 100
end

-- Mirrors vanilla's handling of both fire configuration shapes (the game reads
-- "fire_configurations or fire_configuration"), so a weapon using either form is
-- treated correctly. A weapon with several configurations takes the most restrictive
-- of them, because the effects are created per action rather than per configuration.
local function fire_configuration_intensity(action_settings)
	if not action_settings then
		return 100
	end

	local configuration = action_settings.fire_configuration

	if configuration then
		return damage_type_intensity(configuration.damage_type)
	end

	local configurations = action_settings.fire_configurations

	if not configurations then
		return 100
	end

	local num_configurations = #configurations

	if num_configurations == 0 then
		return 100
	end

	local intensity = 100

	for i = 1, num_configurations do
		local candidate = damage_type_intensity(configurations[i].damage_type)

		if candidate < intensity then
			intensity = candidate
		end
	end

	return intensity
end

-- The active action is not always one that fires (wielding, aiming, reloading), so the
-- weapon's own actions are consulted as a fallback. That is what lets an instance which
-- draws a flame honour the setting even when its current action carries no fire
-- configuration of its own. Resolved once per instance.
local function instance_fire_damage_types(self)
	local damage_types = self._iws_fire_damage_types

	if damage_types then
		return damage_types
	end

	damage_types = {}

	local actions = self._weapon_actions

	if actions then
		for _, settings in pairs(actions) do
			local configuration = settings and settings.fire_configuration
			local damage_type = configuration and configuration.damage_type

			if damage_type then
				damage_types[damage_type] = true
			end

			local configurations = settings and settings.fire_configurations

			if configurations then
				for i = 1, #configurations do
					local entry = configurations[i]
					local entry_damage_type = entry and entry.damage_type

					if entry_damage_type then
						damage_types[entry_damage_type] = true
					end
				end
			end
		end
	end

	self._iws_fire_damage_types = damage_types

	return damage_types
end

local function instance_intensity(self, action_settings)
	local intensity = fire_configuration_intensity(action_settings)

	if intensity < 100 then
		return intensity
	end

	local lowest = 100

	for damage_type in pairs(instance_fire_damage_types(self)) do
		local candidate = damage_type_intensity(damage_type)

		if candidate < lowest then
			lowest = candidate
		end
	end

	return lowest
end

-- Vanilla's scorch decals are queued round robin through self._impact_data, so the
-- slot that moved since the last frame is the one it just queued. Counting queued
-- impacts and clearing a share of them thins the decals out by an exact ratio rather
-- than by chance, and only runs while the effect is being scaled down.
local function thin_impact_decals(self, intensity)
	local impact_index = self._impact_index

	if impact_index == self._iws_last_impact_index then
		return
	end

	self._iws_last_impact_index = impact_index

	local queued = (self._iws_impact_count or 0) + 1

	self._iws_impact_count = queued

	local keep_every = math.max(1, math.floor(100 / intensity + 0.5))

	if queued % keep_every == 0 then
		return
	end

	local impact_data = self._impact_data
	local index = impact_index - 1

	if index < 1 then
		index = #impact_data
	end

	local data = impact_data[index]

	data.time = nil
	data.effect_name = nil
end

-- Shortens how long the flame particles live, which is what the stream's cost is
-- made of: the same particles are spawned, but fewer of them are alive at once. The
-- distance and speed the game derives that life from are mirrored here, and the
-- particle variable index is cached per effect name (vanilla looks it up every frame).
local stream_life_variables = {}

local function scale_stream_life(self, action_settings, intensity)
	local stream_effect_id = self._stream_effect_id

	if not stream_effect_id then
		report("flamer: scaling skipped, no stream yet")

		return
	end

	local effects = action_settings and action_settings.fx
	local stream_effect_data = effects and effects.stream_effect
	local speed = stream_effect_data and stream_effect_data.speed
	local position_finder = self._action_module_position_finder_component

	if not speed or speed == 0 or not position_finder then
		if DEBUG_INTENSITY then
			report(string.format("flamer: scaling skipped, speed %s, position finder %s", tostring(speed), position_finder and "present" or "missing"))
		end

		return
	end

	local distance

	if position_finder.position_valid then
		local pose = self._fx_extension:vfx_spawner_pose(self._fx_source_name)

		distance = Vector3.length(position_finder.position - Matrix4x4.translation(pose))
	else
		distance = self._action_flamer_gas_component.range
	end

	local effect_name = self._fx_extension:should_play_husk_effect() and stream_effect_data.name_3p or stream_effect_data.name

	if not effect_name then
		report("flamer: scaling skipped, no effect name")

		return
	end

	local variable_index = stream_life_variables[effect_name]

	if variable_index == nil then
		variable_index = World.find_particles_variable(self._world, effect_name, "life")
		stream_life_variables[effect_name] = variable_index

		if DEBUG_INTENSITY then
			report(string.format("flamer: %s exposes %s (life lookup returned %s)", effect_name, probe_variables(self._world, effect_name), tostring(variable_index)))
		end
	end

	if not variable_index then
		return
	end

	local life = distance / speed * intensity / 100

	if DEBUG_INTENSITY then
		-- Keyed by the things that stay put, so a drifting distance cannot make this
		-- echo again: one report per effect, per intensity, per variable index.
		report(
			string.format("flamer: %s at %d%% -> life %.3f (speed %s, distance %.2f, variable %s)", effect_name, intensity, life, tostring(speed), distance, tostring(variable_index)),
			string.format("flamer life %s|%d|%s", effect_name, intensity, tostring(variable_index))
		)
	end

	World.set_particles_variable(self._world, stream_effect_id, variable_index, Vector3(life, life, life))
end

-- Wrapping rather than replacing _update_effects: when nothing is configured vanilla
-- runs untouched (no copied body to drift out of date and no extra work). When it is,
-- the pose lookup, the particle variable lookup and the Vector3s and Quaternions
-- vanilla builds to place, move and drive the effects are skipped once the effect is
-- removed, and are only paid for when a scaled down effect still needs them.
mod:hook(CLASS.FlamerGasEffects, "_update_effects", function(func, self, dt, t)
	if FLAMER_INTENSITY >= 100 and PURGATUS_INTENSITY >= 100 then
		return func(self, dt, t)
	end

	local action_settings = Action.current_action_settings_from_component(self._weapon_action_component, self._weapon_actions)
	local intensity = instance_intensity(self, action_settings)

	if DEBUG_INTENSITY then
		report(string.format("flamer: instance (husk %s, local %s), active action damage type %s -> %d%%", tostring(self._is_husk), tostring(self._is_local_unit), tostring(action_settings and action_settings.fire_configuration and action_settings.fire_configuration.damage_type), intensity))
	end

	if intensity >= 100 then
		self._iws_impacts_cleared = false

		return func(self, dt, t)
	end

	if intensity > 0 then
		self._iws_impacts_cleared = false

		func(self, dt, t)

		scale_stream_life(self, action_settings, intensity)
		thin_impact_decals(self, intensity)

		return
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
-- first place rather than being created and then destroyed again. It is a single
-- small effect, so it only goes away with the flame itself.
mod:hook(CLASS.FlamerPilotLightEffects, "_create_effects", function(func, self)
	if FLAMER_INTENSITY <= 0 then
		return
	end

	return func(self)
end)




