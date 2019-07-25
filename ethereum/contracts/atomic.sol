pragma solidity ^0.5.8;

interface ERC20 {
    function totalSupply() external view returns (uint);
    function balanceOf(address who) external view returns (uint);
    function transfer(address to, uint value) external;
    function allowance(address owner, address spender) external view returns (uint);
    function transferFrom(address from, address to, uint value) external;
    function approve(address spender, uint value) external;
}

contract AtomicSwapper {

    struct Swap {
        uint256 outAmount;
        uint256 inAmount;

        uint256 expireHeight;
        bytes32 secretKey;
        uint256 timestamp;

        address sender;
        address receiverAddr;
        bytes20 BEP2Addr;
    }

    enum States {
        INVALID,
        OPEN,
        COMPLETED,
        EXPIRED
    }

    // Events
    event SwapInitialization(address indexed _msgSender, address indexed _receiverAddr, bytes20 _BEP2Addr, uint256 _index, bytes32 _secretHashLock, uint256 _timestamp, uint256 _expireHeight, uint256 _outAmount, uint256 _inAmount);
    event SwapExpire(address indexed _msgSender, address indexed _swapSender, bytes32 _secretHashLock);
    event SwapCompletion(address indexed _msgSender, address indexed _receiverAddr, bytes32 _secretHashLock, bytes32 _secretKey);

    // Storage
    mapping (bytes32 => Swap) private swaps;
    mapping (bytes32 => States) private swapStates;
    mapping (uint256 => bytes32) private indexToSecretHashLock;

    address public ERC20ContractAddr;
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

    /// @param _erc20Contract The ERC20 contract address
    constructor(address _erc20Contract) public {
        ERC20ContractAddr = _erc20Contract;
        index = 0;
    }

    /// @notice Initiates an atomic swap.
    ///
    /// @param _secretHashLock The hash of the secret key and timestamp
    /// @param _timestamp Counted by second
    /// @param _timelock The number of blocks to wait before the asset can be returned to sender
    /// @param _receiverAddr The ethereum address of the swap counterpart.
    /// @param _BEP2Addr The receiver address on Binance Chain
    /// @param _outAmount ERC20 asset to swap out.
    /// @param _inAmount BEP2 asset to swap in.
    function initiate(
        bytes32 _secretHashLock,
        uint256 _timestamp,
        uint256 _timelock,
        address _receiverAddr,
        bytes20 _BEP2Addr,
        uint256 _outAmount,
        uint256 _inAmount
    ) external onlyInvalidSwaps(_secretHashLock) {
        // Assume average block time interval is 10 second
        // The timelock period should be more than 10 minutes and less than one week
        require(_timelock >= 60 && _timelock <= 60480, "_timelock should be in [60, 60480]");
        // Transfer ERC20 token to the swap contract
        ERC20(ERC20ContractAddr).transferFrom(msg.sender, address(this), _outAmount);
        // Store the details of the swap.
        Swap memory swap = Swap({
            outAmount: _outAmount,
            inAmount: _inAmount,
            expireHeight: _timelock + block.number,
            secretKey: 0x0,
            timestamp: _timestamp,
            sender: msg.sender,
            receiverAddr: _receiverAddr,
            BEP2Addr: _BEP2Addr
            });
        uint256 curIndex = index;

        swaps[_secretHashLock] = swap;
        swapStates[_secretHashLock] = States.OPEN;
        indexToSecretHashLock[curIndex] = _secretHashLock;
        index = index + 1;

        // Emit initialization event
        emit SwapInitialization(msg.sender, _receiverAddr, _BEP2Addr, curIndex,  _secretHashLock, _timestamp, swap.expireHeight, _outAmount, _inAmount);
    }

    /// @notice Claims an atomic swap.
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    /// @param _secretKey The secret of the atomic swap.
    function claim(bytes32 _secretHashLock, bytes32 _secretKey) external onlyBeforeExpireHeight(_secretHashLock) onlyOpenSwaps(_secretHashLock) onlyWithSecretKey(_secretHashLock, _secretKey) {
        // Complete the swap.
        swaps[_secretHashLock].secretKey = _secretKey;
        swapStates[_secretHashLock] = States.COMPLETED;

        // Pay erc20 token to receiver
        ERC20(ERC20ContractAddr).transfer(swaps[_secretHashLock].receiverAddr, swaps[_secretHashLock].outAmount);

        // Emit completion event
        emit SwapCompletion(msg.sender, swaps[_secretHashLock].receiverAddr, _secretHashLock, _secretKey);
    }

    /// @notice Refunds an atomic swap.
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    function refund(bytes32 _secretHashLock) external onlyOpenSwaps(_secretHashLock) onlyAfterExpireHeight(_secretHashLock) {
        // Expire the swap.
        swapStates[_secretHashLock] = States.EXPIRED;

        // refund erc20 token to swap creator
        ERC20(ERC20ContractAddr).transfer(swaps[_secretHashLock].sender, swaps[_secretHashLock].outAmount);

        // Emit expire event
        emit SwapExpire(msg.sender, swaps[_secretHashLock].sender, _secretHashLock);
    }

    /// @notice query an atomic swap by secretHashLock
    ///
    /// @param _secretHashLock The hash of secretKey and timestamp
    function querySwapByHashLock(bytes32 _secretHashLock) external view returns(uint256 _timestamp, uint256 _expireHeight, uint256 _outAmount, uint256 _inAmount, address _sender, address _receiver, bytes20 _BEP2Addr, bytes32 _secretKey, States _status) {
        Swap memory swap = swaps[_secretHashLock];
        States status = swapStates[_secretHashLock];
        return (
            swap.timestamp,
            swap.expireHeight,
            swap.outAmount,
            swap.inAmount,
            swap.sender,
            swap.receiverAddr,
            swap.BEP2Addr,
            swap.secretKey,
            status
        );
    }

    /// @notice query an atomic swap by swap index
    ///
    /// @param _index The swap index
    function querySwapByIndex(uint256 _index) external view returns (bytes32 _secretHashLock, uint256 _timestamp, uint256 _expireHeight, uint256 _outAmount, uint256 _inAmount, address _sender, address _receiver, bytes20 _BEP2Addr, bytes32 _secretKey, States _status) {
        bytes32 secretHashLock = indexToSecretHashLock[_index];
        Swap memory swap = swaps[secretHashLock];
        States status = swapStates[secretHashLock];
        return (
            secretHashLock,
            swap.timestamp,
            swap.expireHeight,
            swap.outAmount,
            swap.inAmount,
            swap.sender,
            swap.receiverAddr,
            swap.BEP2Addr,
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
    function calSecretHash(bytes32 _secretKey, uint256 _timestamp) public pure returns (bytes32) {
        return sha256(abi.encodePacked(_secretKey, _timestamp));
    }
}