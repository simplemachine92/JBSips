// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {JBSablier} from "../src/abstract/JBSablier.sol";

import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBSplitAllocator} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSplitAllocator.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBOperatorStore} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBOperatorStore.sol";
import {JBFundingCycle} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBFundingCycle.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import {JBSplitAllocationData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBSplitAllocationData.sol";
import {JBOperatable} from "@jbx-protocol/juice-contracts-v3/contracts/abstract/JBOperatable.sol";
import {JBOperations} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBOperations.sol";

import {ISablierV2ProxyTarget} from "@sablier/v2-periphery/interfaces/ISablierV2ProxyTarget.sol";
import {ISablierV2ProxyPlugin} from "@sablier/v2-periphery/interfaces/ISablierV2ProxyPlugin.sol";
import {ISablierV2LockupDynamic} from "@sablier/v2-core/interfaces/ISablierV2LockupDynamic.sol";
import {ISablierV2LockupLinear} from "@sablier/v2-core/interfaces/ISablierV2LockupLinear.sol";

import {IPRBProxy, IPRBProxyRegistry} from "@sablier/v2-periphery/types/Proxy.sol";

import {ISablierV2LockupDynamic} from "@sablier/v2-core/interfaces/ISablierV2LockupDynamic.sol";
import {ISablierV2LockupLinear} from "@sablier/v2-core/interfaces/ISablierV2LockupLinear.sol";

import {IERC20} from "@sablier/v2-core/types/Tokens.sol";
import {IAllowanceTransfer, Permit2Params} from "@sablier/v2-periphery/types/Permit2.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {IERC20} from "@sablier/v2-core/types/Tokens.sol";

import {IWETH9} from "./interfaces/external/IWETH9.sol";

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
contract JBSips is JBSablier, JBOperatable, IJBSplitAllocator, IUniswapV3SwapCallback {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//

    error JuiceSips_Unauthorized();
    error JuiceSips_MaximumSlippage();

    //*********************************************************************//
    // -----------------------------  events ----------------------------- //
    //*********************************************************************//

    /**
     * @notice Address project token < address terminal token ?
     */
    bool immutable TARGET_TOKEN_IS_TOKEN0;

    address immutable TARGET_TOKEN;

    /**
     * @notice The unit of the max slippage (expressed in 1/10000th)
     */
    uint256 constant SLIPPAGE_DENOMINATOR = 10000;

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

    //*********************************************************************//
    // --------------------- public stored properties -------------------- //
    //*********************************************************************//

    mapping(address => uint256) public idByAddress;
    uint256 public lastCycleNumber;

    // the timeframe to use for the pool twap (from secondAgo to now)
    uint32 public secondsAgo;

    // the twap max deviation acepted (in 10_000th)
    uint256 public twapDelta;

    /* // any ETH left-over in this contract (from swap in the end of liquidity range)
    mapping(address => uint256) public sweepBalanceOf;

    // running cumulative sum of ETH left-over
    uint256 public sweepBalance; */

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
            _controller
        )
        JBOperatable(IJBOperatorStore(_operatorStore))
    {
        /* --- */
        TARGET_TOKEN_IS_TOKEN0 = address(_token) < address(WETH);
        TARGET_TOKEN = address(_token);
        
        POOL = IUniswapV3Pool(address(uint160(uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        uniswapFactory,
                        keccak256(abi.encode(
                            TARGET_TOKEN_IS_TOKEN0 ? address(_token) : address(WETH),
                            TARGET_TOKEN_IS_TOKEN0 ? address(WETH) : address(_token),
                            _fee)),
                        bytes32(0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54)
                    )
                )
        ))));

        secondsAgo = _secondsAgo;
        twapDelta = _twapDelta;
    }

    /// @notice Called by a project's payout (JBTerminal) or reserved token distribution split (JBController)
    /// @dev See https://docs.juicebox.money/dev/learn/glossary/split-allocator/
    /// @param _data See https://docs.juicebox.money/dev/api/data-structures/jbsplitallocationdata/
    function allocate(JBSplitAllocationData calldata _data) external payable {
        // Ensure call is coming from Terminal or Controller
        if (
            !directory.isTerminalOf(
                _data.projectId,
                IJBPaymentTerminal(msg.sender)
            ) && directory.controllerOf(_data.projectId) != msg.sender
        ) revert JuiceSips_Unauthorized();

        if (_data.projectId != projectId) revert JuiceSips_Unauthorized();

         // Track funding cycles in state var for accounting purposes
        (JBFundingCycle memory _cycle, ) = controller.currentFundingCycleOf(
            projectId
        );
        lastCycleNumber = _cycle.number;

        /* int256 toSwap = int256(msg.value); */

        uint256 quote = _getQuote(msg.value);

        uint256 tokensFromSwap = _swap(int256(msg.value), quote);

        // Logic for handling ETH payouts
        if (
            directory.isTerminalOf(
                _data.projectId,
                IJBPaymentTerminal(msg.sender)
            )
        ) {}
    }

    /**
     * @notice The Uniswap V3 pool callback (where token transfer should happens)
     *
     * @dev    Slippage controle is achieved here
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        // Check if this is really a callback
        if (msg.sender != address(POOL)) revert JuiceSips_Unauthorized();

        // Unpack the data
        (uint256 _minimumAmountReceived) = abi.decode(data, (uint256));

        // delta is in regard of the pool balance (positive = pool need to receive)
        uint256 _amountToSendToPool = TARGET_TOKEN_IS_TOKEN0 ? uint256(amount1Delta) : uint256(amount0Delta);
        uint256 _amountReceivedForBeneficiary =
            TARGET_TOKEN_IS_TOKEN0 ? uint256(-amount0Delta) : uint256(-amount1Delta);

        // Revert if slippage is too high
        if (_amountReceivedForBeneficiary < _minimumAmountReceived) revert JuiceSips_MaximumSlippage();

        // Wrap and transfer the WETH to the pool
        WETH.deposit{value: _amountToSendToPool}();
        WETH.transfer(address(POOL), _amountToSendToPool);
    }

    function configureCycleStreams() 
        external
        requirePermission(
            controller.projects().ownerOf(projectId),
            projectId,
            JBOperations.SET_SPLITS
        ) {
                
        }

    function deploy()
        external
        requirePermission(
            controller.projects().ownerOf(projectId),
            projectId,
            JBOperations.SET_SPLITS
        )
        returns (IPRBProxy proxy)
    {
        return super.deployProxyAndInstallPlugin();
    }

    /* function withdrawFromStream() external {}

    function configureRecipients()
        external
        requirePermission(
            controller.projects().ownerOf(projectId),
            projectId,
            JBOperations.SET_SPLITS
        )
    {}

    function cancelStreams()
        external
        requirePermission(
            controller.projects().ownerOf(projectId),
            projectId,
            JBOperations.SET_SPLITS
        )
    {} */

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
        (int24 arithmeticMeanTick,) = OracleLibrary.consult(address(POOL), secondsAgo);

        // Get a quote based on this twap tick
        _amountOut =
            OracleLibrary.getQuoteAtTick(arithmeticMeanTick, uint128(_amountIn), address(WETH), address(TARGET_TOKEN));

        // Return the lowest twap accepted
        _amountOut -= _amountOut * twapDelta / SLIPPAGE_DENOMINATOR;
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
    function _swap(int256 _amount, uint256 _minimumReceivedFromSwap)
        internal
        returns (uint256 _amountReceived)
    {
        // Pass the token and min amount to receive as extra data
        try POOL.swap({
            recipient: address(this),
            zeroForOne: !TARGET_TOKEN_IS_TOKEN0,
            amountSpecified: _amount,
            sqrtPriceLimitX96: TARGET_TOKEN_IS_TOKEN0 ? TickMath.MAX_SQRT_RATIO - 1 : TickMath.MIN_SQRT_RATIO + 1,
            data: abi.encode(_minimumReceivedFromSwap)
        }) returns (int256 amount0, int256 amount1) {
            // Swap succeded, take note of the amount of TARGET_TOKEN received (negative as it is an exact input)
            _amountReceived = uint256(-(TARGET_TOKEN_IS_TOKEN0 ? amount0 : amount1));
        } catch {
            // implies _amountReceived = 0 -> will later mint when back in didPay
            return _amountReceived;
        }
    }


    // Function to receive Ether. msg.data must be empty
    receive() external payable {}
}
