const crypto = require('crypto');

function calculateRandomNumberHash(randomNumber, timestamp) {
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

module.exports = {
    calculateRandomNumberHash,
    calculateSwapID,
}
