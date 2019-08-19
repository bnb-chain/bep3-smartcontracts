pragma solidity ^0.5.8;

contract ETHAtomicSwapper {

    struct Swap {
        uint256 outAmount;
        uint256 expireHeight;
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
    event SwapInit(address indexed _msgSender, address indexed _receiverAddr, bytes32 indexed _secretHashLock, uint64 _timestamp, bytes20 _bep2Addr, uint256 _expireHeight, uint256 _outAmount, uint256 _bep2Amount);
    event SwapExpire(address indexed _msgSender, address indexed _swapSender, bytes32 indexed _secretHashLock);
    event SwapComplete(address indexed _msgSender, address indexed _receiverAddr, bytes32 indexed _secretHashLock, bytes32 _secretKey);

    // Storage
    mapping (bytes32 => Swap) private swaps;
    mapping (bytes32 => States) private swapStates;

    /// @notice Throws if the swap is not invalid (i.e. has already been used)
    modifier onlyInvalidSwaps(bytes32 _secretHashLock) {
        require(swapStates[_secretHashLock] == States.INVALID, "swap is opened previously");
        _;
    }

    /// @notice Throws if the swap is not open.
    modifier onlyOpenSwaps(bytes32 _secretHashLock) {
        require(swapStates[_secretHashLock] == States.OPEN, "swap is not opened");
        _;
    }

    /// @notice Throws if the swap is already expired.
    modifier onlyAfterExpireHeight(bytes32 _secretHashLock) {
        /* solium-disable-next-line security/no-block-members */
        require(block.number >= swaps[_secretHashLock].expireHeight, "swap is not expired");
        _;
    }

    /// @notice Throws if the expireHeight is reached
    modifier onlyBeforeExpireHeight(bytes32 _secretHashLock) {
        /* solium-disable-next-line security/no-block-members */
        require(block.number < swaps[_secretHashLock].expireHeight, "swap is already expired");
        _;
    }

    /// @notice Throws if the secret key is not valid.
    modifier onlyWithSecretKey(bytes32 _secretHashLock, bytes32 _secretKey) {
        require(_secretHashLock == calSecretHash(_secretKey, swaps[_secretHashLock].timestamp), "invalid secretKey");
        _;
    }

    /// @notice Initiates an atomic swap.
    ///
    /// @param _secretHashLock The hash of the secret key and timestamp
    /// @param _timestamp Counted by second
    /// @param _timelock The number of blocks to wait before the asset can be returned to sender
    /// @param _receiverAddr The ethereum address of the swap counterpart.
    /// @param _bep2Addr The receiver address on Binance Chain
    /// @param _bep2Amount BEP2 asset to swap in.
    function initiate(
        bytes32 _secretHashLock,
        uint64  _timestamp,
        uint256 _timelock,
        address payable _receiverAddr,
        bytes20 _bep2Addr,
        uint256 _bep2Amount
    ) external onlyInvalidSwaps(_secretHashLock) payable returns (bool) {
        // Assume average block time interval is 10 second
        // The timelock period should be more than 10 minutes and less than one week
        require(_timelock >= 60 && _timelock <= 60480, "_timelock should be in [60, 60480]");
        require(_receiverAddr != address(0), "_receiverAddr should not be zero");
        require(_timestamp >= now - 7200 && _timestamp <= now + 3600, "The timestamp should not be one hour ahead or two hour behind current time");
        // Store the details of the swap.
        Swap memory swap = Swap({
            outAmount: msg.value,
            expireHeight: _timelock + block.number,
            timestamp: _timestamp,
            sender: msg.sender,
            receiverAddr: _receiverAddr
            });

        swaps[_secretHashLock] = swap;
        swapStates[_secretHashLock] = States.OPEN;

        // Emit initialization event
        emit SwapInit(msg.sender, _receiverAddr, _secretHashLock, _timestamp, _bep2Addr, swap.expireHeight, msg.value, _bep2Amount);
        return true;
    }

    /// @notice Claims an atomic swap.
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    /// @param _secretKey The secret of the atomic swap.
    function claim(bytes32 _secretHashLock, bytes32 _secretKey) external onlyOpenSwaps(_secretHashLock) onlyBeforeExpireHeight(_secretHashLock) onlyWithSecretKey(_secretHashLock, _secretKey) returns (bool) {
        // Complete the swap.
        swapStates[_secretHashLock] = States.COMPLETED;

        // Pay eth coin to receiver
        swaps[_secretHashLock].receiverAddr.transfer(swaps[_secretHashLock].outAmount);

        address receiverAddr = swaps[_secretHashLock].receiverAddr;

        // delete closed swap
        delete swaps[_secretHashLock];

        // Emit completion event
        emit SwapComplete(msg.sender, receiverAddr, _secretHashLock, _secretKey);

        return true;
    }

    /// @notice Refunds an atomic swap.
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    function refund(bytes32 _secretHashLock) external onlyOpenSwaps(_secretHashLock) onlyAfterExpireHeight(_secretHashLock) returns (bool) {
        // Expire the swap.
        swapStates[_secretHashLock] = States.EXPIRED;

        // refund eth coin to swap creator
        swaps[_secretHashLock].sender.transfer(swaps[_secretHashLock].outAmount);

        address swapSender = swaps[_secretHashLock].sender;

        // delete closed swap
        delete swaps[_secretHashLock];

        // Emit expire event
        emit SwapExpire(msg.sender, swapSender, _secretHashLock);

        return true;
    }

    /// @notice query an atomic swap by secretHashLock
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    function queryOpenSwap(bytes32 _secretHashLock) external view returns(uint64 _timestamp, uint256 _expireHeight, uint256 _outAmount, address _sender, address _receiver) {
        Swap memory swap = swaps[_secretHashLock];
        return (
        swap.timestamp,
        swap.expireHeight,
        swap.outAmount,
        swap.sender,
        swap.receiverAddr
        );
    }

    /// @notice Checks whether a _secretHashLock is initializable or not.
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    function initializable(bytes32 _secretHashLock) external view returns (bool) {
        return (swapStates[_secretHashLock] == States.INVALID);
    }

    /// @notice Checks whether a swap is refundable or not.
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    function refundable(bytes32 _secretHashLock) external view returns (bool) {
        /* solium-disable-next-line security/no-block-members */
        return (block.number >= swaps[_secretHashLock].expireHeight && swapStates[_secretHashLock] == States.OPEN);
    }

    /// @notice Checks whether a swap is claimable or not.
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    function claimable(bytes32 _secretHashLock) external view returns (bool) {
        return (block.number < swaps[_secretHashLock].expireHeight && swapStates[_secretHashLock] == States.OPEN);
    }

    /// @notice Calculate the secretHashLock from secretKey and timestamp
    ///
    /// @param _secretKey The secret.
    /// @param _timestamp The timestamp.
    function calSecretHash(bytes32 _secretKey, uint64 _timestamp) public pure returns (bytes32) {
        return sha256(abi.encodePacked(_secretKey, _timestamp));
    }
}