// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* 
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
 */

import {JBSablier} from "../src/abstract/JBSablier.sol";

import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBDirectory} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import {JBSplitAllocationData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol";
import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";

import { IPRBProxy, IPRBProxyRegistry } from "@sablier/v2-periphery/types/Proxy.sol";

import { ISablierV2LockupDynamic } from "@sablier/v2-core/interfaces/ISablierV2LockupDynamic.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/interfaces/ISablierV2LockupLinear.sol";
import { Broker, LockupLinear, LockupDynamic } from "@sablier/v2-core/types/DataTypes.sol";
import { ud60x18, ud2x18 } from "@sablier/v2-core/types/Math.sol";

import { IERC20 } from "@sablier/v2-core/types/Tokens.sol";
import { Batch } from "@sablier/v2-periphery/types/DataTypes.sol";
import { IAllowanceTransfer, Permit2Params } from "@sablier/v2-periphery/types/Permit2.sol";

/** 
 * @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVS MEAM
 *
 * @title Juicebox Sips
 *
 * @author noobwonder.eth
 *
 * @notice Split Allocator Treasury Extension acting as a Sablier v2 Stream Manager, Deployer, and hub for users to
 *         interact with Sablier v2 streams of which they are the beneficiary.
 * @dev -- notes n stuff --
*/
contract JBSips is JBSablier, JBOperatable, IJBSplitAllocator {

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JuiceSips_Unauthorized();

    //*********************************************************************//
    // -----------------------------  events ----------------------------- //
    //*********************************************************************//

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    mapping(address => uint256) public idByAddress;
    address[] public benefics;

    //*********************************************************************//
    // -------------------------- constructor ---------------------------- //
    //*********************************************************************//

    constructor(
        uint256 _projectId, 
        address _directory, 
        address _operatorStore,
        address _lockupLinear,
        address _lockupDynamic,
        address _proxyPlugin,
        address _proxyTarget,
        address _controller
        )
        JBSablier(
            _projectId,
            _directory,
            _lockupLinear,
            _lockupDynamic,
            _proxyPlugin,
            _proxyTarget,
            _controller
        )
        JBOperatable(IJBOperatorStore(_operatorStore))
    {
       /* --- */
    }

    /// @notice Called by a project's payout (JBTerminal) or reserved token distribution split (JBController)
    /// @dev See https://docs.juicebox.money/dev/learn/glossary/split-allocator/
    /// @param _data See https://docs.juicebox.money/dev/api/data-structures/jbsplitallocationdata/
    function allocate(JBSplitAllocationData calldata _data) external payable {
        // Ensure call is coming from Terminal or Controller
        if (!directory.isTerminalOf(_data.projectId, IJBPaymentTerminal(msg.sender))
            && directory.controllerOf(_data.projectId) != msg.sender)
        revert JuiceSips_Unauthorized();
        
        // Logic for payouts
        if (directory.isTerminalOf(_data.projectId, IJBPaymentTerminal(msg.sender))) {}

        /* // Logic for reserved token ditribution split (bonus implementation, not the focus rn)
        if (directory.controllerOf(_data.projectId) == msg.sender) {} */

    }

    function batchDeploy() external returns (uint256[] memory streamIds) {
        if (address(proxy) == address(0)) deployProxyAndInstallPlugin();

        uint256 batchSize = benefics.length;

    }

    function deployProxyAndInstallPlugin() public returns (IPRBProxy proxy) {
        // Get the proxy for this contract
        proxy = PROXY_REGISTRY.getProxy({ user: address(this) });
        if (address(proxy) == address(0)) {
            // If a proxy doesn't exist, deploy one and install the plugin
            proxy = PROXY_REGISTRY.deployAndInstallPlugin({ plugin: proxyPlugin });
        } else {
            // If the proxy exists, then just install the plugin.
            PROXY_REGISTRY.installPlugin({ plugin: proxyPlugin });
        }
    }

    function withdrawFromStream() external {}

    function configureRecipients()
        external requirePermission(controller.projects().ownerOf(projectId), projectId, JBOperations.SET_SPLITS) {}

    function cancelStreams()
        external requirePermission(controller.projects().ownerOf(projectId), projectId, JBOperations.SET_SPLITS) {}

    // Function to receive Ether. msg.data must be empty
    receive() external payable {}

}