// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Permit2 uses this ERC to validate contract signatures.
contract ERC1271 {
    function isValidSignature(
        bytes32,
        /* hash */ bytes memory /* signature */
    ) public pure returns (bytes4) {
        return this.isValidSignature.selector;
    }
}
