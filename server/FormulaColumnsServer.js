const fs = require("fs")
const lib = require('../lib/js/lib.js')
const info = JSON.parse(process.argv[2])
let access_token
process.stdin.setEncoding('utf8');


// Polyfill the console.info to work as console.error
// console.error are output in the server logs and can be read by users
// console.log cant be used for this because it is read by the parent process as the result output
// and its not semantically correct to use console.error for normal output in the custom user code
console.info = console.error

console.info("welcome to formula fields2")


// Shared with the "test" extension so both run the formula against the same helpers.
lib.installApiSearchBySIDs(info, () => access_token)

const VALIDATION_ERROR_CODE = "validation.plugin.error"

// feFieldName turns the internal name of a nested column into the name the
// editor uses in a validation error path: "_nested:<objecttype>__<name>", and
// one level deeper the parent name is repeated in it.
function feFieldName(colName, objecttype, parentName) {
	if (!colName.startsWith("_nested:")) {
		return colName
	}
	let name = colName.substring("_nested:".length + objecttype.length + 2)
	if (parentName && name.startsWith(parentName + "__")) {
		name = name.substring(parentName.length + 2)
	}
	return name
}

// newProblems tracks where in the object the walk currently is, so a failing
// formula can be reported with the path the editor needs to mark the field red.
// See server/validation_errors in fylr-plugin-example for the path rules.
function newProblems(objecttype) {
	return {
		list: [],
		seen: new Set(),
		objecttype: objecttype,
		path: objecttype,
		parent: null,
		ancestors: [],

		// dive returns the tracker for one row of a nested or reverse nested field
		dive: function (col, idx) {
			const sub = Object.create(this)
			if (col.kind == "reverse_link") {
				// "_reverse_nested:<objecttype>:<field>" restarts the path at the other objecttype
				const parts = col.name.split(":")
				sub.objecttype = parts[1]
				sub.parent = parts[2]
				sub.path = `${parts[1]}.${parts[2]}`
			} else {
				sub.parent = feFieldName(col.name, this.objecttype, this.parent)
				sub.path = `${this.path}.${sub.parent}`
			}
			sub.ancestors = this.ancestors.concat(`${sub.path}[]`)
			sub.path += `[${idx}]`
			return sub
		},

		add: function (col, err) {
			const field = `${this.path}.${col.name}`
			this.push(field, `Formula column **${field}** failed: ${err}`)
			// Mark the nested fields on the way down too, the failing row may be collapsed
			for (const ancestor of this.ancestors) {
				this.push(ancestor, `A formula column inside **${ancestor}** failed`)
			}
		},

		push: function (field, message) {
			if (this.seen.has(field)) {
				return
			}
			this.seen.add(field)
			this.list.push({ "field": field, "message": message })
		},
	}
}

// updateObj updates the given object obj, using the
// provided mask.
async function updateObj(mask, objNew, objCurr, dataPath, dataPathCurr, log, problems) {
	let changed = false
	let dataPath2 = dataPath.slice(0)
	dataPath2.push(objNew)
	let dataPathCurr2 = dataPathCurr.slice(0)
	dataPathCurr2.push(objCurr)
	for (const colI in mask._columns) {
		let col = mask._columns[colI]
		let settings = col.custom_settings["formula-columns"]
		if (settings?.disabled) {
			continue
		}
		if (settings?.script) {
			let runScript = "async function(objNew, objCurr, dataPath, dataPathCurr) {" + settings.script + ";}"
			let logEntry = {
				mask: mask,
				objNew: objNew,
				objCurr: objCurr,
				dataPath: dataPath,
				dataPathCurr: dataPathCurr,
				column: col,
				eval: runScript,
			}
			try {
				if (!settings.func) {
					if (settings.run_as_plugin_user && info.plugin_user_access_token) {
						access_token = info.plugin_user_access_token
					} else {
						access_token = info.api_user_access_token
					}
					eval("settings.func = "+runScript)
				}
				objNew[col.name] = await settings.func(objNew, objCurr, dataPath, dataPathCurr)
				if (settings.debug) {
					logEntry.value = objNew[col.name]
					log.push(logEntry)
				}
			} catch (e) {
				logEntry.error = "error:"+e
				console.info(logEntry.error)
				log.push(logEntry)
				problems.add(col, e)
			}
			changed = true
			// await lib.sendDV(JSON.stringify({"col": col}))
		}
		if (col.kind == "link" || col.kind == "reverse_link") {
			let nested = objNew[col.name]
			// await lib.sendDV(JSON.stringify({ "col": col, "objNew": objNew, "nested": nested, "len": nested?.length }))
			if (nested?.length) {
				let nestedCurr
				if (objCurr) {
					nestedCurr = objCurr[col.name]
				}
				for (let i = 0; i < nested.length; i++) {
					let nestedCurrI
					if (nestedCurr) {
						nestedCurrI = nestedCurr[i]
					}
					let subMask
					if (col.is_hierarchical) {
						subMask = mask
					} else {
						subMask = col._mask
					}
					if (await updateObj(subMask, nested[i], nestedCurrI, dataPath2, dataPathCurr2, log, problems.dive(col, i))) {
						changed = true
					}
				}
			}
		}
	}
	return changed
}

// storeLog sends the collected log entries to the api as an event
async function storeLog(log) {
	if (log.length == 0) {
		return
	}
	let evType = "FORMULA_COLUMNS_DEBUG"
	for (var i = 0; i < log.length; i++) {
		if (log[i].error) {
			evType = "FORMULA_COLUMNS_ERROR"
			break
		}
	}
	await lib.storeEvent(info, {
		"event": {
			"type": evType,
			"info": {
				"log": log
			}
		}
	}).then((data) => {
		console.error(data);
	})
}

Promise.all([lib.getSchema(info), lib.getStdin()]).then(
	async (data) => {
		let schema = data[0]
		let objects = data[1].objects
		let objsChanged = []
		let log = []
		let problems = []
		for (var i = 0; i < objects.length; i++) {
			let obj = objects[i]
			let current = obj._current
			let currObj = null
			if (current) {
				currObj = current[obj._objecttype]
			}
			let objProblems = newProblems(obj._objecttype)
			// the editor expects one list of problems per object, in the same order
			problems.push(objProblems.list)
			// dataPath starts with top level, we already add it here
			if (await updateObj(schema[obj._objecttype], obj[obj._objecttype], currObj, [obj], [current], log, objProblems)) {
				objsChanged.push(obj)
			}
		}

		// A failing formula stores a value nobody asked for, so the save is
		// rejected and the editor shows the problem on the field itself.
		if (problems.some((p) => p.length > 0)) {
			console.log(JSON.stringify({
				"code": VALIDATION_ERROR_CODE,
				"error": "A formula column failed, see the editor for details",
				"statuscode": 400,
				"parameters": {
					"problems": problems
				}
			}))
			await storeLog(log)
			process.exit(400)
		}

		// return changed objects
		console.log(JSON.stringify({ "objects": objsChanged }))
		await storeLog(log)
	}
).catch((e) => {
	console.error(e)
	// Without this the editor only shows that "the plugin caused an error"
	console.log(JSON.stringify({
		"code": VALIDATION_ERROR_CODE,
		"error": "The formula columns plugin failed",
		"statuscode": 400,
		"parameters": {
			"problems": [[{ "message": `The formula columns plugin failed: ${e}` }]]
		}
	}))
	process.exit(400)
})
