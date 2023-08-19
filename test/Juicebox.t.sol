// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./helpers/TestBaseWorkflowV3.sol";
import "@jbx-protocol/juice-delegates-registry/src/JBDelegatesRegistry.sol";

import {JBSips} from "../src/JBSips.sol";
import {IJBSablier} from "../src/interfaces/IJBSablier.sol";
import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {JBSplitAllocationData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol";

import {ISablierV2LockupDynamic} from "lib/v2-periphery/lib/v2-core/src/interfaces/ISablierV2LockupDynamic.sol";
import {ISablierV2LockupLinear} from "lib/v2-periphery/lib/v2-core/src/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2ProxyPlugin } from "@sablier/v2-periphery/src/interfaces/ISablierV2ProxyPlugin.sol";
import { ISablierV2ProxyTarget } from "@sablier/v2-periphery/src/interfaces/ISablierV2ProxyTarget.sol";
import {LockupLinear, LockupDynamic} from "@sablier/v2-periphery/src/types/DataTypes.sol";
import {Batch, Broker} from "@sablier/v2-periphery/src/types/DataTypes.sol";
import { ud2x18, ud60x18 } from "@sablier/v2-core/src/types/Math.sol";

import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import {JBSplit} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";

import {IERC20} from "lib/v2-periphery/lib/v2-core/src/types/Tokens.sol";
import {IWETH9} from "../src/interfaces/external/IWETH9.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {AddStreamsData, DeployedStreams} from "../src/structs/Streams.sol";
import {IPRBProxy, IPRBProxyRegistry} from "@sablier/v2-periphery/src/types/Proxy.sol";

import {Test, console2} from "forge-std/Test.sol";

contract SipsTest is TestBaseWorkflowV3 {

    using JBFundingCycleMetadataResolver for JBFundingCycle;

    // Assigned when project is launched
    uint256 _projectId;

    // the identifiers of the forks
    uint256 mainnetFork;
    uint256 optimismFork;

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

        string memory rpc = vm.envString("MAINNET_RPC_URL");

        mainnetFork = vm.createSelectFork(rpc);

        // Provides us with _jbOperatorStore and _jbETHPaymentTerminal
        super.setUp();

        // Placeholder project metadata, would customize this in prod.
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1}); 

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
                distributionLimit: 2 ether,
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
        vm.label(address(_sips), "Sips Contract");

        _splits[0] = JBSplit({
        preferClaimed: false,
        preferAddToBalance: false,
        percent: 1_000_000_000,
        projectId: 1,
        beneficiary: payable(address(0)),
        lockedUntil: 0,
        allocator: IJBSplitAllocator(address(_sips))
        });

        _groupedSplits[0] = JBGroupedSplits({
            group: 1,
            splits: _splits
        });

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
            ""
        );
        
    }

    function testPayoutStreamFlow() public {
        // first deploy our proxy
        vm.prank(address(123));
        IPRBProxy _proxy = _sips.deploy();

        // Declare the first stream in the batch
        Batch.CreateWithDurations memory stream0;
        stream0.sender = address(_proxy); // The sender will be able to cancel the stream
        stream0.recipient = address(0xcafe); // The recipient of the streamed assets
        stream0.totalAmount = uint128(800000000); // The total amount of each stream, inclusive of all fees
        stream0.cancelable = true; // Whether the stream will be cancelable or not
        stream0.durations = LockupLinear.Durations({
            cliff: 4 weeks, // Assets will be unlocked only after 4 weeks
            total: 52 weeks // Setting a total duration of ~1 year
         });
        stream0.broker = Broker(address(0), ud60x18(0)); // Optional parameter left undefined

        Batch.CreateWithDurations[] memory durBatch = new Batch.CreateWithDurations[](1);

        durBatch[0] = stream0;

                // Declare the params struct
        Batch.CreateWithMilestones memory stream1;

        // Declare the second stream
        Batch.CreateWithMilestones[] memory mileBatch = new Batch.CreateWithMilestones[](1);

        // Declare the function parameters
        stream1.sender = address(_proxy); // The sender will be able to cancel the stream
        stream1.recipient = address(0xcafe2); // The recipient of the streamed assets
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

         Batch.CreateWithRange[] memory _range = new Batch.CreateWithRange[](0);
         Batch.CreateWithDeltas[] memory _deltas = new Batch.CreateWithDeltas[](0);

         AddStreamsData memory _data = AddStreamsData({
            total: 3200000000,
            token: USDC,
            linWithDur: durBatch,
            linWithRange: _range,
            dynWithDelta: _deltas,
            dynWithMiles: mileBatch
         });

        vm.prank(address(123));
        _sips.setCurrentCycleStreams(_data);

        // Load our project with some eth
        vm.deal(address(123), 20 ether);
        vm.prank(address(123));
        _jbETHPaymentTerminal.pay{value: 10 ether}(_projectId, 10 ether, address(0x000000000000000000000000000000000000EEEe), address(123), 0, false, "", "");

        // distribute payout
        vm.prank(address(123));
        _jbETHPaymentTerminal.distributePayoutsOf(_projectId, 2 ether, 1, address(0x000000000000000000000000000000000000EEEe), 0, "");
        emit log_uint(USDC.balanceOf(address(_sips)));

    }

    function testPayout() public {
        // Load our project with some eth
        vm.deal(address(123), 20 ether);
        vm.prank(address(123));
        _jbETHPaymentTerminal.pay{value: 10 ether}(_projectId, 10 ether, address(0x000000000000000000000000000000000000EEEe), address(123), 0, false, "", "");
    
        vm.prank(address(123));
        _jbETHPaymentTerminal.distributePayoutsOf(_projectId, 2 ether, 1, address(0x000000000000000000000000000000000000EEEe), 0, "");
        emit log_uint(USDC.balanceOf(address(_sips)));
    }

    function testFail_allocateExternal() public {
        vm.prank(address(123));
        JBSplitAllocationData memory alloData = JBSplitAllocationData({
            token: address(0),
            amount: 0,
            decimals: 0,
            projectId: 1,
            group: 1,
            split: 
            JBSplit({
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

    function testDeployProxyAndPI() public {
        vm.prank(address(123));
        _sips.deploy();
    }

    function testFail_DoubleDeploy() public {
        vm.prank(address(123));
        _sips.deploy();
        _sips.deploy();
    }

    function testPoolValidity() public {
        emit log_address(address(_sips.POOL()));
    }

}
