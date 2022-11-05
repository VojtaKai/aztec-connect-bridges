// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {IConvexBooster} from "../../interfaces/convex/IConvexBooster.sol";
import {ICurveLpToken} from "../../interfaces/convex/ICurveLpToken.sol";
import {ICurveRewards} from "../../interfaces/convex/ICurveRewards.sol";

/**
 @notice A DefiBridge that allows user to stake Curve LP tokens through Convex Finance and earn boosted CRV 
 without locking them in for an extended period of time. Plus earning CVX and possibly other rewards. 
 @notice Staked tokens can be withdrawn (unstaked) any time.
 @dev Convex Finance mints pool specific Convex LP token, however, not for the staking user (the bridge) directly. 
 Hence, a storage of interactions with the bridge had to be implemented to know how much Curve LP token 
 was staked and which Convex LP token was minted to represent this staking action. 
 Since the Convex LP token is not returned to the bridge, Rollup Processor resp., 
 a virtual asset is used on output and an interaction `receipt` is created utilizing the virtual asset ID. 
 The receipt is then used to withdraw the staked means when a virtual asset of the matching ID is provided on input. 
 @dev Synchronous and stateful bridge that keeps track of deposit interactions with the bridge that are later used for withdrawal.
 @author Vojtech Kaiser
 */
