const fs = require('fs')
const BNBToken = artifacts.require("BNBToken");
const AtomicSwapper = artifacts.require("AtomicSwapper");
const truffleAssert = require('truffle-assertions');
const calculateSecretHashLock = require('./secretHashLock')

let profile;
try {
    profile = require('../GasProfile.json') || {};
} catch (error) {
    console.error(error);
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
        showRegression(trial, results[trial].actual);
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


contract('AtomicSwapper', (accounts) => {
    describe('--Gas Profiling--', function() {
        it('works', async function() {
            console.log('nice')
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
