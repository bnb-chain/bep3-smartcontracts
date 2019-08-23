pragma solidity 0.5.8;

interface ERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address who) external view returns (uint);
    function transfer(address to, uint value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
}

contract ERC20AtomicSwapper {

    struct Swap {
        uint256 outAmount;
        uint256 expireHeight;
        uint64  timestamp;
        address sender;
        address receiverAddr;
    }

    enum States {
        INVALID,
        OPEN,
        COMPLETED,
        EXPIRED
    }

    // Events
    event HTLT(address indexed _msgSender, address indexed _receiverAddr, bytes32 indexed _randomNumberHash, uint64 _timestamp, bytes20 _bep2Addr, uint256 _expireHeight, uint256 _outAmount, uint256 _bep2Amount);
    event Refunded(address indexed _msgSender, address indexed _swapSender, bytes32 indexed _randomNumberHash);
    event Claimed(address indexed _msgSender, address indexed _receiverAddr, bytes32 indexed _randomNumberHash, bytes32 _randomNumber);

    // Storage
    mapping (bytes32 => Swap) private swaps;
    mapping (bytes32 => States) private swapStates;

    address public ERC20ContractAddr;

    /// @notice Throws if the swap is not invalid (i.e. has already been used)
    modifier onlyInvalidSwaps(bytes32 _randomNumberHash) {
        require(swapStates[_randomNumberHash] == States.INVALID, "swap is opened previously");
        _;
    }

    /// @notice Throws if the swap is not open.
    modifier onlyOpenSwaps(bytes32 _randomNumberHash) {
        require(swapStates[_randomNumberHash] == States.OPEN, "swap is not opened");
        _;
    }

    /// @notice Throws if the swap is already expired.
    modifier onlyAfterExpireHeight(bytes32 _randomNumberHash) {
        require(block.number >= swaps[_randomNumberHash].expireHeight, "swap is not expired");
        _;
    }

    /// @notice Throws if the expireHeight is reached
    modifier onlyBeforeExpireHeight(bytes32 _randomNumberHash) {
        require(block.number < swaps[_randomNumberHash].expireHeight, "swap is already expired");
        _;
    }

    /// @notice Throws if the random number is not valid.
    modifier onlyWithRandomNumber(bytes32 _randomNumberHash, bytes32 _randomNumber) {
        require(_randomNumberHash == calRandomNumberHash(_randomNumber, swaps[_randomNumberHash].timestamp), "invalid randomNumber");
        _;
    }

    /// @param _erc20Contract The ERC20 contract address
    constructor(address _erc20Contract) public {
        ERC20ContractAddr = _erc20Contract;
    }

    /// @notice hashTimerLockedTransfer locks asset to contract address and create an atomic swap.
    ///
    /// @param _randomNumberHash The hash of the random number and timestamp
    /// @param _timestamp Counted by second
    /// @param _heightSpan The number of blocks to wait before the asset can be returned to sender
    /// @param _receiverAddr The ethereum address of the swap counterpart.
    /// @param _bep2Addr The receiver address on Binance Chain
    /// @param _outAmount ERC20 asset to swap out.
    /// @param _bep2Amount BEP2 asset to swap in.
    function htlt(
        bytes32 _randomNumberHash,
        uint64  _timestamp,
        uint256 _heightSpan,
        address _receiverAddr,
        bytes20 _bep2Addr,
        uint256 _outAmount,
        uint256 _bep2Amount
    ) external onlyInvalidSwaps(_randomNumberHash) returns (bool) {
        require(_outAmount > 0, "_outAmount must be more than 0");
        // Assume average block time interval is 10 second
        // The heightSpan period should be more than 10 minutes and less than one week
        require(_heightSpan >= 60 && _heightSpan <= 60480, "_heightSpan should be in [60, 60480]");
        require(_receiverAddr != address(0), "_receiverAddr should not be zero");
        require(_timestamp > now -7200 && _timestamp < now + 3600, "The timestamp should not be one hour ahead or two hour behind current time");
        // Store the details of the swap.
        Swap memory swap = Swap({
            outAmount: _outAmount,
            expireHeight: _heightSpan + block.number,
            timestamp: _timestamp,
            sender: msg.sender,
            receiverAddr: _receiverAddr
        });

        swaps[_randomNumberHash] = swap;
        swapStates[_randomNumberHash] = States.OPEN;

        // Transfer ERC20 token to the swap contract
        require(ERC20(ERC20ContractAddr).transferFrom(msg.sender, address(this), _outAmount), "failed to transfer client asset to swap contract address");

        // Emit initialization event
        emit HTLT(msg.sender, _receiverAddr, _randomNumberHash, _timestamp, _bep2Addr, swap.expireHeight, _outAmount, _bep2Amount);
        return true;
    }

    /// @notice claim claims the previously locked asset.
    ///
    /// @param _randomNumberHash The hash of randomNumber and timestamp
    /// @param _randomNumber The random number
    function claim(bytes32 _randomNumberHash, bytes32 _randomNumber) external onlyOpenSwaps(_randomNumberHash) onlyBeforeExpireHeight(_randomNumberHash) onlyWithRandomNumber(_randomNumberHash, _randomNumber) returns (bool) {
        // Complete the swap.
        swapStates[_randomNumberHash] = States.COMPLETED;

        address receiverAddr = swaps[_randomNumberHash].receiverAddr;
        uint256 outAmount = swaps[_randomNumberHash].outAmount;
        // delete closed swap
        delete swaps[_randomNumberHash];

        // Pay erc20 token to receiver
        require(ERC20(ERC20ContractAddr).transfer(receiverAddr, outAmount), "Failed to transfer locked asset to receiver");

        // Emit completion event
        emit Claimed(msg.sender, receiverAddr, _randomNumberHash, _randomNumber);

        return true;
    }

    /// @notice refund refunds the previously locked asset.
    ///
    /// @param _randomNumberHash The hash of randomNumber and timestamp
    function refund(bytes32 _randomNumberHash) external onlyOpenSwaps(_randomNumberHash) onlyAfterExpireHeight(_randomNumberHash) returns (bool) {
        // Expire the swap.
        swapStates[_randomNumberHash] = States.EXPIRED;

        address swapSender = swaps[_randomNumberHash].sender;
        uint256 outAmount = swaps[_randomNumberHash].outAmount;
        // delete closed swap
        delete swaps[_randomNumberHash];

        // refund erc20 token to swap creator
        require(ERC20(ERC20ContractAddr).transfer(swapSender, outAmount), "Failed to transfer locked asset back to swap creator");

        // Emit expire event
        emit Refunded(msg.sender, swapSender, _randomNumberHash);

        return true;
    }

    /// @notice query an atomic swap by randomNumberHash
    ///
    /// @param _randomNumberHash The hash of randomNumber and timestamp
    function queryOpenSwap(bytes32 _randomNumberHash) external view returns(uint64 _timestamp, uint256 _expireHeight, uint256 _outAmount, address _sender, address _receiver) {
        Swap memory swap = swaps[_randomNumberHash];
        return (
            swap.timestamp,
            swap.expireHeight,
            swap.outAmount,
            swap.sender,
            swap.receiverAddr
        );
    }

    /// @notice Checks whether a _randomNumberHash can be used to create a hash lock or not.
    ///
    /// @param _randomNumberHash The hash of randomNumber and timestamp
    function hashLockable(bytes32 _randomNumberHash) external view returns (bool) {
        return (swapStates[_randomNumberHash] == States.INVALID);
    }

    /// @notice Checks whether a swap is refundable or not.
    ///
    /// @param _randomNumberHash The hash of randomNumber and timestamp
    function refundable(bytes32 _randomNumberHash) external view returns (bool) {
        return (block.number >= swaps[_randomNumberHash].expireHeight && swapStates[_randomNumberHash] == States.OPEN);
    }

    /// @notice Checks whether a swap is claimable or not.
    ///
    /// @param _randomNumberHash The hash of randomNumber and timestamp
    function claimable(bytes32 _randomNumberHash) external view returns (bool) {
        return (block.number < swaps[_randomNumberHash].expireHeight && swapStates[_randomNumberHash] == States.OPEN);
    }

    /// @notice Calculate the randomNumberHash from randomNumber and timestamp
    ///
    /// @param _randomNumber The random number.
    /// @param _timestamp The timestamp.
    function calRandomNumberHash(bytes32 _randomNumber, uint64 _timestamp) public pure returns (bytes32) {
        return sha256(abi.encodePacked(_randomNumber, _timestamp));
    }
}
