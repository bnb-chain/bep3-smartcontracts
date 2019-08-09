const fs = require('fs')
const BNBToken = artifacts.require("BNBToken");
const ERC20AtomicSwapper = artifacts.require("ERC20AtomicSwapper");
const truffleAssert = require('truffle-assertions');
const calculateSecretHashLock = require('./secretHashLock');
const timeTraveler = require('ganache-time-traveler');

let profile;
try {
    profile = require('../GasProfile.json') || {};
} catch (error) {
    if (!error.message.startsWith('Cannot find module')) {
        console.error(error);
    }
    console.log('Creating GasProfile.json')
    profile = {}
}

function showRegression(type, actual) {
    const expected = profile[type];
    if (actual < expected) {
        console.log("\x1b[32m", type, "improvement:", expected, '->', actual, "\x1b[0m");
    } else if (actual > expected) {
        console.log("\x1b[31m", type, "regression:", expected, '->', actual, "\x1b[0m");
    } else if (typeof(expected) === 'undefined') {
        console.log(type, '=', actual)
    }
    profile[type] = actual
}

function showRegressions(results) {
    for (let trial in results) {
        showRegression(trial, results[trial]);
    }
}


function hasNoZero(address) {
    for (let i = 2; i < address.length; i++) {
        if (address.substr(i, 2) == '00') {
            return false
        }
    }
    return true
}


contract('ERC20AtomicSwapper', (accounts) => {
    const [_, owner, operator, swapA, swapB] = accounts.filter(hasNoZero)
    // Constant swap parameters
    const timestamp = 1565312187;
    const secretKey = "0xaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd";
    const secretHashLock = calculateSecretHashLock(secretKey, timestamp);
    const timelock = 257;
    const receiverAddr = swapB;
    const BEP2Addr = "0xc9a2c4868f0f96faaa739b59934dc9cb304112ec";
    const outAmount = 100000000;
    const inAmount = 100000000;

    describe('--Gas Profiling--', function() {
        beforeEach(async function() {
            this.supply = 10000000000000000;
            this.bnbInstance = await BNBToken.new(web3.utils.toHex(this.supply), "BNB Token", "BNB", 8, {from:owner});
            this.swapInstance = await ERC20AtomicSwapper.new(this.bnbInstance.address, {from:operator});
            await this.bnbInstance.transfer(swapA, inAmount, {from: owner});
            await this.bnbInstance.approve(this.swapInstance.address, outAmount, { from: swapA });
        })
        it('initiateTx and claim', async function() {
            let initiateTx = await this.swapInstance.initiate(secretHashLock, timestamp, timelock, receiverAddr, BEP2Addr, outAmount, inAmount, { from: swapA });
            let claimTx = await this.swapInstance.claim(secretHashLock, secretKey, { from: operator });
            const actual = {
                initiateTx: initiateTx.receipt.gasUsed,
                claimTx: claimTx.receipt.gasUsed,
            }
            showRegressions(actual)
        })
        it('refund', async function() {
            let initiateTx = await this.swapInstance.initiate(secretHashLock, timestamp, timelock, receiverAddr, BEP2Addr, outAmount, inAmount, { from: swapA });
            // advance to expiration
            for (var i = 0; i < timelock; i++) {
                timeTraveler.advanceBlock();
            }
            let refundTx = await this.swapInstance.refund(secretHashLock, { from: operator });
            const actual = {
                refundTx: initiateTx.receipt.gasUsed,
            }
            showRegressions(actual)
        })
        after(async function() {
            await new Promise((resolve, reject) => {
                console.log('Writing GasProfile.json')
                const updatedExpectations = JSON.stringify(profile, null, 2);
                fs.writeFile('./GasProfile.json', updatedExpectations, (error) => {
                    if (error) {
                        console.error(error)
                        reject(error)
                        return
                    }
                    console.log('Wrote GasProfile.json')
                    resolve()
                })
            })
        })
    })
})
