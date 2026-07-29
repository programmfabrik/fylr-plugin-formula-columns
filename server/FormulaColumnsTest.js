// Runs a formula against a single object without saving anything, so the
// datamodel editor can preview the result before the schema is committed.
// Reachable as POST /api/v1/plugin/extension/formula-columns/test
const lib = require('../lib/js/lib.js')
const info = JSON.parse(process.argv[2])

process.stdin.setEncoding('utf8')

// Token used by apiSearchBySIDs, mirrors run_as_plugin_user of the real callback.
let access_token
lib.installApiSearchBySIDs(info, () => access_token)

const MAX_CONSOLE_LINES = 500
const MAX_LINE_LENGTH = 4000

// The formula runs on the caller's behalf, so only somebody who may edit the
// datamodel — and could therefore commit the same code as a real formula — is
// allowed to execute arbitrary Javascript here.
async function assertMayEditDatamodel() {
    let session
    try {
        session = await lib.reqURL(`${info.api_url}/api/v1/user/session?access_token=${info.api_user_access_token}`)
    } catch (e) {
        throw testError("forbidden", "Unable to verify the rights of the calling user")
    }
    // A root user's rights collapse to system.root alone, which fylr treats as
    // satisfying every check (acl.Require).
    const rights = session?.system_rights || {}
    if (!rights["system.datamodel"] && !rights["system.root"]) {
        throw testError("forbidden", "The system right \"system.datamodel\" is required to test a formula")
    }
}

function testError(code, message) {
    const err = new Error(message)
    err.code = code
    return err
}

// stringify tolerates the cycles and exotic values a formula may return.
function stringify(value) {
    const seen = new WeakSet()
    return JSON.stringify(value, (key, v) => {
        if (typeof v === "bigint") {
            return v.toString()
        }
        if (typeof v === "function") {
            return `[Function ${v.name || "anonymous"}]`
        }
        if (v !== null && typeof v === "object") {
            if (seen.has(v)) {
                return "[Circular]"
            }
            seen.add(v)
        }
        return v
    })
}

function formatArg(arg) {
    if (typeof arg === "string") {
        return arg
    }
    try {
        return stringify(arg)
    } catch (e) {
        return String(arg)
    }
}

// Everything the formula prints is collected instead of going to the fylr log,
// and console.log in particular must never reach stdout: that is the response.
async function runCapturing(collected, call) {
    const original = {}
    for (const method of ["log", "info", "warn", "debug", "error"]) {
        original[method] = console[method]
        console[method] = (...args) => {
            if (collected.length >= MAX_CONSOLE_LINES) {
                return
            }
            const line = args.map(formatArg).join(" ")
            collected.push(line.length > MAX_LINE_LENGTH ? line.slice(0, MAX_LINE_LENGTH) + "…" : line)
        }
    }
    try {
        return await call()
    } finally {
        Object.assign(console, original)
    }
}

// callFormula runs the formula once and records how it went. It never throws:
// a broken formula is a result to display, not a failed request.
async function callFormula(ctx, path, objNew, objCurr, dataPath, dataPathCurr) {
    const result = { path: path, console: [] }
    const started = Date.now()
    let raw
    let ok = false
    try {
        raw = await runCapturing(result.console, () => ctx.func(objNew, objCurr, dataPath, dataPathCurr))
        ok = true
        result.value = raw === undefined ? null : raw
        result.value_undefined = raw === undefined
        result.value_type = raw === null ? "null" : typeof raw
    } catch (e) {
        result.error = { message: String(e), stack: e?.stack }
    }
    result.duration_ms = Date.now() - started
    ctx.results.push(result)
    return { ok: ok, raw: raw }
}

// updateObj walks the object exactly like the db_pre_save callback does, but
// only the column under test runs, and with the script from the editor.
async function updateObj(mask, objNew, objCurr, dataPath, dataPathCurr, ctx, path) {
    const dataPath2 = dataPath.slice(0)
    dataPath2.push(objNew)
    const dataPathCurr2 = dataPathCurr.slice(0)
    dataPathCurr2.push(objCurr)

    for (const colI in mask._columns) {
        const col = mask._columns[colI]

        if (mask.table_id === ctx.table_id && col.name === ctx.column) {
            const called = await callFormula(ctx, path, objNew, objCurr, dataPath, dataPathCurr)
            if (called.ok) {
                objNew[col.name] = called.raw
            }
        }

        if (col.kind == "link" || col.kind == "reverse_link") {
            const nested = objNew[col.name]
            if (nested?.length) {
                const nestedCurr = objCurr ? objCurr[col.name] : null
                for (let i = 0; i < nested.length; i++) {
                    const subMask = col.is_hierarchical ? mask : col._mask
                    if (!subMask) {
                        continue
                    }
                    await updateObj(subMask, nested[i], nestedCurr?.[i], dataPath2, dataPathCurr2, ctx,
                        `${path ? path + "." : ""}${col.name}[${i}]`)
                }
            }
        }
    }
}

async function run(body) {
    const { objecttype, script } = body
    if (typeof script !== "string" || script.trim() === "") {
        throw testError("bad_request", "No formula to test")
    }
    if (typeof objecttype !== "string" || !body.object?.[objecttype]) {
        throw testError("bad_request", "The object to test against is missing or does not match the objecttype")
    }

    access_token = body.run_as_plugin_user && info.plugin_user_access_token
        ? info.plugin_user_access_token
        : info.api_user_access_token

    // HEAD lets the preview see columns that are saved but not committed yet.
    const version = body.version === "HEAD" ? "HEAD" : "CURRENT"
    const schema = await lib.getSchema(info, version)
    const mask = schema[objecttype]
    if (!mask) {
        throw testError("bad_request", `Unknown objecttype ${objecttype}`)
    }

    // log and info are the variables the formula sees, so they have to live in
    // the scope the eval runs in.
    const log = []
    let func
    eval("func = async function(objNew, objCurr, dataPath, dataPathCurr) {" + script + ";}")

    const object = body.object
    const current = body.current || null
    const ctx = {
        table_id: body.table_id,
        column: body.column,
        func: func,
        results: [],
    }

    const started = Date.now()
    await updateObj(mask, object[objecttype], current ? current[objecttype] : null, [object], [current], ctx, "")

    // A column which was never saved is in no mask at all, so the walk found
    // nothing. Run once at top level so a brand new formula can still be tried.
    let unknownColumn = false
    if (ctx.results.length === 0) {
        unknownColumn = true
        await callFormula(ctx, "", object[objecttype], current ? current[objecttype] : null, [object], [current])
    }

    return {
        results: ctx.results,
        unknown_column: unknownColumn,
        version: version,
        obj_new: object[objecttype],
        log: log,
        duration_ms: Date.now() - started,
    }
}

function respond(result) {
    try {
        process.stdout.write(stringify(result))
    } catch (e) {
        process.stdout.write(JSON.stringify({ error: { code: "response", message: String(e) } }))
    }
}

lib.getStdin()
    .then(async (body) => {
        await assertMayEditDatamodel()
        return run(body)
    })
    .then(respond)
    .catch((e) => {
        respond({ error: { code: e?.code || "error", message: e?.message || String(e) } })
    })
