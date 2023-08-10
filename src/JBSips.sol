// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBDirectory} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";

import {JBSplitAllocationData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol";
import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";

import { ISablierV2LockupDynamic } from "@sablier/v2-core/interfaces/ISablierV2LockupDynamic.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/interfaces/ISablierV2LockupLinear.sol";
import { Broker, LockupLinear, LockupDynamic } from "@sablier/v2-core/types/DataTypes.sol";
import { ud60x18, ud2x18 } from "@sablier/v2-core/types/Math.sol";
import { IERC20 } from "@sablier/v2-core/types/Tokens.sol";

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
contract JBSips is IJBSplitAllocator, JBOperatable {

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

    IJBDirectory public directory;
    ISablierV2LockupLinear public sablier;
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
        IJBController3_1 _controller
    )   JBOperatable(_operatorStore) 
    {
        projectId = _projectId;

        /// @dev Mainnet JBDirectory as of 8/9/23: 0x65572FB928b46f9aDB7cfe5A4c41226F636161ea
        directory = _directory;

        /// @dev Mainnet SablierV2LockupLinear as of 8/9/23: 0xB10daee1FCF62243aE27776D7a92D39dC8740f95
        sablier = _sablier;

        controller = _controller;
    }

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
    function allocate(JBSplitAllocationData calldata _data) external payable {
        // Ensure call is coming from Terminal or Controller
        if (!directory.isTerminalOf(_data.projectId, IJBPaymentTerminal(msg.sender)) || directory.controllerOf(_data.projectId) != msg.sender)
            revert JuiceSips_Unauthorized();
        
        // Logic for payouts
        if (directory.isTerminalOf(_data.projectId, IJBPaymentTerminal(msg.sender))) {}

        /* // Logic for reserved token ditribution split (bonus implementation, not the focus rn)
        if (directory.controllerOf(_data.projectId) == msg.sender) {} */

    }

    function withdrawFromStream() external {}

    function configureRecipients()
        external requirePermission(controller.projects().ownerOf(projectId), projectId, JBOperations.SET_SPLITS) {

    }

    function cancelStreams()
        external requirePermission(controller.projects().ownerOf(projectId), projectId, JBOperations.SET_SPLITS) {

    }

}