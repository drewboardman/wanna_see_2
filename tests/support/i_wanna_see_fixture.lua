-- Rebuilds the slice of Darktide and Darktide Mod Framework that the mod touches,
-- loads the real mod file into that sandbox and hands back the registered hooks plus
-- fake extension instances for the specs to drive. Nothing here launches the game,
-- so a hook that stops matching the game's behaviour fails here first.

local MOD_PATH = "scripts/mods/i_wanna_see/i_wanna_see.lua"

local function fixture()
	local calls = {}

	local function record(name)
		calls[name] = (calls[name] or 0) + 1
	end

	local function count(name)
		return calls[name] or 0
	end

	local function reset()
		calls = {}
	end

	-- Vectors carry arithmetic so mod expressions such as
	-- `position + Vector3(0, 0, 0.1)` behave the way Stingray's do.
	local vector_mt = {}

	vector_mt.__add = function(a, b)
		return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vector_mt)
	end

	vector_mt.__sub = function(a, b)
		return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vector_mt)
	end

	vector_mt.__mul = function(a, b)
		if type(a) == "number" then
			return setmetatable({ x = a * b.x, y = a * b.y, z = a * b.z }, vector_mt)
		end

		return setmetatable({ x = a.x * b, y = a.y * b, z = a.z * b }, vector_mt)
	end

	local function vec(x, y, z)
		return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, vector_mt)
	end

	local settings = {}
	local action_settings = nil
	local unit = { name = "unit" }
	local last_decal_color = nil
	local last_stream_life = nil
	local env = setmetatable({}, { __index = _G })

	-- Stingray extends the table library; plain LuaJIT does not have this.
	env.table = setmetatable({
		clear = function(t)
			for key in pairs(t) do
				t[key] = nil
			end
		end,
	}, { __index = table })

	env.Vector3 = setmetatable({}, {
		__call = function(_, x, y, z)
			return vec(x, y, z)
		end,
	})
	env.Vector3.multiply = function(v, n)
		record("Vector3.multiply")

		return vec(v.x * n, v.y * n, v.z * n)
	end
	env.Vector3.normalize = function(v)
		record("Vector3.normalize")

		return v
	end
	env.Vector3.length = function(v)
		record("Vector3.length")

		return v.x or 0
	end

	env.Matrix4x4 = {
		translation = function() return vec(0, 0, 0) end,
	}

	env.Quaternion = {
		identity = function()
			return { w = 1 }
		end,
		set_xyzw = function(quad, x, y, z, w)
			record("Quaternion.set_xyzw")

			last_decal_color = { x, y, z, w }

			return quad
		end,
		forward = function()
			record("Quaternion.forward")

			return vec(0, 0, 1)
		end,
		look = function()
			record("Quaternion.look")

			return { w = 1 }
		end,
	}

	env.Vector3Box = function(v)
		return { v = v, unbox = function(self) return self.v end, store = function() end }
	end
	env.QuaternionBox = function(quad)
		return { quad = quad, unbox = function(self) return self.quad end, store = function() end }
	end

	env.World = {
		destroy_unit = function() record("World.destroy_unit") end,
		spawn_unit_ex = function() record("World.spawn_unit_ex") return {} end,
		destroy_particles = function() record("World.destroy_particles") end,
		create_particles = function() record("World.create_particles") return {} end,
		are_particles_playing = function() return true end,
		move_particles = function() record("World.move_particles") end,
		find_particles_variable = function() record("World.find_particles_variable") return 1 end,
		set_particles_variable = function(_, effect_id, variable_index, value)
			record("World.set_particles_variable")

			last_stream_life = value
		end,
	}

	env.Unit = {
		world = function() return {} end,
		local_position = function() return vec() end,
		set_local_scale = function() record("Unit.set_local_scale") end,
		set_vector4_for_material = function() record("Unit.set_vector4_for_material") end,
		set_scalar_for_material = function() record("Unit.set_scalar_for_material") end,
		set_unit_visibility = function() record("Unit.set_unit_visibility") end,
		flow_event = function() record("Unit.flow_event") end,
	}

	env.WwiseWorld = {
		is_playing = function() record("WwiseWorld.is_playing") return true end,
		stop_event = function() record("WwiseWorld.stop_event") end,
		destroy_manual_source = function() record("WwiseWorld.destroy_manual_source") end,
		trigger_resource_event = function() record("WwiseWorld.trigger_resource_event") end,
		make_manual_source = function() return {} end,
		set_source_position = function() end,
	}

	env.Managers = {
		package = {
			has_loaded = function() return true end,
			load = function() record("Managers.package.load") end,
		},
		state = {},
	}

	local ChainLightningTarget = {}
	ChainLightningTarget.add_child = function(self, on_add_func, func_context, ...)
		record("ChainLightningTarget.add_child")

		self._num_children = (self._num_children or 0) + 1

		if on_add_func then
			on_add_func({
				value = function(_, key)
					if key == "unit" then
						return unit
					end
				end,
			}, func_context)
		end

		return "node"
	end

	local function fake_class(name, methods)
		local class = { _name = name }

		for _, method in ipairs(methods) do
			class[method] = function()
				record(name .. "." .. method)

				return "vanilla"
			end
		end

		return class
	end

	env.CLASS = {
		PsykerForceFieldUnitExtension = fake_class("PsykerForceFieldUnitExtension", { "init", "_trigger_death_effects" }),
		ChainLightningLinkEffects = fake_class("ChainLightningLinkEffects", { "_find_no_target" }),
		FlamerGasEffects = fake_class("FlamerGasEffects", { "_update_effects", "_destroy_effects", "_update_moving_lingering_effects" }),
		FlamerPilotLightEffects = fake_class("FlamerPilotLightEffects", { "_create_effects" }),
	}

	env.require = function(path)
		if path == "scripts/utilities/action/action" then
			return {
				current_action_settings_from_component = function()
					record("Action.current_action_settings_from_component")

					return action_settings
				end,
			}
		elseif path == "scripts/utilities/action/chain_lightning_target" then
			return ChainLightningTarget
		end

		error("Unexpected game dependency: " .. tostring(path))
	end

	local registered = {}
	local mod

	mod = {
		get = function(_, setting_id)
			return settings[setting_id]
		end,
		hook = function(_, obj, method, callback)
			local target = type(obj) == "string" and env.CLASS[obj] or obj
			local original = target[method]

			target[method] = function(...)
				return callback(original, ...)
			end

			registered[method] = target
		end,
	}

	env.get_mod = function()
		return mod
	end

	local chunk = assert(loadfile(MOD_PATH))

	setfenv(chunk, env)
	chunk()

	local function set_settings(overrides)
		settings = {
			purgatus_intensity = 100,
			flamer_intensity = 100,
			smite_intensity = 100,
			electro_intensity = 100,
			remove_shield_effect = false,
			remove_shield_sound = false,
			display_shield_radius = false,
			shield_radius_color = { 255, 0, 0, 4 },
		}

		for key, value in pairs(overrides or {}) do
			settings[key] = value
		end

		mod.on_all_mods_loaded()
	end

	local function set_setting(setting_id, value)
		settings[setting_id] = value

		mod.on_setting_changed(setting_id)
	end

	local function set_action_settings(value)
		action_settings = value
	end

	return {
		unit = unit,
		settings = settings,
		hooks = registered,
		count = count,
		reset = reset,
		decal_color = function()
			return last_decal_color
		end,
		stream_life = function()
			return last_stream_life
		end,
		set_settings = set_settings,
		set_setting = set_setting,
		set_action_settings = set_action_settings,
		game_state_changed = function()
			mod.on_game_state_changed()
		end,

		flamer_update = env.CLASS.FlamerGasEffects._update_effects,
		chain_add_child = ChainLightningTarget.add_child,
		find_no_target = env.CLASS.ChainLightningLinkEffects._find_no_target,
		shield_init = env.CLASS.PsykerForceFieldUnitExtension.init,
		shield_death = env.CLASS.PsykerForceFieldUnitExtension._trigger_death_effects,
		pilot_create = env.CLASS.FlamerPilotLightEffects._create_effects,

		vanilla_callback = function()
			return function() record("ORIGINAL_ON_ADD") end
		end,

		new_flamer_self = function()
			local impact_data = {}

			for i = 1, 50 do
				impact_data[i] = { time = nil, effect_name = nil, position = env.Vector3Box(), normal = env.Vector3Box() }
			end

			local self = {
				_weapon_action_component = {},
				_weapon_actions = {},
				_impact_data = impact_data,
				_stream_effect_id = nil,
				_first_person_component = { rotation = {} },
				_action_flamer_gas_component = { range = 10 },
				_action_module_position_finder_component = { position = env.Vector3(0, 0, 0), position_valid = false },
				_fx_extension = {
					vfx_spawner_pose = function()
						record("vfx_spawner_pose")

						return {}
					end,
					should_play_husk_effect = function()
						return false
					end,
				},
				_fx_source_name = "_muzzle",
			}

			self._destroy_effects = function(_, allow_move, rotation)
				record("self._destroy_effects")

				self._destroy_args = { allow_move = allow_move, rotation = rotation }
			end
			self._update_moving_lingering_effects = function()
				record("self._update_moving_lingering_effects")
			end

			return self
		end,

		new_chain_context = function()
			return {
				weapon_action_component = {},
				weapon_actions = {},
				hit_units = {},
				world = {},
				fx_data_tables = {},
			}
		end,

		new_shield_self = function(shield_unit)
			return {
				_wwise_world = {},
				_world = {},
				_source_id = "source",
				_playing_id = "playing",
				_effect_id = "effect",
				_sphere_shield = true,
				_unit = shield_unit or {},
				_position = { unbox = function() return vec() end },
				_rotation = { unbox = function() return { w = 1 } end },
				_particles_sphere = { stop = "sphere_stop", stop_flow_event = "sphere_flow" },
			}
		end,
	}
end

return fixture
