// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IJBSplitAllocator} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol';
import {IJBPaymentTerminal} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol';
import {IJBDirectory} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import {IJBOperatorStore} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol';
import {IJBController3_1} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol';

import {ISablierV2ProxyTarget} from '@sablier/v2-periphery/src/interfaces/ISablierV2ProxyTarget.sol';
import {IPRBProxy, IPRBProxyRegistry} from '@sablier/v2-periphery/src/types/Proxy.sol';
import {ISablierV2ProxyPlugin} from '@sablier/v2-periphery/src/interfaces/ISablierV2ProxyPlugin.sol';

import {ISablierV2LockupDynamic} from '@sablier/v2-core/src/interfaces/ISablierV2LockupDynamic.sol';
import {ISablierV2LockupLinear} from '@sablier/v2-core/src/interfaces/ISablierV2LockupLinear.sol';

interface IJBSablier {
  /* function directory() external view returns (IJBDirectory);

    function projectId() external view returns (uint256);

    function controller() external view returns (IJBController3_1);

    function proxy() external view returns (IPRBProxy);

    function sablier() external view returns (ISablierV2LockupLinear);

    function proxyTarget() external view returns (ISablierV2ProxyTarget);

    function proxyPlugin() external view returns (ISablierV2ProxyPlugin); */
  function PERMIT2() external view returns (address);

  function PROXY_REGISTRY() external view returns (address);

  function controller() external view returns (address);

  function directory() external view returns (address);

  function lockupDynamic() external view returns (address);

  function lockupLinear() external view returns (address);

  function projectId() external view returns (uint256);

  function proxy() external view returns (address);

  function proxyPlugin() external view returns (address);

  function proxyTarget() external view returns (address);

  function supportsInterface(bytes4 _interfaceId) external view returns (bool);
}
