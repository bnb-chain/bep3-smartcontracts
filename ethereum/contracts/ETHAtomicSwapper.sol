pragma solidity ^0.5.8;

contract ETHAtomicSwapper {

    struct Swap {
        uint256 ETHCoin;
        uint256 bep2Amount;

        uint256 expireHeight;
        bytes32 secretKey;
        uint64  timestamp;

        address payable sender;
        address payable receiverAddr;
        bytes20 bep2Addr;
    }

    enum States {
        INVALID,
        OPEN,
        COMPLETED,
        EXPIRED
    }

    // Events
    event SwapInit(address indexed _msgSender, address indexed _receiverAddr, bytes20 _bep2Addr, uint256 _index, bytes32 _secretHashLock, uint64 _timestamp, uint256 _expireHeight, uint256 _ETHCoin, uint256 _bep2Amount);
    event SwapExpire(address indexed _msgSender, address indexed _swapSender, bytes32 _secretHashLock);
    event SwapComplete(address indexed _msgSender, address indexed _receiverAddr, bytes32 _secretHashLock, bytes32 _secretKey);

    // Storage
    mapping (bytes32 => Swap) private swaps;
    mapping (bytes32 => States) private swapStates;
    mapping (uint256 => bytes32) private indexToSecretHashLock;

    uint256 public index;

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

    constructor() public {
        index = 0;
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
        // Store the details of the swap.
        Swap memory swap = Swap({
            ETHCoin: msg.value,
            bep2Amount: _bep2Amount,
            expireHeight: _timelock + block.number,
            secretKey: 0x0,
            timestamp: _timestamp,
            sender: msg.sender,
            receiverAddr: _receiverAddr,
            bep2Addr: _bep2Addr
            });
        uint256 curIndex = index;

        swaps[_secretHashLock] = swap;
        swapStates[_secretHashLock] = States.OPEN;
        indexToSecretHashLock[curIndex] = _secretHashLock;
        index = index + 1;

        // Emit initialization event
        emit SwapInit(msg.sender, _receiverAddr, _bep2Addr, curIndex,  _secretHashLock, _timestamp, swap.expireHeight, msg.value, _bep2Amount);
        return true;
    }

    /// @notice Claims an atomic swap.
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    /// @param _secretKey The secret of the atomic swap.
    function claim(bytes32 _secretHashLock, bytes32 _secretKey) external onlyBeforeExpireHeight(_secretHashLock) onlyOpenSwaps(_secretHashLock) onlyWithSecretKey(_secretHashLock, _secretKey) returns (bool) {
        // Complete the swap.
        swaps[_secretHashLock].secretKey = _secretKey;
        swapStates[_secretHashLock] = States.COMPLETED;

        // Pay eth coin to receiver
        swaps[_secretHashLock].receiverAddr.transfer(swaps[_secretHashLock].ETHCoin);

        // Emit completion event
        emit SwapComplete(msg.sender, swaps[_secretHashLock].receiverAddr, _secretHashLock, _secretKey);

        return true;
    }

    /// @notice Refunds an atomic swap.
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    function refund(bytes32 _secretHashLock) external onlyOpenSwaps(_secretHashLock) onlyAfterExpireHeight(_secretHashLock) returns (bool) {
        // Expire the swap.
        swapStates[_secretHashLock] = States.EXPIRED;

        // refund eth coin to swap creator
        swaps[_secretHashLock].sender.transfer(swaps[_secretHashLock].ETHCoin);

        // Emit expire event
        emit SwapExpire(msg.sender, swaps[_secretHashLock].sender, _secretHashLock);

        return true;
    }

    /// @notice query an atomic swap by secretHashLock
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    function querySwapByHashLock(bytes32 _secretHashLock) external view returns(uint64 _timestamp, uint256 _expireHeight, uint256 _ETHCoin, uint256 _bep2Amount, address _sender, address _receiver, bytes20 _bep2Addr, bytes32 _secretKey, States _status) {
        Swap memory swap = swaps[_secretHashLock];
        States status = swapStates[_secretHashLock];
        return (
        swap.timestamp,
        swap.expireHeight,
        swap.ETHCoin,
        swap.bep2Amount,
        swap.sender,
        swap.receiverAddr,
        swap.bep2Addr,
        swap.secretKey,
        status
        );
    }

    /// @notice query an atomic swap by swap index
    ///
    /// @param _index The swap index
    function querySwapByIndex(uint256 _index) external view returns (bytes32 _secretHashLock, uint64 _timestamp, uint256 _expireHeight, uint256 _ETHCoin, uint256 _bep2Amount, address _sender, address _receiver, bytes20 _bep2Addr, bytes32 _secretKey, States _status) {
        bytes32 secretHashLock = indexToSecretHashLock[_index];
        Swap memory swap = swaps[secretHashLock];
        States status = swapStates[secretHashLock];
        return (
        secretHashLock,
        swap.timestamp,
        swap.expireHeight,
        swap.ETHCoin,
        swap.bep2Amount,
        swap.sender,
        swap.receiverAddr,
        swap.bep2Addr,
        swap.secretKey,
        status
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
