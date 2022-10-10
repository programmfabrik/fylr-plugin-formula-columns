class CustomDatamodelSettings extends SchemaPlugin
	getCustomSettings: (data) ->
		if (!data.custom_settings["formula-columns"])
			data.custom_settings["formula-columns"] = {}
		pData = data.custom_settings["formula-columns"]
		fields = [
			type: CUI.Input
			textarea: true
			name: "script"
			form:
				label: "Javascript"
			data: pData
		,
			type: CUI.Checkbox
			name: "debug"
			form:
				label: "Debug"
			data: pData
		]
		return fields

	getCustomSettingsLabel: (data) ->
		return "Formula Code"

	getCustomSettingsDisplay: (data) ->
		if data.custom_settings["formula-columns"]?.script
			return ["Formula"]

	getName: () ->
		return "formula-columns"

Schema.registerPlugin(new CustomDatamodelSettings())
