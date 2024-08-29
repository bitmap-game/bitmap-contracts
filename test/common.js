const axios = require('axios');

function renterRequest(renter, propsContract, n) {
    const data = JSON.stringify({
        "renter": renter,
        "props_contract": propsContract,
        "n": n
    });

    const config = {
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
        data: data
    };

    return axios(config);
}

module.exports = { renterRequest };


//local test
function main() {
    renterRequest("0x22df207ec3c8d18fedeed87752c5a68e5b4f6fbd", "0x09C824554840Aed574A3eBe9394fD6e9B5fa6eA7", 1).then(function (res) {
        console.log(res.data)

        if(res.data.code === 0) {
            console.log('res 2 = ', res.data.data.id)
        }
    })
}

main();

//test: node test/common.js