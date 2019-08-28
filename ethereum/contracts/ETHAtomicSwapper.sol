pragma solidity 0.5.8;

contract ETHAtomicSwapper {

    struct Swap {
        uint256 outAmount;
        uint256 expireHeight;
        bytes32 randomNumberHash;
        uint64  timestamp;
        address payable sender;
        address payable receiverAddr;
    }

    enum States {
        INVALID,
        OPEN,
        COMPLETED,
        EXPIRED
    }

    // Events
    event HTLT(address indexed _msgSender, address indexed _receiverAddr, bytes32 indexed _swapID, bytes32 _randomNumberHash, uint64 _timestamp, bytes20 _bep2Addr, uint256 _expireHeight, uint256 _outAmount, uint256 _bep2Amount);
    event Refunded(address indexed _msgSender, address indexed _swapSender, bytes32 indexed _swapID, bytes32 _randomNumberHash);
    event Claimed(address indexed _msgSender, address indexed _receiverAddr, bytes32 indexed _swapID, bytes32 _randomNumberHash, bytes32 _randomNumber);

    // Storage
    mapping (bytes32 => Swap) private swaps;
    mapping (bytes32 => States) private swapStates;

    /// @notice Throws if the swap is not invalid (i.e. has already been used)
    modifier onlyInvalidSwaps(bytes32 _randomNumberHash) {
        require(swapStates[_randomNumberHash] == States.INVALID, "swap is opened previously");
        _;
    }

    /// @notice Throws if the swap is not open.
    modifier onlyOpenSwaps(bytes32 _swapID) {
        require(swapStates[_swapID] == States.OPEN, "swap is not opened");
        _;
    }

    /// @notice Throws if the swap is already expired.
    modifier onlyAfterExpireHeight(bytes32 _swapID) {
        require(block.number >= swaps[_swapID].expireHeight, "swap is not expired");
        _;
    }

    /// @notice Throws if the expireHeight is reached
    modifier onlyBeforeExpireHeight(bytes32 _swapID) {
        require(block.number < swaps[_swapID].expireHeight, "swap is already expired");
        _;
    }

    /// @notice Throws if the random number is not valid.
    modifier onlyWithRandomNumber(bytes32 _swapID, bytes32 _randomNumber) {
        require(swaps[_swapID].randomNumberHash == sha256(abi.encodePacked(_randomNumber, swaps[_swapID].timestamp)), "invalid randomNumber");
        _;
    }

    /// @notice htlt locks asset to contract address and create an atomic swap.
    ///
    /// @param _randomNumberHash The hash of the random number and timestamp
    /// @param _timestamp Counted by second
    /// @param _heightSpan The number of blocks to wait before the asset can be returned to sender
    /// @param _receiverAddr The ethereum address of the swap counterpart.
    /// @param _bep2Addr The receiver address on Binance Chain
    /// @param _bep2Amount BEP2 asset to swap in.
    function htlt(
        bytes32 _randomNumberHash,
        uint64  _timestamp,
        uint256 _heightSpan,
        address payable _receiverAddr,
        bytes20 _bep2Addr,
        uint256 _bep2Amount
    ) external payable returns (bool) {
        require(msg.value > 0, "msg.value must be more than 0");
        bytes32 swapID = sha256(abi.encodePacked(_randomNumberHash, msg.sender));
        require(swapStates[swapID] == States.INVALID, "swap is opened previously");
        // Assume average block time interval is 10 second
        // The heightSpan period should be more than 10 minutes and less than one week
        require(_heightSpan >= 60 && _heightSpan <= 60480, "_heightSpan should be in [60, 60480]");
        require(_receiverAddr != address(0), "_receiverAddr should not be zero");
        require(_timestamp > now -7200 && _timestamp < now + 3600, "The timestamp should not be one hour ahead or two hour behind current time");
        // Store the details of the swap.
        Swap memory swap = Swap({
            outAmount: msg.value,
            expireHeight: _heightSpan + block.number,
            randomNumberHash: _randomNumberHash,
            timestamp: _timestamp,
            sender: msg.sender,
            receiverAddr: _receiverAddr
            });

        swaps[swapID] = swap;
        swapStates[swapID] = States.OPEN;

        // Emit initialization event
        emit HTLT(msg.sender, _receiverAddr, swapID, _randomNumberHash, _timestamp, _bep2Addr, swap.expireHeight, msg.value, _bep2Amount);
        return true;
    }

    /// @notice claim claims the previously locked asset.
    ///
    /// @param _swapID The hash of randomNumberHash and swap creator
    /// @param _randomNumber The random number
    function claim(bytes32 _swapID, bytes32 _randomNumber) external onlyOpenSwaps(_swapID) onlyBeforeExpireHeight(_swapID) onlyWithRandomNumber(_swapID, _randomNumber) returns (bool) {
        // Complete the swap.
        swapStates[_swapID] = States.COMPLETED;

        address payable receiverAddr = swaps[_swapID].receiverAddr;
        uint256 outAmount = swaps[_swapID].outAmount;
        bytes32 randomNumberHash = swaps[_swapID].randomNumberHash;
        // delete closed swap
        delete swaps[_swapID];

        // Pay eth coin to receiver
        receiverAddr.transfer(outAmount);

        // Emit completion event
        emit Claimed(msg.sender, receiverAddr, _swapID, randomNumberHash, _randomNumber);

        return true;
    }

    /// @notice refund refunds the previously locked asset.
    ///
    /// @param _swapID The hash of randomNumberHash and swap creator
    function refund(bytes32 _swapID) external onlyOpenSwaps(_swapID) onlyAfterExpireHeight(_swapID) returns (bool) {
        // Expire the swap.
        swapStates[_swapID] = States.EXPIRED;

        address payable swapSender = swaps[_swapID].sender;
        uint256 outAmount = swaps[_swapID].outAmount;
        bytes32 randomNumberHash = swaps[_swapID].randomNumberHash;
        // delete closed swap
        delete swaps[_swapID];

        // refund eth coin to swap creator
        swapSender.transfer(outAmount);

        // Emit expire event
        emit Refunded(msg.sender, swapSender, _swapID, randomNumberHash);

        return true;
    }

    /// @notice query an atomic swap by randomNumberHash
    ///
    /// @param _swapID The hash of randomNumberHash and swap creator
    function queryOpenSwap(bytes32 _swapID) external view returns(bytes32 _randomNumberHash, uint64 _timestamp, uint256 _expireHeight, uint256 _outAmount, address _sender, address _receiver) {
        Swap memory swap = swaps[_swapID];
        return (
            swap.randomNumberHash,
            swap.timestamp,
            swap.expireHeight,
            swap.outAmount,
            swap.sender,
            swap.receiverAddr
        );
    }

    /// @notice Checks whether a swap with specified swapID exist
    ///
    /// @param _swapID The hash of randomNumberHash and swap creator
    function swapExistence(bytes32 _swapID) external view returns (bool) {
        return (swapStates[_swapID] == States.INVALID);
    }

    /// @notice Checks whether a swap is refundable or not.
    ///
    /// @param _swapID The hash of randomNumberHash and swap creator
    function refundable(bytes32 _swapID) external view returns (bool) {
        return (block.number >= swaps[_swapID].expireHeight && swapStates[_swapID] == States.OPEN);
    }

    /// @notice Checks whether a swap is claimable or not.
    ///
    /// @param _swapID The hash of randomNumberHash and swap creator
    function claimable(bytes32 _swapID) external view returns (bool) {
        return (block.number < swaps[_swapID].expireHeight && swapStates[_swapID] == States.OPEN);
    }

    /// @notice Calculate the swapID from randomNumberHash and swapCreator
    ///
    /// @param _randomNumberHash The hash of random number and timestamp.
    /// @param _swapCreator The creator of swap.
    function calSwapID(bytes32 _randomNumberHash, address _swapCreator) public pure returns (bytes32) {
        return sha256(abi.encodePacked(_randomNumberHash, _swapCreator));
    }
}