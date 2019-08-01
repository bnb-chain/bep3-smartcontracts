const BNBToken = artifacts.require("BNBToken");
const ERC20AtomicSwapper = artifacts.require("ERC20AtomicSwapper");
const ETHAtomicSwapper = artifacts.require("ETHAtomicSwapper");

module.exports = function(deployer) {
    deployer.deploy(BNBToken, "10000000000000000", "BNB Token", "BNB", "8").then(function(){
        return deployer.deploy(ERC20AtomicSwapper, BNBToken.address);
    });
    deployer.deploy(ETHAtomicSwapper)
};
