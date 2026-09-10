local mod = get_mod("i_wanna_see")

return {
	name = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "remove_purgatus_effect",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "remove_smite_effect",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "remove_electro_effect",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "remove_flamer_effect",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id  = "shield_group",
				type        = "group",
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
						setting_id = "R",
						type = "numeric",
						default_value = 0,
						range = {0, 255},
						decimals_number = 0,  
					},
					{
						setting_id = "G",
						type = "numeric",
						default_value = 0,
						range = {0, 255},
						decimals_number = 0,  
					},
					{
						setting_id = "B",
						type = "numeric",
						default_value = 4,
						range = {0, 255},
						decimals_number = 0,  
					},
				}
			},
		}
	}
}
