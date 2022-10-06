console.error("welcome to formula fields2")
const lib = require('../lib/js/lib.js')
const info = JSON.parse(process.argv[2])
process.stdin.setEncoding('utf8');

console.error("huu")

// updateObj updates the given object obj, using the
// provided mask.
function updateObj(mask, objNew, objCurr, dataPath) {
	let changed = false
	let dataPath2 = dataPath.slice(0)
	dataPath2.push(objNew)
	for (const colI in mask._columns) {
		let col = mask._columns[colI]
		if (col.custom_settings.script) {
			if (!col.custom_settings.func) {
				eval("col.custom_settings.func = function(objNew, objCurr, dataPath) {" + col.custom_settings.script + ";}")
			}
			objNew[col.name] = col.custom_settings.func(objNew, objCurr, dataPath)
			changed = true
		}
		if (col.kind == "link") {
			let nested = objNew[col.name]
			let nestedCurr
			if (objCurr) {
				nestedCurr = objCurr[col.name]
			}
			for (let i=0; i < nested.length; i++) {
				let nestedCurrI
				if (nestedCurr) {
					nestedCurrI = nestedCurr[i]
				}
				if (updateObj(col._mask, nested[i], nestedCurrI, dataPath2)) {
					changed = true
				}
			}
		}
	}
	return changed
}

Promise.all([lib.getSchema(info), lib.getStdin()]).then(
	async (data) => {
		let schema = data[0]
		let objects = data[1].objects
		let objsChanged = []
		// await lib.sendDV(objects)
		for (var i = 0; i < objects.length; i++) {
			let obj = objects[i]
			let current = obj._current
			let currObj = null
			if (current) {
				currObj = current[obj._objecttype]
			}
			if (updateObj(schema[obj._objecttype], obj[obj._objecttype], currObj, [obj])) {
				objsChanged.push(obj)
			}
		}
		// await lib.sendDV(objsChanged)
		console.log(JSON.stringify({ "objects": objsChanged }))
	}
).catch((e) => {
	console.error(e)
	process.exit(1)
})
