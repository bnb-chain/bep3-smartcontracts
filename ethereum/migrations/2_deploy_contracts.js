const BNBToken = artifacts.require("BNBToken");
const AtomicSwapper = artifacts.require("AtomicSwapper");

module.exports = function(deployer) {
    deployer.deploy(BNBToken, "10000000000000000", "BNB Token", "BNB", "8").then(function(){
        return deployer.deploy(AtomicSwapper, BNBToken.address);
    });
};
