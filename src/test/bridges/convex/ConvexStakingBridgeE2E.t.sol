// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {IConvexBooster} from "../../../interfaces/convex/IConvexBooster.sol";

contract ConvexStakingBridgeE2ETest is BridgeTestBase {
    address private constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private constant BENEFICIARY = address(777);

    address private curveLpToken;
    address private convexLpToken;
    address private representingConvexToken;
    address private rctImplementation;
    address private rctClone;
    address private staker;
    address private gauge;
    address private stash;
    address private crvRewards;
    // The reference to the convex staking bridge
    ConvexStakingBridge private bridge;

    uint16[] public invalidPids = [48]; // define invalid pids
    // map of invalid pools, mapping(poolId)
    mapping(uint16 => bool) public invalidPoolIds;

    // map of already tested pools, mapping(poolId => bool)
    mapping(uint16 => bool) public alreadyTestedPoolIds;

    // To store the id of the convex staking bridge after being added
    uint256 private bridgeId;


    function setUp() public {
        staker = IConvexBooster(BOOSTER).staker();
        _setupInvalidPoolIds();

        // labels
        vm.label(address(ROLLUP_PROCESSOR), "Rollup Processor");
        vm.label(address(this), "E2E Test Contract");
        vm.label(msg.sender, "MSG sender");
        vm.label(BOOSTER, "Booster");
        vm.label(staker, "Staker Contract Address");
        vm.label(BENEFICIARY, "Beneficiary");
    }

    /**
     * @notice Tests staking and withdrawing by constructing bridgeCallData and passing it directly
     * to RollupProcessor function that initializes the interaction with the bridge.
     * @dev Compound test for 5 randomly selected pools from all available pools.
     */
    function testStakeWithdrawFlow(
        uint64 _depositAmount,
        uint16 _poolId
    ) public {
        vm.assume(_depositAmount > 1);

        uint16 poolId = _getPoolId(_poolId);

        _setupBridge(poolId);

        _loadPool(poolId);
        _setupRepresentingConvexTokenClone();
        _setupSubsidy();

        vm.startPrank(MULTI_SIG);
        // Add the new bridge and set its initial gasLimit
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 2500000);
        // Add assets and set their initial gasLimits
        ROLLUP_PROCESSOR.setSupportedAsset(curveLpToken, 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(rctClone, 100000);
        vm.stopPrank();

        // Fetch the id of the convex staking bridge
        bridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        // get Aztec assets
        AztecTypes.AztecAsset memory curveLpAsset = ROLLUP_ENCODER.getRealAztecAsset(curveLpToken);
        AztecTypes.AztecAsset memory representingConvexAsset = ROLLUP_ENCODER.getRealAztecAsset(rctClone);

        // // Mint depositAmount of Curve LP tokens for RollUp Processor
        deal(curveLpToken, address(ROLLUP_PROCESSOR), _depositAmount);

        _deposit(bridgeId, curveLpAsset, representingConvexAsset, _depositAmount);

        _withdraw(bridgeId, representingConvexAsset, curveLpAsset, _depositAmount);
    }

    function _deposit(
        uint256 _bridgeId,
        AztecTypes.AztecAsset memory _curveLpAsset,
        AztecTypes.AztecAsset memory _representingConvexAsset,
        uint256 _depositAmount
    ) internal {
        ROLLUP_ENCODER.defiInteractionL2(
            _bridgeId, _curveLpAsset, emptyAsset, _representingConvexAsset, emptyAsset, 0, _depositAmount
        );

        // move time forward to have claimable amount on beneficiary
        skip(1 days);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        assertEq(outputValueA, _depositAmount); // number of staked tokens match deposited LP Tokens
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
        assertEq(IERC20(rctClone).balanceOf(address(ROLLUP_PROCESSOR)), _depositAmount);
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");
    }

    function _withdraw(
        uint256 _bridgeId,
        AztecTypes.AztecAsset memory _representingConvexAsset,
        AztecTypes.AztecAsset memory _curveLpAsset,
        uint256 _depositAmount
    ) internal {
        // Compute withdrawal calldata
        ROLLUP_ENCODER.defiInteractionL2(
            _bridgeId, _representingConvexAsset, emptyAsset, _curveLpAsset, emptyAsset, 0, _depositAmount
        );

        skip(1 days); // move time forward to have claimable amount on beneficiary
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();
        rewind(2 days); // move time back to original for the next bridge run

        assertEq(outputValueA, _depositAmount); // number of withdrawn tokens match deposited LP Tokens
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");

        assertEq(IERC20(curveLpToken).balanceOf(address(ROLLUP_PROCESSOR)), _depositAmount); // Curve LP tokens owned by RollUp

        assertEq(IERC20(rctClone).balanceOf(address(bridge)), 0); // RCT succesfully burned
        assertEq(IERC20(rctClone).balanceOf(address(ROLLUP_PROCESSOR)), 0); // RCT succesfully burned

        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");
    }

    function _setupSubsidy() internal {
        // Set ETH balance of bridge and BENEFICIARY to 0
        vm.deal(address(bridge), 0);
        vm.deal(BENEFICIARY, 0);

        uint256[] memory criterias = new uint256[](2);

        // different criteria for deposit and withdrawal
        criterias[0] = bridge.computeCriteria(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            0
        );

        criterias[1] = bridge.computeCriteria(
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            0
        );

        uint32 minGasPerMinute = 350;

        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criterias[0], minGasPerMinute);
        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criterias[1], minGasPerMinute);

        SUBSIDY.registerBeneficiary(BENEFICIARY);

        // Set the rollupBeneficiary on BridgeTestBase so that it gets included in the proofData
        ROLLUP_ENCODER.setRollupBeneficiary(BENEFICIARY);
    }

    function _setupBridge(uint256 _poolId) internal {
        bridge = new ConvexStakingBridge(address(ROLLUP_PROCESSOR));
        (curveLpToken, convexLpToken, gauge, crvRewards, stash,) = IConvexBooster(BOOSTER).poolInfo(_poolId);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(curveLpToken, "Curve LP Token Contract");
        vm.label(convexLpToken, "Convex LP Token Contract");
        vm.label(crvRewards, "CrvRewards Contract");
        vm.label(stash, "Stash Contract");
        vm.label(gauge, "Gauge Contract");
    }

    function _getPoolId(
        uint16 _poolId
    ) internal returns(uint16 poolId) {
        bool poolClosed;
        uint256 poolLength = IConvexBooster(BOOSTER).poolLength();

        // select a pool from a given range
        poolId = uint16(bound(_poolId, 0, poolLength - 1));

        // Pool is shut down
        (,,,,, poolClosed) = IConvexBooster(BOOSTER).poolInfo(poolId);
        if (poolClosed) {
            invalidPoolIds[poolId] = true;
        }
        
        // select a pool that is not invalid, closed or has been already tested
        while (invalidPoolIds[poolId] || alreadyTestedPoolIds[poolId]) {
            poolId++;

            // If poolId incremented by 1 jumps out of bounds, reset poolId back to 0
            if (poolId == poolLength) {
                poolId = 0;
            }

            // Pool is shut down, add it among the invalid pools
            (,,,,, poolClosed) = IConvexBooster(BOOSTER).poolInfo(poolId);
            if (poolClosed) {
                invalidPoolIds[poolId] = true;
            }
        }

        alreadyTestedPoolIds[poolId] = true;
    }

    function _setupInvalidPoolIds() internal {
        for (uint256 pid = 0; pid < invalidPids.length; pid++) {
            invalidPoolIds[invalidPids[pid]] = true;
        }
    }

    function _loadPool(uint256 _poolId) internal {
        bridge.loadPool(_poolId);
    }

    function _setupRepresentingConvexTokenClone() internal {
        rctImplementation = bridge.RCT_IMPLEMENTATION();
        vm.label(rctImplementation, "Representing Convex Token Implementation");

        rctClone = bridge.deployedClones(curveLpToken);
        vm.label(rctClone, "Representing Convex Token Clone");
    }
}
