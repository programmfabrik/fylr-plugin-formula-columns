#!/bin/zsh
INFO=$(cat <<-END
{
    "api_url": "http://localhost:8080",
    "api_user_access_token": "<put a valid access token here>"
}
END
)

DATA=$(cat <<-END
{"objects": [ {
		"object": {
			"_id": 1,
			"_version": 3,
			"cola": "a",
			"colb": "b",
            "_nested:object__nested": [
				{
                    "amount": 2,
                    "price": 5
				}
			]
		},
		"_mask": "object__all_fields",
		"_objecttype": "object"
	} ] }
END
)

echo $DATA | node FormulaColumnsServer.js $INFO