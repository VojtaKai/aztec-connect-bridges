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
import {IConvexToken} from "../../interfaces/convex/IConvexToken.sol";
import {ICurveLpToken} from "../../interfaces/convex/ICurveLpToken.sol";
import {ICurveRewards} from "../../interfaces/convex/ICurveRewards.sol";


/**
 * @notice A DefiBridge that stakes Curve LP Token into Convex Finance. Unstaking supported as well.
 * @notice A DefiBridge that stakes Curve LP Token into Convex Finance. Convex Finance transfers Curve LP Tokens 
 * from bridge to a liquidity gauge. New Convex Tokens are minted and then staked (transfered) to CRV Rewards.
 * Bridge mints a matching version of the staked Convex Tokens, CSB Tokens, and assignes their ownership to the RollUpProcessor.
 * At unstaking, both - CSB Tokens and Convex Tokens - are burned and ownership of Curve LP Tokens is given back to the RollUpProcessor.
 * @dev Synchronous and stateful bridge that will hold track of interactions and information about minted tokens.
 * @author Vojtech Kaiser
 */
contract ConvexStakingBridge is BridgeBase {
    using SafeERC20 for IConvexDeposit;
    using SafeERC20 for IConvexToken;
    using SafeERC20 for ICurveLpToken;
    // using SafeERC20 for ICurveRewards; // not really needed...I am not sending anything, just checking balance

    // CONTRACTS
    // Deposit Contract for Convex Finance - Main File
    IConvexDeposit public constant DEPOSIT = IConvexDeposit(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    // General Interface for any Curve LP Token Contract
    ICurveLpToken public CURVE_LP_TOKEN;
    // General Interface for any Curve LP Token Contract
    IConvexToken public CONVEX_TOKEN;
    // General Interface for any Curve Rewards Contract
    ICurveRewards public CURVE_REWARDS;
    
    // POOLS
    uint public lastPoolLength;

    struct PoolInfo {
        uint poolPid;
        address curveLpToken;
        address convexToken;
        address curveRewards;
        bool exists;
    }
    mapping(address => PoolInfo) public pools;

    // INTERACTIONS - virtual asset
    struct Interaction {
        address representedConvexToken;
        bool exists;
    }

    mapping(uint => Interaction) public interactions;

    // ERRORS
    error InvalidAssetType();
    error UnknownVirtualAsset();

    // EVENT FOR ME
    

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        loadPools();
    }

    /**
    @notice Loads Curve Pool information into a map. Cached unless number of pools has changed.
    */
    function loadPools() internal {
        uint currentPoolLength = DEPOSIT.poolLength();
        if (currentPoolLength != lastPoolLength) {
            for (uint i=0; i < currentPoolLength; i++) {
                (address curveLpToken, address convexToken,, address curveRewards,,) = DEPOSIT.poolInfo(i);
                pools[curveLpToken] = PoolInfo(i, curveLpToken, convexToken, curveRewards, true);
            }
            lastPoolLength = currentPoolLength;
        }
    }

    /** 
    @notice sets up pool tokens
    */
    function setTokens(PoolInfo memory selectedPool) internal {
        CURVE_LP_TOKEN = ICurveLpToken(selectedPool.curveLpToken);
        CONVEX_TOKEN = IConvexToken(selectedPool.convexToken);
        CURVE_REWARDS = ICurveRewards(selectedPool.curveRewards);
    }

    // receive() external payable {} // Probably not needed

    /**
    * @notice Staking and unstaking of Curve LP Tokens via Convex Finance in a form of Convex Tokens.
    * @notice To be able to stake a token, you already need to own Curve LP Token from one of its pools.
    * Staking: Curve LP Token is then placed into liquidity gauge by pool specific staker contract. 
    * New Convex Token is minted and then staked/deposited into rewardsContract.
    * Withdrawing of Curve LP Tokens goes in reversed order. First, the minted Convex Tokens will get burned.
    * If there is enough Curve LP tokens, tokens will be credited to the bridge. If this is not the case, 
    * the necessary rest of Curve LP Token amount will be withdrawn from pool's liquidity gauge contract 
    * and subsequently credited to the bridge and back to RollUpProcessor.
    * @notice Converting rate between Curve LP Token and corresponding Convex Token is 1:1
    * @param _inputAssetA Curve LP Token or Convex Token
    * @param _outputAssetA Convex Token or Curve LP Token
    * @param _totalInputValue Total number of Curve LP Tokens / Convex Tokens
    * @param outputValueA Number of Convex Tokens / Curve LP Tokens back
    */ 
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata, 
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint _totalInputValue,
        uint _interactionNonce,
        uint64 _auxData,
        address
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

        PoolInfo memory selectedPool;

        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 &&
        _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL) {
            // deposit
            if (!pools[_inputAssetA.erc20Address].exists) {
                revert ErrorLib.InvalidInputA();
            }

            selectedPool = pools[_inputAssetA.erc20Address];

            setTokens(selectedPool);

            // approvals
            CURVE_LP_TOKEN.approve(address(DEPOSIT), _totalInputValue);

            uint startCurveRewards = CURVE_REWARDS.balanceOf(address(this));

            DEPOSIT.deposit(selectedPool.poolPid, _totalInputValue, true);

            uint endCurveRewards = CURVE_REWARDS.balanceOf(address(this)); 

            outputValueA = (endCurveRewards - startCurveRewards);
            // emit InteractionAdd(_outputAssetA.id);
            interactions[_outputAssetA.id] = Interaction(selectedPool.convexToken, true);
        } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
        _outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
            // withdraw
            if (!interactions[_inputAssetA.id].exists) {
                revert UnknownVirtualAsset();
            }

            selectedPool = pools[_outputAssetA.erc20Address];

            if (!selectedPool.exists || 
            selectedPool.convexToken != interactions[_inputAssetA.id].representedConvexToken) {
                revert ErrorLib.InvalidOutputA();
            }

            setTokens(selectedPool);

            outputValueA = _withdraw(_inputAssetA, _totalInputValue, _auxData, selectedPool);
        } else {
             revert InvalidAssetType();
        }
    }

    function _withdraw(AztecTypes.AztecAsset memory inputAssetA, uint totalInputValue, uint64 auxData, PoolInfo memory selectedPool) internal returns(uint outputValueA) {
        // approvals
        CURVE_LP_TOKEN.approve(ROLLUP_PROCESSOR, totalInputValue);

        uint startCurveLpTokens = CURVE_LP_TOKEN.balanceOf(address(this));

        // transfer CONVEX Tokens from CrvRewards back to the bridge
        bool claim = auxData == 1; // if passed anything else but 1, rewards will not be claimed, shouldn't be limited to 0 and 1 only?
        
        CURVE_REWARDS.withdraw(totalInputValue, claim); // claim should be probably sent in AuxData if yes or no
        
        DEPOSIT.withdraw(selectedPool.poolPid, totalInputValue);

        uint endCurveLpTokens = CURVE_LP_TOKEN.balanceOf(address(this));

        outputValueA = (endCurveLpTokens - startCurveLpTokens);

        // delete interactions[inputAssetA.id];
    }
}