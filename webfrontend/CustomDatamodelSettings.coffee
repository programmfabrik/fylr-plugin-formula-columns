class CustomDatamodelSettings extends SchemaPlugin
	getCustomSettings: (data) ->
		if (!data.custom_settings["formula-columns"])
			data.custom_settings["formula-columns"] = {}
		pData = data.custom_settings["formula-columns"]
		fields = [
			type: CUI.DataFieldProxy
			name: "newscript"
			form:
				label: "Javascript"
			data: pData
			element: (editorBtn) =>
				return new CUI.Button
					text: "Edit Script"
					onClick: () =>
						@openEditorPopover(editorBtn)
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

	openEditorPopover: (editorBtn) ->
		popover = new CUI.Popover
			element: editorBtn
			placement: "wm"
			class: "commonPlugin_Popover"
			pane:
				header_left: new CUI.Label(text: "JavaScript Code")
				content: @renderEditor(editorBtn)
				footer_right: [
						text: "Save"
						primary: true
						onClick: () =>
							popover.destroy()
				]

		popover.show()

	renderEditor: (editorBtn) ->
		editorForm = new CUI.Form
			data: editorBtn.getData()
			maximize_horizontal: true
			fields: [
				type: CUI.CodeInput
				mode: "javascript"
				name: "script"
			]
			onDataChanged: =>
				CUI.Events.trigger
					node: editorBtn
					type: "data-changed"

		return editorForm.start()



Schema.registerPlugin(new CustomDatamodelSettings())


