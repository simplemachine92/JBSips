// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IJBSips {
    struct JBSplit {
        bool preferClaimed;
        bool preferAddToBalance;
        uint256 percent;
        uint256 projectId;
        address beneficiary;
        uint256 lockedUntil;
        address allocator;
    }

    struct JBSplitAllocationData {
        address token;
        uint256 amount;
        uint256 decimals;
        uint256 projectId;
        uint256 group;
        JBSplit split;
    }

    function allocate(JBSplitAllocationData memory _data) external payable;

    function cancelStreams() external;

    function configureRecipients() external;

    function controller() external view returns (address);

    function directory() external view returns (address);

    function idByAddress(address) external view returns (uint256);

    function operatorStore() external view returns (address);

    function projectId() external view returns (uint256);

    function sablier() external view returns (address);

    function supportsInterface(
        bytes4 _interfaceId
    ) external view returns (bool);

    function withdrawFromStream() external;
}
