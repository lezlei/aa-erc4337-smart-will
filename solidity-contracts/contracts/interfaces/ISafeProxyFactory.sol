// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISafeProxyFactory {
    /**
     * @notice Creates a new proxy contract that points to a singleton mastercopy.
     * @param _singleton The address of the mastercopy contract (the Safe L2 blueprint).
     * @param data The calldata used to initialize the new proxy (the setup instructions).
     * @return proxy The address of the newly created proxy contract.
     */
    function createProxy(address _singleton, bytes calldata data)
        external
        returns (address proxy);
}