// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {JBSablier} from '../src/abstract/JBSablier.sol';
import {AddStreamsData, DeployedStreams} from './structs/Streams.sol';

import {JBSplitAllocationData} from '@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol';
import {JBOperatable} from '@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol';
import {JBOperations} from '@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol';

import {IJBDirectory} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import {IJBController3_1} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol';
import {IJBSplitAllocator} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol';
import {IJBPaymentTerminal} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol';
import {IJBDirectory} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import {IJBOperatorStore} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol';
import {JBFundingCycle} from '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol';

import {ISablierV2ProxyTarget} from '@sablier/v2-periphery/src/interfaces/ISablierV2ProxyTarget.sol';
import {ISablierV2ProxyPlugin} from '@sablier/v2-periphery/src/interfaces/ISablierV2ProxyPlugin.sol';
import {ISablierV2LockupDynamic} from 'lib/v2-periphery/lib/v2-core/src/interfaces/ISablierV2LockupDynamic.sol';
import {ISablierV2LockupLinear} from 'lib/v2-periphery/lib/v2-core/src/interfaces/ISablierV2LockupLinear.sol';
import {IERC20} from 'lib/v2-periphery/lib/v2-core/src/types/Tokens.sol';

/**
 * @custom:benediction DEVS BENEDICAT ET PROTEGAT CONTRACTVS MEAM
 *
 * @title Juicebox Sips
 *
 * @author noobwonder.eth
 *
 * @notice Split Allocator Treasury Extension acting as a Sablier v2 Stream Manager, Deployer, and hub for users to
 *         interact with Sablier v2 streams of which they are the beneficiary.
 *
 * @dev   This derived contract handles most stream management, stream accounting (by funding cycle), and admin duties.
 *        JBSablier holds all logic and state variables for deploying Sablier v2 streams.
 */
contract JBSips is JBSablier, JBOperatable, IJBSplitAllocator {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error JuiceSips_Unauthorized();
  error JuiceSips_MaximumSlippage();

  //*********************************************************************//
  // -----------------------------  events ----------------------------- //
  //*********************************************************************//

  //*********************************************************************//
  // --------------------- public stored properties -------------------- //
  //*********************************************************************//

  /**
   * @notice Future streams data sorted by juicebox projects funding cycle number
   */
  mapping(uint256 cycleNumber => AddStreamsData) public streamsToDeploy;

  /**
   * @notice Deployed streams data sorted by juicebox projects funding cycle number
   */
  mapping(uint256 cycleNumber => DeployedStreams) public streamsByCycle;

  /// @notice bool: are streams optimistically deployed upon receiving an ETH payout from JB?
  bool public streamOnPayout;

  uint256 public lastCycleNumber;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  constructor(
    uint256 _projectId,
    IJBDirectory _directory,
    IJBOperatorStore _operatorStore,
    ISablierV2LockupLinear _lockupLinear,
    ISablierV2LockupDynamic _lockupDynamic,
    ISablierV2ProxyPlugin _proxyPlugin,
    ISablierV2ProxyTarget _proxyTarget,
    IJBController3_1 _controller,
    // Pool Params configured by deployer to swap via Uni V3 Pool
    IERC20 _token,
    uint24 _fee,
    uint32 _secondsAgo,
    uint256 _twapDelta
  )
    JBSablier(
      _projectId,
      _directory,
      _lockupLinear,
      _lockupDynamic,
      _proxyPlugin,
      _proxyTarget,
      _controller,
      _token,
      _fee,
      _secondsAgo,
      _twapDelta
    )
    JBOperatable(IJBOperatorStore(_operatorStore))
  {
    
  }

  //*********************************************************************//
  // ---------------------- external functions ------------------------- //
  //*********************************************************************//

  /// @notice Called by a project's payout (JBTerminal) or reserved token distribution split (JBController)
  /// @dev See https://docs.juicebox.money/dev/learn/glossary/split-allocator/
  /// @param _data See https://docs.juicebox.money/dev/api/data-structures/jbsplitallocationdata/
  function allocate(JBSplitAllocationData calldata _data) external override payable {
    // Ensure call is coming from Terminal or Controller
    if (
      !directory.isTerminalOf(_data.projectId, IJBPaymentTerminal(msg.sender)) &&
      directory.controllerOf(_data.projectId) != msg.sender
    ) revert JuiceSips_Unauthorized();

    if (_data.projectId != projectId) revert JuiceSips_Unauthorized();

    // Logic for handling ETH payouts
    if (directory.isTerminalOf(_data.projectId, IJBPaymentTerminal(msg.sender))) {
      // Track funding cycles in state var for accounting purposes
      (JBFundingCycle memory _cycle, ) = controller.currentFundingCycleOf(projectId);
      lastCycleNumber = _cycle.number;

      uint256 quote = _getQuote(msg.value);

      uint256 tokensFromSwap = _swap(int256(msg.value), quote);

      AddStreamsData memory _streamsTo = streamsToDeploy[lastCycleNumber];

      DeployedStreams memory streams = super._deployStreams(_streamsTo);

      streamsByCycle[lastCycleNumber] = streams;
    }
  }

  /// @notice Sets any number of streams to be deployed upon a projects funding cycle payout
  /// @dev See https://docs.sablier.com/concepts/protocol/stream-types
  /// @param _streams {AddStreamsData} Struct that includes cycle #, token & total, stream configs
  function setCurrentCycleStreams(
    AddStreamsData calldata _streams
  )
    external
    requirePermission(controller.projects().ownerOf(projectId), projectId, JBOperations.SET_SPLITS)
  {
    // Track funding cycles in state var for accounting purposes
    (JBFundingCycle memory _cycle, ) = controller.currentFundingCycleOf(projectId);
    uint256 cycleNumber = _cycle.number;

    streamsToDeploy[cycleNumber] = _streams;
  }

  receive() external payable {}
}
