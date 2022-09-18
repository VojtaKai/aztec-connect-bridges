// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeBase} from "../base/BridgeBase.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {IConvexFinanceBooster} from "../../interfaces/convex/IConvexFinanceBooster.sol";
import {IConvexToken} from "../../interfaces/convex/IConvexToken.sol";
import {ICurveLpToken} from "../../interfaces/convex/ICurveLpToken.sol";
import {ICurveRewards} from "../../interfaces/convex/ICurveRewards.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice A DefiBridge that stakes Curve LP Token into Convex Finance and receives Convex Token as an ouput 
 * @dev Synchronous and stateless bridge that will hold no funds beyond dust for gas-savings.
 * @author Vojtech Kaiser
 */
contract ConvexStakingBridge is BridgeBase {
    using SafeERC20 for IConvexFinanceBooster;
    using SafeERC20 for IConvexToken;
    using SafeERC20 for ICurveLpToken;
    // using SafeERC20 for ICurveRewards; // not really needed...I am not sending anything, just checking balance

    address public immutable rollupProcessor;
    uint public poolPid;
    bool public isMatchingPoolFound;
    // uint public constant PRECISION = 1e18;

    // Deposit Contract for Convex Finance
    IConvexFinanceBooster public constant CONVEX_DEPOSIT = IConvexFinanceBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    // General Interface for any Convex Token Contract
    IConvexToken public CONVEX_TOKEN;

    // General Interface for any Curve LP Token Contract
    ICurveLpToken public CURVE_LP_TOKEN;

    // General Interface for any Curve Rewards Contract
    ICurveRewards public CURVE_REWARDS = ICurveRewards(0x14F02f3b47B407A7a0cdb9292AA077Ce9E124803); // NENI DYNAMICKY, HAZI ERROR!!!
    
    error stakingUnsuccessful();
    error withdrawalUnsuccessful();
    error invalidTotalInputValue();

    event StakingResult(bool isStakingSuccessful);

    
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        rollupProcessor = _rollupProcessor;
    }

    // receive() external payable {} // now needed but I think it should be anywhere
    
    /**
    * @notice Stake Curve LP Token or withdraw Convex Token and exchange it back for Curve LP Tokens
    * @notice To be able to stake a token, you'll already need to own Curve LP Token from one of its pools.
    * This token is then placed into liquidity gauge by pool specific stash contract by Curve (or Convex? Unsure now). 
    * New Convex Token is minted and then staked/deposited into rewardsContract.
    * Withdrawing of stashed Convex Token goes in reversed order. First, the minted Convex Tokens will get burned.
    * Curve LP Token will be after some more transfers credited back to RollUpProcessor.
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
        uint, // _interactionNonce, // whatever Interaction None, something for pulling balancing later on
        uint64, // _auxData, // some extra data, not sure what now
        address
    ) 
    external
    payable 
    override(BridgeBase) 
    onlyRollup 
    returns(
        uint outputValueA,
        uint isStakingSuccessful, 
        bool // tady je vetsinou nejakej isAsync
    ) {
        if (_totalInputValue == 0) {
            revert invalidTotalInputValue();
        }
        bool isInputCurveLpToken; // if input not Curve LP Token than it is Convex Token

        uint poolLength = CONVEX_DEPOSIT.poolLength();
        address _curveLpToken;
        address _convexToken;
        // address _curveRewards; // stack too deep, try removing local variables
        for (uint i=0; i < poolLength; i++) {
            (_curveLpToken, _convexToken,,,,) = CONVEX_DEPOSIT.poolInfo(i);
            if (_curveLpToken == _inputAssetA.erc20Address && _convexToken == _outputAssetA.erc20Address) {
                isInputCurveLpToken = true;
                poolPid = i;
                isMatchingPoolFound = true;
                break;
            }
            if (_curveLpToken == _outputAssetA.erc20Address && _convexToken == _inputAssetA.erc20Address) {
                isInputCurveLpToken = false; // could be removed, bool false by default
                poolPid = i;
                isMatchingPoolFound = true;
                break;
            }
        }

        require(isMatchingPoolFound, "No matching Curve pool found");

        CURVE_LP_TOKEN = ICurveLpToken(_curveLpToken);
        CONVEX_TOKEN = IConvexToken(_convexToken); // not used
        // CURVE_REWARDS = ICurveRewards(_curveRewards);

        // approvals
        // CURVE_LP_TOKEN.approve(address(this), _totalInputValue);
        CURVE_LP_TOKEN.approve(address(CONVEX_DEPOSIT), _totalInputValue);

         // Approve rollup processor to take input value of input asset
        // IERC20(_outputAssetA.erc20Address).approve(ROLLUP_PROCESSOR, _totalInputValue);


        if (isInputCurveLpToken) {
            uint startCurveRewards = CURVE_REWARDS.balanceOf(address(this));

            bool isStakingSuccessful = CONVEX_DEPOSIT.deposit(poolPid, _totalInputValue, true);
            
            emit StakingResult(isStakingSuccessful);

            if(!isStakingSuccessful) {
                revert stakingUnsuccessful();
            }

            uint endCurveRewards = CURVE_REWARDS.balanceOf(address(this)); 

            // outputValueA = 10;

            outputValueA = (endCurveRewards - startCurveRewards); // maybe devide by precision 
        } else {
            uint startCurveLpTokenAmount = CURVE_LP_TOKEN.balanceOf(address(this));

            bool isWithdrawalSuccessful = CONVEX_DEPOSIT.withdraw(poolPid, _totalInputValue);

            if(!isWithdrawalSuccessful) {
                revert withdrawalUnsuccessful();
            }

            uint endCurveLpTokenAmount = CURVE_LP_TOKEN.balanceOf(address(this));

            outputValueA = (endCurveLpTokenAmount - startCurveLpTokenAmount); // maybe devide by precision
        }
    }
}