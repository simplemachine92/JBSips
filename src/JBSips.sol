// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {JBSplitAllocationData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol";

contract JBSips is IJBSplitAllocator {


    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return _interfaceId == type(IJBSplitAllocator).interfaceId;
    }

    
    /// @notice Called by a project's payout (JBTerminal) or reserved token distribution split (JBController)
    /// @dev See https://docs.juicebox.money/dev/learn/glossary/split-allocator/
    /// @param _data See https://docs.juicebox.money/dev/api/data-structures/jbsplitallocationdata/
    function allocate(JBSplitAllocationData calldata _data) external payable {}
}