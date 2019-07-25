# Atomic Swap Contract

## Summary

This contract implement secret hash lock mechanism which enables atomic swap between ERC20 token and any other tokens from different Blockchains which also implement this mechanism. 

## Smart Contract Interface

### Transaction interfaces

1. function **initiate**(bytes32 _secretHashLock, uint256 _timestamp, uint256 _timelock, address _receiverAddr, bytes20 _BEP2Addr, uint256 _outAmount, uint256 _inAmount)
    1. `_timestamp` is supposed to be the time of sending transaction, counted by second.
    2. `_secretHashLock` is the hash of `_secretKey` and `_timestamp`
    3. `_timelock` is the number of blocks to wait before the asset can be refunded
    4. `_receiverAddr` is the Ethereum address of swap counter party
    5. `_BEP2Addr` is the receiver address on Binance Chain. 
    6. `_outAmount` is the swapped out ERC20 token.
    7. `_inAmount` is the expected received BEP2 token on Binance Chain.
    
    Before calling this function, client should call `approve` to approve a certain amount of ERC20 token to swap contract address. Then client should prepare the above parameters and call **initiate**.
    The following steps will be executed:
    1. Check if the `_secretHashLock` has been used already. If true, just abort execution.
    2. Call `transferFrom` to transfer approved token from client address to swap contract address.
    3. Create a swap record and save in a mapper.
        ```
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
        ```
    4. `expireHeight` equals to `block.number + _timelock`.
    5. `sender` equals to `msg.sender`.
    6. Mark `Swap` status to `OPEN`.
    7. Increase swap `index`.
    8. Emit **SwapInitialization** event.
    
2. function **refund**(bytes32 _secretHashLock)
    
    `_secretHashLock` is the hash of `_secretKey` and `_timestamp`
    
    This function will try to refund locked ERC20 token to the swap creator. Anyone can call this function, but the locked ERC20 tokens will only be paid to `Swap.sender`.
    1. Get the `Swap` record by `_secretHashLock`
    2. Check if status of `Swap` is `OPEN`, if false, abort execution.
    3. Compare if the current block height is greater than the `expireHeight`. if false, abort execution.
    4. Transfer `Swap.outAmount` ERC20 token from swap contract address to `Swap.sender`
    5. Mark `Swap` status to `EXPIRED`.
    6. Emit **SwapExpire** event
    
3. function **claim**(bytes32 _secretHashLock, bytes32 _secretKey)
    1. `_secretHashLock` is the hash of `_secretKey` and `_timestamp`
    2. `_secretKey` is a random 32-length byte array. Client should keep it private strictly.
    
    This function will try to claim lock ERC20 token to the `Swap.receiverAddr`. Anyone can call this function, but the locked ERC20 token will only be paid to `Swap.receiverAddr`.
    1. Get the `Swap` record by `_secretHashLock`.
    2. Check if status of `Swap` is `OPEN`, if false, abort execution.
    3. Check if the current block height is less then `Swap.expireHeight`, if false, abort execution.
    4. Verify if `_secretHashLock` equals to the hash of `_secretKey` and `Swap.timestamp`
    5. Save `_secretKey` to `Swap.secretKey` and update `Swap`. Then anyone can get the `secretKey` later.
    6. Transfer `Swap.outAmount` ERC20 token from swap contract address to `Swap.receiverAddr`
    7. Mark `Swap` status to `COMPLETED`.
    8. Emit **SwapCompletion** event

### Query interfaces

1. function **initializable**(bytes32 _secretHashLock) returns (bool)
    
    Judge if the `_secretHashLock` has been used already. If true, then the `_secretHashLock` can't be used for creating another swap.
    
2. function **refundable**(bytes32 _secretHashLock) returns (bool)

    Judge if the asset locked by the specified swap can be refunded or not. If true, anyone can call refund function to refund locked asset to the swap creator.
    
3. function **claimable**(bytes32 _secretHashLock) returns (bool)

    Judge if the asset locked by the specified swap can be claimed or not. If true, anyone can call claim function to transfer locked asset to the `_receiverAddr` address.

4. function **querySwapByHashLock**(bytes32 _secretHashLock) returns (uint256 _timestamp,  uint256 _expireHeight, uint256 _outAmount, uint256 _inAmount, address _sender, address _receiver, bytes20 _BEP2Addr, bytes32 _secretKey, uint8 _status)

    Query swap record by secret hash lock.
    
5. function **querySwapByIndex**(uin256 _index) returns (bytes32 _secretHashLock, uint256 _timestamp, uint256 _expireHeight, uint256 _outAmount, uint256 _inAmount, address _sender, address _receiver, bytes20 _BEP2Addr, bytes32 _secretKey, uint8 _status)

    Query swap record by swap index. The index is a sequence number of a swap. For instance, the index of the first swap is 0.

6. function **index**() returns (uint256 _index)

    Get the next swap index. If the swap contract is new deployed, **index** returns 0. If there are already 100 swaps, then **index** returns 100.

### Event

1. event **SwapInitialization**(address indexed _msgSender, address indexed _receiverAddr, bytes20 _BEP2Addr, uint256 _index, bytes32 _secretHashLock, uint256 _timestamp, uint256 _expireHeight, uint256 _outAmount, uint256 _inAmount);

    Once a swap is created, then event **SwapInitialization** will be emitted. Client can monitor this event to get all new created swaps.

2. event **SwapExpire**(address indexed _msgSender, address indexed _swapSender, bytes32 _secretHashLock);

    One a swap expire height is passed and someone call **refund** function, then event **SwapExpire** will be emitted.
    
3. event **SwapCompletion**(address indexed _msgSender, address indexed _receiverAddr, bytes32 _secretHashLock, bytes32 _secretKey);

    If someone call **claim** to a swap with correct secretKey and the swap expire height is not passed, then event **SwapCompletion** will be emitted. Client can monitor this event to get the secretKey.

