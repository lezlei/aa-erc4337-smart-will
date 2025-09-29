// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// This file now contains everything your module needs to know about a Safe.
// It is completely self-contained and requires no external imports.

library Enum {
    enum Operation {
        Call,
        DelegateCall
    }
}

interface ISafe {
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external returns (bool success);
}