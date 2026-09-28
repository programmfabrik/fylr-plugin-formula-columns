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
						@openEditorPopover(editorBtn, data)
		,
			type: CUI.Checkbox
			name: "debug"
			form:
				label: $$("formula_columns_plugin.schema.debug")
			data: pData
			disabled: CUI.util.isEmpty(pData.script)
		,
			type: CUI.Checkbox
			name: "disabled"
			form:
				label: $$("formula_columns_plugin.schema.disabled")
			data: pData
			disabled: CUI.util.isEmpty(pData.script)
		,
			type: CUI.Checkbox
			name: "run_as_plugin_user"
			form:
				label: $$("formula_columns_plugin.schema.as_user")
			data: pData
			disabled: CUI.util.isEmpty(pData.script)
		]
		return fields

	getCustomSettingsLabel: (data) ->
		return $$("formula_columns_plugin.schema.label")

	getCustomSettingsDisplay: (data) ->
		if data.custom_settings["formula-columns"]?.script
			return ["Formula"]

	getName: () ->
		return "formula-columns"

	openEditorPopover: (editorBtn, columnData) ->
		tmpData =
			script: editorBtn.getData().script or ""

		test = @__initTest(columnData, editorBtn.getData(), tmpData)

		applyButton = new CUI.Button
			text: $$("formula_columns_plugin.schema.applybtn")
			primary: true
			onClick: () =>
				editorBtn.getData().script = tmpData.script
				for k in ["debug", "disabled"]
					if CUI.util.isEmpty(tmpData.script)
						editorBtn.getForm().getFieldsByName(k)[0].disable()
					else
						editorBtn.getForm().getFieldsByName(k)[0].enable()
				CUI.Events.trigger
					node: editorBtn
					type: "data-changed"
				modal.destroy()

		cancelButton = new CUI.Button
			text: $$("formula_columns_plugin.schema.cancelbtn")
			onClick: () =>
				modal.destroy()

		outputPane = @__renderOutputPane(test)

		test.layout = new CUI.HorizontalLayout
			class: "formula-column-layout"
			left:
				class: "formula-column-docs"
				content: @__renderDocsPane(test)
				flexHandle:
					label:
						text: $$("formula_columns_plugin.editor.docs.title", null, null, "Documentation")
						icon: "right"
					state_name: "formula-columns-docs"
					closable: true
					hidden: false
			center:
				class: "formula-column-center"
				content: @__renderCenterPane(test, applyButton)
			right:
				class: "formula-column-output"
				content: outputPane
				flexHandle:
					state_name: "formula-columns-output"
					hidden: false

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
				content: test.layout

		# Capture phase, so the shortcut also works while Ace has the focus.
		modal.DOM.addEventListener("keydown", (ev) =>
			return if ev.key != "Enter" or not (ev.metaKey or ev.ctrlKey)
			ev.preventDefault()
			ev.stopPropagation()
			@__runTest(test)
		, true)

		@__errorMessage.hide()
		modal.show()

	__renderDocsPane: (test) ->
		return new CUI.SimplePane
			class: "formula-column-docs-pane"
			header_left: new CUI.Label(text: $$("formula_columns_plugin.editor.docs.title", null, null, "Documentation"))
			header_right: new CUI.Button
				icon: "left"
				appearance: "flat"
				tooltip: text: $$("formula_columns_plugin.editor.docs.close", null, null, "Hide documentation")
				onClick: =>
					test.layout.getFlexHandle("left").close()
			content: new CUI.Label
				class: "formula-column-docs-text"
				text: @__returnHelp() + "\n\n" + $$("formula_columns_plugin.editor.infotext")
				multiline: true
				centered: false
				markdown: true

	# The formula returns the value of its own column, not an object of fields.
	__returnHelp: ->
		$$("formula_columns_plugin.editor.return_help", null, null, """
			## What the formula returns

			The formula computes the value of **this column only**. Whatever you `return` is stored in the column, so return it in the format of the column type:

			| Column type | Return |
			| --- | --- |
			| Text | `"Some text"` |
			| Multilingual text | `{"de-DE": "Text", "en-US": "Text"}` |
			| Integer / decimal | `42` / `3.5` |
			| Boolean | `true` |
			| Date | `{"value": "2026-09-24"}` |

			Returning an object like `{field: value}` does **not** fill other fields. To compute another field, give that field its own formula. Returning nothing empties the column.

			Read the other fields of the record from `objNew`:

			```javascript
			return objNew.first_name + " " + objNew.last_name;
			```
		""")

	# Center: the code or the record the formula is tested with. Right: what the
	# formula returned or the record it leaves behind. Opening the test switches
	# the right side to the record, going back to the code switches it back.
	__renderCenterPane: (test, applyButton) ->
		test.codeDOM = CUI.dom.div("formula-column-code")
		CUI.dom.append(test.codeDOM, @renderEditorTab(test, applyButton).DOM)

		test.testDOM = CUI.dom.div("formula-column-test")
		test.testButtons = null
		test.centerButtonsDOM = CUI.dom.div("formula-column-center-buttons")

		return new CUI.Tabs
			class: "formula-column-tabs"
			maximize: true
			padded: false
			header_right: test.centerButtonsDOM
			tabs: [
				name: "editor"
				text: $$("formula_columns_plugin.editor.tab.editor", null, null, "Editor")
				content: test.codeDOM
				onActivate: =>
					@__showCenter(test, "editor")
			,
				name: "test"
				text: $$("formula_columns_plugin.editor.tab.test", null, null, "Test")
				content: test.testDOM
				onActivate: =>
					@__showCenter(test, "test")
			]

	__renderOutputPane: (test) ->
		test.runButton = new CUI.Button
			text: $$("formula_columns_plugin.test.run.button", null, null, "Run formula")
			icon: "play"
			primary: true
			tooltip: text: if /Mac/.test(navigator.platform) then "⌘ + Enter" else "Ctrl + Enter"
			onClick: =>
				@__runTest(test)

		@__showTestMessage(test, $$("formula_columns_plugin.test.hint", null, null,
			"Pick a record, change the values you want to try, then run the formula."))

		test.outputTabs = new CUI.Tabs
			class: "formula-column-tabs"
			maximize: true
			padded: false
			header_right: test.runButton
			tabs: [
				name: "result"
				text: $$("formula_columns_plugin.test.result.title", null, null, "Formula output")
				content: test.resultDOM
			,
				name: "detail"
				text: $$("formula_columns_plugin.test.detail.title", null, null, "Resulting record")
				content: test.detailDOM
			]
		return test.outputTabs

	__showCenter: (test, name) ->
		test.center = name
		if name == "test" and not test.testRendered
			test.testRendered = true
			@__renderTestTab(test)
		if name == "test"
			CUI.dom.showElement(test.centerButtonsDOM)
		else
			CUI.dom.hideElement(test.centerButtonsDOM)
		test.outputTabs.activate(if name == "test" then "detail" else "result")
		return

	renderEditorTab: (test, applyButton) ->
		@__errorMessage = new LocaLabel
			class: "ez5-editor-required-message"
			loca_key: "editor.required_input_message"
			group: "required"
		requiredWrapper = CUI.dom.div("ez5-required-message")
		CUI.dom.append(requiredWrapper, @__errorMessage)

		return new CUI.VerticalList
			class: "editor-wrapper"
			maximize: true
			content: [
				new CUI.Label
					text:"`async function (objNew, objCurr, dataPath, dataPathCurr) {`"
					markdown: true
			,
				@renderEditor(test.tmpData, applyButton)
			,
				new CUI.Label
					text:"`}`"
					markdown: true
			,
				requiredWrapper
			]

	renderEditor: (tmpData, applyButton) ->
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
				error = @__syntaxError(tmpData.script)
				if error
					@__errorMessage.show()
					@__errorMessage.setText(error.message)
					applyButton.disable()
				else
					@__errorMessage.hide()
					applyButton.enable()
		editorForm.start()
		@__trustEngineSyntax(editorForm, tmpData)
		return editorForm

	__syntaxError: (script) ->
		try
			eval("async function test(){" + script + "}")
			return null
		catch e
			return e

	# Ace lints with a jshint that stops at ES2020 and flags valid code such as
	# 1_000_000. The browser's parser decides: if it accepts the script, Ace's
	# syntax errors are dropped, otherwise they stay to point at the line.
	__trustEngineSyntax: (editorForm, tmpData) ->
		session = editorForm.DOM.querySelector(".ace_editor")?.env?.editor?.getSession()
		return if not session

		# jshint also warns when it gives up parsing, that one is just as wrong
		isSyntax = (a) => a.type == "error" or /^Unrecoverable syntax error/.test(a.text)

		session.on "changeAnnotation", =>
			annotations = session.getAnnotations()
			return if not annotations.some(isSyntax)
			return if @__syntaxError(tmpData.script)
			session.setAnnotations(annotations.filter((a) => not isSyntax(a)))
		return

	# The test runs the formula server side against a real record. Everything it
	# needs is kept per modal so two columns never share a selected record.
	#
	# Two schema versions are in play: the server looks the column up in the one
	# the datamodel editor is on, so a column that is saved but not committed is
	# still found in its real place, while masks and records here always come
	# from CURRENT — mask instances only exist for the committed schema.
	__initTest: (columnData, settings, tmpData) ->
		version = if ez5.admin.version == "HEAD" then "HEAD" else "CURRENT"
		tableId = @__findTableId(columnData, version)
		objecttypeTable = @__findObjecttypeTable(tableId, version)
		test =
			column: columnData?.name
			settings: settings
			tmpData: tmpData
			version: version
			tableId: tableId
			objecttypeTable: objecttypeTable
			uiTable: objecttypeTable and ez5.schema.CURRENT?._table_by_name?[objecttypeTable.name]
			columnInCurrent: !!ez5.schema.CURRENT?._table_by_id?[tableId]?._column_by_name?[columnData?.name]
			maskName: "_all_fields"
			center: "code"
			object: null
			resultObject: null
			recordDOM: CUI.dom.div("formula-column-test-record-body")
			detailDOM: CUI.dom.div("formula-column-test-detail-body")
			resultDOM: CUI.dom.div("formula-column-test-result-body")
		test.nested = tableId and objecttypeTable and tableId != objecttypeTable.table_id
		return test

	# The column options form only knows the column, so the objecttype is looked
	# up over the column id. A column which was just added has no id yet: fall
	# back to any sibling so at least the record picker works.
	__findTableId: (columnData, version) ->
		schema = ez5.schema[version]
		return null if not schema

		findByColumnId = (columnId) ->
			return null if not columnId
			for table in schema.tables
				if table._column_by_id?[columnId]
					return table.table_id
			return null

		tableId = findByColumnId(columnData?.column?.column_id)
		return tableId if tableId

		for sibling in columnData?._node?.getRoot()?.children or []
			tableId = findByColumnId(sibling.data?.column?.column_id)
			return tableId if tableId

		return null

	# Records are searched and rendered for the top level objecttype, which for a
	# nested column is the owner further up.
	__findObjecttypeTable: (tableId, version) ->
		table = ez5.schema[version]?._table_by_id?[tableId]
		while table?.owned_by
			table = ez5.schema[version]._table_by_id[table.owned_by.other_table_id]
		return table

	__renderTestButtons: (test) ->
		buttons = []

		# An objecttype without records has nothing to pick, demo data is all we can offer.
		if ez5.objecttypes.getObjecttypes().some((el) => el.objecttype._id == test.uiTable.table_id)
			selectButton = new CUI.Button
				text: $$("formula_columns_plugin.test.select_record.button", null, null, "Select record")
				onClick: =>
					@__openRecordSelector(test, selectButton)
			buttons.push(selectButton)

		buttons.push(new CUI.Button
			text: $$("formula_columns_plugin.test.demo_record.button", null, null, "Demo record")
			onClick: =>
				test.object = null
				@__renderRecordPane(test)
		)

		maskSelector = @__renderMaskSelector(test)
		buttons.push(maskSelector) if maskSelector

		return new CUI.Buttonbar(buttons: buttons)

	# The editor and the detail view differ per mask, so the mask is picked here.
	# It only decides what is shown: the object handed to the formula always comes
	# from the all fields mask, which is what db_pre_save serialises.
	__renderMaskSelector: (test) ->
		masks = [@__allFieldsMask(test)]
		for mask in ez5.mask.CURRENT._masks_by_table_id?[test.uiTable.table_id] or []
			instance = ez5.mask.CURRENT._mask_instance_by_name[mask.name]
			masks.push(instance) if instance

		return null if masks.length < 2

		selector = new MaskFieldSelectorDetail
			mask_name: test.maskName
			masks: masks
			show_all_fields_mask: true
			onChanged: (oldMask, newMask) =>
				test.maskName = newMask
				@__renderRecordPane(test)
				return CUI.resolvedPromise()

		return selector.getSelect().start()

	__selectedMask: (test) ->
		if test.maskName == "_all_fields"
			return @__allFieldsMask(test)
		return ez5.mask.CURRENT._mask_instance_by_name[test.maskName] or @__allFieldsMask(test)

	__openRecordSelector: (test, button) ->
		collection = new CollectionMemory
			preventBlurOnSelect: true

		new SearchPopover(
			link_mask: @__allFieldsMask(test)
			popover_element: button
			collection: collection
			request_format: "long"
			localOnly: true
			onDone: =>
				object = collection.getObjects()?[0]?.getObject()
				return if not object
				test.object = object
				@__renderRecordPane(test)
		).openPopover()

	__allFieldsMask: (test) ->
		Mask.getMaskByMaskName("_all_fields", test.uiTable.table_id)

	__renderTestTab: (test) ->
		CUI.dom.empty(test.testDOM)

		if not test.uiTable
			CUI.dom.append(test.testDOM, @__renderMessage($$("formula_columns_plugin.test.no_objecttype", null, null,
				"Save the data model once so that the formula can be tested against a record of this objecttype.")).DOM)
			return

		test.testButtons = @__renderTestButtons(test)
		CUI.dom.append(test.centerButtonsDOM, test.testButtons.DOM)
		CUI.dom.append(test.testDOM, test.recordDOM)
		@__renderRecordPane(test)

	__renderRecordPane: (test) ->
		CUI.dom.empty(test.recordDOM)
		CUI.dom.empty(test.detailDOM)
		@__showTestMessage(test, $$("formula_columns_plugin.test.hint", null, null,
			"Pick a record, change the values you want to try, then run the formula."))

		ro = @__newResultObject(test)

		if test.object
			# The mask is built in the frontend, so the standard from the server
			# does not match it and has to be regenerated (same as the MaskEditor).
			object = CUI.util.copyObject(test.object, true)
			object._standard = ro.getStandardData(object)
			ro.data = object

		ro.getData()._example_object = true
		test.resultObject = ro

		editor = CUI.dom.div("formula-column-test-editor")
		CUI.dom.append(editor, @__selectedMask(test).copy()
			.renderEditor(ro.getData(), "editor", "editor-header", skip_columnfilter: true))

		CUI.dom.append(test.recordDOM, @__renderRecordHeader(test).DOM)
		CUI.dom.append(test.recordDOM, editor)
		return

	__renderRecordHeader: (test) ->
		name = test.uiTable.name
		if test.object
			id = test.object[name]?._id
			text = "#{name} · " +
				$$("formula_columns_plugin.test.record.real", null, null, "record") + " #{id}"
		else
			text = "#{name} · " +
				$$("formula_columns_plugin.test.record.demo", null, null, "generated demo record")

		return new CUI.Label
			class: "formula-column-test-title"
			text: text

	__newResultObject: (test) ->
		new ResultObjectDemo
			mask: @__allFieldsMask(test)
			version: "CURRENT"
			format: "long"

	# The detail view of the object as the formula left it: a formula may touch
	# more than the column it belongs to, and that is invisible in the raw output.
	__renderDetail: (test, objNew) ->
		CUI.dom.empty(test.detailDOM)
		return if not objNew

		try
			data = CUI.util.copyObject(test.resultObject.getData(), true)
			data[test.uiTable.name] = objNew
			delete(data._example_object)
			data._standard = @__newResultObject(test).getStandardData(data)

			CUI.dom.append(test.detailDOM, @__selectedMask(test)
				.renderDetail(data, "detail", "detail-header", skip_columnfilter: true))
		catch e
			CUI.dom.append(test.detailDOM, @__renderMessage("```\n#{e.message or e}\n```", "error").DOM)
		return

	__runTest: (test) ->
		# Without an opened test there is no record yet, the demo one is used.
		if not test.testRendered
			test.testRendered = true
			@__renderTestTab(test)

		if not test.resultObject
			@__showTestMessage(test, $$("formula_columns_plugin.test.no_objecttype", null, null,
				"Save the data model once so that the formula can be tested against a record of this objecttype."), "warning")
			return

		CUI.dom.empty(test.detailDOM)

		if CUI.util.isEmpty(test.tmpData.script)
			@__showTestMessage(test, $$("formula_columns_plugin.test.no_script", null, null,
				"Write a formula in the editor tab first."), "warning")
			return

		try
			object = test.resultObject.getSaveData()
		catch e
			@__showTestMessage(test, "```\n#{e.message or e}\n```", "error")
			return

		@__mergeSystemFields(object, test.object)

		test.runButton.startSpinner()
		# Not a relative url: cross-server it would hit the frontend's own server.
		ez5.server
			api: "/plugin/extension/formula-columns/test"
			type: "POST"
			handle_error: => true
			json_data:
				objecttype: object._objecttype
				table_id: test.tableId
				column: test.column
				version: test.version
				script: test.tmpData.script
				run_as_plugin_user: !!test.settings?.run_as_plugin_user
				object: object
				current: test.object
		.done (response) =>
			@__renderTestResult(test, response)
			@__renderDetail(test, response?.obj_new)
		.fail (xhr, statusText) =>
			body = xhr?.response
			body = JSON.stringify(body, null, 2) if not CUI.util.isString(body)
			@__showTestMessage(test, "**#{xhr?.status} #{statusText or ""}**\n\n```\n#{body}\n```", "error")
		.always =>
			test.runButton.stopSpinner()

	# getSaveData drops _id, _version and the other system fields, but db_pre_save
	# sees them, so they are taken back from the record that was loaded.
	__mergeSystemFields: (object, source) ->
		return if not source

		skip = ["_standard", "_path", "_versions", "_generated_rights"]
		merge = (target, from) ->
			for key, value of from
				continue if not key.startsWith("_") or key in skip
				continue if target.hasOwnProperty(key)
				target[key] = value
			return

		merge(object, source)
		if source[object._objecttype]
			merge(object[object._objecttype], source[object._objecttype])
		return

	__showTestMessage: (test, text, type = null) ->
		CUI.dom.empty(test.resultDOM)
		CUI.dom.append(test.resultDOM, @__renderMessage(text, type).DOM)

	__renderMessage: (text, type = null) ->
		cls = "formula-column-test-message"
		cls += " formula-column-test-message--#{type}" if type
		return new CUI.Label
			class: cls
			multiline: true
			markdown: true
			text: text

	__renderTestResult: (test, response) ->
		if response?.error
			@__showTestMessage(test, "**#{response.error.code}**\n\n```\n#{response.error.message}\n```", "error")
			return

		content = []

		if response.unknown_column
			text = $$("formula_columns_plugin.test.unknown_column", null, null,
				"This column is not part of the saved data model yet, so the formula was run once against the record without writing the result into a column. Save the data model to test it in its real place.")
			if test.nested
				text += "\n\n" + $$("formula_columns_plugin.test.unknown_column.nested", null, null,
					"It belongs to a nested table, so it ran against the top level record instead of once per nested row.")
			content.push(@__renderMessage(text, "warning"))
		else if not test.columnInCurrent
			content.push(@__renderMessage($$("formula_columns_plugin.test.not_committed", null, null,
				"This column is not committed yet, so the resulting record next to this cannot show it. The value below is what it would get."), "warning"))

		for result in response.results or []
			content.push(@__renderSingleResult(result))

		if response.log?.length
			content.push(@__renderBlock(
				$$("formula_columns_plugin.test.log.title", null, null, "log"),
				"```json\n#{JSON.stringify(response.log, null, 2)}\n```"))

		CUI.dom.empty(test.resultDOM)
		for item in content
			CUI.dom.append(test.resultDOM, item.DOM)

	__renderSingleResult: (result) ->
		content = []

		if result.path
			content.push(new CUI.Label
				class: "formula-column-test-path"
				markdown: true
				text: "`#{result.path}`")

		if result.error
			content.push(@__renderBlock(
				$$("formula_columns_plugin.test.error.title", null, null, "Error"),
				"```\n#{result.error.message}\n```",
				"error"))
		else if result.value_undefined
			content.push(@__renderBlock(
				$$("formula_columns_plugin.test.value.title", null, null, "Value"),
				$$("formula_columns_plugin.test.value.undefined", null, null,
					"The formula returned nothing, the column would be emptied."),
				"warning"))
		else
			content.push(@__renderBlock(
				"#{$$("formula_columns_plugin.test.value.title", null, null, "Value")} · #{result.value_type}",
				"```json\n#{JSON.stringify(result.value, null, 2)}\n```",
				"success"))

		if result.console?.length
			content.push(@__renderBlock(
				$$("formula_columns_plugin.test.console.title", null, null, "Console"),
				"```\n#{result.console.join("\n")}\n```"))

		content.push(new CUI.Label
			class: "formula-column-test-duration"
			text: "#{result.duration_ms} ms")

		return new CUI.VerticalList
			class: "formula-column-test-single-result"
			content: content

	__renderBlock: (title, text, type = "") ->
		return new CUI.VerticalList
			class: "formula-column-test-block formula-column-test-block--#{type}"
			content: [
				new CUI.Label
					class: "formula-column-test-block-title"
					text: title
			,
				new CUI.Label
					multiline: true
					markdown: true
					text: text
			]

Schema.registerPlugin(new CustomDatamodelSettings())
