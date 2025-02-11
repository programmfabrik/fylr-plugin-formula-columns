# fylr-formula-columns-plugin

Plugin for FYLR to store computed values in most column types using a small Javascript snippet.

## Installation

The latest plugin can be download from [Github](https://github.com/programmfabrik/fylr-plugin-formula-columns/releases/latest/download/fylr-plugin-formula-columns.zip). Latest release notes can be found [here](https://github.com/programmfabrik/fylr-plugin-formula-columns/releases).

## Web frontend

After activation of the plugin, the web frontend shows custom settings for "formula columns" in "Data model > Object type > Columns > Option".

There a Javascript can be defined which calculates the value of the column during the "db_pre_save" callback phase which runs on /api/db before objects are inserted into the database. A "debug" option exists to store an event of type "FORMULA_COLUMNS_DEBUG" which helps debugging.

If the formula throws an Exception, an event of type "FORMULA_COLUMNS_ERROR" is stored.

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

The plugin works as `db_pre_save` plugin and as such it used the `_all_fields` mask with all object data present to calculate the fields. The callback receives the current context of the data cell and writes back the result into the JSON response of the plugin.

## Javascript

The Javscript snippet is defined as the body of the function. This code runs within an asynchronous function, meaning you can use `async` and `await` within it.

```
async function (objNew, objCurr, dataPath, dataPathCurr) {
    ... snippet as defined in the web frontend ...
}
```

It is executed using `eval`, a `try..catch` catches Exception. If an Exception is caught the event is written using the type `FORMULA_COLUMNS_ERROR`.

* `objNew`: The new data of the currently saved object. This includes the record for top level objects, the nested record for nested objects.
* `objCurr`: This data is the data as found in the database. It represents the old / current version of the data.
* `dataPath`: During the recursive crawling of the data, the dataPath is extended for each iteration. It contains the path to the data starting from the top level.
* `dataPathCurr`: Same as `dataPath` but for the current object data.

> A known limitation is that the callback for a nested record does not know which record idx it is currently in.

## Utility functions and use of async functions

We provide an utility function that can be used inside the formula.

### `async apiSearchBySIDs(sids, mode)`:

This asynchronous function allows you to find objects in the instance using their `system_global_id`. It accepts either a single `sid` or an array of `sids` and supports different data formats: `long`, `short`, `long_inheritance`, `full`, and `standard`. The function returns an array containing the found objects, or an empty array if no objects are found.

#### Example 1 - Fetching a single linked object by `sid`:
In this example, we fetch a single linked object by its `sid` and return the `category` field of the linked object.
```javascript
console.info("Example of fetching linked object by sid");
if (!objNew.linked) {
    return "No linked object provided.";
}

const sid = objNew.linked._system_object_id;
const linkedObjectData = await apiSearchBySIDs(sid);

console.info("Objects found: ", linkedObjectData);

if (linkedObjectData && linkedObjectData.length > 0) {
    // Retrieve the linked object's fields using its _objecttype
    const linkedObjectType = linkedObjectData[0]._objecttype;
    const linkedFields = linkedObjectData[0][linkedObjectType];
    return linkedFields.category;
} else {
    return "Empty Linked Object...";
}
```
Or you can use your own code for fetching data, from fylr or external api.

#### Example 2 - Using fetch inside the formula for fetching an external api endpoint:
Formula code is inside an async function, so we can make use of async functions like fetch. In this example, we fetch an external API endpoint to get the final value of the field.
```javascript
// We define an async function to fetch the title of a todo from an external API
async function fetchTodoTitle() {
    // Send a GET request to the sample API
    console.info("Start fetching external data..."); // This will be logged in the fylr console
    // Use await to wait for the response, if not the function will return a promise, promises are not supported as return of the formula
      const response = await fetch('https://jsonplaceholder.typicode.com/todos/1');
    if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
    }
    // Parse the response as JSON
    const data = await response.json();
    // Return a string that includes the title of the todo this will be used as data for the target formula field
    return `Todo Title: ${data.title}`;
}

return await fetchTodoTitle();

```


## Available Variables

Within the code, you have access to the following scoped variables:

- `log`: Allows you to add messages that will be stored in system events.
- `info`: Contains instance-related information, such as the `apiToken` or `url`. This is useful for making API calls.

To inspect the contents of `info`, you can use:

```javascript
log.push({"info": info});