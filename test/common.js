var axios = require('axios');


var data = JSON.stringify({
    "renter": "0x22df207ec3c8d18fedeed87752c5a68e5b4f6fbd",
    "props_contract": "0x09C824554840Aed574A3eBe9394fD6e9B5fa6eA7",
    "n": 1
});

var config = {
    method: 'post',
    url: 'http://47.236.139.34:8888/api/v1/general_rent/',
    headers: {
        'User-Agent': 'Apifox/1.0.0 (https://apifox.com)',
        'Content-Type': 'application/json',
        'Accept': '*/*',
        'Host': '47.236.139.34:8888',
        'Connection': 'keep-alive',
        'Referer': 'http://47.236.139.34:8888/api/v1/general_rent/'
    },
    data : data
};

axios(config)
    .then(function (response) {
        console.log(JSON.stringify(response.data));
    })
    .catch(function (error) {
        console.log(error);
    });
