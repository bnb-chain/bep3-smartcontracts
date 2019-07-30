# Atomic Swap Contract

## Construct test environment

1. Install truffle and ganache-cli
    ```
    npm install
    ```
2. Start Ethereum test environment
    ```
    npm run ganache
    ```

## Run deploy tests and functionality tests.
1. Run deploy tests:
    ```
    npm run migration
    ```
2. Run functionality tests:
    ```
    npm run test
    ```
    
## Specification

Please refer to [ERC20 swap](spec/ERC20AtomicSwap.md) and [ETH swap](spec/ETHAtomicSwap.md)
