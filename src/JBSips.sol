// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBDirectory} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";

import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import {JBSplitAllocationData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol";
import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";

import { ISablierV2ProxyTarget } from "@sablier/v2-periphery/interfaces/ISablierV2ProxyTarget.sol";
import { IPRBProxy, IPRBProxyRegistry } from "@sablier/v2-periphery/types/Proxy.sol";
import { ISablierV2ProxyPlugin } from "@sablier/v2-periphery/interfaces/ISablierV2ProxyPlugin.sol";

import { ISablierV2LockupDynamic } from "@sablier/v2-core/interfaces/ISablierV2LockupDynamic.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/interfaces/ISablierV2LockupLinear.sol";
import { Broker, LockupLinear, LockupDynamic } from "@sablier/v2-core/types/DataTypes.sol";
import { ud60x18, ud2x18 } from "@sablier/v2-core/types/Math.sol";

import { IERC20 } from "@sablier/v2-core/types/Tokens.sol";
import { Batch, Broker } from "@sablier/v2-periphery/types/DataTypes.sol";
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
contract JBSips is IJBSplitAllocator, JBOperatable, ERC165 {

    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JuiceSips_Unauthorized();

    //*********************************************************************//
    // -----------------------------  events ----------------------------- //
    //*********************************************************************//

    //*********************************************************************//
    // --------------------- public constant properties ------------------ //
    //*********************************************************************//

    IPRBProxy public proxy;
    IPRBProxyRegistry public constant PROXY_REGISTRY = IPRBProxyRegistry(0x584009E9eDe26e212182c9745F5c000191296a78);
    ISablierV2ProxyPlugin public immutable proxyPlugin;
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IAllowanceTransfer public constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    
    ISablierV2LockupLinear public sablier;
    ISablierV2ProxyTarget public immutable proxyTarget;

    IJBDirectory public directory;
    uint256 public immutable projectId;
    IJBController3_1 public controller;

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    mapping(address => uint256) public idByAddress;

    constructor(
        uint256 _projectId, 
        IJBDirectory _directory, 
        IJBOperatorStore _operatorStore,
        ISablierV2LockupLinear _sablier,
        ISablierV2ProxyPlugin proxyPlugin_,
        IJBController3_1 _controller
    )   JBOperatable(_operatorStore) 
    {
        projectId = _projectId;

        /// @dev Mainnet JBDirectory as of 8/9/23: 0x65572FB928b46f9aDB7cfe5A4c41226F636161ea
        directory = _directory;

        /// @dev Mainnet SablierV2LockupLinear as of 8/9/23: 0xB10daee1FCF62243aE27776D7a92D39dC8740f95
        sablier = _sablier;

        /// @dev Proxy deployer with plugin https://docs.sablier.com/contracts/v2/guides/proxy-architecture/deploy
        proxyPlugin = proxyPlugin_;

        controller = _controller;
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return _interfaceId == type(IJBSplitAllocator).interfaceId || super.supportsInterface(_interfaceId);
    }

    /// @notice Called by a project's payout (JBTerminal) or reserved token distribution split (JBController)
    /// @dev See https://docs.juicebox.money/dev/learn/glossary/split-allocator/
    /// @param _data See https://docs.juicebox.money/dev/api/data-structures/jbsplitallocationdata/
    function allocate(JBSplitAllocationData calldata _data) external payable {
        // Ensure call is coming from Terminal or Controller
        if (!directory.isTerminalOf(_data.projectId, IJBPaymentTerminal(msg.sender)) && directory.controllerOf(_data.projectId) != msg.sender)
            revert JuiceSips_Unauthorized();
        
        // Logic for payouts
        if (directory.isTerminalOf(_data.projectId, IJBPaymentTerminal(msg.sender))) {}

        /* // Logic for reserved token ditribution split (bonus implementation, not the focus rn)
        if (directory.controllerOf(_data.projectId) == msg.sender) {} */

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