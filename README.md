# fylr-formula-columns-plugin

Store computed values in most column types using a small Javascript snippet. The
snippet runs on the server whenever an object is saved, and its return value becomes
the value of the column.

## Installation

The latest plugin can be downloaded from [Github](https://github.com/programmfabrik/fylr-plugin-formula-columns/releases/latest/download/fylr-plugin-formula-columns.zip).
Release notes are [here](https://github.com/programmfabrik/fylr-plugin-formula-columns/releases).

## Setting a formula

After the plugin is enabled, "Data model > Object type > Columns > Options" shows a
"Formula Code" block:

| Option | Meaning |
| --- | --- |
| Javascript | opens the code editor, see [Writing a formula](#writing-a-formula) |
| Debug | store a `FORMULA_COLUMNS_DEBUG` event with the log of every run |
| Disabled | keep the formula but stop running it |
| Run as a user plugin | run with the plugin user from the base config instead of the calling user |

The formula runs during the `db_pre_save` callback phase of `/api/db`, before objects
are written. If it throws, a `FORMULA_COLUMNS_ERROR` event is stored.

## Writing a formula

The snippet is the body of a function. It runs inside an asynchronous function, so
`async` and `await` are available:

```javascript
async function (objNew, objCurr, dataPath, dataPathCurr) {
    ... snippet as defined in the web frontend ...
}
```

It is executed with `eval`, wrapped in a `try..catch`.

### Arguments

* `objNew`: the new data of the object being saved — the record for top level
  objects, the nested record for nested ones.
* `objCurr`: the same data as currently found in the database, so the old version.
* `dataPath`: during the recursive crawl of the data this is extended for each
  iteration. It holds the path to the data starting from the top level.
* `dataPathCurr`: the same as `dataPath`, for the current object data.

> A known limitation is that the callback for a nested record does not know which
> record idx it is currently in.

### Scoped variables

* `log`: push messages here and they are stored in system events.
* `info`: instance information such as the api token and url, useful for api calls.
  Inspect it with `log.push({"info": info})`.

### `async apiSearchBySIDs(sids, mode)`

Finds objects by their `system_global_id`. Takes a single `sid` or an array, and a
format: `long`, `short`, `long_inheritance`, `full` or `standard` (the default).
Returns the objects found, or an empty array.

Fetching a linked object and returning one of its fields:

```javascript
if (!objNew.linked) {
    return "No linked object provided.";
}

const linkedObjectData = await apiSearchBySIDs(objNew.linked._system_object_id);
if (!linkedObjectData || linkedObjectData.length === 0) {
    return "Empty Linked Object...";
}

const linkedObjectType = linkedObjectData[0]._objecttype;
return linkedObjectData[0][linkedObjectType].category;
```

`fetch` is available too, so an external API works the same way. Note that a Promise
is not accepted as the value of the column — await it:

```javascript
async function fetchTodoTitle() {
    console.info("Start fetching external data...");
    const response = await fetch('https://jsonplaceholder.typicode.com/todos/1');
    if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
    }
    const data = await response.json();
    return `Todo Title: ${data.title}`;
}

return await fetchTodoTitle();
```

## Testing a formula

The code editor has a "Test" tab which runs the formula you are writing against a
real record — without saving anything and without committing the schema.

Pick a record with "Select record" (or keep the generated demo record), change any
value you want to try in the editor on the left, then press "Run formula". The tab
shows three columns:

* **the record**, the input the formula gets, editable;
* **the resulting record**, the detail view of the object as the formula left it — a
  formula may write to fields other than its own column, and that is invisible in the
  raw value;
* **the formula output**, the value the column would get and its type, everything the
  formula printed with `console.info` / `console.log`, whatever it pushed into `log`,
  the run time, and the exception with its stack if it threw.

The mask selector next to the buttons switches which mask the record and the result
are rendered with, since the editor differs per mask. It only changes what is shown:
the object handed to the formula is always the complete record, because that is what
fylr serialises for `db_pre_save` whatever mask the object was saved with.

For a column of a nested table the formula runs once per nested row, and every result
is listed with its path (`_nested:objecttype__nested[0]`).

The test runs on the server, in the same node process, through the same object walk
and with the same helpers as the real `db_pre_save` callback, so `apiSearchBySIDs`,
`info`, `fetch` and "Run as a user plugin" behave as they will in production.

### Columns which are not committed

The column is looked up in the schema version the datamodel editor is on, so a column
that is **saved but not yet committed** is found in its real place and the formula
runs for it normally. The resulting record next to it is rendered from the committed
schema, so it cannot show that column yet; the output panel says so.

A column that has not even been saved is in no schema at all. The formula is then run
once against the record and the returned value is shown, but nothing is written into
a column — again the output panel says so.

### POST /api/v1/plugin/extension/formula-columns/test

The test tab posts to this endpoint. It requires the system right `system.datamodel`
(or `system.root`) — running arbitrary Javascript on the server is exactly what
committing a formula does, so the same people may do it here. Nothing is written to
the database.

```json
{
    "objecttype": "object",
    "table_id": 42,
    "column": "computed",
    "version": "HEAD",
    "script": "return objNew.cola.toUpperCase()",
    "run_as_plugin_user": false,
    "object": { "_objecttype": "object", "object": { "_id": 1, "cola": "a" } },
    "current": { "_objecttype": "object", "object": { "_id": 1, "cola": "old" } }
}
```

`object` is the new data (`objNew`), `current` the data as stored (`objCurr`) and may
be omitted. `version` is `CURRENT` (the schema `db_pre_save` runs against) or `HEAD`,
and decides which schema the column is looked up in.

The response holds one entry in `results` per executed formula. `unknown_column` is
true when the column was in no mask and the formula was run once at top level
instead:

```json
{
    "results": [
        {
            "path": "",
            "value": "A",
            "value_type": "string",
            "value_undefined": false,
            "console": ["..."],
            "duration_ms": 3
        }
    ],
    "unknown_column": false,
    "version": "HEAD",
    "obj_new": { "_id": 1, "cola": "a", "computed": "A" },
    "log": [],
    "duration_ms": 3
}
```

Failures that prevent the formula from running at all come back as
`{"error": {"code": "forbidden|bad_request|error", "message": "..."}}`. A formula
that throws is not a failure of the request: its `results` entry carries `error`
instead of `value`.

## /api/schema

In /api/schema the custom setting looks like this:

```json
{
    "custom_setting": {
        "formula-columns": {
            "debug": false,
            "script": "... snippet ..."
        }
    }
}
```

## /api/db

The plugin works as a `db_pre_save` plugin and as such uses the `_all_fields` mask,
with all object data present, to calculate the fields. The callback receives the
current context of the data cell and writes the result back into the JSON response of
the plugin.

## Development

`make build` assembles the plugin into `build/<name>/`, `make zip` builds the release
zip, `make loca` pulls the localisation CSV from its Google Sheet. See
[fylr-build-plugin](https://github.com/programmfabrik/fylr-build-plugin).

When loading the built plugin from disk, point the fylr server's `plugin.paths` at
`build/`, never at the repo root — fylr walks the path for any `manifest.yml` and the
source manifest would collide with the built one.
