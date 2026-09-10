return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`i_wanna_see` encountered an error loading the Darktide Mod Framework.")

		new_mod("i_wanna_see", {
			mod_script       = "i_wanna_see/scripts/mods/i_wanna_see/i_wanna_see",
			mod_data         = "i_wanna_see/scripts/mods/i_wanna_see/i_wanna_see_data",
			mod_localization = "i_wanna_see/scripts/mods/i_wanna_see/i_wanna_see_localization",
		})
	end,
	packages = {},
}
