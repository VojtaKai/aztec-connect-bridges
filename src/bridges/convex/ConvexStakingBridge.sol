// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {IConvexFinanceBooster} from "../../interfaces/convex/IConvexFinanceBooster.sol";
import {IConvexToken} from "../../interfaces/convex/IConvexToken.sol";
import {ICurveLpToken} from "../../interfaces/convex/ICurveLpToken.sol";
import {ICurveRewards} from "../../interfaces/convex/ICurveRewards.sol";


/**
 * @notice A DefiBridge that stakes Curve LP Token into Convex Finance and receives Convex Token as an ouput 
 * @dev Synchronous and stateless bridge that will hold no funds beyond dust for gas-savings.
 * @author Vojtech Kaiser
 */
contract ConvexStakingBridge is BridgeBase, ERC20("ConvexStakingBridge", "CSB") {
    using SafeERC20 for IConvexFinanceBooster;
    using SafeERC20 for IConvexToken;
    using SafeERC20 for ICurveLpToken;
    // using SafeERC20 for ICurveRewards; // not really needed...I am not sending anything, just checking balance
    struct PoolInfo {
        uint poolPid;
        address curveLpToken;
        address convexToken;
        address curveRewards;
        bool exists;
    }

    address public immutable rollupProcessor;

    PoolInfo public poolinfo;

    mapping(address => PoolInfo) public pools;
    uint public lastPoolLength;

    // Deposit Contract for Convex Finance - Main File
    IConvexFinanceBooster public constant CONVEX_DEPOSIT = IConvexFinanceBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    // General Interface for any Convex Token Contract
    IConvexToken public CONVEX_TOKEN;

    // General Interface for any Curve LP Token Contract
    ICurveLpToken public CURVE_LP_TOKEN;

    // General Interface for any Curve Rewards Contract
    ICurveRewards public CURVE_REWARDS;
    
    error stakingUnsuccessful();
    error withdrawalUnsuccessful();
    error invalidTotalInputValue();
    error invalidInputOutputAssets();
    error poolIsClosed();

    event StakingResult(bool isStakingSuccessful);
    event BridgeTokenAmount(uint tokenAmount);

    
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        rollupProcessor = _rollupProcessor;
        // _mint(address(this), DUST) // for optimization
    }

    function fillPools(uint currentPoolLength) public {
        for (uint i=0; i < currentPoolLength; i++) {
            (address curveLpToken, address convexToken,, address curveRewards,,) = CONVEX_DEPOSIT.poolInfo(i);
            pools[curveLpToken] = PoolInfo(i, curveLpToken, convexToken, curveRewards, true);
        }
    }

    // receive() external payable {} // now needed but I think it should be anywhere
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
        uint, 
        bool
    ) {
        if (_totalInputValue == 0) {
            revert invalidTotalInputValue();
        }

        uint currentPoolLength = CONVEX_DEPOSIT.poolLength();
        if (lastPoolLength != currentPoolLength) {
            fillPools(currentPoolLength);
            lastPoolLength = currentPoolLength;
        }
        
        PoolInfo memory selectedPool;
        bool isInputCurveLpToken;

        if (pools[_inputAssetA.erc20Address].exists) {
            isInputCurveLpToken = true;
            selectedPool = pools[_inputAssetA.erc20Address];
        } else if (pools[_outputAssetA.erc20Address].exists) {
            selectedPool = pools[_outputAssetA.erc20Address];
        } else {
            revert invalidInputOutputAssets();
        }

        CURVE_LP_TOKEN = ICurveLpToken(selectedPool.curveLpToken);
        CONVEX_TOKEN = IConvexToken(selectedPool.convexToken);
        CURVE_REWARDS = ICurveRewards(selectedPool.curveRewards);
        (,,,,,bool isPoolShutDown) = CONVEX_DEPOSIT.poolInfo(selectedPool.poolPid);

        if (isPoolShutDown) {
            revert poolIsClosed(); // aby se nestalo, ze ten pool bude zavrenej a ja z nej chci alespon vybrat tokeny, ale nemuzu, mozna neni muj ukol though
        }

        // staking
        if (isInputCurveLpToken) {
            // approval
            CURVE_LP_TOKEN.approve(address(CONVEX_DEPOSIT), _totalInputValue);
            _approve(address(this), rollupProcessor, _totalInputValue);

            uint startCurveRewards = CURVE_REWARDS.balanceOf(address(this));

            bool isStakingSuccessful = CONVEX_DEPOSIT.deposit(selectedPool.poolPid, _totalInputValue, true);

            if(!isStakingSuccessful) {
                revert stakingUnsuccessful();
            }

            uint endCurveRewards = CURVE_REWARDS.balanceOf(address(this)); 

            outputValueA = (endCurveRewards - startCurveRewards);

            _mint(address(this), outputValueA);
        } else { //withdrawing (unstaking)

            // approvals
            CURVE_LP_TOKEN.approve(rollupProcessor, _totalInputValue);
            _approve(address(this), rollupProcessor, _totalInputValue);

            uint startCurveLpTokens = CURVE_LP_TOKEN.balanceOf(address(this));

            bool isWithdrawalSuccessful = CONVEX_DEPOSIT.withdraw(selectedPool.poolPid, _totalInputValue);

            if(!isWithdrawalSuccessful) {
                revert withdrawalUnsuccessful();
            }

            uint endCurveLpTokens = CURVE_LP_TOKEN.balanceOf(address(this));

            outputValueA = (endCurveLpTokens - startCurveLpTokens);

            _burn(address(this), outputValueA);
        }
    }
}