# Atomic Swap Contract

## Summary

This contract implement secret hash lock mechanism which enables atomic swap between ERC20 token and BEP2 tokens on BNB Beacon Chain. 

## Smart Contract Interface

### Transaction interfaces

1. function **htlt**(bytes32 _randomNumberHash, uint64  _timestamp, uint256 _heightSpan, address _recipientAddr, bytes20 _bep2SenderAddr, bytes20 _bep2RecipientAddr, uint256 _outAmount, uint256 _bep2Amount)
    1. `_timestamp` is supposed to be the time of sending transaction, counted by second. If this htlt is response to another htlt on other chain, then their timestamp should be identical.
    2. `_randomNumberHash` sha256(_randomNumber, _timestamp)
    3. `_heightSpan` is the number of blocks to wait before the asset can be refunded
    4. `_recipientAddr` is the Ethereum address of swap counter party
    5. `_bep2SenderAddr` is the swap sender address on BNB Beacon Chain
    5. `_bep2RecipientAddr` is the receiver address on BNB Beacon Chain. 
    6. `_outAmount` is the recipient address on BNB Beacon Chain.
    7. `_bep2Amount` is the expected received BEP2 token on BNB Beacon Chain.
    
2. function **refund**(bytes32 _swapID)
    
    `_swapID` sha256(swap.randomNumberHash, swap.From, swap.SenderOtherChain)
    
3. function **claim**(bytes32 _swapID, bytes32 _randomNumber)
    1. `_swapID` sha256(swap.randomNumberHash, swap.From, swap.SenderOtherChain)
    2. `_randomNumber` is a random 32-length byte array. Client should keep it private strictly.

### Query interfaces

1. function **isSwapExist**(bytes32 _swapID) returns (bool)
    
    Judge if the `_swapID` has been used already.
    
2. function **refundable**(bytes32 _swapID) returns (bool)

    Judge if the asset locked by the specified swap can be refunded or not. If true, anyone can call refund function to refund locked asset to the swap creator.
    
3. function **claimable**(bytes32 _swapID) returns (bool)

    Judge if the asset locked by the specified swap can be claimed or not. If true, anyone can call claim function to transfer locked asset to the `_receiverAddr` address.
    
5. function **queryOpenSwap**(uin256 _swapID) returns (bytes32 _randomNumberHash, uint64 _timestamp, uint256 _expireHeight, uint256 _outAmount, address _sender, address _recipient)

    Query an opened swap record by swapID.

### Event

1. event **HTLT**(address indexed _msgSender, address indexed _recipientAddr, bytes32 indexed _swapID, bytes32 _randomNumberHash, uint64 _timestamp, bytes20 _bep2Addr, uint256 _expireHeight, uint256 _outAmount, uint256 _bep2Amount);

    Once a swap is created, then this event will be emitted. Client can monitor this event to get all new created swaps.

2. event **Refunded**(address indexed _msgSender, address indexed _recipientAddr, bytes32 indexed _swapID, bytes32 _randomNumberHash);

    One a swap expire height is passed and someone call **refund** function, then this event will be emitted.
    
3. event **Claimed**(address indexed _msgSender, address indexed _recipientAddr, bytes32 indexed _swapID, bytes32 _randomNumberHash, bytes32 _randomNumber);

    If someone call **claim** to a swap with correct secretKey and the swap expire height is not passed, then this event will be emitted. Client can monitor this event to get the secretKey.

