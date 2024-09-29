const { ethers } = require('ethers');

async function SignPrivateKeyInMessage(privateKey,message) {
    const wallet = new ethers.Wallet(privateKey);
    const signature = await wallet.signMessage(message);
    console.log("signature :", signature);

    return signature
}

SignPrivateKeyInMessage('744ba22387c27cf73dff283a37f0a7e63054a86be15965be97c807816d79da39', 'hello')