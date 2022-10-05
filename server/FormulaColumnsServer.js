console.error("welcome to formula fields2")
const lib = require('../lib/js/lib.js')
const info = JSON.parse(process.argv[2])
process.stdin.setEncoding('utf8');

let schema = null // global to manage schema
let schemaPromise = lib.get(info.api_url+"/api/v1/schema/user/CURRENT?access_token="+info.api_user_access_token)

let stdinPromise = new Promise((resolve, reject) => {
	let input = ""
	process.stdin.on('data', (d) => {
		try {
			input += d.toString()
		} catch(e) {
			console.error("Could not read input into string: ${e.message}", e.stack)
			reject()
		}
	});
	process.stdin.on('end', () => {
		try {
			data = JSON.parse(input)
			delete(data.info)
			resolve(data)
		} catch (e) {
			console.error("Could not parse input: ${e.message}", e.stack)
			reject()
		}
	})
});

byTable = (tableName) => {
	for(var i=0; i < schema.tables.length; i++) {
		if (schema.tables[i].name === tableName) {
			return schema.tables[i]
		}
	}
	return null
}

Promise.all([schemaPromise, stdinPromise]).then(
	(data) => {
		schema = data[0]
		lib.sendDV(data)
		let objects = data[1].objects
		let changed = false
		let objsChanged = []
		for(var i=0; i < objects.length; i++) {
			let obj = objects[i]
			let tbl = byTable(obj._objecttype)
			// console.error("tbl", tbl)
			for (var j=0; j < tbl.columns.length; j++) {
				let col = tbl.columns[j]
				if (col.custom_settings.script) {
					obj[obj._objecttype][col.name] = eval("(function(objNew) {"+col.custom_settings.script+";})(obj)")
					// console.error("col", col.name, "script", col.custom_settings.script, val)
					changed = true
				}
			}
			if (changed) {
				objsChanged.push(obj)
			}
		}
		console.log(JSON.stringify({"objects": objsChanged}))
	}
).catch((e) =>  {
	process.exit(1)
})

