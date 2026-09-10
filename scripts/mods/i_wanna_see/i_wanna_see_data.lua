local mod = get_mod("i_wanna_see")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "purgatus_intensity",
				type = "numeric",
				default_value = 0,
				range = { 0, 100 },
				decimals_number = 0,
			},
			{
				setting_id = "flamer_intensity",
				type = "numeric",
				default_value = 0,
				range = { 0, 100 },
				decimals_number = 0,
			},
			{
				setting_id = "smite_intensity",
				type = "numeric",
				default_value = 0,
				range = { 0, 100 },
				decimals_number = 0,
			},
			{
				setting_id = "electro_intensity",
				type = "numeric",
				default_value = 0,
				range = { 0, 100 },
				decimals_number = 0,
			},
			{
				setting_id = "shield_group",
				type = "group",
				sub_widgets = {
					{
						setting_id = "remove_shield_effect",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "remove_shield_sound",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "display_shield_radius",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "shield_radius_color",
						type = "color",
						default_value = { 255, 0, 0, 4 },
						has_alpha = false,
					},
				},
			},
		},
	},
}

