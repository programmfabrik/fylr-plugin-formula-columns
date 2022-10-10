const http = require('http');

module.exports = {
    // send eventData to the api to store an event
    storeEvent: async function (info, eventData) {
        return this.reqURL(info.api_url + "/api/v1/event?background=1&access_token=" + info.api_user_access_token, "POST", eventData)
    },
    // sendDV send data to a dv server. https://github.com/programmfabrik/dv
    sendDV: async function (data) {
        let prom = this.reqURL("http://localhost:10000/data", "POST", data)
        prom.catch((e) => {
            console.error(e)
        })
        return prom
    },
    // getSchema returns an enriched _all_fields mask list, parameter info must be provided
    getSchema: async function (info) {
        // setCols sets mask._columns to an array of
        // all columns found in mask m
        function setCols(m) {
            m._columns = []
            for (var j = 0; j < m.fields.length; j++) {
                let f = m.fields[j]
                if (f.column) {
                    f.column._mask = f.mask
                    m._columns.push(f.column)
                }
                // dive into submasks
                if (f.mask) {
                    setCols(f.mask)
                }
            }
        }
        return new Promise((resolve, reject) => {
            this.reqURL(info.api_url + "/api/v1/mask/CURRENT/_all_fields?format=long&access_token=" + info.api_user_access_token)
                .then((data) => {
                    // build an object mapping table to mask
                    data._mask_by_table_name = {}
                    for (var i = 0; i < data.masks.length; i++) {
                        // add a column_by_name map
                        let m = data.masks[i]
                        setCols(m)
                        data._mask_by_table_name[m.table_name_hint] = m
                    }
                    resolve(data._mask_by_table_name)
                })
                .catch(reject)
        })
    },
    // getStdin returns a Promise. stdin data is passed to resolve
    getStdin: async function () {
        return new Promise((resolve, reject) => {
            let input = ""
            process.stdin.on('data', (d) => {
                try {
                    input += d.toString()
                } catch (e) {
                    console.error("Could not read input into string: ${e.message}", e.stack)
                    reject()
                }
            });
            process.stdin.on('end', () => {
                try {
                    data = JSON.parse(input)
                    delete (data.info)
                    resolve(data)
                } catch (e) {
                    console.error("Could not parse input: ${e.message}", e.stack)
                    reject()
                }
            })
        });
    },
    // reqURL sends a request to url using the given method and body data
    // (stringified as JSON)
    reqURL: async function (url, method, body) {
        let u = new URL(url)
        if (!method) {
            method = "GET"
        }
        let prom = new Promise((resolve, reject) => {
            const options = {
                hostname: u.hostname,
                port: u.port,
                path: u.pathname + u.search,
                method: method
            };
            let jsonData
            if (body) {
                jsonData = JSON.stringify(body)
                options.headers = {
                    'Content-Type': 'application/json',
                    'Content-Length': jsonData.length
                }
            }

            const callback = function (response) {
                // console.error(`statusCode: ${response.statusCode}`);
                var str = '';
                response.on('data', function (chunk) {
                    str += chunk;
                });
                response.on('end', function () {
                    // console.error("end respsone", str);
                    try {
                        let data = JSON.parse(str)
                        if (response.statusCode == 200) {
                            resolve(data);
                        } else {
                            reject(data);
                        }
                    } catch (e) {
                        resolve(data)
                    }
                });
            };
            var req = http.request(options, callback);
            if (body) {
                req.write(jsonData)
            }
            req.on('error', error => {
                console.error(error);
                reject(error);
            });
            req.end();
            console.error("http get", url)
        })
        return prom
    }
}