contract ConvexStakingBridge is BridgeBase {
    using SafeERC20 for IConvexBooster;
    using SafeERC20 for ICurveLpToken;

    struct PoolInfo {
        uint256 poolPid;
        address curveLpToken;
        address convexToken;
        address curveRewards;
        bool exists;
    }

    struct Interaction {
        uint256 valueStaked;
        address representingConvexToken;
        bool exists;
    }

    // Contracts
    IConvexBooster public constant BOOSTER = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ICurveLpToken public curveLpToken;
    ICurveRewards public curveRewards;

    // Pools
    uint256 public lastPoolLength;

    mapping(address => PoolInfo) public pools;

    // Interactions - represent deposit action, stored for withdrawal
    mapping(uint256 => Interaction) public interactions;

    // Errors
    error InvalidAssetType();
    error UnknownVirtualAsset();
    error IncorrectInteractionValue(uint256 stakedValue, uint256 valueToWithdraw);

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        _loadPools();

        uint256[] memory criterias = new uint256[](2 * lastPoolLength);
        uint32[] memory gasUsage = new uint32[](2 * lastPoolLength);
        uint32[] memory minGasPerMinute = new uint32[](2 * lastPoolLength);

        for (uint256 i = 0; i < lastPoolLength; i++) {
            (address curveLpToken, , , , , ) = BOOSTER.poolInfo(i);
            criterias[i] = uint256(keccak256(abi.encodePacked(curveLpToken, address(0))));
            gasUsage[i] = 1000000;
            minGasPerMinute[i] = 690;

            criterias[lastPoolLength + i] = uint256(keccak256(abi.encodePacked(address(0), curveLpToken)));
            gasUsage[lastPoolLength + i] = 375000;
            minGasPerMinute[lastPoolLength + i] = 260;
        }

        SUBSIDY.setGasUsageAndMinGasPerMinute(criterias, gasUsage, minGasPerMinute);
    }

    /**
    @notice function so the bridge can receive ether. Used for subsidy.
    */
    receive() external payable {}

    /**
    @notice Stake and unstake Curve LP tokens through Convex Finance Booster anytime.
    @notice Convert rate between Curve LP token and corresponding Convex LP token is 1:1
    @notice Stake == Deposit, Unstake == Withdraw
    @param _inputAssetA Curve LP token (staking), virtual asset (unstaking)
    @param _outputAssetA Virtual asset (staking), Curve LP token (unstaking)
    @param _totalInputValue Total number of Curve LP tokens to deposit / withdraw
    @param _auxData Data to claim staking rewards
    @param outputValueA Number of Curve LP tokens staked / unstaked
    @param _rollupBeneficiary Address of the contract that receives subsidy
    */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _inputAssetB,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _totalInputValue,
        uint256,
        uint64 _auxData,
        address _rollupBeneficiary
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        if (_totalInputValue == 0) {
            revert ErrorLib.InvalidInputAmount();
        }

        _loadPools();

        PoolInfo memory selectedPool;

        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            // deposit
            if (!pools[_inputAssetA.erc20Address].exists) {
                revert ErrorLib.InvalidInputA();
            }

            selectedPool = pools[_inputAssetA.erc20Address];

            _setTokens(selectedPool);

            // approvals
            curveLpToken.approve(address(BOOSTER), _totalInputValue);

            uint256 startCurveRewards = curveRewards.balanceOf(address(this));

            BOOSTER.deposit(selectedPool.poolPid, _totalInputValue, true);

            uint256 endCurveRewards = curveRewards.balanceOf(address(this));

            outputValueA = (endCurveRewards - startCurveRewards);

            interactions[_outputAssetA.id] = Interaction(_totalInputValue, selectedPool.convexToken, true);
        } else if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20
        ) {
            // withdraw
            if (!interactions[_inputAssetA.id].exists) {
                revert UnknownVirtualAsset();
            }
            // withdraw amount needs to be equal to the staked value of the interaction
            if (interactions[_inputAssetA.id].valueStaked != _totalInputValue) {
                revert IncorrectInteractionValue(interactions[_inputAssetA.id].valueStaked, _totalInputValue);
            }

            selectedPool = pools[_outputAssetA.erc20Address];

            if (
                !selectedPool.exists ||
                selectedPool.convexToken != interactions[_inputAssetA.id].representingConvexToken
            ) {
                revert ErrorLib.InvalidOutputA();
            }

            _setTokens(selectedPool);

            outputValueA = _withdraw(_inputAssetA, _totalInputValue, _auxData, selectedPool);
        } else {
            revert InvalidAssetType();
        }

        // Pay out subsidy to the rollupBeneficiary
        SUBSIDY.claimSubsidy(
            computeCriteria(_inputAssetA, _inputAssetB, _outputAssetA, _outputAssetB, _auxData),
            _rollupBeneficiary
        );
    }

    /** 
    @notice Internal function to withdraw Curve LP tokens
    */
    function _withdraw(
        AztecTypes.AztecAsset memory _inputAssetA,
        uint256 _totalInputValue,
        uint64 _auxData,
        PoolInfo memory _selectedPool
    ) internal returns (uint256 outputValueA) {
        // approvals
        curveLpToken.approve(ROLLUP_PROCESSOR, _totalInputValue);

        uint256 startCurveLpTokens = curveLpToken.balanceOf(address(this));

        // transfer CONVEX tokens from CrvRewards back to the bridge
        bool claimRewards = _auxData == 1; // if passed anything but 1, rewards will not be claimed
        curveRewards.withdraw(_totalInputValue, claimRewards);

        BOOSTER.withdraw(_selectedPool.poolPid, _totalInputValue);

        uint256 endCurveLpTokens = curveLpToken.balanceOf(address(this));

        outputValueA = (endCurveLpTokens - startCurveLpTokens);

        delete interactions[_inputAssetA.id];
    }

    /**
    @notice Loads pool information for all pools supported by Convex Finance.
    @notice Cached. Loads only new pools.
    */
    function _loadPools() internal {
        uint256 currentPoolLength = BOOSTER.poolLength();
        if (currentPoolLength != lastPoolLength) {
            for (uint256 i = lastPoolLength; i < currentPoolLength; i++) {
                (address curveLpToken, address convexToken, , address curveRewards, , ) = BOOSTER.poolInfo(i);
                pools[curveLpToken] = PoolInfo(i, curveLpToken, convexToken, curveRewards, true);
            }
            lastPoolLength = currentPoolLength;
        }
    }

    /** 
    @notice Sets up pool specific tokens.
    */
    function _setTokens(PoolInfo memory _selectedPool) internal {
        curveLpToken = ICurveLpToken(_selectedPool.curveLpToken);
        curveRewards = ICurveRewards(_selectedPool.curveRewards);
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
    ) public view override(BridgeBase) returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_inputAssetA.erc20Address, _outputAssetA.erc20Address)));
    }
}
