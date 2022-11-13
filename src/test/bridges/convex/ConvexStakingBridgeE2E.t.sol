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
    address private curveLpToken;
    address private convexLpToken;
    address private representingConvexToken;
    address private constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private staker;
    address private gauge;
    address private stash;
    address private crvRewards;
    address private constant BENEFICIARY = address(777);

    // The reference to the convex staking bridge
    ConvexStakingBridge private bridge;

    mapping(uint256 => bool) public invalidPoolIds;

    // To store the id of the convex staking bridge after being added
    uint256 private bridgeId;

    // 5 arbitrarily selected pool ids
    uint16[] private poolIdsToTest = new uint16[](5);

    // Bridge response
    uint256 private outputValueA;
    uint256 private outputValueB;
    bool private isAsync;

    function setUp() public {
        staker = IConvexBooster(BOOSTER).staker();
        _setUpInvalidPoolIds(48);

        // labels
        vm.label(address(ROLLUP_PROCESSOR), "Rollup Processor");
        vm.label(address(this), "E2E Test Contract");
        vm.label(msg.sender, "MSG sender");
        vm.label(BOOSTER, "Booster");
        vm.label(staker, "Staker Contract Address");
        vm.label(BENEFICIARY, "Beneficiary");
    }

    /**
    @notice Tests staking and withdrawing by constructing bridgeCallData and passing it directly
    to RollupProcessor function that initializes the interaction with the bridge.
    @notice Compound test for all available Curve LP tokens.
    @dev Each interaction with a bridge gets a new nonce. Starts at 0 and increments by 32.
    @dev Virtual asset on output ignores virtual asset definition. It sets the virtual asset's ID to always be equal to interaction nonce.
    @dev Virtual asset on input takes on ID of the defined virtual asset.
    */
    function testStakeWithdrawFlow(
        uint64 _depositAmount,
        uint16 _poolId1,
        uint16 _poolId2,
        uint16 _poolId3,
        uint16 _poolId4,
        uint16 _poolId5
    ) public {
        vm.assume(_depositAmount > 1);

        uint256 poolLength = IConvexBooster(BOOSTER).poolLength();

        _setupTestPoolIds(poolLength, _poolId1, _poolId2, _poolId3, _poolId4, _poolId5);

        for (uint256 i = 0; i < poolIdsToTest.length; i++) {
            if (invalidPoolIds[i]) {
                continue;
            }

            _setUpBridge(i);
            _setupRepresentingConvexToken();
            _setupSubsidy();

            vm.startPrank(MULTI_SIG);
            // Add the new bridge and set its initial gasLimit
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);
            // Add Assets and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedAsset(curveLpToken, 100000);
            ROLLUP_PROCESSOR.setSupportedAsset(representingConvexToken, 100000);
            vm.stopPrank();

            // Fetch the id of the convex staking bridge
            bridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

            // get Aztec assets
            AztecTypes.AztecAsset memory curveLpAsset = ROLLUP_ENCODER.getRealAztecAsset(curveLpToken);
            AztecTypes.AztecAsset memory representingConvexAsset = ROLLUP_ENCODER.getRealAztecAsset(
                representingConvexToken
            );

            // Mint depositAmount of CURVE LP tokens for RollUp Processor
            deal(curveLpToken, address(ROLLUP_PROCESSOR), _depositAmount);

            _deposit(bridgeId, curveLpAsset, representingConvexAsset, _depositAmount);

            _withdraw(bridgeId, representingConvexAsset, curveLpAsset, _depositAmount);
        }
    }

    function _deposit(
        uint256 _bridgeId,
        AztecTypes.AztecAsset memory _curveLpAsset,
        AztecTypes.AztecAsset memory _representingConvexAsset,
        uint256 _depositAmount
    ) internal {
        ROLLUP_ENCODER.defiInteractionL2(
            _bridgeId,
            _curveLpAsset,
            emptyAsset,
            _representingConvexAsset,
            emptyAsset,
            0,
            _depositAmount
        );

        // move time forward to have claimable amount on beneficiary
        skip(1 days);
        (outputValueA, outputValueB, isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        assertEq(outputValueA, _depositAmount); // number of staked tokens match deposited LP Tokens
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
        assertEq(IERC20(representingConvexToken).balanceOf(address(ROLLUP_PROCESSOR)), _depositAmount);
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
            _bridgeId,
            _representingConvexAsset,
            emptyAsset,
            _curveLpAsset,
            emptyAsset,
            0,
            _depositAmount
        );

        skip(1 days); // move time forward to have claimable amount on beneficiary
        (outputValueA, outputValueB, isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();
        rewind(2 days); // move time back to original for the next bridge run

        assertEq(outputValueA, _depositAmount); // number of withdrawn tokens match deposited LP Tokens
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");

        assertEq(IERC20(curveLpToken).balanceOf(address(ROLLUP_PROCESSOR)), _depositAmount); // Curve LP tokens owned by RollUp

        assertEq(IERC20(representingConvexToken).balanceOf(address(bridge)), 0); // RCT succesfully burned
        assertEq(IERC20(representingConvexToken).balanceOf(address(ROLLUP_PROCESSOR)), 0); // RCT succesfully burned

        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");
    }

    function _setupSubsidy() internal {
        // Set ETH balance of bridge and BENEFICIARY to 0 for clarity (somebody sent ETH to that address on mainnet)
        vm.deal(address(bridge), 0);
        vm.deal(BENEFICIARY, 0);

        AztecTypes.AztecAsset memory curveLpAsset = AztecTypes.AztecAsset(
            1,
            curveLpToken,
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory representingConvexAsset = AztecTypes.AztecAsset(
            0,
            representingConvexToken,
            AztecTypes.AztecAssetType.ERC20
        );

        // different criteria for deposit and withdrawal
        uint256 criteria = bridge.computeCriteria(curveLpAsset, emptyAsset, representingConvexAsset, emptyAsset, 0);

        uint32 minGasPerMinute = 350;

        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criteria, minGasPerMinute);

        SUBSIDY.registerBeneficiary(BENEFICIARY);

        // Set the rollupBeneficiary on BridgeTestBase so that it gets included in the proofData
        ROLLUP_ENCODER.setRollupBeneficiary(BENEFICIARY);
    }

    function _setUpBridge(uint256 _poolId) internal {
        bridge = new ConvexStakingBridge(address(ROLLUP_PROCESSOR));
        (curveLpToken, convexLpToken, gauge, crvRewards, stash, ) = IConvexBooster(BOOSTER).poolInfo(_poolId);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(curveLpToken, "Curve LP Token Contract");
        vm.label(convexLpToken, "Convex Token Contract");
        vm.label(crvRewards, "CrvRewards Contract");
        vm.label(stash, "Stash Contract");
        vm.label(gauge, "Gauge Contract");
    }

    function _setupTestPoolIds(
        uint256 _poolLength,
        uint16 _poolId1,
        uint16 _poolId2,
        uint16 _poolId3,
        uint16 _poolId4,
        uint16 _poolId5
    ) internal {
        delete poolIdsToTest;

        // poolId value limitation
        bound(_poolId1, 0, _poolLength - 1);
        bound(_poolId2, 0, _poolLength - 1);
        bound(_poolId3, 0, _poolLength - 1);
        bound(_poolId4, 0, _poolLength - 1);
        bound(_poolId5, 0, _poolLength - 1);

        // test pools filled
        poolIdsToTest.push(_poolId1);
        poolIdsToTest.push(_poolId2);
        poolIdsToTest.push(_poolId3);
        poolIdsToTest.push(_poolId4);
        poolIdsToTest.push(_poolId5);
    }

    function _setUpInvalidPoolIds(uint256 _pid) internal {
        invalidPoolIds[_pid] = true;
    }

    function _setupRepresentingConvexToken() internal {
        representingConvexToken = bridge.deployedTokens(curveLpToken);
        vm.label(representingConvexToken, "Representing Convex Token");
    }
}
