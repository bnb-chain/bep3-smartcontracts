const ETHAtomicSwapper = artifacts.require("ETHAtomicSwapper");
const crypto = require('crypto');
const truffleAssert = require('truffle-assertions');
const Big = require('big.js');

function calculateSecretHashLock (secretKey, timestamp) {
    const timestampHexStr = timestamp.toString(16);
    var timestampHexStrFormat = timestampHexStr;
    // timestampHexStrFormat should be the hex string of a 32-length byte array. Fill 0 if the timestampHexStr length is less than 64
    for (var i = 0; i < 16 - timestampHexStr.length; i++) {
        timestampHexStrFormat = '0' + timestampHexStrFormat;
    }
    const timestampBytes = Buffer.from(timestampHexStrFormat, "hex");
    const newBuffer = Buffer.concat([Buffer.from(secretKey.substring(2, 66), "hex"), timestampBytes]);
    const hash = crypto.createHash('sha256');
    hash.update(newBuffer);
    return "0x" + hash.digest('hex');
}

contract('Verify ETHAtomicSwapper', (accounts) => {
    it('Test secret hash lock calculation', async () => {
        const swapInstance = await ETHAtomicSwapper.deployed();

        const timestamp = Date.now();
        const secretKey = "0xaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd";
        const secretHashLock = (await swapInstance.calSecretHash.call(secretKey, timestamp));

        assert.equal(secretHashLock, calculateSecretHashLock(secretKey, timestamp), "the secretHashLock should equal to hash result of secretKey and timestamp");
    });
    it('Test swap initiate, claim', async () => {
        const swapInstance = await ETHAtomicSwapper.deployed();

        const swapA = accounts[1];
        const swapB = accounts[2];

        const timestamp = Math.floor(Date.now()/1000); // counted by second
        const secretKey = "0xaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd";
        const secretHashLock = calculateSecretHashLock(secretKey, timestamp);
        const timelock = 1000;
        const receiverAddr = swapB;
        const bep2Addr = "0xc9a2c4868f0f96faaa739b59934dc9cb304112ec";
        const ETHCoin = 100000000;
        const bep2Amount = 100000000;

        var initializable = (await swapInstance.initializable.call(secretHashLock)).valueOf();
        assert.equal(initializable, true);

        const initialbalanceOfSwapA = await web3.eth.getBalance(swapA);
        const initialbalanceOfSwapB = await web3.eth.getBalance(swapB);

        let initiateTx = await swapInstance.initiate(secretHashLock, timestamp, timelock, receiverAddr, bep2Addr, bep2Amount, { from: swapA , value: ETHCoin});
        //SwapInit event should be emitted
        truffleAssert.eventEmitted(initiateTx, 'SwapInit', (ev) => {
            return ev._msgSender === swapA &&
                ev._receiverAddr === swapB &&
                ev._bep2Addr === bep2Addr &&
                Number(ev._index.toString()) === 0 &&
                ev._secretHashLock === secretHashLock &&
                Number(ev._timestamp.toString()) === timestamp &&
                Number(ev._ETHCoin.toString()) === ETHCoin &&
                Number(ev._bep2Amount.toString()) === bep2Amount;
        });

        //Verify swap index
        const index = await swapInstance.index.call();
        assert.equal(index, 1, "swap index initial value should be 1");

        // Verify if the swapped ERC20 token has been transferred to contract address
        var balanceOfSwapContract = await web3.eth.getBalance(ETHAtomicSwapper.address);
        assert.equal(Number(balanceOfSwapContract.toString()), ETHCoin);

        // querySwapByHashLock
        var swap = (await swapInstance.querySwapByHashLock.call(secretHashLock)).valueOf();
        assert.equal(timestamp, swap._timestamp);
        assert.equal(0x0, swap._secretKey);
        assert.equal(ETHCoin, swap._ETHCoin);
        assert.equal(bep2Amount, swap._bep2Amount);
        assert.equal(swapA, swap._sender);
        assert.equal(bep2Addr, swap._bep2Addr);
        // swap status should be OPEN 1
        assert.equal(1, swap._status);
        //querySwapByIndex
        swap = (await swapInstance.querySwapByIndex.call(0)).valueOf();
        assert.equal(secretHashLock, swap._secretHashLock);
        assert.equal(timestamp, swap._timestamp);
        assert.equal(0x0, swap._secretKey);
        assert.equal(ETHCoin, swap._ETHCoin);
        assert.equal(bep2Amount, swap._bep2Amount);
        assert.equal(swapA, swap._sender);
        assert.equal(bep2Addr, swap._bep2Addr);
        assert.equal(1, swap._status);

        initializable = (await swapInstance.initializable.call(secretHashLock)).valueOf();
        assert.equal(initializable, false);
        var claimable = (await swapInstance.claimable.call(secretHashLock)).valueOf();
        assert.equal(claimable, true);
        var refundable = (await swapInstance.refundable.call(secretHashLock)).valueOf();
        assert.equal(refundable, false);

        const gasUsed = initiateTx.receipt.gasUsed;
        const tx = await web3.eth.getTransaction(initiateTx.tx);
        const txFee = gasUsed * tx.gasPrice;

        var balanceOfSwapA = await web3.eth.getBalance(swapA);
        assert.equal(balanceOfSwapA.toString(), new Big(initialbalanceOfSwapA).minus(ETHCoin).minus(txFee).toString());
        var balanceOfSwapB = await web3.eth.getBalance(swapB);
        assert.equal(balanceOfSwapB, initialbalanceOfSwapB);

        // Anyone can call claim and the token will be paid to swapB address
        let claimTx = await swapInstance.claim(secretHashLock, secretKey, { from: accounts[6] });
        //SwapComplete n event should be emitted
        truffleAssert.eventEmitted(claimTx, 'SwapComplete', (ev) => {
            return ev._msgSender === accounts[6] && ev._receiverAddr === swapB && ev._secretHashLock === secretHashLock && ev._secretKey === secretKey;
        });

        swap = (await swapInstance.querySwapByHashLock.call(secretHashLock)).valueOf();
        // swap status should be COMPLETED 2
        assert.equal(2, swap._status);
        assert.equal(secretKey, swap._secretKey);

        balanceOfSwapB = await web3.eth.getBalance(swapB);
        assert.equal(balanceOfSwapB.toString(), new Big(initialbalanceOfSwapB).plus(ETHCoin).toString());

        balanceOfSwapContract = await web3.eth.getBalance(ETHAtomicSwapper.address);
        assert.equal(Number(balanceOfSwapContract), 0);

        claimable = (await swapInstance.claimable.call(secretHashLock)).valueOf();
        assert.equal(claimable, false);
        refundable = (await swapInstance.refundable.call(secretHashLock)).valueOf();
        assert.equal(refundable, false);
    });
    it('Test swap initiate, refund', async () => {
        const swapInstance = await ETHAtomicSwapper.deployed();

        const swapA = accounts[3];
        const swapB = accounts[4];

        const timestamp = Math.floor(Date.now()/1000); // counted by second
        const secretKey = "0x1122334411223344112233441122334411223344112233441122334411223344";
        const secretHashLock = calculateSecretHashLock(secretKey, timestamp);
        const timelock = 100;
        const receiverAddr = swapB;
        const bep2Addr = "0xc9a2c4868f0f96faaa739b59934dc9cb304112ec";
        const ETHCoin = 100000000;
        const bep2Amount = 100000000;

        var initializable = (await swapInstance.initializable.call(secretHashLock)).valueOf();
        assert.equal(initializable, true);

        const initialbalanceOfSwapA = await web3.eth.getBalance(swapA);
        const initialbalanceOfSwapB = await web3.eth.getBalance(swapB);

        let initiateTx = await swapInstance.initiate(secretHashLock, timestamp, timelock, receiverAddr, bep2Addr, bep2Amount, { from: swapA , value: ETHCoin});
        //SwapInit event should be emitted
        truffleAssert.eventEmitted(initiateTx, 'SwapInit', (ev) => {
            return ev._msgSender === swapA &&
                ev._receiverAddr === swapB &&
                ev._bep2Addr === bep2Addr &&
                Number(ev._index.toString()) === 1 &&
                ev._secretHashLock === secretHashLock &&
                Number(ev._timestamp.toString()) === timestamp &&
                Number(ev._ETHCoin.toString()) === ETHCoin &&
                Number(ev._bep2Amount.toString()) === bep2Amount;
        });

        const gasUsed = initiateTx.receipt.gasUsed;
        const tx = await web3.eth.getTransaction(initiateTx.tx);
        const txFee = gasUsed * tx.gasPrice;

        const index = await swapInstance.index.call();
        assert.equal(index, 2, "swap index initial value should be 2");

        initializable = (await swapInstance.initializable.call(secretHashLock)).valueOf();
        assert.equal(initializable, false);
        var claimable = (await swapInstance.claimable.call(secretHashLock)).valueOf();
        assert.equal(claimable, true);
        var refundable = (await swapInstance.refundable.call(secretHashLock)).valueOf();
        assert.equal(refundable, false);


        // Just for producing new blocks
        for (var i = 0; i <timelock; i++) {
            await web3.eth.sendTransaction({ from: accounts[6], to: accounts[6], value: 10 });
        }

        claimable = (await swapInstance.claimable.call(secretHashLock)).valueOf();
        assert.equal(claimable, false);
        refundable = (await swapInstance.refundable.call(secretHashLock)).valueOf();
        assert.equal(refundable, true);

        var balanceOfSwapABeforeRefund = await web3.eth.getBalance(swapA);
        assert.equal(balanceOfSwapABeforeRefund.toString(), new Big(initialbalanceOfSwapA).minus(txFee).minus(ETHCoin).toString());

        // Anyone can call refund and the token will always been refunded to swapA address
        let refundTx = await swapInstance.refund(secretHashLock, { from: accounts[6] });

        //SwapExpire n event should be emitted
        truffleAssert.eventEmitted(refundTx, 'SwapExpire', (ev) => {
            return ev._msgSender === accounts[6] && ev._swapSender === swapA && ev._secretHashLock === secretHashLock;
        });

        // swap status should be EXPIRED 3
        const swap = (await swapInstance.querySwapByHashLock.call(secretHashLock)).valueOf();
        assert.equal(3, swap._status);

        var balanceOfSwapB = await web3.eth.getBalance(swapB);
        assert.equal(initialbalanceOfSwapB, balanceOfSwapB);

        var balanceOfSwapANew = await web3.eth.getBalance(swapA);
        assert.equal(balanceOfSwapANew, new Big(initialbalanceOfSwapA).minus(txFee));

        var balanceOfSwapContract = await web3.eth.getBalance(ETHAtomicSwapper.address);
        assert.equal(Number(balanceOfSwapContract.toString()), 0);

        claimable = (await swapInstance.claimable.call(secretHashLock)).valueOf();
        assert.equal(claimable, false);
        refundable = (await swapInstance.refundable.call(secretHashLock)).valueOf();
        assert.equal(refundable, false);
    });
});