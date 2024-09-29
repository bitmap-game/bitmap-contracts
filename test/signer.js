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






var Web3 = require('web3');
var web3 = new Web3();
var message = "Hello, I am Kenneth!";

console.log("version :", web3.version);

var signature = web3.eth.accounts.sign(message, '0xb5b1870957d373ef0eeffecc6e4812c0fd08f554b37b233526acc331bf1544f7');

console.log("signature :", signature);

var messageHash= web3.eth.accounts.hashMessage(message);
// recover 1
var recover_1 = web3.eth.accounts.recover({
    messageHash: messageHash,
    v: signature.v,
    r: signature.r,
    s: signature.s
});

console.log("recover 1 :", recover_1);


// message, signature
var recover_2 = web3.eth.accounts.recover(message, signature.signature);
console.log("recover 2 :", recover_2);

// message, v, r, s
var recover_3 = web3.eth.accounts.recover(message, signature.v, signature.r, signature.s);
console.log("recover 3 :", recover_3);