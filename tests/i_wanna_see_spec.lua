local fixture = require("tests.support.i_wanna_see_fixture")

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

	describe("flamer", function()
		it("runs vanilla and never reads a setting when every option is off", function()
			f.set_settings()
			f.set_action_settings({ fire_configuration = { damage_type = "warpfire" } })
			f.reset()

			f.flamer_update(f.new_flamer_self(), 0.1, 1)

			assert.are.equal(1, f.count("FlamerGasEffects._update_effects"), "vanilla body runs")
			assert.are.equal(0, f.count("Action.current_action_settings_from_component"), "settings are not consulted")
		end)

		it("skips the vanilla body and tears the stream down when suppressed", function()
			f.set_settings({ remove_purgatus_effect = true })
			f.set_action_settings({ fire_configuration = { damage_type = "warpfire" } })
			f.reset()
			local flamer = f.new_flamer_self()

			f.flamer_update(flamer, 0.1, 1)

			assert.are.equal(0, f.count("FlamerGasEffects._update_effects"), "vanilla body skipped")
			assert.are.equal(1, f.count("self._destroy_effects"), "stream torn down")
			assert.are.equal(1, f.count("self._update_moving_lingering_effects"), "lingering particles still updated")
			assert.are.equal(true, flamer._destroy_args.allow_move, "allow_move passed")
			assert.are.equal(nil, flamer._destroy_args.rotation, "nil rotation accepted with no stream")
			assert.are.equal(1, f.count("Action.current_action_settings_from_component"), "settings read once")
			assert.are.equal(0, f.count("World.find_particles_variable"), "no particle variable lookup")
		end)

		it("builds a rotation once when the stream is still alive", function()
			f.set_settings({ remove_purgatus_effect = true })
			f.set_action_settings({ fire_configuration = { damage_type = "warpfire" } })
			f.reset()
			local flamer = f.new_flamer_self()

			flamer._stream_effect_id = {}

			f.flamer_update(flamer, 0.1, 1)

			assert.is_not_nil(flamer._destroy_args.rotation, "rotation built for _destroy_effects")
			assert.are.equal(1, f.count("Quaternion.look"), "rotation built exactly once")
			assert.are.equal(0, f.count("World.find_particles_variable"), "no particle variable lookup")
		end)

		it("drops impacts that were queued before the suppression", function()
			f.set_settings({ remove_purgatus_effect = true })
			f.set_action_settings({ fire_configuration = { damage_type = "warpfire" } })
			f.reset()
			local flamer = f.new_flamer_self()

			flamer._impact_data[1].time = 5
			flamer._impact_data[1].effect_name = "content/fx/particles/weapons/x"

			f.flamer_update(flamer, 0.1, 1)

			assert.is_nil(flamer._impact_data[1].time, "queued impact time cleared")
			assert.is_nil(flamer._impact_data[1].effect_name, "queued impact effect cleared")
		end)

		it("leaves a burning weapon alone while only purgatus removal is on", function()
			f.set_settings({ remove_purgatus_effect = true })
			f.set_action_settings({ fire_configuration = { damage_type = "burning" } })
			f.reset()

			f.flamer_update(f.new_flamer_self(), 0.1, 1)

			assert.are.equal(1, f.count("FlamerGasEffects._update_effects"), "vanilla untouched")
		end)

		it("suppresses a weapon that uses the plural fire configurations", function()
			f.set_settings({ remove_purgatus_effect = true })
			f.set_action_settings({ fire_configurations = { { damage_type = "warpfire" } } })
			f.reset()

			f.flamer_update(f.new_flamer_self(), 0.1, 1)

			assert.are.equal(0, f.count("FlamerGasEffects._update_effects"), "plural all-warpfire suppressed")
		end)

		it("leaves a mixed plural weapon to vanilla", function()
			f.set_settings({ remove_purgatus_effect = true })
			f.set_action_settings({
				fire_configurations = { { damage_type = "warpfire" }, { damage_type = "burning" } },
			})
			f.reset()

			f.flamer_update(f.new_flamer_self(), 0.1, 1)

			assert.are.equal(1, f.count("FlamerGasEffects._update_effects"), "mixed configurations left alone")
		end)

		it("follows the setting when it changes at runtime", function()
			f.set_settings({ remove_purgatus_effect = true })
			f.set_action_settings({ fire_configuration = { damage_type = "warpfire" } })

			f.set_setting("remove_purgatus_effect", false)
			f.reset()

			f.flamer_update(f.new_flamer_self(), 0.1, 1)

			assert.are.equal(1, f.count("FlamerGasEffects._update_effects"), "cache refreshed by on_setting_changed")
		end)
	end)

	describe("chain lightning", function()
		it("suppresses Smite beams but keeps the node tree and hit_units bookkeeping", function()
			f.set_settings({ remove_smite_effect = true })
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
			f.set_settings({ remove_smite_effect = true })
			f.set_action_settings({ chain_settings = { staff = false } })
			local context = f.new_chain_context()

			f.chain_add_child({}, f.vanilla_callback(), context)
			f.reset()

			f.chain_add_child({}, f.vanilla_callback(), context)

			assert.are.equal(0, f.count("Action.current_action_settings_from_component"), "classification cached")
		end)

		it("leaves the chain alone when the option is off", function()
			f.set_settings()
			f.set_action_settings({ chain_settings = { staff = false } })
			f.reset()

			f.chain_add_child({}, f.vanilla_callback(), f.new_chain_context())

			assert.are.equal(1, f.count("ORIGINAL_ON_ADD"), "vanilla callback used")
		end)

		it("keeps electrokinetic staff beams while remove_electro_effect is off", function()
			f.set_settings({ remove_smite_effect = true })
			f.set_action_settings({ chain_settings = { staff = true } })
			f.reset()

			f.chain_add_child({}, f.vanilla_callback(), f.new_chain_context())

			assert.are.equal(1, f.count("ORIGINAL_ON_ADD"), "staff beams kept")
		end)

		it("suppresses staff beams once remove_electro_effect is on", function()
			f.set_settings({ remove_smite_effect = true, remove_electro_effect = true })
			f.set_action_settings({ chain_settings = { staff = true } })
			f.reset()
			local context = f.new_chain_context()

			f.chain_add_child({}, f.vanilla_callback(), context)

			assert.are.equal(0, f.count("ORIGINAL_ON_ADD"), "staff beams skipped")
			assert.is_true(context.hit_units[f.unit], "hit_units bookkeeping preserved")
		end)

		it("suppresses the no target arc, which is spawned outside add_child", function()
			f.set_settings({ remove_smite_effect = true })
			f.set_action_settings({ chain_settings = { staff = false } })
			f.reset()

			f.find_no_target({ _func_context = f.new_chain_context() }, 1)

			assert.are.equal(0, f.count("ChainLightningLinkEffects._find_no_target"), "arc skipped")
		end)

		it("leaves the no target arc to vanilla when the option is off", function()
			f.set_settings()
			f.reset()

			f.find_no_target({ _func_context = f.new_chain_context() }, 1)

			assert.are.equal(1, f.count("ChainLightningLinkEffects._find_no_target"), "arc left to vanilla")
		end)
	end)

	describe("psyker shield", function()
		it("runs vanilla init and changes nothing when every option is off", function()
			f.set_settings()
			f.reset()

			f.shield_init(f.new_shield_self())

			assert.are.equal(1, f.count("PsykerForceFieldUnitExtension.init"), "vanilla init runs")
			assert.are.equal(0, f.count("Unit.set_unit_visibility"), "unit left visible")
			assert.are.equal(0, f.count("WwiseWorld.destroy_manual_source"), "sound left alone")
			assert.are.equal(0, f.count("World.destroy_particles"), "particles left alone")
			assert.are.equal(0, f.count("World.spawn_unit_ex"), "no decal spawned")
		end)

		it("stops the start sound, removes the start particle and spawns the decal when all options are on", function()
			f.set_settings({ remove_shield_sound = true, remove_shield_effect = true, display_shield_radius = true })
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
			assert.are.equal(1, f.count("Unit.set_vector4_for_material"), "decal colour applied")
		end)

		it("removes the shield visuals without touching the sound when only the effect is on", function()
			f.set_settings({ remove_shield_effect = true })
			f.reset()

			f.shield_init(f.new_shield_self())

			assert.are.equal(0, f.count("WwiseWorld.destroy_manual_source"), "sound untouched")
			assert.are.equal(1, f.count("World.destroy_particles"), "start particle removed")
			assert.are.equal(1, f.count("Unit.set_unit_visibility"), "shield mesh hidden")
		end)

		it("runs vanilla death effects when every option is off", function()
			f.set_settings()
			f.reset()

			f.shield_death(f.new_shield_self())

			assert.are.equal(1, f.count("PsykerForceFieldUnitExtension._trigger_death_effects"), "vanilla handles it")
		end)

		it("never triggers a wwise event with a nil source once the sound is removed", function()
			f.set_settings({ remove_shield_sound = true, remove_shield_effect = true })
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
			f.set_settings({ remove_shield_sound = true })
			f.reset()

			f.shield_death(f.new_shield_self())

			assert.are.equal(0, f.count("WwiseWorld.trigger_resource_event"), "still no event triggered")
			assert.are.equal(1, f.count("World.create_particles"), "fade particle kept")
		end)

		it("runs vanilla for the sound and then removes the fade particle", function()
			f.set_settings({ remove_shield_effect = true })
			f.reset()
			local shield = f.new_shield_self()

			f.shield_death(shield)

			assert.are.equal(1, f.count("PsykerForceFieldUnitExtension._trigger_death_effects"), "vanilla run")
			assert.are.equal(1, f.count("World.destroy_particles"), "fade particle removed after")
			assert.is_nil(shield._effect_id, "effect id cleared")
		end)

		it("destroys the radius decal on death even after the option is turned off", function()
			f.set_settings({ display_shield_radius = true })
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
			f.set_settings({ display_shield_radius = true })
			f.shield_init(f.new_shield_self({}))

			assert.has_no.errors(function()
				f.game_state_changed()
			end)
		end)
	end)

	describe("flamer pilot light", function()
		it("never creates the pilot light when the flamer option is on", function()
			f.set_settings({ remove_flamer_effect = true })
			f.reset()

			f.pilot_create({})

			assert.are.equal(0, f.count("FlamerPilotLightEffects._create_effects"), "never created")
		end)

		it("lets vanilla create it when the option is off", function()
			f.set_settings()
			f.reset()

			f.pilot_create({})

			assert.are.equal(1, f.count("FlamerPilotLightEffects._create_effects"), "created by vanilla")
		end)
	end)
end)
