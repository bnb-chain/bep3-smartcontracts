const ETHAtomicSwapper = artifacts.require("ETHAtomicSwapper");
const crypto = require('crypto');
const truffleAssert = require('truffle-assertions');
const Big = require('big.js');

function calculateRandomNumberHash (randomNumber, timestamp) {
    const timestampHexStr = timestamp.toString(16);
    var timestampHexStrFormat = timestampHexStr;
    // timestampHexStrFormat should be the hex string of a 32-length byte array. Fill 0 if the timestampHexStr length is less than 64
    for (var i = 0; i < 16 - timestampHexStr.length; i++) {
        timestampHexStrFormat = '0' + timestampHexStrFormat;
    }
    const timestampBytes = Buffer.from(timestampHexStrFormat, "hex");
    const newBuffer = Buffer.concat([Buffer.from(randomNumber.substring(2, 66), "hex"), timestampBytes]);
    const hash = crypto.createHash('sha256');
    hash.update(newBuffer);
    return "0x" + hash.digest('hex');
}

function calculateSwapID(randomNumberHash, sender, recipient) {
    const newBuffer = Buffer.concat([Buffer.from(randomNumberHash.substring(2, 66), "hex"), Buffer.from(sender.substring(2, 42), "hex"), Buffer.from(recipient.substring(2, 42), "hex")]);
    const hash = crypto.createHash('sha256');
    hash.update(newBuffer);
    return "0x" + hash.digest('hex');
}

