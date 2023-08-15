// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1271} from "./ERC1271.sol";

import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBDirectory} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";

import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";

import { ISablierV2ProxyTarget } from "@sablier/v2-periphery/interfaces/ISablierV2ProxyTarget.sol";
import { IPRBProxy, IPRBProxyRegistry } from "@sablier/v2-periphery/types/Proxy.sol";
import { ISablierV2ProxyPlugin } from "@sablier/v2-periphery/interfaces/ISablierV2ProxyPlugin.sol";

import { ISablierV2LockupDynamic } from "@sablier/v2-core/interfaces/ISablierV2LockupDynamic.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/interfaces/ISablierV2LockupLinear.sol";

import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC20 } from "@sablier/v2-core/types/Tokens.sol";

import { IAllowanceTransfer, Permit2Params } from "@sablier/v2-periphery/types/Permit2.sol";

abstract contract JBSablier is ERC165, ERC1271 {
    //*********************************************************************//
    // --------------------- public constant properties ------------------ //
    //*********************************************************************//

    uint256 public immutable projectId;
    IJBDirectory public directory;
    IJBController3_1 public controller;

    IPRBProxy public proxy;
    ISablierV2LockupLinear public lockupLinear;
    ISablierV2LockupDynamic public lockupDynamic;
    ISablierV2ProxyTarget public proxyTarget;
    ISablierV2ProxyPlugin public proxyPlugin;

    IPRBProxyRegistry public constant PROXY_REGISTRY = 
        IPRBProxyRegistry(0x584009E9eDe26e212182c9745F5c000191296a78);
    IAllowanceTransfer public constant PERMIT2 = 
        IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    constructor(
        uint256 _projectId, 
        address _directory, 
        address _lockupLinear,
        address _lockupDynamic,
        address _proxyPlugin,
        address _proxyTarget,
        address _controller
    )
    {
        projectId = _projectId;

        /// @dev Mainnet JBDirectory as of 8/9/23: 0x65572FB928b46f9aDB7cfe5A4c41226F636161ea
        directory = IJBDirectory(_directory);

        /// @dev Mainnet SablierV2LockupLinear as of 8/9/23: 0xB10daee1FCF62243aE27776D7a92D39dC8740f95
        lockupLinear = ISablierV2LockupLinear(_lockupLinear);

        lockupDynamic = ISablierV2LockupDynamic(_lockupDynamic);

        /// @dev Proxy deployer with plugin https://docs.sablier.com/contracts/v2/guides/proxy-architecture/deploy
        proxyPlugin = ISablierV2ProxyPlugin(_proxyPlugin);

        proxyTarget = ISablierV2ProxyTarget(_proxyTarget);

        controller = IJBController3_1(_controller);
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override(ERC165) returns (bool) {
        return _interfaceId == type(IJBSplitAllocator).interfaceId || super.supportsInterface(_interfaceId);
    }


}