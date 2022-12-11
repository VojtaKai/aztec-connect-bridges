// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IConvexBooster} from "../../interfaces/convex/IConvexBooster.sol";
import {ICurveRewards} from "../../interfaces/convex/ICurveRewards.sol";
import {IRepConvexToken} from "../../interfaces/convex/IRepConvexToken.sol";
import {ICrvEthExchange} from "../../interfaces/convex/ICrvEthExchange.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {RepresentingConvexToken} from "./RepresentingConvexToken.sol";

/**
 * @notice Bridge that allows users stake their Curve LP tokens and earn rewards on them.
 * @dev User earns boosted CRV without locking them in for an extended period of time. Plus CVX and possibly other rewards.
 * Rewards are swapped for ether if sufficient amount is earned.
 * User can withdraw (unstake) any time.
 * @dev Convex Finance mints pool specific Convex LP token but not for the staking user (the bridge) directly.
 * RCT ERC20 token is deployed for each loaded pool and mirrors balance of minted Convex LP tokens for the bridge.
 * Main purpose of RCT tokens is that they can be owned by the bridge and recovered by the Rollup Processor.
 * @dev Synchronous and stateless bridge
 * @author Vojtech Kaiser (VojtaKai on GitHub)
 */
contract ConvexStakingBridge is BridgeBase {
    using SafeERC20 for IConvexBooster;
    using SafeERC20 for IRepConvexToken;
    using SafeERC20 for IERC20;

    /**
     * @param poolId Id of the staking pool
     * @param convexLpToken Token minted for Convex Finance to track ownership and amount of staked tokens
     * @param curveRewards Contract that keeps tracks of minted Convex LP tokens and earned rewards
     */
    struct PoolInfo {
        uint96 poolId;
        address convexLpToken;
        address curveRewards;
    }

    // Convex Finance Booster
    IConvexBooster public constant BOOSTER = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    // Representing Convex Token implementation address
    address public immutable RCT_IMPLEMENTATION;

    // Deployed RCT clones, mapping(CurveLpToken => RCT)
    mapping(address => address) public deployedClones;

    // Pools information
    uint256 public poolsLength;
    // mapping(CurveLpToken => PoolInfo)
    mapping(address => PoolInfo) public pools;

    // Reward tokens
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    // Swapping pools
    address public constant CRVETH = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    address public constant CVXETH = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;

    /**
     * @notice Sets the address of the RollupProcessor and deploys RCT token
     * @dev Deploys RCT token implementation
     * @param _rollupProcessor The address of the RollupProcessor to use
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        RCT_IMPLEMENTATION = address(new RepresentingConvexToken());
    }

    /**
     * @notice Empty receive function so the bridge can receive ether. Used for subsidy and swap of rewards for ether.
     */
    receive() external payable {}

    /**
     * @notice Stakes Curve LP tokens and earns rewards on them. Gets back RCT token.
     * @dev Convert rate between Curve LP token and corresponding Convex LP token is 1:1.
     * Stake == Deposit, Unstake == Withdraw
     * RCT (Representing Convex Token) is a representation of Convex LP token minted for bridge but fully owned by the bridge.
     * CRV and CXV rewards are swapped for ether if sufficient amount is present.
     * @param _inputAssetA Curve LP token (staking), RCT (unstaking)
     * @param _outputAssetA RCT (staking), Curve LP token (unstaking)
     * @param _outputAssetB ETH (Unstaking) - CRV and CVX token rewards are turned into ether
     * @param _totalInputValue Total number of Curve LP tokens to deposit / withdraw
     * @param _interactionNonce A unique identifier of the DeFi interaction
     * @param _rollupBeneficiary Address of the beneficiary that receives subsidy
     * @return outputValueA Number of Curve LP tokens staked / unstaked, number of RCT minted / burned
     * @return outputValueB Amount of ETH collected for swapped rewards
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint64,
        address _rollupBeneficiary
    ) external payable override (BridgeBase) onlyRollup returns (uint256 outputValueA, uint256 outputValueB, bool) {
        if (
            _inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20
                || _outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20
        ) {
            revert ErrorLib.InvalidInput();
        }

        if (deployedClones[_inputAssetA.erc20Address] == _outputAssetA.erc20Address) {
            // deposit
            PoolInfo memory selectedPool = pools[_inputAssetA.erc20Address];

            outputValueA = _deposit(_outputAssetA, _totalInputValue, selectedPool);
        } else if (
            deployedClones[_outputAssetA.erc20Address] == _inputAssetA.erc20Address
                && _outputAssetB.assetType == AztecTypes.AztecAssetType.ETH
        ) {
            // withdrawal
            (outputValueA, outputValueB) = _withdraw(_inputAssetA, _outputAssetA, _totalInputValue, _interactionNonce);
        } else {
            revert ErrorLib.InvalidInput(); // invalid address or pool has not been loaded yet / RCT token not deployed yet
        }

        // Pays out subsidy to the rollupBeneficiary
        SUBSIDY.claimSubsidy(
            _computeCriteria(_inputAssetA.erc20Address, _outputAssetA.erc20Address), _rollupBeneficiary
        );
    }

    /**
     * @notice Sets allowance for exchange pools to collect earned rewards
     */
    function setApprovals() external {
        if (!IERC20(CRV).approve(CRVETH, type(uint256).max)) revert ErrorLib.ApproveFailed(CRV);
        if (!IERC20(CVX).approve(CVXETH, type(uint256).max)) revert ErrorLib.ApproveFailed(CVX);
    }

    /**
     * @notice Loads pool information for a specific pool and sets up auxiliary services.
     * @dev Loads pool information for a specific pool supported by Convex Finance.
     * Deployment of RCT token for the specific pool is part of the loading.
     * Set allowance for Booster and Rollup Processor to manipulate bridge's Curve LP tokens and RCT (through RCT Clone).
     * Setup bridge subsidy.
     * @param _poolId Id of the pool to load
     */
    function loadPool(uint256 _poolId) external {
        (address curveLpToken, address convexLpToken,, address curveRewards,,) = BOOSTER.poolInfo(_poolId);
        pools[curveLpToken] = PoolInfo(uint96(_poolId), convexLpToken, curveRewards);

        // deploy RCT clone, log clone address
        address deployedClone = Clones.clone(RCT_IMPLEMENTATION);
        // RCT token initialization - deploy fully working ERC20 RCT token
        RepresentingConvexToken(deployedClone).initialize("RepresentingConvexToken", "RCT");

        deployedClones[curveLpToken] = deployedClone;

        // approvals for pool specific tokens
        IERC20(curveLpToken).safeIncreaseAllowance(address(BOOSTER), type(uint256).max);
        IERC20(curveLpToken).safeIncreaseAllowance(ROLLUP_PROCESSOR, type(uint256).max);
        IRepConvexToken(deployedClone).safeIncreaseAllowance(ROLLUP_PROCESSOR, type(uint256).max);

        // subsidy
        uint256[] memory criterias = new uint256[](2);
        uint32[] memory gasUsage = new uint32[](2);
        uint32[] memory minGasPerMinute = new uint32[](2);

        criterias[0] = uint256(keccak256(abi.encodePacked(curveLpToken, deployedClone)));
        criterias[1] = uint256(keccak256(abi.encodePacked(deployedClone, curveLpToken)));
        gasUsage[0] = 500000;
        gasUsage[1] = 500000;
        minGasPerMinute[0] = 350;
        minGasPerMinute[1] = 350;

        SUBSIDY.setGasUsageAndMinGasPerMinute(criterias, gasUsage, minGasPerMinute);
    }

    /**
     * @notice Computes the criteria that is passed when claiming subsidy.
     * @param _inputAssetA The input asset
     * @param _outputAssetA The output asset
     * @return The criteria
     */
    function computeCriteria(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint64
    ) public pure override (BridgeBase) returns (uint256) {
        return _computeCriteria(_inputAssetA.erc20Address, _outputAssetA.erc20Address);
    }

    /**
     * @notice Deposits Curve LP tokens
     * @dev RCT is minted for the bridge. Mirrors balance of minted Convex LP tokens for the bridge.
     * @param _outputAssetA Asset for the RCT token
     * @param _totalInputValue Number of Curve LP tokens to stake
     * @param _selectedPool Pool info about the staking pool
     * @return outputValueA Number of successfully staked Curve LP tokens
     */
    function _deposit(
        AztecTypes.AztecAsset memory _outputAssetA,
        uint256 _totalInputValue,
        PoolInfo memory _selectedPool
    ) internal returns (uint256 outputValueA) {
        uint256 startCurveRewards = ICurveRewards(_selectedPool.curveRewards).balanceOf(address(this));

        BOOSTER.deposit(_selectedPool.poolId, _totalInputValue, true);

        uint256 endCurveRewards = ICurveRewards(_selectedPool.curveRewards).balanceOf(address(this));

        outputValueA = (endCurveRewards - startCurveRewards);

        IRepConvexToken(_outputAssetA.erc20Address).mint(_totalInputValue);
    }

    /**
     * @notice Withdraws Curve LP tokens.
     * @dev RCT is burned for the bridge. Mirrors balance of minted Convex LP tokens for the bridge.
     * @param _inputAssetA Asset for the RCT token.
     * @param _outputAssetA Asset for the Curve LP token.
     * @param _totalInputValue Number of Curve LP tokens to unstake.
     * @return outputValueA Number of withdrawn Curve LP tokens.
     */
    function _withdraw(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _outputAssetA,
        uint256 _totalInputValue,
        uint256 _interactionNonce
    ) internal returns (uint256 outputValueA, uint256 outputValueB) {
        PoolInfo memory selectedPool = pools[_outputAssetA.erc20Address];

        uint256 startCurveLpTokens = IERC20(_outputAssetA.erc20Address).balanceOf(address(this));

        // transfer ConvexLP tokens from CrvRewards back to the bridge
        ICurveRewards(selectedPool.curveRewards).withdraw(_totalInputValue, true); // always claim rewards

        outputValueB += _swapRewardTokenForEth(CRVETH, CRV);
        outputValueB += _swapRewardTokenForEth(CVXETH, CVX);

        BOOSTER.withdraw(selectedPool.poolId, _totalInputValue);

        uint256 endCurveLpTokens = IERC20(_outputAssetA.erc20Address).balanceOf(address(this));

        outputValueA = (endCurveLpTokens - startCurveLpTokens);

        IRepConvexToken(_inputAssetA.erc20Address).burn(_totalInputValue);

        // Send ETH to rollup processor
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueB}(_interactionNonce);
    }

    /**
     * @notice Swaps reward tokens for ether.
     * @dev dyMin is the least acceptable amount of ether for the amount of _token. Tolerated price difference due to slippage is 1 %.
     * @param _exchangePool Curve swapping (exchange) pool used to exchange a reward token for ether.
     * @param _token Reward token to swap for ether.
     * @return collectedEth Amount of ether collected for the amount of _token.
     */
    function _swapRewardTokenForEth(address _exchangePool, address _token) private returns (uint256 collectedEth) {
        uint256 dyMin;
        try ICrvEthExchange(_exchangePool).get_dy(1, 0, IERC20(_token).balanceOf(address(this))) returns (uint256 dy) {
            dyMin = dy * 99 / 100;
        } catch {}

        if (dyMin > 0) {
            try ICrvEthExchange(_exchangePool).exchange_underlying(1, 0, IERC20(_token).balanceOf(address(this)), dyMin)
            returns (uint256 value) {
                collectedEth = value;
            } catch {}
        }
    }

    /**
     * @notice Computes the criteria that is passed when claiming subsidy.
     * @param _inputToken The input asset address
     * @param _outputToken The output asset address
     * @return The criteria
     */
    function _computeCriteria(address _inputToken, address _outputToken) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_inputToken, _outputToken)));
    }
}
