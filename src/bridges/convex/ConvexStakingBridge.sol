// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IConvexBooster} from "../../interfaces/convex/IConvexBooster.sol";
import {ICurveLpToken} from "../../interfaces/convex/ICurveLpToken.sol";
import {ICurveRewards} from "../../interfaces/convex/ICurveRewards.sol";
import {IRepConvexToken} from "../../interfaces/convex/IRepConvexToken.sol";
import {RepresentingConvexToken} from "./RepresentingConvexToken.sol";

/**
 * @notice Bridge that allows users stake their Curve LP tokens and earn rewards on them
 * @dev Synchronous and stateless bridge
 * @author Vojtech Kaiser
 */
contract ConvexStakingBridge is BridgeBase {
    using SafeERC20 for IConvexBooster;
    using SafeERC20 for ICurveLpToken;

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

    /**
     * @notice Sets the address of the RollupProcessor and deploys RCT token
     * @dev Deploys RCT token implementation
     * @param _rollupProcessor The address of the RollupProcessor to use
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        RCT_IMPLEMENTATION = address(new RepresentingConvexToken());
    }

    /**
     * @notice Empty receive function so the bridge can receive ether. Used for subsidy.
     */
    receive() external payable {}

    /**
     * @notice Stakes Curve LP tokens and earns rewards on them. Gets back RCT token.
     * @dev Convert rate between Curve LP token and corresponding Convex LP token is 1:1.
     * @dev Stake == Deposit, Unstake == Withdraw
     * @dev RCT (Representing Convex Token) is a representation of Convex LP token minted for bridge but fully owned by the bridge
     * @param _inputAssetA Curve LP token (staking), RCT (unstaking)
     * @param _outputAssetA RCT (staking), Curve LP token (unstaking)
     * @param _totalInputValue Total number of Curve LP tokens to deposit / withdraw
     * @param outputValueA Number of Curve LP tokens staked / unstaked, Number of RCT minted / burned
     * @param _rollupBeneficiary Address of the beneficiary that receives subsidy
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256,
        uint64,
        address _rollupBeneficiary
    ) external payable override (BridgeBase) onlyRollup returns (uint256 outputValueA, uint256, bool) {
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
        } else if (deployedClones[_outputAssetA.erc20Address] == _inputAssetA.erc20Address) {
            // withdrawal
            outputValueA = _withdraw(_inputAssetA, _outputAssetA, _totalInputValue);
        } else {
            revert ErrorLib.InvalidInput(); // invalid address or pool has not been loaded yet / RCT token not deployed yet
        }

        // Pays out subsidy to the rollupBeneficiary
        SUBSIDY.claimSubsidy(
            _computeCriteria(_inputAssetA.erc20Address, _outputAssetA.erc20Address), _rollupBeneficiary
        );
    }

    /**
     * @notice Loads pool information for a specific pool and sets up auxiliary services.
     * @dev Loads pool information for a specific pool supported by Convex Finance.
     * @dev Deployment of RCT token for the specific pool is part of the loading.
     * @dev Set allowance for Booster and Rollup Processor to manipulate bridge's Curve LP tokens and RCT (through RCT Clone).
     * @dev Setup bridge subsidy.
     * @param _poolId Id of the pool to load
     */
    function loadPool(uint256 _poolId) external {
        (address curveLpToken, address convexLpToken,, address curveRewards,,) = BOOSTER.poolInfo(_poolId);
        pools[curveLpToken] = PoolInfo(uint96(_poolId), convexLpToken, curveRewards);

        // deploy clone, log clone address
        address deployedClone = Clones.clone(RCT_IMPLEMENTATION);
        // RCT token initialization - deploy fully working ERC20 RCT token
        RepresentingConvexToken(deployedClone).initialize("RepresentingConvexToken", "RCT");

        deployedClones[curveLpToken] = deployedClone;

        // approvals
        ICurveLpToken(curveLpToken).approve(address(BOOSTER), type(uint256).max);
        ICurveLpToken(curveLpToken).approve(ROLLUP_PROCESSOR, type(uint256).max);
        IRepConvexToken(deployedClone).approve(ROLLUP_PROCESSOR, type(uint256).max);

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
     * @param _inputAssetA Asset for the RCT token
     * @param _outputAssetA Asset for the Curve LP token
     * @param _totalInputValue Number of Curve LP tokens to unstake
     */
    function _withdraw(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _outputAssetA,
        uint256 _totalInputValue
    ) internal returns (uint256 outputValueA) {
        PoolInfo memory selectedPool = pools[_outputAssetA.erc20Address];

        uint256 startCurveLpTokens = ICurveLpToken(_outputAssetA.erc20Address).balanceOf(address(this));

        // transfer ownership of ConvexLP tokens from CrvRewards back to the bridge
        ICurveRewards(selectedPool.curveRewards).withdraw(_totalInputValue, true); // always claim rewards

        BOOSTER.withdraw(selectedPool.poolId, _totalInputValue);

        uint256 endCurveLpTokens = ICurveLpToken(_outputAssetA.erc20Address).balanceOf(address(this));

        outputValueA = (endCurveLpTokens - startCurveLpTokens);

        IRepConvexToken(_inputAssetA.erc20Address).burn(_totalInputValue);
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
