# fylr-formula-columns-plugin

Compute the value of a column with a small Javascript snippet. The snippet runs on
the server whenever a record is saved, and what it returns becomes the value of the
column: a full title built from other fields, a value looked up in a linked record or
an external API, a check that refuses bad input.

* write and **test** a formula in the data model editor, against a real record,
  without saving anything and without committing the data model
* a formula that fails **rejects the save** and marks its own field in the editor, so
  with ten formulas on an object type you see right away which one broke, and why
* throw an error with your own message to refuse input, or catch it and keep going

## Requirements and installation

fylr 6.34 or newer.

The latest plugin can be downloaded from [Github](https://github.com/programmfabrik/fylr-plugin-formula-columns/releases/latest/download/fylr-plugin-formula-columns.zip)
and installed in the plugin manager. Release notes are
[here](https://github.com/programmfabrik/fylr-plugin-formula-columns/releases).

## Quick start

A small example that shows the whole cycle: two formulas on one object type, one of
them refuses odd numbers.

1. In **Data model**, pick an object type and add three columns:

   | Column | Type |
   | --- | --- |
   | `demo_number` | Number |
   | `demo_double` | Number |
   | `demo_parity` | Single line text |

   Save, and add the three to the masks you edit with. A formula also runs for
   columns which are not in the mask, but the editor can only mark a field it shows.

2. Open the options of `demo_double`. The **Formula Code** block has an **Edit Code**
   button, which opens the formula editor. Enter:

   ```javascript
   return (objNew.demo_number || 0) * 2;
   ```

3. Do the same for `demo_parity`:

   ```javascript
   const n = objNew.demo_number;
   if (n === null || n === undefined) {
       return "";   // nothing to check yet
   }
   if (n % 2 !== 0) {
       throw new Error(`${n} is odd, please enter an even number`);
   }
   return `${n} is even`;
   ```

4. Still in the editor of `demo_parity`, open the **Test** tab. It shows a generated
   demo record (or pick a real one with **Select record**). Enter `4` in
   `demo_number` and press **Run formula** (or `Cmd+Enter` / `Ctrl+Enter`).
   **Resulting record** shows the record as it would be saved, **Formula output** the
   value `"4 is even"`. Try `7`: the output shows the error. Nothing is saved, and the
   data model does not have to be committed for this.

5. **Apply**, save and commit the data model, then edit a record:

   * with `4` the record saves, `demo_double` is `8` and `demo_parity` is `4 is even`
   * with `7` the save is rejected and `demo_parity` is marked with the message.
     `demo_double` worked and is not marked, so you see which formula broke.

## The formula options

"Data model > Object type > Columns > Options" shows a **Formula Code** block:

| Option | Meaning |
| --- | --- |
| Javascript | opens the formula editor, see [The formula editor](#the-formula-editor) |
| Debug | store a `FORMULA_COLUMNS_DEBUG` event with the log of every run |
| Disabled | keep the formula but stop running it |
| Run as a user plugin | run with the plugin user from the base config instead of the user who saves |

The formula runs during the `db_pre_save` callback phase of `/api/db`, before
records are written.

## Writing a formula

The snippet is the body of an asynchronous function, so `async` and `await` are
available:

```javascript
async function (objNew, objCurr, dataPath, dataPathCurr) {
    ... your snippet ...
}
```

### What the formula returns

The formula computes the value of **its own column only**: whatever it returns is
stored in that column, replacing what was there. So return a value in the format of
the column type, the same as in `/api/db`:

| Column type | Return |
| --- | --- |
| Text | `"Some text"` |
| Multilingual text | `{"de-DE": "Text", "en-US": "Text"}` |
| Number / decimal | `42` / `3.5` |
| Boolean | `true` |
| Date | `{"value": "2026-09-24"}` |

Returning an object with the fields of the record, like `{ field: value, nested: [...] }`,
does **not** fill those fields: the whole object would be the value of this one column.
To compute another field, give that field its own formula. Returning nothing
(`undefined`) empties the column.

The other fields of the record are read from `objNew`:

```javascript
return objNew.first_name + " " + objNew.last_name;
```

### Arguments

* `objNew`: the new data of the record being saved. For a column of a nested table
  this is the nested row.
* `objCurr`: the same data as currently stored, so the old version. `null` when the
  record is new.
* `dataPath`: the path from the top level record down to `objNew`, one entry per
  level. From a nested row, `dataPath[0]` is the top level record as sent to the api
  (`dataPath[0][dataPath[0]._objecttype]` holds its fields).
* `dataPathCurr`: the same as `dataPath`, for the stored data.

> A formula of a nested table runs once per row, but does not know the index of the
> row it runs for.

### Scoped variables

* `log`: push messages here and they are stored in system events (see
  [Debugging](#debugging)).
* `info`: instance information such as the api token and url, useful for api calls.
  Inspect it with `log.push({"info": info})`.

### Looking up linked records: `apiSearchBySIDs(sids, mode)`

Finds records by their `system_global_id`. Takes a single `sid` or an array, and a
format: `long`, `short`, `long_inheritance`, `full` or `standard` (the default).
Returns the records found, or an empty array.

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

### Calling an external API

`fetch` is available too. A Promise is not accepted as the value of the column, so
`await` it:

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

## When a formula fails

A formula that throws **rejects the save**, and the error is reported on the field
itself: the editor marks the column and shows the message next to it, like a failed
input check.

```
Formula column person.demo_parity failed: Error: 7 is odd, please enter an even number
```

The field path names the object type and the column. For a column of a nested table
the failing row is named (`artwork.images[2].caption`) and the nested field itself is
marked as well, so the problem is visible even when the row is collapsed. Reverse
nested fields are reported under the object type they belong to.

A failure of the plugin itself (an unreachable api, a broken schema) is reported the
same way, without a field, so the editor shows the reason instead of only "the plugin
caused an error".

A `FORMULA_COLUMNS_ERROR` event is stored with the full log. A column whose formula is
known to be broken can be switched off with "Disabled" instead of blocking every save.

> Before version 1.0, a throwing formula was swallowed: the column kept its old value
> and the record was saved anyway, with only a line in the server log.

### Throwing on purpose

Because the message reaches the editor as it is, throwing is how a formula refuses
input. Write the message for the person saving the record, not for the log:

```javascript
if (!objNew.width || !objNew.height) {
    throw new Error("Width and height are both needed to compute the area");
}
return objNew.width * objNew.height;
```

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

### Debugging

`console.info` goes to the fylr server log during a real save, and to the
**Formula output** of the Test tab, which is the faster way to look at it:

```javascript
console.info("objNew", JSON.stringify(objNew));
```

Anything pushed into `log` is written to the `FORMULA_COLUMNS_DEBUG` event when
"Debug" is on, and to `FORMULA_COLUMNS_ERROR` when something failed.

## The formula editor

The editor has three columns:

* **Documentation** on the left, collapsible: the arrow in its header folds it into a
  bar, a click on the bar opens it again.
* **Editor** and **Test** tabs in the middle: the code, or the record the formula is
  tested with.
* **Formula output** and **Resulting record** tabs on the right, with **Run formula**
  on top. `Cmd+Enter` (`Ctrl+Enter`) runs the formula from anywhere in the editor,
  also while typing code.

Opening the Test tab switches the right side to the resulting record, going back to
the code switches it to the output. Running from the Editor tab without a record picked
uses the demo record.

### Testing a formula

In the **Test** tab pick a record with **Select record** (or keep the generated demo
record) and change any value you want to try. Then run the formula:

* **Resulting record** is the detail view of the record as the formula left it;
* **Formula output** is the value the column would get and its type, everything the
  formula printed with `console.info` / `console.log`, whatever it pushed into `log`,
  the run time, and the error with its stack if it threw.

The mask selector next to the buttons switches which mask the record and the result
are rendered with. It only changes what is shown: the record handed to the formula is
always the complete record, because that is what fylr hands to `db_pre_save` whatever
mask the record was saved with.

For a column of a nested table the formula runs once per nested row, and every result
is listed with its path (`_nested:objecttype__nested[0]`).

The test runs on the server, through the same code and with the same helpers as a real
save, so `apiSearchBySIDs`, `info`, `fetch` and "Run as a user plugin" behave as they
will in production.

### Columns which are not committed

The column is looked up in the data model version the editor is on, so a column that
is **saved but not yet committed** is found in its real place and the formula runs for
it normally. The resulting record next to it is rendered from the committed data
model, so it cannot show that column yet; the output says so.

A column that has not even been saved is in no data model at all. The formula is then
run once against the record and the returned value is shown, but nothing is written
into a column. Again the output says so.

## API

### POST /api/v1/plugin/extension/formula-columns/test

The Test tab posts to this endpoint. It requires the system right `system.datamodel`
(or `system.root`): running arbitrary Javascript on the server is exactly what
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
be omitted. `version` is `CURRENT` (the data model `db_pre_save` runs against) or
`HEAD`, and decides which data model the column is looked up in.

The response holds one entry in `results` per executed formula. `unknown_column` is
true when the column was in no mask and the formula was run once at top level instead:

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
`{"error": {"code": "forbidden|bad_request|error", "message": "..."}}`. A formula that
throws is not a failure of the request: its `results` entry carries `error` instead of
`value`.

### /api/schema

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

### /api/db

The plugin works as a `db_pre_save` plugin and as such uses the `_all_fields` mask,
with all record data present, to calculate the fields. The callback receives the
current context of the data cell and writes the result back into the JSON response of
the plugin. A failing formula answers with `validation.plugin.error`, which carries
the field paths the editor marks.

## Development

`make build` assembles the plugin into `build/<name>/`, `make zip` builds the release
zip, `make loca` pulls the localisation CSV from its Google Sheet. See
[fylr-build-plugin](https://github.com/programmfabrik/fylr-build-plugin).

The manifest master is **`manifest.master.yml`**, as in the other fylr plugins.
`fylr-build-plugin` insists on reading `manifest.yml` from the repo root, so the
Makefile generates it for the run and removes it again (it is gitignored and never
committed). That keeps the root free of a second manifest: a fylr server whose
`plugin.paths` crawls this directory would otherwise find the plugin twice, here and
in `build/`, and refuse to start with *"Already loaded before with the same name"*.
