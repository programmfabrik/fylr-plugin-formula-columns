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
					text: $$("formula_columns_plugin.schema.editscript.button")
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
		return $$("formula_columns_plugin.schema.label")

	getCustomSettingsDisplay: (data) ->
		if data.custom_settings["formula-columns"]?.script
			return ["Formula"]

	getName: () ->
		return "formula-columns"

	openEditorPopover: (editorBtn) ->
		tmpData =
			script: editorBtn.getData().script or ""

		applyButton = new CUI.Button
			text: $$("formula_columns_plugin.schema.applybtn")
			primary: true
			onClick: () =>
				editorBtn.getData().script = tmpData.script
				CUI.Events.trigger
					node: editorBtn
					type: "data-changed"
				popover.destroy()

		cancelButton = new CUI.Button
			text: $$("formula_columns_plugin.schema.cancelbtn")
			onClick: () =>
				popover.destroy()

		editorWrapper = new CUI.VerticalList
			class: "editor-wrapper"
			maximize: true
			content: [
				new CUI.Label
					text:"`function (objNew, objCurr, dataPath, dataPathCurr) {`"
					markdown: true
			,
				@renderEditor(editorBtn, tmpData, applyButton)
			,
				new CUI.Label
					text:"`}`"
					markdown: true
			]

		info = new CUI.Label
			class: "formula-column-plugin-info-label"
			text: $$("formula_columns_plugin.editor.infotext")
			multiline: true
			centered: false
			markdown: true

		modal = new CUI.Modal
			cancel: true
			fill_space: "both"
			class: "formula-column-plugin-modal"
			pane:
				header_left: new CUI.Label(text: $$("formula_columns_plugin.editor.label"))
				footer_right: [
					cancelButton
					applyButton
				]
				content: new CUI.HorizontalList
					maximize: true
					class: "formula-column-modal-hl"
					content: [
						editorWrapper
					,
						info
					]

		modal.show()

	renderEditor: (editorBtn, tmpData, applyButton) ->
		editorForm = new CUI.Form
			data: tmpData
			maximize_horizontal: true
			maximize_vertical: true
			fields: [
				type: CUI.CodeInput
				maximize_horizontal: true
				mode: "javascript"
				name: "script"
			]
			onDataChanged: =>
				try
					eval("function test(){" + tmpData.script + "}")
					applyButton.enable()
				catch e
					applyButton.disable()
		return editorForm.start()

Schema.registerPlugin(new CustomDatamodelSettings())


