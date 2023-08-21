// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1271} from './ERC1271.sol';

import {IJBSplitAllocator} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol';
import {IJBPaymentTerminal} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol';
import {IJBDirectory} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol';
import {IJBOperatorStore} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol';
import {IJBController3_1} from '@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol';

import {JBOperatable} from '@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol';

import {IPRBProxy, IPRBProxyRegistry} from '@sablier/v2-periphery/src/types/Proxy.sol';
import {ISablierV2ProxyTarget} from '@sablier/v2-periphery/src/interfaces/ISablierV2ProxyTarget.sol';
import {ISablierV2ProxyPlugin} from '@sablier/v2-periphery/src/interfaces/ISablierV2ProxyPlugin.sol';
import {ISablierV2LockupDynamic} from 'lib/v2-periphery/lib/v2-core/src/interfaces/ISablierV2LockupDynamic.sol';
import {ISablierV2LockupLinear} from 'lib/v2-periphery/lib/v2-core/src/interfaces/ISablierV2LockupLinear.sol';

import {ERC165, IERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
import {IERC20} from 'lib/v2-periphery/lib/v2-core/src/types/Tokens.sol';

import {LockupLinear, LockupDynamic} from '@sablier/v2-periphery/src/types/DataTypes.sol';
import {Batch, Broker} from '@sablier/v2-periphery/src/types/DataTypes.sol';
import {ud60x18, ud2x18} from '@sablier/v2-core/src/types/Math.sol';

import {IAllowanceTransfer, Permit2Params} from '@sablier/v2-periphery/src/types/Permit2.sol';

import {AddStreamsData, DeployedStreams} from '../structs/Streams.sol';

import {IUniswapV3Pool} from '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import {IUniswapV3SwapCallback} from '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import {TickMath} from '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import {OracleLibrary} from '@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol';
import {IWETH9} from '../interfaces/external/IWETH9.sol';
import {IERC20} from 'lib/v2-periphery/lib/v2-core/src/types/Tokens.sol';

abstract contract JBSablier is ERC165, ERC1271, IUniswapV3SwapCallback {
  //*********************************************************************//
  // --------------------------- custom errors ------------------------- //
  //*********************************************************************//

  error JBSablier_Unauthorized();
  error JBSablier_MaxSlippage();
  error JBSablier_InsufficientBalance();

  //*********************************************************************//
  // --------------------- public constant properties ------------------ //
  //*********************************************************************//

  uint256 public immutable projectId;
  IJBDirectory public directory;
  IJBController3_1 public controller;

  /**
   * @dev Proxy used for batch deploys. see https://docs.sablier.com/contracts/v2/guides/proxy-architecture/overview
   */
  IPRBProxy public proxy;

  /// @dev Creates linear streams. see https://docs.sablier.com/contracts/v2/reference/core/contract.SablierV2LockupLinear
  ISablierV2LockupLinear public immutable lockupLinear;

  /// @dev Creates dynamic streams. see https://docs.sablier.com/contracts/v2/reference/core/contract.SablierV2LockupDynamic
  ISablierV2LockupDynamic public immutable lockupDynamic;

  /// @dev Includes stateless scripts for deploying streams.
  /// see https://docs.sablier.com/contracts/v2/reference/periphery/interfaces/interface.ISablierV2ProxyTarget
  ISablierV2ProxyTarget public proxyTarget;

  /// @dev Forwards refunded assets to the proxy owner (this contract) when a stream is cancelled.
  /// see https://docs.sablier.com/contracts/v2/reference/periphery/interfaces/interface.ISablierV2ProxyPlugin
  ISablierV2ProxyPlugin public proxyPlugin;

  /// @dev see https://github.com/PaulRBerg/prb-proxy
  IPRBProxyRegistry public constant PROXY_REGISTRY =
    IPRBProxyRegistry(0x584009E9eDe26e212182c9745F5c000191296a78);
  IAllowanceTransfer public constant PERMIT2 =
    IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

  /**
   * @notice The uniswap pool corresponding to the project token-other token market
   *         (this should be carefully chosen liquidity wise)
   */
  IUniswapV3Pool public immutable POOL;

  /**
   * @notice The WETH contract
   */
  IWETH9 public immutable WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  /**
   * @notice The Uniswap V3 Factory contract
   */
  address public immutable uniswapFactory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

  /// @notice the timeframe to use for the pool twap (from secondAgo to now)
  uint32 public secondsAgo;

  /// @notice the twap max deviation acepted (in 10_000th)
  uint256 public twapDelta;

  //*********************************************************************//
  // --------------------- private constant properties ----------------- //
  //*********************************************************************//

  /**
   * @notice The unit of the max slippage (expressed in 1/10000th)
   */
  uint256 constant SLIPPAGE_DENOMINATOR = 10000;

  /**
   * @notice Address project token < address terminal token ?
   */
  bool immutable TARGET_TOKEN_IS_TOKEN0;

  /**
   * @notice The project token address
   *
   * @dev In this context, this is the token to be streamed
   */
  address immutable TARGET_TOKEN;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  constructor(
    uint256 _projectId,
    IJBDirectory _directory,
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
  ) {
    /* --- */
    TARGET_TOKEN_IS_TOKEN0 = address(_token) < address(WETH);
    TARGET_TOKEN = address(_token);

    POOL = IUniswapV3Pool(
      address(
        uint160(
          uint256(
            keccak256(
              abi.encodePacked(
                hex'ff',
                uniswapFactory,
                keccak256(
                  abi.encode(
                    TARGET_TOKEN_IS_TOKEN0 ? address(_token) : address(WETH),
                    TARGET_TOKEN_IS_TOKEN0 ? address(WETH) : address(_token),
                    _fee
                  )
                ),
                bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54)
              )
            )
          )
        )
      )
    );
    /* --- */

    secondsAgo = _secondsAgo;
    twapDelta = _twapDelta;

    projectId = _projectId;
    directory = _directory;

    lockupLinear = _lockupLinear;
    lockupDynamic = _lockupDynamic;

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
      _interfaceId == type(IJBSplitAllocator).interfaceId || super.supportsInterface(_interfaceId);
  }

  /**
   * @notice The Uniswap V3 pool callback (where token transfer should happens)
   *
   * @dev  Slippage controle is achieved here
   */
  function uniswapV3SwapCallback(
    int256 amount0Delta,
    int256 amount1Delta,
    bytes calldata data
  ) external override {
    // Check if this is really a callback
    if (msg.sender != address(POOL)) revert JBSablier_Unauthorized();

    // Unpack the data
    uint256 _minimumAmountReceived = abi.decode(data, (uint256));

    // delta is in regard of the pool balance (positive = pool need to receive)
    uint256 _amountToSendToPool = TARGET_TOKEN_IS_TOKEN0
      ? uint256(amount1Delta)
      : uint256(amount0Delta);
    uint256 _amountReceivedForBeneficiary = TARGET_TOKEN_IS_TOKEN0
      ? uint256(-amount0Delta)
      : uint256(-amount1Delta);

    // Revert if slippage is too high
    if (_amountReceivedForBeneficiary < _minimumAmountReceived) revert JBSablier_MaxSlippage();

    // Wrap and transfer the WETH to the pool
    WETH.deposit{value: _amountToSendToPool}();
    WETH.transfer(address(POOL), _amountToSendToPool);
  }

  /// @notice Deploys a PRB proxy and plugin that returns tokens to this address
  /// @dev See https://docs.sablier.com/contracts/v2/guides/proxy-architecture/deploy
  /// @return _proxy {IPRBProxy} proxy address
  function deployProxyAndInstallPlugin() public returns (IPRBProxy) {
    // Get the proxy for this contract
    IPRBProxy _proxy = PROXY_REGISTRY.getProxy({user: address(this)});
    if (address(_proxy) == address(0)) {
      // If a proxy doesn't exist, deploy one and install the plugin
      _proxy = PROXY_REGISTRY.deployAndInstallPlugin({plugin: proxyPlugin});
    } else {
      // If the proxy exists, then just install the plugin.
      PROXY_REGISTRY.installPlugin({plugin: proxyPlugin});
    }
    proxy = _proxy;
    return _proxy;
  }

  /// @notice Deploys streams for each stream type defined by user
  /// @dev See https://docs.sablier.com/contracts/v2/guides/proxy-architecture/batch-stream
  /// @param _data see {AddStreamsData} from "../structs/Streams.sol";
  /// @return streams {DeployedStreams} a struct that carries the cycleNumber, and streamIds deployed via Sablier v2
  function _deployStreams(AddStreamsData memory _data) internal returns (DeployedStreams memory) {
    if (IERC20(_data.token).balanceOf(address(this)) < _data.total)
      revert JBSablier_InsufficientBalance();

    // Check if PRBProxy has been setup
    if (address(proxy) == address(0)) deployProxyAndInstallPlugin();

    // Approve tokens for transfer
    _data.token.approve({spender: address(PERMIT2), amount: type(uint160).max});

    // Returned after execution for accounting
    DeployedStreams memory streams;

    // Encode and proxy.execute with data for the proxy target call if user defined each *stream type*
    if (_data.linWithDur.length > 0) {
      bytes memory data = abi.encodeCall(
        proxyTarget.batchCreateWithDurations,
        (lockupLinear, _data.token, _data.linWithDur, _issueNewPermit(_data.token, proxy))
      );

      // Create a batch of Lockup Linear streams via the proxy and Sablier's proxy target
      bytes memory response = proxy.execute(address(proxyTarget), data);
      streams.linearDurStreams = abi.decode(response, (uint256[]));
    }

    if (_data.linWithRange.length > 0) {
      bytes memory data = abi.encodeCall(
        proxyTarget.batchCreateWithRange,
        (lockupLinear, _data.token, _data.linWithRange, _issueNewPermit(_data.token, proxy))
      );

      bytes memory response = proxy.execute(address(proxyTarget), data);
      streams.linearRangeStreams = abi.decode(response, (uint256[]));
    }

    if (_data.dynWithDelta.length > 0) {
      bytes memory data = abi.encodeCall(
        proxyTarget.batchCreateWithDeltas,
        (lockupDynamic, _data.token, _data.dynWithDelta, _issueNewPermit(_data.token, proxy))
      );

      bytes memory response = proxy.execute(address(proxyTarget), data);
      streams.dynDeltaStreams = abi.decode(response, (uint256[]));
    }

    if (_data.dynWithMiles.length > 0) {
      bytes memory data = abi.encodeCall(
        proxyTarget.batchCreateWithMilestones,
        (lockupDynamic, _data.token, _data.dynWithMiles, _issueNewPermit(_data.token, proxy))
      );

      bytes memory response = proxy.execute(address(proxyTarget), data);
      streams.dynMileStreams = abi.decode(response, (uint256[]));
    }

    return streams;
  }

  /// @notice Issues distinct permits for deploying batches of streams via PRBProxy/Permit2
  /// @dev See https://docs.sablier.com/contracts/v2/guides/proxy-architecture/overview
  /// @param _token Our token as an IERC20
  /// @param _proxy Our proxy assigned to this contract
  /// @return Permit2Params The new permit params, which should include a new nonce, as this is called in succession of a proxy.execute()
  function _issueNewPermit(
    IERC20 _token,
    IPRBProxy _proxy
  ) private view returns (Permit2Params memory) {
    // Set up Permit2. See the full documentation at https://github.com/Uniswap/permit2
    IAllowanceTransfer.PermitDetails memory permitDetails;
    permitDetails.token = address(_token);
    permitDetails.amount = type(uint160).max;
    permitDetails.expiration = type(uint48).max; // maximum expiration possible
    (, , permitDetails.nonce) = PERMIT2.allowance({
      user: address(this),
      token: address(_token),
      spender: address(_proxy)
    });

    IAllowanceTransfer.PermitSingle memory permitSingle;
    permitSingle.details = permitDetails;
    permitSingle.spender = address(_proxy); // the proxy will be the spender
    permitSingle.sigDeadline = type(uint48).max; // same deadline as expiration

    // Declare the Permit2 params needed by Sablier
    Permit2Params memory permit2Params;
    permit2Params.permitSingle = permitSingle;
    permit2Params.signature = bytes(''); // dummy signature

    return permit2Params;
  }

  //*********************************************************************//
  // ---------------------- internal functions ------------------------- //
  //*********************************************************************//

  /**
   * @notice  Get a quote based on twap over a secondsAgo period, taking into account a twapDelta max deviation
   *
   * @param   _amountIn the amount to swap
   *
   * @return  _amountOut the minimum amount received according to the twap
   */
  function _getQuote(uint256 _amountIn) internal view returns (uint256 _amountOut) {
    // If non-existing or non-initialized pool, quote 0
    try POOL.slot0() returns (uint160, int24, uint16, uint16, uint16, uint8, bool unlocked) {
      // non initialized?
      if (!unlocked) return 0;
    } catch {
      // invalid address or not deployed yet?
      return 0;
    }

    // Get the twap tick
    (int24 arithmeticMeanTick, ) = OracleLibrary.consult(address(POOL), secondsAgo);

    // Get a quote based on this twap tick
    _amountOut = OracleLibrary.getQuoteAtTick(
      arithmeticMeanTick,
      uint128(_amountIn),
      address(WETH),
      address(TARGET_TOKEN)
    );

    // Return the lowest twap accepted
    _amountOut -= (_amountOut * twapDelta) / SLIPPAGE_DENOMINATOR;
  }

  /**
   * @notice Swap the terminal token to receive the project toke_beforeTransferTon
   *
   * @dev    This delegate first receive the whole amount of project token,
   *         then send the non-reserved token to the beneficiary,
   *         then burn the rest of this delegate balance (ie the amount of reserved token),
   *         then mint the same amount as received (this will add the reserved token, following the fc rate)
   *         then burn the difference (ie this delegate balance)
   *         -> End result is having the correct balances (beneficiary and reserve), according to the reserve rate
   *
   * @param  _amount amount being swapped
   * @param  _minimumReceivedFromSwap the minimum amount received, to prevent slippage
   */
  function _swap(
    int256 _amount,
    uint256 _minimumReceivedFromSwap
  ) internal returns (uint256 _amountReceived) {
    // Pass the token and min amount to receive as extra data
    try
      POOL.swap({
        recipient: address(this),
        zeroForOne: !TARGET_TOKEN_IS_TOKEN0,
        amountSpecified: _amount,
        sqrtPriceLimitX96: TARGET_TOKEN_IS_TOKEN0
          ? TickMath.MAX_SQRT_RATIO - 1
          : TickMath.MIN_SQRT_RATIO + 1,
        data: abi.encode(_minimumReceivedFromSwap)
      })
    returns (int256 amount0, int256 amount1) {
      // Swap succeded, take note of the amount of TARGET_TOKEN received (negative as it is an exact input)
      _amountReceived = uint256(-(TARGET_TOKEN_IS_TOKEN0 ? amount0 : amount1));
    } catch {
      // implies _amountReceived = 0 -> will later mint when back in didPay
      return _amountReceived;
    }
  }
}
