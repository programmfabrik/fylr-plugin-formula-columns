const fs = require("fs")
console.error("welcome to formula fields2")
const lib = require('../lib/js/lib.js')
const info = JSON.parse(process.argv[2])
process.stdin.setEncoding('utf8');

// updateObj updates the given object obj, using the
// provided mask.
function updateObj(mask, objNew, objCurr, dataPath, dataPathCurr) {
	let changed = false
	let dataPath2 = dataPath.slice(0)
	dataPath2.push(objNew)
	let dataPathCurr2 = dataPathCurr.slice(0)
	dataPathCurr2.push(objCurr)
	for (const colI in mask._columns) {
		let col = mask._columns[colI]
		if (col.custom_settings.script) {
			if (!col.custom_settings.func) {
				eval("col.custom_settings.func = function(objNew, objCurr, dataPath) {" + col.custom_settings.script + ";}")
			}
			objNew[col.name] = col.custom_settings.func(objNew, objCurr, dataPath, dataPathCurr)
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
					if (updateObj(subMask, nested[i], nestedCurrI, dataPath2, dataPathCurr2)) {
						changed = true
					}
				}
			}
		}
	}
	return changed
}

Promise.all([lib.getSchema(info), lib.getStdin()]).then(
	(data) => {
		let schema = data[0]
		let objects = data[1].objects
		let objsChanged = []
		for (var i = 0; i < objects.length; i++) {
			let obj = objects[i]
			let current = obj._current
			let currObj = null
			if (current) {
				currObj = current[obj._objecttype]
			}
			// dataPath starts with top level, we already add it here
			if (updateObj(schema[obj._objecttype], obj[obj._objecttype], currObj, [obj], [current])) {
				objsChanged.push(obj)
			}
		}
		// huhu2
		// await lib.sendDV(objsChanged)
		console.log(JSON.stringify({ "objects": objsChanged }))
	}
).catch((e) => {
	console.error(e)
	process.exit(1)
})
