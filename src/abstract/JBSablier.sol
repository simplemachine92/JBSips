// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1271} from "./ERC1271.sol";

import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";

import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";

import {IPRBProxy, IPRBProxyRegistry} from "@sablier/v2-periphery/src/types/Proxy.sol";
import {ISablierV2ProxyTarget} from "@sablier/v2-periphery/src/interfaces/ISablierV2ProxyTarget.sol";
import {ISablierV2ProxyPlugin} from "@sablier/v2-periphery/src/interfaces/ISablierV2ProxyPlugin.sol";
import { ISablierV2LockupDynamic } from "@sablier/v2-core/src/interfaces/ISablierV2LockupDynamic.sol";
import { ISablierV2LockupLinear } from "@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol";

import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC20 } from "@sablier/v2-core/src/types/Tokens.sol";

import {LockupLinear, LockupDynamic} from "@sablier/v2-core/src/types/DataTypes.sol";
import {Batch, Broker} from "@sablier/v2-periphery/src/types/DataTypes.sol";
import {ud60x18, ud2x18} from "@sablier/v2-core/src/types/Math.sol";

import {IAllowanceTransfer, Permit2Params} from "@sablier/v2-periphery/src/types/Permit2.sol";

import {AddStreamsData, DeployedStreams} from "../structs/Streams.sol";

abstract contract JBSablier is ERC165, ERC1271 {
        //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JBSablier_InsufficientBalance();

    //*********************************************************************//
    // --------------------- public constant properties ------------------ //
    //*********************************************************************//

    uint256 public immutable projectId;
    IJBDirectory public directory;
    IJBController3_1 public controller;

    IPRBProxy public proxy;
    ISablierV2LockupLinear public immutable lockupLinear;
    ISablierV2LockupDynamic public immutable lockupDynamic;
    ISablierV2ProxyTarget public proxyTarget;
    ISablierV2ProxyPlugin public proxyPlugin;

    IPRBProxyRegistry public constant PROXY_REGISTRY =
        IPRBProxyRegistry(0x584009E9eDe26e212182c9745F5c000191296a78);
    IAllowanceTransfer public constant PERMIT2 =
        IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    constructor(
        uint256 _projectId,
        IJBDirectory _directory,
        ISablierV2LockupLinear _lockupLinear,
        ISablierV2LockupDynamic _lockupDynamic,
        ISablierV2ProxyPlugin _proxyPlugin,
        ISablierV2ProxyTarget _proxyTarget,
        IJBController3_1 _controller
    ) {
        projectId = _projectId;

        /// @dev Mainnet JBDirectory as of 8/9/23: 0x65572FB928b46f9aDB7cfe5A4c41226F636161ea
        directory = _directory;

        /// @dev Mainnet SablierV2LockupLinear as of 8/9/23: 0xB10daee1FCF62243aE27776D7a92D39dC8740f95
        lockupLinear = _lockupLinear;

        lockupDynamic = _lockupDynamic;

        /// @dev Proxy deployer with plugin https://docs.sablier.com/contracts/v2/guides/proxy-architecture/deploy
        proxyPlugin = _proxyPlugin;

        proxyTarget = _proxyTarget;

        controller = _controller;
    }

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            _interfaceId == type(IJBSplitAllocator).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @notice Deploys a PRB proxy and plugin that returns tokens to this address
    /// @dev See https://docs.sablier.com/contracts/v2/guides/proxy-architecture/deploy
    /// @return proxy {IPRBProxy} proxy address
    function deployProxyAndInstallPlugin() internal returns (IPRBProxy proxy) {
        // Get the proxy for this contract
        proxy = PROXY_REGISTRY.getProxy({user: address(this)});
        if (address(proxy) == address(0)) {
            // If a proxy doesn't exist, deploy one and install the plugin
            proxy = PROXY_REGISTRY.deployAndInstallPlugin({
                plugin: proxyPlugin
            });
        } else {
            // If the proxy exists, then just install the plugin.
            PROXY_REGISTRY.installPlugin({plugin: proxyPlugin});
        }
    }

    function deployStreams(
        AddStreamsData calldata _data
    ) internal returns (DeployedStreams memory streams){
        if (IERC20(_data.token).balanceOf(address(this)) < _data.total ) revert JBSablier_InsufficientBalance();

        Permit2Params memory permit2Params;
        
        // Set up Permit2. See the full documentation at https://github.com/Uniswap/permit2
        IAllowanceTransfer.PermitDetails memory permitDetails;
        permitDetails.token = address(_data.token);
        permitDetails.amount = uint160(_data.total);
        permitDetails.expiration = type(uint48).max; // maximum expiration possible
        (,, permitDetails.nonce) =
            PERMIT2.allowance({ user: address(this), token: address(_data.token), spender: address(proxy) });

        IAllowanceTransfer.PermitSingle memory permitSingle;
        permitSingle.details = permitDetails;
        permitSingle.spender = address(proxy); // the proxy will be the spender
        permitSingle.sigDeadline = type(uint48).max; // same deadline as expiration

        // Declare the Permit2 params needed by Sablier
        /* Permit2Params memory permit2Params; */
        permit2Params.permitSingle = permitSingle;
        permit2Params.signature = bytes(""); // dummy signature
        
        DeployedStreams memory streams;

        if (_data.linWithDur.length > 0) {
            // Encode the data for the proxy target call
            bytes memory data =
                abi.encodeCall(proxyTarget.batchCreateWithDurations, (lockupLinear, _data.token, _data.linWithDur, permit2Params));

            // Create a batch of Lockup Linear streams via the proxy and Sablier's proxy target
            bytes memory response = proxy.execute(address(proxyTarget), data);
            streams.linearDurStreams = abi.decode(response, (uint256[]));
        }

        if (_data.linWithRange.length > 0) {
            bytes memory data =
                abi.encodeCall(proxyTarget.batchCreateWithRange, (lockupLinear, _data.token, _data.linWithRange, permit2Params));

            // Create a batch of Lockup Linear streams via the proxy and Sablier's proxy target
            bytes memory response = proxy.execute(address(proxyTarget), data);
            streams.linearRangeStreams = abi.decode(response, (uint256[]));
        }

        if (_data.dynWithDelta.length > 0) {
            bytes memory data =
                abi.encodeCall(proxyTarget.batchCreateWithDeltas, (lockupDynamic, _data.token, _data.dynWithDelta, permit2Params));

            // Create a batch of Lockup Linear streams via the proxy and Sablier's proxy target
            bytes memory response = proxy.execute(address(proxyTarget), data);
            streams.dynDeltaStreams = abi.decode(response, (uint256[]));
        }

        if (_data.dynWithMiles.length > 0) {
            bytes memory data =
                abi.encodeCall(proxyTarget.batchCreateWithMilestones, (lockupDynamic, _data.token, _data.dynWithMiles, permit2Params));

            // Create a batch of Lockup Linear streams via the proxy and Sablier's proxy target
            bytes memory response = proxy.execute(address(proxyTarget), data);
            streams.dynMileStreams = abi.decode(response, (uint256[]));
        }

        return streams;
    }
}
