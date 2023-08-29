// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Vm.sol';

import './helpers/TestBaseWorkflowV3.sol';
import '@jbx-protocol/juice-delegates-registry/src/JBDelegatesRegistry.sol';

import {JBSips} from '../src/JBSips.sol';
import {IJBSplitAllocator} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol';
import {JBSplitAllocationData} from '@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol';

import {ISablierV2LockupDynamic} from 'lib/v2-periphery/lib/v2-core/src/interfaces/ISablierV2LockupDynamic.sol';
import {ISablierV2LockupLinear} from 'lib/v2-periphery/lib/v2-core/src/interfaces/ISablierV2LockupLinear.sol';
import {ISablierV2ProxyPlugin} from '@sablier/v2-periphery/src/interfaces/ISablierV2ProxyPlugin.sol';
import {ISablierV2ProxyTarget} from '@sablier/v2-periphery/src/interfaces/ISablierV2ProxyTarget.sol';
import {LockupLinear, LockupDynamic} from '@sablier/v2-periphery/src/types/DataTypes.sol';
import {Batch, Broker} from '@sablier/v2-periphery/src/types/DataTypes.sol';
import {ud2x18, ud60x18} from '@sablier/v2-core/src/types/Math.sol';

import {IJBFundingCycleBallot} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol';
import {JBGlobalFundingCycleMetadata} from '@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol';
import {JBSplit} from '@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol';

import {IERC20} from 'lib/v2-periphery/lib/v2-core/src/types/Tokens.sol';
import {IWETH9} from '../src/interfaces/external/IWETH9.sol';

import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';

import {AddStreamsData} from '../src/structs/Streams.sol';
import {IPRBProxy} from '@sablier/v2-periphery/src/types/Proxy.sol';
import {Lockup} from 'lib/v2-periphery/lib/v2-core/src/types/DataTypes.sol';

import {LockupDynamic, LockupLinear} from '@sablier/v2-core/src/types/DataTypes.sol';

