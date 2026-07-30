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

## When a formula fails

A formula that throws **rejects the save** and the error is reported as a validation
error on the field itself: the editor marks the column red and shows the message
next to it, exactly like a failed input check.

```
Formula column **artwork.inventory_number** failed: TypeError: Cannot read properties of undefined (reading 'name')
```

The field path tells you the objecttype and the column, so with ten formula columns
on an objecttype you no longer have to guess which one broke. For a column in a
nested table the failing row is named (`artwork.images[2].caption`) and the nested
field itself is marked as well, so the problem is visible even when the row is
collapsed. Reverse nested fields are reported under the objecttype they belong to.

A failure of the plugin itself — an unreachable api, a broken schema — is reported
the same way, without a field, so the editor shows the reason instead of only "the
plugin caused an error".

A `FORMULA_COLUMNS_ERROR` event is still stored with the full log, and a column whose
formula is known to be broken can be switched off with "Disabled" instead of blocking
every save.

> Before this, a throwing formula was swallowed: the column kept its old value and the
> object was saved anyway, with only a line in the server log.

### Throwing on purpose

Because the message reaches the editor verbatim, throwing is how a formula refuses
input. Write the message for the person saving the record, not for the log:

```javascript
if (!objNew.width || !objNew.height) {
    throw new Error("Width and height are both needed to compute the area");
}
return objNew.width * objNew.height;
```

The editor marks the column and shows *"Formula column artwork.area failed: Error:
Width and height are both needed to compute the area"*.

### Failing softly

When a failure should not stop the save, catch it and decide what the column gets.
Returning the stored value is usually better than returning nothing:

```javascript
try {
    const found = await apiSearchBySIDs(objNew.linked?._system_object_id);
    const linked = found?.[0];
    return linked ? linked[linked._objecttype].category : "";
} catch (e) {
    log.push({ column: "category_copy", error: String(e) });
    return objCurr?.category_copy;   // keep what is already stored
}
```

Anything pushed into `log` is written to the `FORMULA_COLUMNS_DEBUG` event when
"Debug" is on, and to `FORMULA_COLUMNS_ERROR` when something failed.

### Only compute when the input changed

`objCurr` is the stored version, so an expensive lookup can be skipped when nothing
relevant changed. On insert there is no `objCurr`, so check it before reading it:

```javascript
if (objCurr && objNew.isbn === objCurr.isbn) {
    return objCurr.title;   // nothing changed, keep what is stored
}
const res = await fetch(`https://openlibrary.org/isbn/${objNew.isbn}.json`);
if (!res.ok) {
    throw new Error(`Lookup for ISBN ${objNew.isbn} failed: ${res.status} ${res.statusText}`);
}
return (await res.json()).title;
```

### Debugging

`console.info` goes to the fylr server log during a real save, and to the output panel
of the "Test" tab, which is the faster way to look at it:

```javascript
console.info("objNew", JSON.stringify(objNew));
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

The manifest master is **`manifest.master.yml`**, as in the other fylr plugins.
`fylr-build-plugin` insists on reading `manifest.yml` from the repo root, so the
Makefile generates it for the run and removes it again — it is gitignored and never
committed. That keeps the root free of a second manifest: a fylr server whose
`plugin.paths` crawls this directory would otherwise find the plugin twice, here and
in `build/`, and refuse to start with *"Already loaded before with the same name"*.
