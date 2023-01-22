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
		tmpData =
			script: editorBtn.getData().script or ""

		editorWrapper = new CUI.VerticalList
			content: [
				new CUI.Label(text:"function (objNew, objCurr, dataPath, dataPathCurr) {")
			,
				@renderEditor(editorBtn, tmpData)
			,
				new CUI.Label(text:"}")
			]

		popover = new CUI.Popover
			element: editorBtn
			placement: "wm"
			class: "commonPlugin_Popover"
			pane:
				header_left: new CUI.Label(text: "JavaScript Code")
				content: editorWrapper
				footer_right: [
						text: "Apply"
						primary: true
						onClick: () =>
							editorBtn.getData().script = tmpData.script
							CUI.Events.trigger
								node: editorBtn
								type: "data-changed"
							popover.destroy()
				]

		popover.show()

	renderEditor: (editorBtn, tmpData) ->
		editorForm = new CUI.Form
			data: tmpData
			maximize_horizontal: true
			fields: [
				type: CUI.CodeInput
				mode: "javascript"
				name: "script"
			]
			onDataChanged: =>

		return editorForm.start()

Schema.registerPlugin(new CustomDatamodelSettings())


