local fixture = require("tests.support.i_wanna_see_fixture")

-- Intensities are percentages: 100 leaves vanilla alone, 0 removes the effect, and
-- values in between scale how much of it is drawn.
local VANILLA = {
	purgatus_intensity = 100,
	flamer_intensity = 100,
	smite_intensity = 100,
	electro_intensity = 100,
	enemy_flame_intensity = 100,
}

local function merged(overrides)
	local settings = {}

	for key, value in pairs(VANILLA) do
		settings[key] = value
	end
	for key, value in pairs(overrides or {}) do
		settings[key] = value
	end

	return settings
end

describe("i_wanna_see", function()
	local f

	before_each(function()
		f = fixture()
	end)

	it("hooks every effect class it needs to intercept", function()
		assert.is_not_nil(f.hooks.init, "PsykerForceFieldUnitExtension.init")
		assert.is_not_nil(f.hooks._trigger_death_effects, "PsykerForceFieldUnitExtension._trigger_death_effects")
		assert.is_not_nil(f.hooks.add_child, "ChainLightningTarget.add_child")
		assert.is_not_nil(f.hooks._find_no_target, "ChainLightningLinkEffects._find_no_target")
		assert.is_not_nil(f.hooks._update_effects, "FlamerGasEffects._update_effects")
		assert.is_not_nil(f.hooks._create_effects, "FlamerPilotLightEffects._create_effects")
	end)

	describe("localization and options", function()
		it("survives string.format, so no percent sign is left unescaped", function()
			for text_id, translations in pairs(f.localization) do
				for language, text in pairs(translations) do
					local formatted, message = pcall(string.format, text)

					assert.is_true(formatted, text_id .. " (" .. language .. "): " .. tostring(message))
				end
			end
		end)

		it("has a localization entry for every widget the data file declares", function()
			local function check_widget(widget)
				assert.is_not_nil(f.localization[widget.setting_id], "widget " .. tostring(widget.setting_id))

				for _, child in ipairs(widget.sub_widgets or {}) do
					check_widget(child)
				end
			end

			for _, widget in ipairs(f.mod_data.options.widgets) do
				check_widget(widget)
			end
		end)
	end)

	describe("flamer", function()
		it("runs vanilla and never reads a setting at full intensity", function()
			f.set_settings(merged())
			f.set_action_settings({ fire_configuration = { damage_type = "warpfire" } })
			f.reset()

			f.flamer_update(f.new_flamer_self(), 0.1, 1)

			assert.are.equal(1, f.count("FlamerGasEffects._update_effects"), "vanilla body runs")
			assert.are.equal(0, f.count("Action.current_action_settings_from_component"), "settings are not consulted")
		end)

		it("skips the vanilla body and tears the stream down at 0%", function()
			f.set_settings(merged({ purgatus_intensity = 0 }))
			f.set_action_settings({ fire_configuration = { damage_type = "warpfire" } })
			f.reset()
			local flamer = f.new_flamer_self()

			f.flamer_update(flamer, 0.1, 1)

			assert.are.equal(0, f.count("FlamerGasEffects._update_effects"), "vanilla body skipped")
			assert.are.equal(1, f.count("self._destroy_effects"), "stream torn down")
			assert.are.equal(1, f.count("self._update_moving_lingering_effects"), "lingering particles still updated")
			assert.are.equal(true, flamer._destroy_args.allow_move, "allow_move passed")
			assert.are.equal(nil, flamer._destroy_args.rotation, "nil rotation accepted with no stream")
			assert.are.equal(0, f.count("World.find_particles_variable"), "no particle variable lookup")
		end)

		it("builds a rotation once when the stream is still alive", function()
			f.set_settings(merged({ purgatus_intensity = 0 }))
			f.set_action_settings({ fire_configuration = { damage_type = "warpfire" } })
			f.reset()
			local flamer = f.new_flamer_self()

			flamer._stream_effect_id = {}

			f.flamer_update(flamer, 0.1, 1)

			assert.is_not_nil(flamer._destroy_args.rotation, "rotation built for _destroy_effects")
			assert.are.equal(1, f.count("Quaternion.look"), "rotation built exactly once")
		end)

		it("drops impacts that were queued before the removal", function()
			f.set_settings(merged({ purgatus_intensity = 0 }))
			f.set_action_settings({ fire_configuration = { damage_type = "warpfire" } })
			f.reset()
			local flamer = f.new_flamer_self()

			flamer._impact_data[1].time = 5
			flamer._impact_data[1].effect_name = "content/fx/particles/weapons/x"

			f.flamer_update(flamer, 0.1, 1)

			assert.is_nil(flamer._impact_data[1].time, "queued impact time cleared")
			assert.is_nil(flamer._impact_data[1].effect_name, "queued impact effect cleared")
		end)

		it("scales the particle life at partial intensity", function()
			f.set_settings(merged({ purgatus_intensity = 50 }))
			f.set_action_settings({
				fire_configuration = { damage_type = "warpfire" },
				fx = { stream_effect = { speed = 2, name = "content/fx/test_stream" } },
			})
			f.reset()
			local flamer = f.new_flamer_self()

			flamer._stream_effect_id = {}

			f.flamer_update(flamer, 0.1, 1)

			assert.are.equal(1, f.count("FlamerGasEffects._update_effects"), "vanilla body still runs")
			assert.are.equal(1, f.count("World.set_particles_variable"), "particle variable set")
			assert.are.equal(2.5, f.stream_life().x, "life is halved (range 10 / speed 2 * 50%)")
		end)

		it("thins the scorch marks by an exact ratio at partial intensity", function()
			f.set_settings(merged({ purgatus_intensity = 50 }))
			f.set_action_settings({
				fire_configuration = { damage_type = "warpfire" },
				fx = { stream_effect = { speed = 2, name = "content/fx/test_stream" } },
			})
			local flamer = f.new_flamer_self()

			flamer._impact_data[1].time = 5
			flamer._impact_index = 2

			f.flamer_update(flamer, 0.1, 1)

			assert.is_nil(flamer._impact_data[1].time, "first queued decal dropped")

			flamer._impact_data[2].time = 6
			flamer._impact_index = 3

			f.flamer_update(flamer, 0.1, 1)

			assert.are.equal(6, flamer._impact_data[2].time, "second queued decal kept")
		end)

		it("reports what the scaling resolved to when debugging is on", function()
			f.set_settings(merged({ purgatus_intensity = 50, debug_intensity = true }))
			f.set_action_settings({
				fire_configuration = { damage_type = "warpfire" },
				fx = { stream_effect = { speed = 2, name = "content/fx/test_stream" } },
			})
			f.reset()
			local flamer = f.new_flamer_self()

			flamer._stream_effect_id = {}

			f.flamer_update(flamer, 0.1, 1)

			assert.is_truthy(f.last_echo())
			assert.is_truthy(f.last_echo():find("life", 1, true), f.last_echo())
		end)

		it("stays quiet when debugging is off", function()
			f.set_settings(merged({ purgatus_intensity = 50 }))
			f.set_action_settings({
				fire_configuration = { damage_type = "warpfire" },
				fx = { stream_effect = { speed = 2, name = "content/fx/test_stream" } },
			})
			f.reset()
			local flamer = f.new_flamer_self()

			flamer._stream_effect_id = {}

			f.flamer_update(flamer, 0.1, 1)

			assert.are.equal(0, f.count("mod.echo"), "no chat messages")
		end)

		it("caches the particle variable lookup per effect name", function()
			f.set_settings(merged({ purgatus_intensity = 50 }))
			f.set_action_settings({
				fire_configuration = { damage_type = "warpfire" },
				fx = { stream_effect = { speed = 2, name = "content/fx/test_stream" } },
			})
			f.reset()
			local flamer = f.new_flamer_self()

			flamer._stream_effect_id = {}

			f.flamer_update(flamer, 0.1, 1)
			f.flamer_update(flamer, 0.1, 1)

			assert.are.equal(1, f.count("World.find_particles_variable"), "looked up once, not once per frame")
			assert.are.equal(2, f.count("World.set_particles_variable"), "still set every frame")
		end)

		it("leaves a burning weapon alone while only purgatus is configured", function()
			f.set_settings(merged({ purgatus_intensity = 0 }))
			f.set_action_settings({ fire_configuration = { damage_type = "burning" } })
			f.reset()

			f.flamer_update(f.new_flamer_self(), 0.1, 1)

			assert.are.equal(1, f.count("FlamerGasEffects._update_effects"), "vanilla untouched")
		end)

		it("suppresses a weapon whose plural configurations are all removed", function()
			f.set_settings(merged({ purgatus_intensity = 0, flamer_intensity = 0 }))
			f.set_action_settings({
				fire_configurations = { { damage_type = "warpfire" }, { damage_type = "burning" } },
			})
			f.reset()

			f.flamer_update(f.new_flamer_self(), 0.1, 1)

			assert.are.equal(0, f.count("FlamerGasEffects._update_effects"), "suppressed")
		end)

		it("takes the most restrictive of several configurations", function()
			f.set_settings(merged({ purgatus_intensity = 0, flamer_intensity = 100 }))
			f.set_action_settings({
				fire_configurations = { { damage_type = "warpfire" }, { damage_type = "burning" } },
			})
			f.reset()

			f.flamer_update(f.new_flamer_self(), 0.1, 1)

			assert.are.equal(0, f.count("FlamerGasEffects._update_effects"), "a removed configuration wins")
		end)

		it("follows the intensity when it changes at runtime", function()
			f.set_settings(merged({ purgatus_intensity = 0 }))
			f.set_action_settings({ fire_configuration = { damage_type = "warpfire" } })

			f.set_setting("purgatus_intensity", 100)
			f.reset()

			f.flamer_update(f.new_flamer_self(), 0.1, 1)

			assert.are.equal(1, f.count("FlamerGasEffects._update_effects"), "cache refreshed by on_setting_changed")
		end)
	end)

	describe("chain lightning", function()
		it("suppresses Smite beams but keeps the node tree and hit_units bookkeeping", function()
			f.set_settings(merged({ smite_intensity = 0 }))
			f.set_action_settings({ chain_settings = { staff = false } })
			f.reset()
			local context = f.new_chain_context()
			local node = {}

			f.chain_add_child(node, f.vanilla_callback(), context)

			assert.are.equal(1, f.count("ChainLightningTarget.add_child"), "node is still added")
			assert.are.equal(1, node._num_children, "node bookkeeping preserved")
			assert.are.equal(0, f.count("ORIGINAL_ON_ADD"), "the spawn callback is skipped")
			assert.is_true(context.hit_units[f.unit], "hit_units bookkeeping preserved")
		end)

		it("classifies a source once and reuses it", function()
			f.set_settings(merged({ smite_intensity = 0 }))
			f.set_action_settings({ chain_settings = { staff = false } })
			local context = f.new_chain_context()

			f.chain_add_child({}, f.vanilla_callback(), context)
			f.reset()

			f.chain_add_child({}, f.vanilla_callback(), context)

			assert.are.equal(0, f.count("Action.current_action_settings_from_component"), "classification cached")
		end)

		it("leaves the chain alone at full intensity", function()
			f.set_settings(merged())
			f.set_action_settings({ chain_settings = { staff = false } })
			f.reset()

			f.chain_add_child({}, f.vanilla_callback(), f.new_chain_context())

			assert.are.equal(1, f.count("ORIGINAL_ON_ADD"), "vanilla callback used")
			assert.are.equal(0, f.count("Action.current_action_settings_from_component"), "sources are not even classified")
		end)

		it("keeps electrokinetic staff beams while only Smite is removed", function()
			f.set_settings(merged({ smite_intensity = 0 }))
			f.set_action_settings({ chain_settings = { staff = true } })
			f.reset()

			f.chain_add_child({}, f.vanilla_callback(), f.new_chain_context())

			assert.are.equal(1, f.count("ORIGINAL_ON_ADD"), "staff beams kept")
		end)

		it("suppresses staff beams when the staff is at 0%", function()
			f.set_settings(merged({ smite_intensity = 100, electro_intensity = 0 }))
			f.set_action_settings({ chain_settings = { staff = true } })
			f.reset()
			local context = f.new_chain_context()

			f.chain_add_child({}, f.vanilla_callback(), context)

			assert.are.equal(0, f.count("ORIGINAL_ON_ADD"), "staff beams skipped")
			assert.is_true(context.hit_units[f.unit], "hit_units bookkeeping preserved")
		end)

		it("keeps every other link at partial intensity", function()
			f.set_settings(merged({ smite_intensity = 50 }))
			f.set_action_settings({ chain_settings = { staff = false } })
			f.reset()
			local context = f.new_chain_context()

			f.chain_add_child({}, f.vanilla_callback(), context)
			assert.are.equal(0, f.count("ORIGINAL_ON_ADD"), "first link dropped")

			f.chain_add_child({}, f.vanilla_callback(), context)
			assert.are.equal(1, f.count("ORIGINAL_ON_ADD"), "second link kept")

			f.chain_add_child({}, f.vanilla_callback(), context)
			assert.are.equal(1, f.count("ORIGINAL_ON_ADD"), "third link dropped")

			f.chain_add_child({}, f.vanilla_callback(), context)
			assert.are.equal(2, f.count("ORIGINAL_ON_ADD"), "fourth link kept")
		end)

		it("suppresses the no target arc only when the chain is removed", function()
			f.set_settings(merged({ smite_intensity = 0 }))
			f.set_action_settings({ chain_settings = { staff = false } })
			f.reset()

			f.find_no_target({ _func_context = f.new_chain_context() }, 1)

			assert.are.equal(0, f.count("ChainLightningLinkEffects._find_no_target"), "arc skipped")

			f.set_settings(merged({ smite_intensity = 50 }))
			f.reset()

			f.find_no_target({ _func_context = f.new_chain_context() }, 1)

			assert.are.equal(1, f.count("ChainLightningLinkEffects._find_no_target"), "arc kept while thinning")
		end)

		it("leaves the no target arc to vanilla at full intensity", function()
			f.set_settings(merged())
			f.reset()

			f.find_no_target({ _func_context = f.new_chain_context() }, 1)

			assert.are.equal(1, f.count("ChainLightningLinkEffects._find_no_target"), "arc left to vanilla")
		end)
	end)

	describe("psyker shield", function()
		it("runs vanilla init and changes nothing when every option is off", function()
			f.set_settings(merged())
			f.reset()

			f.shield_init(f.new_shield_self())

			assert.are.equal(1, f.count("PsykerForceFieldUnitExtension.init"), "vanilla init runs")
			assert.are.equal(0, f.count("Unit.set_unit_visibility"), "unit left visible")
			assert.are.equal(0, f.count("WwiseWorld.destroy_manual_source"), "sound left alone")
			assert.are.equal(0, f.count("World.destroy_particles"), "particles left alone")
			assert.are.equal(0, f.count("World.spawn_unit_ex"), "no decal spawned")
		end)

		it("stops the start sound, removes the start particle and spawns the decal when all options are on", function()
			f.set_settings(merged({ remove_shield_sound = true, remove_shield_effect = true, display_shield_radius = true }))
			f.reset()
			local shield = f.new_shield_self()

			f.shield_init(shield)

			assert.are.equal(1, f.count("PsykerForceFieldUnitExtension.init"), "vanilla init still runs")
			assert.are.equal(1, f.count("WwiseWorld.stop_event"), "start sound stopped")
			assert.are.equal(1, f.count("WwiseWorld.destroy_manual_source"), "sound source released")
			assert.is_nil(shield._source_id, "source id cleared")
			assert.is_nil(shield._playing_id, "playing id cleared")
			assert.are.equal(1, f.count("World.destroy_particles"), "start particle removed")
			assert.is_nil(shield._effect_id, "effect id cleared")
			assert.are.equal(1, f.count("Unit.set_unit_visibility"), "shield mesh hidden")
			assert.are.equal(1, f.count("World.spawn_unit_ex"), "radius decal spawned")
		end)

		it("takes the decal colour from the color widget", function()
			f.set_settings(merged({ display_shield_radius = true, shield_radius_color = { 255, 8, 9, 10 } }))
			f.reset()

			f.shield_init(f.new_shield_self({}))

			local color = f.decal_color()

			assert.are.equal(8, color[1], "red channel")
			assert.are.equal(9, color[2], "green channel")
			assert.are.equal(10, color[3], "blue channel")
			assert.are.equal(0.5, color[4], "alpha left as vanilla draws it")
		end)

		it("removes the shield visuals without touching the sound when only the effect is on", function()
			f.set_settings(merged({ remove_shield_effect = true }))
			f.reset()

			f.shield_init(f.new_shield_self())

			assert.are.equal(0, f.count("WwiseWorld.destroy_manual_source"), "sound untouched")
			assert.are.equal(1, f.count("World.destroy_particles"), "start particle removed")
			assert.are.equal(1, f.count("Unit.set_unit_visibility"), "shield mesh hidden")
		end)

		it("runs vanilla death effects when every option is off", function()
			f.set_settings(merged())
			f.reset()

			f.shield_death(f.new_shield_self())

			assert.are.equal(1, f.count("PsykerForceFieldUnitExtension._trigger_death_effects"), "vanilla handles it")
		end)

		it("never triggers a wwise event with a nil source once the sound is removed", function()
			f.set_settings(merged({ remove_shield_sound = true, remove_shield_effect = true }))
			f.reset()
			local shield = f.new_shield_self()

			shield._source_id = nil
			shield._playing_id = nil

			f.shield_death(shield)

			assert.are.equal(0, f.count("PsykerForceFieldUnitExtension._trigger_death_effects"), "vanilla skipped")
			assert.are.equal(0, f.count("WwiseWorld.trigger_resource_event"), "no event triggered")
			assert.are.equal(0, f.count("WwiseWorld.destroy_manual_source"), "no source destroyed")
			assert.are.equal(1, f.count("Unit.flow_event"), "sphere stop flow event kept")
			assert.are.equal(1, f.count("World.destroy_particles"), "start particle removed")
			assert.are.equal(0, f.count("World.create_particles"), "fade particle suppressed")
		end)

		it("keeps the fade particle when only the sound is removed", function()
			f.set_settings(merged({ remove_shield_sound = true }))
			f.reset()

			f.shield_death(f.new_shield_self())

			assert.are.equal(0, f.count("WwiseWorld.trigger_resource_event"), "still no event triggered")
			assert.are.equal(1, f.count("World.create_particles"), "fade particle kept")
		end)

		it("runs vanilla for the sound and then removes the fade particle", function()
			f.set_settings(merged({ remove_shield_effect = true }))
			f.reset()
			local shield = f.new_shield_self()

			f.shield_death(shield)

			assert.are.equal(1, f.count("PsykerForceFieldUnitExtension._trigger_death_effects"), "vanilla run")
			assert.are.equal(1, f.count("World.destroy_particles"), "fade particle removed after")
			assert.is_nil(shield._effect_id, "effect id cleared")
		end)

		it("destroys the radius decal on death even after the option is turned off", function()
			f.set_settings(merged({ display_shield_radius = true }))
			f.reset()
			local shield = f.new_shield_self({})

			f.shield_init(shield)

			assert.are.equal(1, f.count("World.spawn_unit_ex"), "decal spawned")

			f.set_setting("display_shield_radius", false)
			f.reset()

			f.shield_death(shield)

			assert.are.equal(1, f.count("World.destroy_unit"), "decal destroyed anyway")
		end)

		it("clears decal bookkeeping when the game state changes", function()
			f.set_settings(merged({ display_shield_radius = true }))
			f.shield_init(f.new_shield_self({}))

			assert.has_no.errors(function()
				f.game_state_changed()
			end)
		end)
	end)

	describe("flamer pilot light", function()
		it("never creates the pilot light when the flamer is removed", function()
			f.set_settings(merged({ flamer_intensity = 0 }))
			f.reset()

			f.pilot_create({})

			assert.are.equal(0, f.count("FlamerPilotLightEffects._create_effects"), "never created")
		end)

		it("keeps the pilot light while the flame is only scaled down", function()
			f.set_settings(merged({ flamer_intensity = 50 }))
			f.reset()

			f.pilot_create({})

			assert.are.equal(1, f.count("FlamerPilotLightEffects._create_effects"), "created by vanilla")
		end)

		it("lets vanilla create it at full intensity", function()
			f.set_settings(merged())
			f.reset()

			f.pilot_create({})

			assert.are.equal(1, f.count("FlamerPilotLightEffects._create_effects"), "created by vanilla")
		end)
	end)

	describe("enemy flames", function()
		local enemy = { name = "enemy_flamer" }
		local ally = { name = "ally_flamer" }
		local stranger = { name = "prop" }

		before_each(function()
			f.put_unit_on_side(enemy, "enemies")
			f.put_unit_on_side(ally, "players")
		end)

		it("leaves every enemy flame alone at full intensity", function()
			f.set_settings(merged())
			f.reset()

			f.flamer_start_shooting(1, enemy)
			f.flamer_update_shooting(1, enemy)

			assert.are.equal(1, f.count("Flamer.start_shooting_fx"), "jet created by vanilla")
			assert.are.equal(1, f.count("Flamer.update_shooting_fx"), "sparks and ground fire left to vanilla")
		end)

		it("removes every enemy flame at 0%", function()
			f.set_settings(merged({ enemy_flame_intensity = 0 }))
			f.reset()

			f.flamer_start_shooting(1, enemy)
			f.flamer_update_shooting(1, enemy)

			assert.are.equal(0, f.count("Flamer.start_shooting_fx"), "jet skipped")
			assert.are.equal(0, f.count("Flamer.update_shooting_fx"), "sparks and ground fire skipped")
		end)

		it("never touches units on the player's side", function()
			f.set_settings(merged({ enemy_flame_intensity = 0 }))
			f.reset()

			f.flamer_start_shooting(1, ally)
			f.flamer_start_shooting(1, f.player_unit)

			assert.are.equal(2, f.count("Flamer.start_shooting_fx"), "own side untouched")
		end)

		it("never touches units the side system does not know about", function()
			f.set_settings(merged({ enemy_flame_intensity = 0 }))
			f.reset()

			f.flamer_start_shooting(1, stranger)

			assert.are.equal(1, f.count("Flamer.start_shooting_fx"), "unknown units left to vanilla")
		end)

		it("drops a stable share of enemies at partial intensity", function()
			f.set_settings(merged({ enemy_flame_intensity = 50 }))

			f.set_random(0.9)
			f.reset()

			f.flamer_start_shooting(1, enemy)

			assert.are.equal(0, f.count("Flamer.start_shooting_fx"), "enemy dropped")

			f.set_random(0.1)
			f.reset()

			f.flamer_start_shooting(1, enemy)

			assert.are.equal(0, f.count("Flamer.start_shooting_fx"), "the decision is stable per enemy")

			local other = { name = "other_flamer" }

			f.put_unit_on_side(other, "enemies")
			f.reset()

			f.flamer_start_shooting(1, other)

			assert.are.equal(1, f.count("Flamer.start_shooting_fx"), "another enemy keeps its flame")
		end)

		it("follows the setting when it changes at runtime", function()
			f.set_settings(merged({ enemy_flame_intensity = 0 }))
			f.set_setting("enemy_flame_intensity", 100)
			f.reset()

			f.flamer_start_shooting(1, enemy)

			assert.are.equal(1, f.count("Flamer.start_shooting_fx"), "cache refreshed by on_setting_changed")
		end)
	end)
end)
