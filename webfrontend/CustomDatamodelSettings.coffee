class CustomDatamodelSettings extends SchemaPlugin
	getCustomSettings: (data) ->
		fields = [
			type: CUI.Input
			textarea: true
			name: "script"
			form:
				label: "Javascript"
			data: data.custom_settings
		]
		return fields

	getCustomSettingsLabel: (data) ->
		return "Formula Code"

	getCustomSettingsDisplay: (data) ->
		if data.custom_settings.script
			return ["Formula"]

Schema.registerPlugin(new CustomDatamodelSettings())
