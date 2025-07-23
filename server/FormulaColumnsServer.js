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


// Helper function to search for objects by SID.
// This function is added to the global scope so that it can be used
// in the custom user code (inside the eval).
global.apiSearchBySIDs = async function(sids, mode) {
    if (!mode) {
		mode = "full";
	}

	if (!Array.isArray(sids)) {
        sids = [sids];
    }

    const url = `${info.api_url}/api/v1/search`;

    const requestBody = {
        limit: 1000,
        search: [{
                type: "in",
                in: sids,
                fields: ["_system_object_id"],
        	}]
        ,
        format: mode
    };

    const response = await fetch(url, {
        method: "POST",
        headers: {
            'Content-Type': 'application/json',
            'authorization': `Bearer ${access_token}`
        },
        body: JSON.stringify(requestBody)
    });

    if (!response.ok) {
        throw new Error(`Error fetching objects by SID: ${response.statusText}`);
    }
	const responseJson = await response.json();
	// console.info("responseJson", responseJson);
	return responseJson.objects;
};

// updateObj updates the given object obj, using the
// provided mask.
async function updateObj(mask, objNew, objCurr, dataPath, dataPathCurr, log) {
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
					if (await updateObj(subMask, nested[i], nestedCurrI, dataPath2, dataPathCurr2, log)) {
						changed = true
					}
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
		let log = []
		for (var i = 0; i < objects.length; i++) {
			let obj = objects[i]
			let current = obj._current
			let currObj = null
			if (current) {
				currObj = current[obj._objecttype]
			}
			// dataPath starts with top level, we already add it here
			if (await updateObj(schema[obj._objecttype], obj[obj._objecttype], currObj, [obj], [current], log)) {
				objsChanged.push(obj)
			}
		}
		// return changed objects
		console.log(JSON.stringify({ "objects": objsChanged }))

		// send event to api, if log entries exist
		if (log.length > 0) {
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
	}
).catch((e) => {
	console.error(e)
	process.exit(1)
})
