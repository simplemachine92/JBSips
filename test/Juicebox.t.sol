// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./helpers/TestBaseWorkflowV3.sol";
import "@jbx-protocol/juice-delegates-registry/src/JBDelegatesRegistry.sol";

import {JBSips} from "../src/JBSips.sol";
import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {JBSplitAllocationData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol";

import { ISablierV2LockupDynamic } from "@sablier/v2-core/interfaces/ISablierV2LockupDynamic.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/interfaces/ISablierV2LockupLinear.sol";
import { ISablierV2ProxyPlugin } from "@sablier/v2-periphery/interfaces/ISablierV2ProxyPlugin.sol";
import { ISablierV2ProxyTarget } from "@sablier/v2-periphery/interfaces/ISablierV2ProxyTarget.sol";

import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import {JBSplit} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";

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

    function setUp() public override {
         /* 
        This setup deploys a new JB project and funding cycle, 
        and then attaches our Split Allocator to that funding cycle
        */

        string memory rpc = vm.envString("MAINNET_RPC_URL");

        mainnetFork = vm.createFork(rpc);

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
            address(_jbDirectory), 
            address(_jbOperatorStore),
            //Linear
            0xB10daee1FCF62243aE27776D7a92D39dC8740f95, 
            // Lockup Dynamic
            0x39EFdC3dbB57B2388CcC4bb40aC4CB1226Bc9E44,
            // Proxy
            0x9bdebF4F9adEB99387f46e4020FBf3dDa885D2b8,
            // Proxy Target
            0x297b43aE44660cA7826ef92D8353324C018573Ef,
            address(_jbController)
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

    function testPayout() public {
        // Load our project with some eth
        vm.deal(address(123), 20 ether);
        vm.prank(address(123));
        _jbETHPaymentTerminal.pay{value: 10 ether}(_projectId, 10 ether, address(0x000000000000000000000000000000000000EEEe), address(123), 0, false, "", "");
    
        vm.prank(address(123));
        _jbETHPaymentTerminal.distributePayoutsOf(_projectId, 2 ether, 1, address(0x000000000000000000000000000000000000EEEe), 0, "");
        emit log_uint(address(_sips).balance);
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

}