contract('Verify ETHAtomicSwapper', (accounts) => {
    it('Test swap initiate, claim', async () => {
        const swapInstance = await ETHAtomicSwapper.deployed();

        const swapA = accounts[1];
        const swapB = accounts[2];

        const timestamp = Math.floor(Date.now()/1000); // counted by second
        const randomNumber = "0xaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd";
        const randomNumberHash = calculateRandomNumberHash(randomNumber, timestamp);
        const timelock = 1000;
        const recipientAddr = swapB;
        const bep2Addr = "0xc9a2c4868f0f96faaa739b59934dc9cb304112ec";
        const ETHCoin = 100000000;
        const bep2Amount = 100000000;
        const swapID = calculateSwapID(randomNumberHash, swapA, swapB);

        var swapExistence = (await swapInstance.swapExistence.call(randomNumberHash)).valueOf();
        assert.equal(swapExistence, true);

        const initialbalanceOfSwapA = await web3.eth.getBalance(swapA);
        const initialbalanceOfSwapB = await web3.eth.getBalance(swapB);

        let initiateTx = await swapInstance.htlt(randomNumberHash, timestamp, timelock, recipientAddr, bep2Addr, bep2Amount, { from: swapA , value: ETHCoin});
        //SwapInit event should be emitted
        truffleAssert.eventEmitted(initiateTx, 'HTLT', (ev) => {
            return ev._msgSender === swapA &&
                ev._recipientAddr === swapB &&
                ev._swapID === swapID &&
                ev._bep2Addr === bep2Addr &&
                ev._randomNumberHash === randomNumberHash &&
                Number(ev._timestamp.toString()) === timestamp &&
                Number(ev._outAmount.toString()) === ETHCoin &&
                Number(ev._bep2Amount.toString()) === bep2Amount;
        });

        // Verify if the swapped ERC20 token has been transferred to contract address
        var balanceOfSwapContract = await web3.eth.getBalance(ETHAtomicSwapper.address);
        assert.equal(Number(balanceOfSwapContract.toString()), ETHCoin);

        // querySwapByHashLock
        var swap = (await swapInstance.queryOpenSwap.call(swapID)).valueOf();
        assert.equal(timestamp, swap._timestamp);
        assert.equal(ETHCoin, swap._outAmount);

        swapExistence = (await swapInstance.swapExistence.call(swapID)).valueOf();
        assert.equal(swapExistence, false);
        var claimable = (await swapInstance.claimable.call(swapID)).valueOf();
        assert.equal(claimable, true);
        var refundable = (await swapInstance.refundable.call(swapID)).valueOf();
        assert.equal(refundable, false);

        const gasUsed = initiateTx.receipt.gasUsed;
        const tx = await web3.eth.getTransaction(initiateTx.tx);
        const txFee = gasUsed * tx.gasPrice;
        console.log("initiateTx gasUsed: ", initiateTx.receipt.gasUsed);

        var balanceOfSwapA = await web3.eth.getBalance(swapA);
        assert.equal(balanceOfSwapA.toString(), new Big(initialbalanceOfSwapA).minus(ETHCoin).minus(txFee).toString());
        var balanceOfSwapB = await web3.eth.getBalance(swapB);
        assert.equal(balanceOfSwapB, initialbalanceOfSwapB);

        // Anyone can call claim and the token will be paid to swapB address
        let claimTx = await swapInstance.claim(swapID, randomNumber, { from: accounts[6] });
        //SwapComplete n event should be emitted
        truffleAssert.eventEmitted(claimTx, 'Claimed', (ev) => {
            return ev._msgSender === accounts[6] && ev._recipientAddr === swapB && ev._randomNumberHash === randomNumberHash && ev._swapID === swapID && ev._randomNumber === randomNumber;
        });
        console.log("claimTx gasUsed: ", claimTx.receipt.gasUsed);

        balanceOfSwapB = await web3.eth.getBalance(swapB);
        assert.equal(balanceOfSwapB.toString(), new Big(initialbalanceOfSwapB).plus(ETHCoin).toString());

        balanceOfSwapContract = await web3.eth.getBalance(ETHAtomicSwapper.address);
        assert.equal(Number(balanceOfSwapContract), 0);

        claimable = (await swapInstance.claimable.call(swapID)).valueOf();
        assert.equal(claimable, false);
        refundable = (await swapInstance.refundable.call(swapID)).valueOf();
        assert.equal(refundable, false);
    });
    it('Test swap initiate, refund', async () => {
        const swapInstance = await ETHAtomicSwapper.deployed();

        const swapA = accounts[3];
        const swapB = accounts[4];

        const timestamp = Math.floor(Date.now()/1000); // counted by second
        const randomNumber = "0x1122334411223344112233441122334411223344112233441122334411223344";
        const randomNumberHash = calculateRandomNumberHash(randomNumber, timestamp);
        const timelock = 100;
        const recipientAddr = swapB;
        const bep2Addr = "0xc9a2c4868f0f96faaa739b59934dc9cb304112ec";
        const ETHCoin = 100000000;
        const bep2Amount = 100000000;
        const swapID = calculateSwapID(randomNumberHash, swapA, swapB);

        var swapExistence = (await swapInstance.swapExistence.call(swapID)).valueOf();
        assert.equal(swapExistence, true);

        const initialbalanceOfSwapA = await web3.eth.getBalance(swapA);
        const initialbalanceOfSwapB = await web3.eth.getBalance(swapB);

        let initiateTx = await swapInstance.htlt(randomNumberHash, timestamp, timelock, recipientAddr, bep2Addr, bep2Amount, { from: swapA , value: ETHCoin});
        //SwapInit event should be emitted
        truffleAssert.eventEmitted(initiateTx, 'HTLT', (ev) => {
            return ev._msgSender === swapA &&
                ev._recipientAddr === swapB &&
                ev._swapID === swapID &&
                ev._bep2Addr === bep2Addr &&
                ev._randomNumberHash === randomNumberHash &&
                Number(ev._timestamp.toString()) === timestamp &&
                Number(ev._outAmount.toString()) === ETHCoin &&
                Number(ev._bep2Amount.toString()) === bep2Amount;
        });

        const gasUsed = initiateTx.receipt.gasUsed;
        const tx = await web3.eth.getTransaction(initiateTx.tx);
        const txFee = gasUsed * tx.gasPrice;
        console.log("initiateTx gasUsed: ", initiateTx.receipt.gasUsed);

        swapExistence = (await swapInstance.swapExistence.call(swapID)).valueOf();
        assert.equal(swapExistence, false);
        var claimable = (await swapInstance.claimable.call(swapID)).valueOf();
        assert.equal(claimable, true);
        var refundable = (await swapInstance.refundable.call(swapID)).valueOf();
        assert.equal(refundable, false);


        // Just for producing new blocks
        for (var i = 0; i <timelock; i++) {
            await web3.eth.sendTransaction({ from: accounts[6], to: accounts[6], value: 10 });
        }

        claimable = (await swapInstance.claimable.call(swapID)).valueOf();
        assert.equal(claimable, false);
        refundable = (await swapInstance.refundable.call(swapID)).valueOf();
        assert.equal(refundable, true);

        var balanceOfSwapABeforeRefund = await web3.eth.getBalance(swapA);
        assert.equal(balanceOfSwapABeforeRefund.toString(), new Big(initialbalanceOfSwapA).minus(txFee).minus(ETHCoin).toString());

        // Anyone can call refund and the token will always been refunded to swapA address
        let refundTx = await swapInstance.refund(swapID, { from: accounts[6] });

        //SwapExpire n event should be emitted
        truffleAssert.eventEmitted(refundTx, 'Refunded', (ev) => {
            return ev._msgSender === accounts[6] && ev._swapSender === swapA && ev._swapID === swapID && ev._randomNumberHash === randomNumberHash;
        });
        console.log("refundTx gasUsed: ", refundTx.receipt.gasUsed);

        var balanceOfSwapB = await web3.eth.getBalance(swapB);
        assert.equal(initialbalanceOfSwapB, balanceOfSwapB);

        var balanceOfSwapANew = await web3.eth.getBalance(swapA);
        assert.equal(balanceOfSwapANew, new Big(initialbalanceOfSwapA).minus(txFee));

        var balanceOfSwapContract = await web3.eth.getBalance(ETHAtomicSwapper.address);
        assert.equal(Number(balanceOfSwapContract.toString()), 0);

        claimable = (await swapInstance.claimable.call(swapID)).valueOf();
        assert.equal(claimable, false);
        refundable = (await swapInstance.refundable.call(swapID)).valueOf();
        assert.equal(refundable, false);
    });
});