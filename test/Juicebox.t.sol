// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./helpers/TestBaseWorkflowV3.sol";
import "@jbx-protocol/juice-delegates-registry/src/JBDelegatesRegistry.sol";

import {JBSips} from "../src/JBSips.sol";
import {IJBSips} from "../src/interfaces/IJBSips.sol";
import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";

import { ISablierV2LockupDynamic } from "@sablier/v2-core/interfaces/ISablierV2LockupDynamic.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/interfaces/ISablierV2LockupLinear.sol";

import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBFundingCycleBallot} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleBallot.sol";
import {JBGlobalFundingCycleMetadata} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycleMetadata.sol";
import {JBOperatorData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBOperatorData.sol";
import {JBSplit} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplit.sol";

import {Test, console2} from "forge-std/Test.sol";

contract CounterTest is TestBaseWorkflowV3 {

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

    // Delegate setup params
    JBDelegatesRegistry delegatesRegistry;

    function setUp() public override {

        string memory rpc = vm.envString("MAINNET_RPC_URL");

        mainnetFork = vm.createFork(rpc);

         /* 
        This setup deploys a new JB project and funding cycle, 
        and then attaches our Split Allocator to that funding cycle's splits
        */

        // Provides us with _jbOperatorStore and _jbETHPaymentTerminal
        super.setUp();

        // Placeholder project metadata, would customize this in prod.
        _projectMetadata = JBProjectMetadata({content: "myIPFSHash", domain: 1});

        /* // https://docs.juicebox.money/dev/extensions/juice-delegates-registry/jbdelegatesregistry/
        delegatesRegistry = new JBDelegatesRegistry(IJBDelegatesRegistry(address(0))); */

        address _delegateImpl = address(0);

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
            useDataSourceForPay: true,
            useDataSourceForRedeem: false,
            dataSource: address(_delegateImpl),
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
            _jbDirectory, 
            _jbOperatorStore, 
            ISablierV2LockupLinear(0xB10daee1FCF62243aE27776D7a92D39dC8740f95), 
            _jbController
        );

        _splits[0] = JBSplit({
        preferClaimed: false,
        preferAddToBalance: false,
        percent: 1_000_000_000,
        projectId: 1,
        beneficiary: payable(0),
        lockedUntil: 0,
        allocator: IJBSplitAllocator(address(_sips))
        });

        _groupedSplits[0] = JBGroupedSplits({
            group: 0,
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

        (, JBFundingCycleMetadata memory metadata, ) = _jbController.latestConfiguredFundingCycleOf(1);

        vm.label(metadata.dataSource, "Initialized DS");
    }

}
