// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

abstract contract JBSablier {
    //*********************************************************************//
    // --------------------- public constant properties ------------------ //
    //*********************************************************************//

    IPRBProxy public proxy;
    IPRBProxyRegistry public constant PROXY_REGISTRY = IPRBProxyRegistry(0x584009E9eDe26e212182c9745F5c000191296a78);
    ISablierV2ProxyPlugin public  immutable proxyPlugin;
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IAllowanceTransfer public constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    
    ISablierV2LockupLinear public sablier;
    ISablierV2ProxyTarget public  immutable proxyTarget;

    IJBDirectory public  directory;
    uint256 public  immutable projectId;
    IJBController3_1 public  controller;

        constructor(
        uint256 _projectId, 
        IJBDirectory _directory, 
        ISablierV2LockupLinear _sablier,
        ISablierV2ProxyPlugin _proxyPlugin,
        ISablierV2ProxyTarget _proxyTarget,
        IJBController3_1 _controller
    )
    {
        projectId = _projectId;

        /// @dev Mainnet JBDirectory as of 8/9/23: 0x65572FB928b46f9aDB7cfe5A4c41226F636161ea
        directory = _directory;

        /// @dev Mainnet SablierV2LockupLinear as of 8/9/23: 0xB10daee1FCF62243aE27776D7a92D39dC8740f95
        sablier = _sablier;

        /// @dev Proxy deployer with plugin https://docs.sablier.com/contracts/v2/guides/proxy-architecture/deploy
        proxyPlugin = _proxyPlugin;

        proxyTarget = _proxyTarget;

        controller = _controller;
    }

}