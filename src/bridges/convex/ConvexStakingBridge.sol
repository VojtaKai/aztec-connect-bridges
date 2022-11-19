// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";
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
 Hence, for each pool is deployed a new token, Representing Convex Token, RCT. RCT represents how much Convex token was minted / burned
 and is minted / burned accordingly directly for the bridge, Rollup Processor resp.
 @dev RCT ERC20 token is deployed for each loaded pool. This token identically matches the minted / burned Convex token in the Convex Finance network. 
 @dev Synchronous and stateless bridge
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

    // Representing Convex Token implementation address
    address public immutable rctImplementation;

    // Pools
    uint256 public poolsLength;

    mapping(address => PoolInfo) public pools;

    // Deployed RCT clones, mapping(Curve LP token => RCT)
    mapping(address => address) public deployedClones;

    // Errors
    error InvalidAssetType();
    error UnknownAssetA();
    error PoolAlreadyLoaded();

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        rctImplementation = address(new RepresentingConvexToken());
    }

    /**
    @notice Function so the bridge can receive ether. Used for subsidy.
    */
    receive() external payable {}

    /**
    @notice Stake and unstake Curve LP tokens through Convex Finance Booster anytime.
    @notice Convert rate between Curve LP token and corresponding Convex LP token is 1:1
    @notice Stake == Deposit, Unstake == Withdraw
    @notice RCT = Representing Convex Token
    @notice Convex LP token is represented by RCT
    @param _inputAssetA Curve LP token (staking), RCT (unstaking)
    @param _outputAssetA RCT (staking), Curve LP token (unstaking)
    @param _totalInputValue Total number of Curve LP tokens to deposit / withdraw
    @param outputValueA Number of Curve LP tokens staked / unstaked, Number of RCT minted / burned
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
        if (
            _inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20 ||
            _outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20
        ) {
            revert InvalidAssetType();
        }

        address inputDeployedClone =  deployedClones[_inputAssetA.erc20Address];
        address outputDeployedClone = deployedClones[_outputAssetA.erc20Address];

        if (
            inputDeployedClone == address(0) &&
            outputDeployedClone == address(0)
        ) {
            revert UnknownAssetA(); // invalid address or pool has not been loaded yet/token not deployed yet  --> this will need to get tested
        }

        PoolInfo memory selectedPool;

        if (inputDeployedClone == _outputAssetA.erc20Address) {
            // deposit
            selectedPool = pools[_inputAssetA.erc20Address];

            outputValueA = _deposit(_outputAssetA, _totalInputValue, selectedPool);
        } else if (outputDeployedClone == _inputAssetA.erc20Address) {
            // withdrawal
            selectedPool = pools[_outputAssetA.erc20Address];

            outputValueA = _withdraw(_inputAssetA, _outputAssetA, _totalInputValue, selectedPool);
        } else {
            revert ErrorLib.InvalidOutputA();
        }

        // Pay out subsidy to the rollupBeneficiary
        _claimSubsidy(SUBSIDY, _inputAssetA, _inputAssetB, _outputAssetA, _outputAssetB, _rollupBeneficiary);
    }

    function _claimSubsidy(ISubsidy _SUBSIDY, AztecTypes.AztecAsset calldata _inputAssetA, AztecTypes.AztecAsset calldata _inputAssetB, AztecTypes.AztecAsset calldata _outputAssetA, AztecTypes.AztecAsset calldata _outputAssetB, address _rollupBeneficiary) internal {
        _SUBSIDY.claimSubsidy(
            computeCriteria(_inputAssetA, _inputAssetB, _outputAssetA, _outputAssetB, 0),
            _rollupBeneficiary
        );
    }

     /** 
    @notice Internal function to withdraw Curve LP tokens
    @notice RCT is minted for the bridge. Symbolizes Convex token minted for the staked Curve LP tokens.
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
    @notice Internal function to withdraw Curve LP tokens
    @notice RCT is burned for the bridge.
    */
    function _withdraw(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _outputAssetA,
        uint256 _totalInputValue,
        PoolInfo memory _selectedPool
    ) internal returns (uint256 outputValueA) {
        uint256 startCurveLpTokens = ICurveLpToken(_outputAssetA.erc20Address).balanceOf(address(this));

        // transfer CONVEX tokens from CrvRewards back to the bridge
        ICurveRewards(_selectedPool.curveRewards).withdraw(_totalInputValue, true); // always claim rewards

        BOOSTER.withdraw(_selectedPool.poolId, _totalInputValue);

        uint256 endCurveLpTokens = ICurveLpToken(_outputAssetA.erc20Address).balanceOf(address(this));

        outputValueA = (endCurveLpTokens - startCurveLpTokens);

        IRepConvexToken(_inputAssetA.erc20Address).burn(_totalInputValue);
    }

    /**
    @notice Loads pool information for a specific pool supported by Convex Finance.
    @notice Deploying RCT token for the specific pool is part of the loading.
    @notice Set allowance for Booster and Rollup Processor to manipulate bridge's Curve LP tokens and RCT (through RCT Clone).
    @notice Setup subsidy.
    // @notice Pool can only be loaded once
    */
    function loadPool(uint _poolId) external {
        (address curveLpToken, address convexToken, , address curveRewards, , ) = BOOSTER.poolInfo(_poolId);
        // if (pools[curveLpToken].curveRewards != address(0)) {
        //     revert PoolAlreadyLoaded();
        // }
        pools[curveLpToken] = PoolInfo(uint96(_poolId), convexToken, curveRewards);

        // deploy clone, log clone address
        address deployedClone = Clones.clone(rctImplementation);
        // RCT token initialization - deploy fully working ERC20 RCT token
        RepresentingConvexToken(deployedClone).initialize("RepresentingConvexToken", "RCT");

        deployedClones[curveLpToken] = deployedClone;
        
        // approvals
        ICurveLpToken(curveLpToken).approve(address(BOOSTER), type(uint256).max);
        ICurveLpToken(curveLpToken).approve(ROLLUP_PROCESSOR, type(uint256).max);
        IRepConvexToken(deployedClone).approve(ROLLUP_PROCESSOR, type(uint256).max);

        // subsidy
        uint256 criteria = uint256(keccak256(abi.encodePacked(curveLpToken, deployedClone)));
        uint32 gasUsage = 500000; // deposit 1M, withdrawal 375k -> compromise 500k
        uint32 minGasPerMinute = 350;

        SUBSIDY.setGasUsageAndMinGasPerMinute(criteria, gasUsage, minGasPerMinute);
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
        if (deployedClones[_inputAssetA.erc20Address] == _outputAssetA.erc20Address) {
            return uint256(keccak256(abi.encodePacked(_inputAssetA.erc20Address, _outputAssetA.erc20Address)));
        } else {
            return uint256(keccak256(abi.encodePacked(_outputAssetA.erc20Address, _inputAssetA.erc20Address)));
        }
    }
}

/**
 @notice ERC20 token that represents pool specific Convex LP token. RCT is deployed for a specific pool that has been loaded.
 @notice RCT mirrors balance of Convex LP token. Can only be minted for the owner (generally the bridge) by the owner.
 @notice RCT is an ERC20 upgradable token which allows initialization after the time it was deployed.
 @dev RCT implementation is deployed on bridge contract deployments.
 @dev RCT is a proxied contract and is called via a clone that is created for each loaded pool. 
 @dev Clone initializes the RCT implementation by calling the `initialize` function.
 */
contract RepresentingConvexToken is ERC20Upgradeable, OwnableUpgradeable {
    function initialize(string memory _tokenName, string memory _tokenSymbol) public initializer {
        __ERC20_init(_tokenName, _tokenSymbol);
        _transferOwnership(_msgSender());
    }

    function mint(uint256 _amount) public onlyOwner {
        _mint(_msgSender(), _amount);
    }

    function burn(uint256 amount) public onlyOwner {
        _burn(_msgSender(), amount);
    }
}
