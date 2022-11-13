// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IConvexBooster} from "../../interfaces/convex/IConvexBooster.sol";
import {ICurveLpToken} from "../../interfaces/convex/ICurveLpToken.sol";
import {ICurveRewards} from "../../interfaces/convex/ICurveRewards.sol";
import {IRepConvexToken} from "../../interfaces/convex/IRepConvexToken.sol";

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
        uint96 poolId;
        address convexToken;
        address curveRewards;
    }

    // Convex Finance Booster
    IConvexBooster public constant BOOSTER = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    // Pools
    uint256 public poolLength;

    mapping(address => PoolInfo) public pools;

    // Deployed RepresentingConvexTokens, mapping(Curve LP token => representing Convex token)
    mapping(address => address) public deployedTokens;

    // Errors
    error InvalidAssetType();
    error UnknownAssetA();

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        loadPools();

        uint256[] memory criterias = new uint256[](poolLength);
        uint32[] memory gasUsage = new uint32[](poolLength);
        uint32[] memory minGasPerMinute = new uint32[](poolLength);

        for (uint256 i = 0; i < poolLength; i++) {
            (address curveLpToken, , , , , ) = BOOSTER.poolInfo(i);
            criterias[i] = uint256(keccak256(abi.encodePacked(curveLpToken, deployedTokens[curveLpToken])));
            gasUsage[i] = 500000; // deposit 1M, withdrawal 375k -> compromise 500k
            minGasPerMinute[i] = 350;
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
        uint64,
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

        if (
            _inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20 ||
            _outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20
        ) {
            revert InvalidAssetType();
        }

        if (
            deployedTokens[_inputAssetA.erc20Address] == address(0) &&
            deployedTokens[_outputAssetA.erc20Address] == address(0)
        ) {
            revert UnknownAssetA(); // invalid address or pool has not been loaded yet/token not deployed yet  --> this will need to get tested
        }

        PoolInfo memory selectedPool;

        if (deployedTokens[_inputAssetA.erc20Address] == _outputAssetA.erc20Address) {
            selectedPool = pools[_inputAssetA.erc20Address];

            uint256 startCurveRewards = ICurveRewards(selectedPool.curveRewards).balanceOf(address(this));

            BOOSTER.deposit(selectedPool.poolId, _totalInputValue, true);

            uint256 endCurveRewards = ICurveRewards(selectedPool.curveRewards).balanceOf(address(this));

            outputValueA = (endCurveRewards - startCurveRewards);

            IRepConvexToken(_outputAssetA.erc20Address).mint(_totalInputValue);
        } else if (deployedTokens[_outputAssetA.erc20Address] == _inputAssetA.erc20Address) {
            // withdrawal

            selectedPool = pools[_outputAssetA.erc20Address];

            uint256 startCurveLpTokens = ICurveLpToken(_outputAssetA.erc20Address).balanceOf(address(this));

            // transfer CONVEX tokens from CrvRewards back to the bridge
            ICurveRewards(selectedPool.curveRewards).withdraw(_totalInputValue, true); // always claim rewards

            BOOSTER.withdraw(selectedPool.poolId, _totalInputValue);

            uint256 endCurveLpTokens = ICurveLpToken(_outputAssetA.erc20Address).balanceOf(address(this));

            outputValueA = (endCurveLpTokens - startCurveLpTokens);

            IRepConvexToken(_inputAssetA.erc20Address).burn(_totalInputValue);
        } else {
            revert ErrorLib.InvalidOutputA();
        }

        // Pay out subsidy to the rollupBeneficiary
        SUBSIDY.claimSubsidy(
            computeCriteria(_inputAssetA, _inputAssetB, _outputAssetA, _outputAssetB, 0),
            _rollupBeneficiary
        );
    }

    /**
    @notice Loads pool information for all pools supported by Convex Finance.
    @notice Set allowance for Rollup's Curve LP tokens.
    @notice Cached. Loads only new pools.
    */
    function loadPools() public {
        uint256 currentPoolLength = BOOSTER.poolLength();
        if (currentPoolLength != poolLength) {
            for (uint256 i = poolLength; i < currentPoolLength; i++) {
                (address curveLpToken, address convexToken, , address curveRewards, , ) = BOOSTER.poolInfo(i);
                pools[curveLpToken] = PoolInfo(uint96(i), convexToken, curveRewards);

                // deploy token, log token address
                address deployedToken = address(new RepresentingConvexToken("RepresentingConvexToken", "RCT"));
                // deployedTokens[curveLpToken] = address(new RepresentingConvexToken(string.concat("RepresentingConvexToken", Strings.toString(i)), string.concat("RCT", Strings.toString(i))));
                deployedTokens[curveLpToken] = deployedToken;
                // approvals
                ICurveLpToken(curveLpToken).approve(address(BOOSTER), type(uint256).max);
                ICurveLpToken(curveLpToken).approve(ROLLUP_PROCESSOR, type(uint256).max);
                IRepConvexToken(deployedToken).approve(ROLLUP_PROCESSOR, type(uint256).max);
            }
            poolLength = currentPoolLength;
        }
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
        if (deployedTokens[_inputAssetA.erc20Address] == _outputAssetA.erc20Address) {
            return uint256(keccak256(abi.encodePacked(_inputAssetA.erc20Address, _outputAssetA.erc20Address)));
        } else {
            return uint256(keccak256(abi.encodePacked(_inputAssetA.erc20Address, _outputAssetA.erc20Address)));
        }
    }
}

contract RepresentingConvexToken is ERC20, ERC20Burnable, Ownable {
    constructor(string memory _tokenName, string memory _tokenSymbol) ERC20(_tokenName, _tokenSymbol) {}

    function mint(uint256 _amount) public onlyOwner {
        _mint(msg.sender, _amount);
    }
}
