# fylr-ejc-plugin
Plugin to support EJC classes

## Installation

The latest version of this plugin can be found [here](https://github.com/programmfabrik/fylr-plugin-ejc/releases/latest/download/fylr-plugin-ejc.zip).

The ZIP can be downloaded and installed using the plugin manager, or used directly (recommended).

Github has an overwiew page to get a list of [all release](https://github.com/programmfabrik/fylr-plugin-ejc/releases/).

## Config endpoint

Use the following endpoints to work with preferences:

### `GET /api/v1/config/plugin/ejc/config`

Returns all preferences known to the plugin. Currently there is only `prefs` available.

For access the [GJSON Syntax](https://github.com/tidwall/gjson/blob/master/SYNTAX.md) is used. For that the path is converted to **GJSON** by replacing `/` with `.`. `.` is replaced by `\.`. Make sure to escape all path elements using the URL % escape notation. A `#` becomes a `%23`.

### `POST /api/v1/config/plugin/ejc/config/prefs`

Post all prefs, supported top level keys are:

* `viewsets`

To access deeper members of JSON data, [SJSON](https://github.com/tidwall/sjson) is used. The GET rules for path replacements are applied for SJSON too, see the Example section for an example.

## Examples

### Replace all prefs with new data

```bash
> curl -X 'POST' -d '{"viewsets": {"views": [{"a": "b"},{"c": "d"}]}}' -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost/api/v1/config/plugin/ejc/config/prefs
{
    "viewsets": {
        "views": [
            {
                "a": "b"
            },
            {
                "c": "d"
            },
        ]
    },
    "viewsets:info": {
        "is_default": false
    }
}
```

### Append an deeper nested item

```bash
> curl -X 'POST' -d '{"e": "f"}' -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost/api/v1/config/plugin/ejc/config/prefs/viewsets/views/-1
null
```
`null` is returned, because the `-1` doesn't work as a `GJSON` path.

### Delete the first item in viewsets.views

```bash
> curl -X 'DELETE' -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost/api/v1/config/plugin/ejc/config/prefs/viewsets/views/0
{
    "c": "d"
}
```

### Get all prefs of the plugin

```bash
> curl -X 'GET' -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost/api/v1/config/plugin/ejc/config
{
    "prefs": {
        "viewsets": {
            "views": [
                {
                    "c": "d"
                },
                {
                    "e": "f"
                }
            ]
        },
        "viewsets:info": {
            "is_default": false
        }
    }
}
```

### Deep filter prefs
```bash
> curl -X 'GET' -H "Authorization: Bearer $ACCESS_TOKEN" http://localhost/api/v1/config/plugin/ejc/config/prefs/viewsets/views/%23(c=d)/c"
"d"
```


