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

The Javscript snippet is defined as the body of the function

```
function (objNew, objCurr, dataPath, dataPathCurr) {
    ... snippet as defined in the web frontend ...
}
```

It is executed using `eval`, a `try..catch` catches Exception. If an Exception is caught the event is written using the type `FORMULA_COLUMNS_ERROR`.

* `objNew`: The new data of the currently saved object. This includes the record for top level objects, the nested record for nested objects.
* `objCurr`: This data is the data as found in the database. It represents the old / current version of the data.
* `dataPath`: During the recursive crawling of the data, the dataPath is extended for each iteration. It contains the path to the data starting from the top level.
* `dataPathCurr`: Same as `dataPath` but for the current object data.

> A known limitation is that the callback for a nested record does not know which record idx it is currently in.