contract SipsTest_Int is TestBaseWorkflowV3 {
  using JBFundingCycleMetadataResolver for JBFundingCycle;

  // Assigned when project is launched
  uint256 _projectId;

  // the identifiers of the forks
  uint256 mainnetFork;
  uint256 optimismFork;

  ISablierV2LockupLinear public constant lockupLinear =
    ISablierV2LockupLinear(0xB10daee1FCF62243aE27776D7a92D39dC8740f95);

  ISablierV2LockupDynamic public constant lockupDynamic =
    ISablierV2LockupDynamic(0x39EFdC3dbB57B2388CcC4bb40aC4CB1226Bc9E44);

  // Project setup params
  JBProjectMetadata _projectMetadata;
  JBFundingCycleData _data;
  JBFundingCycleMetadata _metadata;
  JBFundAccessConstraints[] _fundAccessConstraints; // Default empty
  IJBPaymentTerminal[] _terminals; // Default empty
  JBSips _sips;

  ISablierV2ProxyPlugin proxyPlugin;

  // Delegate setup params
  JBDelegatesRegistry delegatesRegistry;

  // Pool config
  uint32 secondsAgo = 100;
  uint256 twapDelta = 100;

  IUniswapV3Pool pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
  IERC20 USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  IWETH9 weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  address _uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
  uint24 fee = 500;

  function setUp() public override {
    /* 
        This setup deploys a new JB project and funding cycle, 
        and then attaches our Split Allocator to that funding cycle
        */

    string memory rpc = vm.envString('MAINNET_RPC_URL');

    mainnetFork = vm.createSelectFork(rpc);

    // Provides us with _jbOperatorStore and _jbETHPaymentTerminal
    super.setUp();

    // Placeholder project metadata, would customize this in prod.
    _projectMetadata = JBProjectMetadata({content: 'myIPFSHash', domain: 1});

    // The following describes the funding cycle, access constraints, and metadata necessary for our project.
    _data = JBFundingCycleData({
      duration: 30 days,
      weight: 10 ** 18,
      discountRate: 0,
      ballot: IJBFundingCycleBallot(address(0))
    });

    _metadata = JBFundingCycleMetadata({
      global: JBGlobalFundingCycleMetadata({
        allowSetTerminals: false,
        allowSetController: false,
        pauseTransfers: false
      }),
      reservedRate: 0,
      redemptionRate: 5000,
      ballotRedemptionRate: 0,
      pausePay: false,
      pauseDistributions: false,
      pauseRedeem: false,
      pauseBurn: false,
      allowMinting: true,
      preferClaimedTokenOverride: false,
      allowTerminalMigration: false,
      allowControllerMigration: false,
      holdFees: false,
      useTotalOverflowForRedemptions: false,
      useDataSourceForPay: false,
      useDataSourceForRedeem: false,
      dataSource: address(0),
      metadata: 0
    });

    _fundAccessConstraints.push(
      JBFundAccessConstraints({
        terminal: _jbETHPaymentTerminal,
        token: jbLibraries().ETHToken(),
        distributionLimit: 10 ether,
        overflowAllowance: type(uint232).max,
        distributionLimitCurrency: 1, // Currency = ETH
        overflowAllowanceCurrency: 1
      })
    );

    // Imported from TestBaseWorkflowV3.sol via super.setUp() https://docs.juicebox.money/dev/learn/architecture/terminals/
    _terminals = [_jbETHPaymentTerminal];

    JBGroupedSplits[] memory _groupedSplits = new JBGroupedSplits[](1); // Default empty
    JBSplit[] memory _splits = new JBSplit[](1);

    _sips = new JBSips(
      1,
      IJBDirectory(_jbDirectory),
      IJBOperatorStore(_jbOperatorStore),
      //Linear
      ISablierV2LockupLinear(0xB10daee1FCF62243aE27776D7a92D39dC8740f95),
      // Lockup Dynamic
      ISablierV2LockupDynamic(0x39EFdC3dbB57B2388CcC4bb40aC4CB1226Bc9E44),
      // Proxy
      ISablierV2ProxyPlugin(0x9bdebF4F9adEB99387f46e4020FBf3dDa885D2b8),
      // Proxy Target
      ISablierV2ProxyTarget(0x297b43aE44660cA7826ef92D8353324C018573Ef),
      IJBController3_1(_jbController),
      // Pool Params
      USDC,
      fee,
      secondsAgo,
      twapDelta
    );
    vm.label(address(_sips), 'Sips Contract');

    _splits[0] = JBSplit({
      preferClaimed: false,
      preferAddToBalance: false,
      percent: 1_000_000_000,
      projectId: 1,
      beneficiary: payable(address(0)),
      lockedUntil: 0,
      allocator: IJBSplitAllocator(address(_sips))
    });

    _groupedSplits[0] = JBGroupedSplits({group: 1, splits: _splits});

    // Blastoff
    vm.prank(address(123));
    _projectId = _jbController.launchProjectFor(
      address(123),
      _projectMetadata,
      _data,
      _metadata,
      0,
      _groupedSplits,
      _fundAccessConstraints,
      _terminals,
      ''
    );

    // first deploy our proxy
    vm.prank(address(123));
    IPRBProxy _proxy = _sips.deployProxy();

    emit log_address(address(_sips.proxy()));

    // Load our project with some eth
    vm.deal(address(123), 20 ether);
    vm.prank(address(123));
    _jbETHPaymentTerminal.pay{value: 10 ether}(
      _projectId,
      10 ether,
      address(0x000000000000000000000000000000000000EEEe),
      address(123),
      0,
      false,
      '',
      ''
    );

    // distribute payout
    vm.prank(address(123));
    _jbETHPaymentTerminal.distributePayoutsOf(
      _projectId,
      4 ether,
      1,
      address(0x000000000000000000000000000000000000EEEe),
      0,
      ''
    );
    emit log_uint(USDC.balanceOf(address(_sips)));

    // Declare the first stream in the batch
    Batch.CreateWithDurations memory stream0;
    stream0.sender = address(_proxy); // The sender will be able to cancel the stream
    stream0.recipient = address(0xcafe); // The recipient of the streamed assets
    stream0.totalAmount = uint128(800000000); // The total amount of each stream, inclusive of all fees
    stream0.cancelable = true; // Whether the stream will be cancelable or not
    stream0.durations = LockupLinear.Durations({
      cliff: 1 days, // Assets will be unlocked only after 4 weeks
      total: 52 weeks // Setting a total duration of ~1 year
    });
    stream0.broker = Broker(address(0), ud60x18(0)); // Optional parameter left undefined

    Batch.CreateWithDurations[] memory durBatch = new Batch.CreateWithDurations[](1);

    durBatch[0] = stream0;

    // Declare the params struct
    Batch.CreateWithMilestones memory stream1;

    // Declare the second stream
    Batch.CreateWithMilestones[] memory mileBatch = new Batch.CreateWithMilestones[](2);

    // Declare the function parameters
    stream1.sender = address(_proxy); // The sender will be able to cancel the stream
    stream1.recipient = address(0xcafe); // The recipient of the streamed assets
    stream1.totalAmount = uint128(800000000); // Total amount is the amount inclusive of all fees
    /* stream1.asset = USDC; // The streaming asset */
    stream1.cancelable = true; // Whether the stream will be cancelable or not
    /* stream1.startTime = uint40(block.timestamp); */
    stream1.broker = Broker(address(0), ud60x18(0)); // Optional parameter left undefined

    // Declare some dummy segments
    stream1.segments = new LockupDynamic.Segment[](2);
    stream1.segments[0] = LockupDynamic.Segment({
      amount: uint128(400000000),
      exponent: ud2x18(1e18),
      milestone: uint40(block.timestamp + 4 weeks)
    });
    stream1.segments[1] = (
      LockupDynamic.Segment({
        amount: uint128(400000000),
        exponent: ud2x18(3.14e18),
        milestone: uint40(block.timestamp + 52 weeks)
      })
    );

    mileBatch[0] = stream1;

    // Declare the params struct
    Batch.CreateWithMilestones memory stream3;

    // Declare the function parameters
    stream3.sender = address(_proxy); // The sender will be able to cancel the stream
    stream3.recipient = address(0xcafe3); // The recipient of the streamed assets
    stream3.totalAmount = uint128(800000000); // Total amount is the amount inclusive of all fees
    /* stream1.asset = USDC; // The streaming asset */
    stream3.cancelable = true; // Whether the stream will be cancelable or not
    /* stream1.startTime = uint40(block.timestamp); */
    stream3.broker = Broker(address(0), ud60x18(0)); // Optional parameter left undefined

    // Declare some dummy segments
    stream3.segments = new LockupDynamic.Segment[](2);
    stream3.segments[0] = LockupDynamic.Segment({
      amount: uint128(400000000),
      exponent: ud2x18(1e18),
      milestone: uint40(block.timestamp + 4 weeks)
    });
    stream3.segments[1] = (
      LockupDynamic.Segment({
        amount: uint128(400000000),
        exponent: ud2x18(3.14e18),
        milestone: uint40(block.timestamp + 52 weeks)
      })
    );

    mileBatch[1] = stream3;

    Batch.CreateWithRange[] memory _range = new Batch.CreateWithRange[](0);
    Batch.CreateWithDeltas[] memory _deltas = new Batch.CreateWithDeltas[](0);

    AddStreamsData memory _sData = AddStreamsData({
      total: 3200000000,
      token: USDC,
      linWithDur: durBatch,
      linWithRange: _range,
      dynWithDelta: _deltas,
      dynWithMiles: mileBatch
    });

    vm.prank(address(123));
    _sips.deployStreams(3 ether, _sData);
  }

  function test_AddWethStreams() public {
    // distribute payout
    vm.prank(address(123));
    _jbETHPaymentTerminal.distributePayoutsOf(
      _projectId,
      3 ether,
      1,
      address(0x000000000000000000000000000000000000EEEe),
      0,
      ''
    );
    emit log_uint(USDC.balanceOf(address(_sips)));

    // Declare the first stream in the batch
    Batch.CreateWithDurations memory stream0;
    stream0.sender = address(_sips.proxy()); // The sender will be able to cancel the stream
    stream0.recipient = address(0xbeef); // The recipient of the streamed assets
    stream0.totalAmount = uint128(1 ether); // The total amount of each stream, inclusive of all fees
    stream0.cancelable = true; // Whether the stream will be cancelable or not
    stream0.durations = LockupLinear.Durations({
      cliff: 1 days, // Assets will be unlocked only after 4 weeks
      total: 52 weeks // Setting a total duration of ~1 year
    });
    stream0.broker = Broker(address(0), ud60x18(0)); // Optional parameter left undefined

    Batch.CreateWithDurations[] memory durBatch = new Batch.CreateWithDurations[](1);

    durBatch[0] = stream0;

    // Declare the params struct
    Batch.CreateWithMilestones memory stream1;

    // Declare the second stream
    Batch.CreateWithMilestones[] memory mileBatch = new Batch.CreateWithMilestones[](2);

    // Declare the function parameters
    stream1.sender = address(_sips.proxy()); // The sender will be able to cancel the stream
    stream1.recipient = address(0xbeef2); // The recipient of the streamed assets
    stream1.totalAmount = uint128(1 ether); // Total amount is the amount inclusive of all fees
    /* stream1.asset = USDC; // The streaming asset */
    stream1.cancelable = true; // Whether the stream will be cancelable or not
    /* stream1.startTime = uint40(block.timestamp); */
    stream1.broker = Broker(address(0), ud60x18(0)); // Optional parameter left undefined

    // Declare some dummy segments
    stream1.segments = new LockupDynamic.Segment[](2);
    stream1.segments[0] = LockupDynamic.Segment({
      amount: uint128(0.5 ether),
      exponent: ud2x18(1e18),
      milestone: uint40(block.timestamp + 4 weeks)
    });
    stream1.segments[1] = (
      LockupDynamic.Segment({
        amount: uint128(0.5 ether),
        exponent: ud2x18(3.14e18),
        milestone: uint40(block.timestamp + 52 weeks)
      })
    );

    mileBatch[0] = stream1;

    // Declare the params struct
    Batch.CreateWithMilestones memory stream3;

    // Declare the function parameters
    stream3.sender = address(_sips.proxy()); // The sender will be able to cancel the stream
    stream3.recipient = address(0xbeef3); // The recipient of the streamed assets
    stream3.totalAmount = uint128(1 ether); // Total amount is the amount inclusive of all fees
    /* stream1.asset = USDC; // The streaming asset */
    stream3.cancelable = true; // Whether the stream will be cancelable or not
    /* stream1.startTime = uint40(block.timestamp); */
    stream3.broker = Broker(address(0), ud60x18(0)); // Optional parameter left undefined

    // Declare some dummy segments
    stream3.segments = new LockupDynamic.Segment[](2);
    stream3.segments[0] = LockupDynamic.Segment({
      amount: uint128(0.5 ether),
      exponent: ud2x18(1e18),
      milestone: uint40(block.timestamp + 4 weeks)
    });
    stream3.segments[1] = (
      LockupDynamic.Segment({
        amount: uint128(0.5 ether),
        exponent: ud2x18(3.14e18),
        milestone: uint40(block.timestamp + 52 weeks)
      })
    );

    mileBatch[1] = stream3;

    Batch.CreateWithRange[] memory _range = new Batch.CreateWithRange[](0);
    Batch.CreateWithDeltas[] memory _deltas = new Batch.CreateWithDeltas[](0);

    AddStreamsData memory _sData = AddStreamsData({
      total: 3 ether,
      token: weth,
      linWithDur: durBatch,
      linWithRange: _range,
      dynWithDelta: _deltas,
      dynWithMiles: mileBatch
    });

    LockupLinear.CreateWithDurations memory reEncoded = LockupLinear.CreateWithDurations({
      sender: address(_sips.proxy()),
      recipient: stream0.recipient,
      totalAmount: stream0.totalAmount,
      asset: weth,
      cancelable: stream0.cancelable,
      durations: stream0.durations,
      broker: stream0.broker
    });

    // Just checking for one call here as more would be incredibly tedious
    vm.expectCall(
      address(lockupLinear),
      abi.encodeCall(ISablierV2LockupLinear.createWithDurations, (reEncoded))
    );

    vm.prank(address(123));
    _sips.deployStreams(3 ether, _sData);
  }

  function test_WithdrawAllDust() public {
    vm.prank(address(123));
    _sips.withdrawAllTokenDust(USDC);
  }

  function test_BatchCancelStreams() public {
    // Arrange our data for proxy call of batchCancelMultiple
    uint256[] memory _ids = new uint256[](1);
    uint256[] memory ids = _sips.getStreamsByCycleAndAddress(
      1,
      0x000000000000000000000000000000000000cafE
    );
    _ids[0] = ids[0];

    Batch.CancelMultiple memory stream1;
    Batch.CancelMultiple[] memory batch = new Batch.CancelMultiple[](1);

    IERC20[] memory tokens = new IERC20[](1);

    tokens[0] = USDC;

    stream1.streamIds = _ids;
    _sips.isStreamLinear(ids[0]) ? stream1.lockup = lockupLinear : stream1.lockup = lockupDynamic;

    batch[0] = stream1;

    vm.warp(block.timestamp + 1 weeks);

    // Cancel the stream
    vm.startPrank(address(123));
    _sips.batchCancelStreams(batch, tokens);

    Lockup.Status expectedStatus = Lockup.Status.CANCELED;
    Lockup.Status actualLinearStatus = lockupLinear.statusOf(stream1.streamIds[0]);
    if (expectedStatus != actualLinearStatus) {
      revert();
    }
  }

  function test_StreamWithdraw() public {
    // Since we've forked mainnet, we can't really expect specific values, but there should be 2 stream ids
    uint256[] memory ids = _sips.getStreamsByCycleAndAddress(
      1,
      0x000000000000000000000000000000000000cafE
    );

    // ETH for call
    vm.deal(address(0xcafe), 1 ether);
    // Must call from recipient
    vm.startPrank(address(0xcafe), address(0xcafe));
    // Call after some tokens have acrued
    vm.warp(block.timestamp + 2 weeks);
    // Call lockup linear as recipient
    lockupLinear.withdrawMax({streamId: ids[0], to: address(0xcafe)});
    vm.stopPrank();
  }

  function testFail_allocateExternal() public {
    vm.prank(address(123));
    JBSplitAllocationData memory alloData = JBSplitAllocationData({
      token: address(0),
      amount: 0,
      decimals: 0,
      projectId: 1,
      group: 1,
      split: JBSplit({
        preferClaimed: false,
        preferAddToBalance: false,
        percent: 1_000_000_000,
        projectId: 1,
        beneficiary: payable(address(0)),
        lockedUntil: 0,
        allocator: IJBSplitAllocator(address(_sips))
      })
    });

    _sips.allocate{value: 0}(alloData);
  }

  function testFail_DoubleDeploy() public {
    // Will fail as proxy was deployed by owner in setup
    vm.prank(address(123));
    _sips.deployProxy();
  }

  function test_PoolValidity() public {
    emit log_address(address(_sips.POOL()));
  }
}
