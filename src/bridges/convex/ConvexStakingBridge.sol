// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {IConvexDeposit} from "../../interfaces/convex/IConvexDeposit.sol";
import {ICurveLpToken} from "../../interfaces/convex/ICurveLpToken.sol";
import {ICurveRewards} from "../../interfaces/convex/ICurveRewards.sol";


/**
 @notice A DefiBridge that allows Convex Finance to stake Curve LP tokens on our behalf and earn boosted CRV 
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
    using SafeERC20 for IConvexDeposit;
    using SafeERC20 for ICurveLpToken;

    // Contracts
    IConvexDeposit public constant DEPOSIT = IConvexDeposit(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ICurveLpToken public CURVE_LP_TOKEN;
    ICurveRewards public CURVE_REWARDS;
    
    // Pools
    uint public lastPoolLength;

    struct PoolInfo {
        uint poolPid;
        address curveLpToken;
        address convexToken;
        address curveRewards;
        bool exists;
    }
    mapping(address => PoolInfo) public pools;

    // Interactions - represent deposit action, stored for withdrawal
    struct Interaction {
        uint valueStaked;
        address representedConvexToken;
        bool exists;
    }

    mapping(uint => Interaction) public interactions;

    // Errors
    error InvalidAssetType();
    error UnknownVirtualAsset();
    error IncorrectInteractionValue(uint stakedValue, uint valueToWithdraw);
    

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        _loadPools();

        uint[] memory criterias = new uint[](2* lastPoolLength);
        uint32[] memory gasUsage = new uint32[](2 * lastPoolLength);
        uint32[] memory minGasPerMinute = new uint32[](2 * lastPoolLength);

        for (uint i = 0; i < lastPoolLength; i++) {
            (address curveLpToken,,,,,) = DEPOSIT.poolInfo(i);
            criterias[i] = uint(keccak256(abi.encodePacked(curveLpToken, address(0))));
            gasUsage[i] = 1000000;
            minGasPerMinute[i] = 690;

            criterias[lastPoolLength + i] = uint(keccak256(abi.encodePacked(address(0), curveLpToken)));
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
    @notice Stake and unstake Curve LP tokens through Convex Finance Deposit contract anytime.
    @notice Convert rate between Curve LP Token and corresponding Convex LP Token is 1:1
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
        uint _totalInputValue,
        uint,
        uint64 _auxData,
        address _rollupBeneficiary
    ) 
    external
    payable 
    override(BridgeBase) 
    onlyRollup 
    returns(
        uint outputValueA,
        uint, 
        bool
    ) {
        if (_totalInputValue == 0) {
            revert ErrorLib.InvalidInputAmount();
        }

        _loadPools();

        PoolInfo memory selectedPool;

        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 &&
        _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL) {
            // deposit
            if (!pools[_inputAssetA.erc20Address].exists) {
                revert ErrorLib.InvalidInputA();
            }

            selectedPool = pools[_inputAssetA.erc20Address];

            _setTokens(selectedPool);

            // approvals
            CURVE_LP_TOKEN.approve(address(DEPOSIT), _totalInputValue);

            uint startCurveRewards = CURVE_REWARDS.balanceOf(address(this));

            DEPOSIT.deposit(selectedPool.poolPid, _totalInputValue, true);

            uint endCurveRewards = CURVE_REWARDS.balanceOf(address(this)); 

            outputValueA = (endCurveRewards - startCurveRewards);

            interactions[_outputAssetA.id] = Interaction(_totalInputValue, selectedPool.convexToken, true);
        } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
        _outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
            // withdraw
            if (!interactions[_inputAssetA.id].exists) {
                revert UnknownVirtualAsset();
            }
            // withdraw amount needs to be equal to the staked value of the interaction
            if (interactions[_inputAssetA.id].valueStaked != _totalInputValue) {
                revert IncorrectInteractionValue(interactions[_inputAssetA.id].valueStaked, _totalInputValue);
            }

            selectedPool = pools[_outputAssetA.erc20Address];

            if (!selectedPool.exists || 
            selectedPool.convexToken != interactions[_inputAssetA.id].representedConvexToken) {
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
    function _withdraw(AztecTypes.AztecAsset memory inputAssetA, uint totalInputValue, uint64 auxData, PoolInfo memory selectedPool) internal returns(uint outputValueA) {
        // approvals
        CURVE_LP_TOKEN.approve(ROLLUP_PROCESSOR, totalInputValue);

        uint startCurveLpTokens = CURVE_LP_TOKEN.balanceOf(address(this));

        // transfer CONVEX tokens from CrvRewards back to the bridge
        bool claimRewards = auxData == 1; // if passed anything but 1, rewards will not be claimed
        CURVE_REWARDS.withdraw(totalInputValue, claimRewards);
        
        DEPOSIT.withdraw(selectedPool.poolPid, totalInputValue);

        uint endCurveLpTokens = CURVE_LP_TOKEN.balanceOf(address(this));

        outputValueA = (endCurveLpTokens - startCurveLpTokens);

        delete interactions[inputAssetA.id];
    }

    /**
    @notice Loads pool information for all pools supported by Convex Finance.
    @notice Cached. Loads only new pools.
    */
    function _loadPools() internal {
        uint currentPoolLength = DEPOSIT.poolLength();
        if (currentPoolLength != lastPoolLength) {
            // for (uint i=0; i < currentPoolLength; i++) {
            for (uint i=lastPoolLength; i < currentPoolLength; i++) { // caching (assuming only new pools can be added and current cannot be changed)
                (address curveLpToken, address convexToken,, address curveRewards,,) = DEPOSIT.poolInfo(i);
                pools[curveLpToken] = PoolInfo(i, curveLpToken, convexToken, curveRewards, true);
            }
            lastPoolLength = currentPoolLength;
        }
    }

    /** 
    @notice Sets up pool specific tokens.
    */
    function _setTokens(PoolInfo memory selectedPool) internal {
        CURVE_LP_TOKEN = ICurveLpToken(selectedPool.curveLpToken);
        CURVE_REWARDS = ICurveRewards(selectedPool.curveRewards);
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