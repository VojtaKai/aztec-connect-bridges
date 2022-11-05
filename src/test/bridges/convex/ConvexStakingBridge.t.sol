// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {IConvexBooster} from "../../../interfaces/convex/IConvexBooster.sol";

contract ConvexStakingBridgeTest is BridgeTestBase {
    address private curveLpToken;
    address private convexLpToken;
    address private constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private staker;
    address private gauge;
    address private stash;
    address private crvRewards;
    address private minter;
    address private constant CRV_TOKEN = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address private constant CVX_TOKEN = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address private constant BENEFICIARY = address(777);

    address private rollupProcessor;

    uint256 private constant INTERACTION_NONCE = 2**30;

    ConvexStakingBridge private bridge;

    uint256[] public invalidPids = [48]; // define invalid pids
    mapping(uint256 => bool) public invalidPoolIds;

    uint16[] public poolIdsToTest = new uint16[](5); // 5 test pool ids

    uint256[] private rewardsGreater;

    error InvalidAssetType();
    error UnknownVirtualAsset();
    error IncorrectInteractionValue(uint256 stakedValue, uint256 valueToWithdraw);

    function setUp() public {
        rollupProcessor = address(this);
        staker = IConvexBooster(BOOSTER).staker();
        minter = IConvexBooster(BOOSTER).minter();

        _setUpInvalidPoolIds();

        // labels
        vm.label(address(this), "Test Contract");
        vm.label(address(msg.sender), "Test Contract Msg Sender");
        vm.label(BOOSTER, "Booster");
        vm.label(staker, "Staker Contract Address");
        vm.label(minter, "Minter");
        vm.label(CRV_TOKEN, "Reward boosted CRV Token");
        vm.label(CVX_TOKEN, "Reward CVX Token");
        vm.label(BENEFICIARY, "Beneficiary");
    }

    function testInvalidInput() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        address invalidCurveLpToken = address(123);
        uint256 depositAmount = 10;

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(invalidCurveLpToken, "Invalid Curve LP Token Address");

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(
            AztecTypes.AztecAsset(1, invalidCurveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            depositAmount,
            INTERACTION_NONCE,
            0,
            BENEFICIARY
        );
    }

    function testInvalidInputEth() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint256 depositAmount = 10e18;

        vm.label(address(bridge), "Bridge");

        vm.expectRevert(InvalidAssetType.selector);
        bridge.convert{value: depositAmount}(
            AztecTypes.AztecAsset(1, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            depositAmount,
            INTERACTION_NONCE,
            0,
            BENEFICIARY
        );
    }

    function testInvalidOutput() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint256 withdrawalAmount = 10;
        address invalidLpToken = address(123);
        uint256 lastPoolId = IConvexBooster(BOOSTER).poolLength() - 1;

        (curveLpToken, , , , , ) = IConvexBooster(BOOSTER).poolInfo(lastPoolId);

        vm.label(address(bridge), "Bridge");
        vm.label(curveLpToken, "Curve LP Token Contract");

        // make deposit and create an interaction
        _deposit(withdrawalAmount);

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, invalidLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            withdrawalAmount,
            INTERACTION_NONCE,
            0,
            BENEFICIARY
        );
    }

    function testInvalidOutput2() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint256 withdrawalAmount = 10;
        uint256 lastPoolId = IConvexBooster(BOOSTER).poolLength() - 1;
        uint256 anotherPoolId = lastPoolId - 1;
        // valid curve lp token of another pool
        address incorrectCurveLpToken;

        (curveLpToken, , , , , ) = IConvexBooster(BOOSTER).poolInfo(lastPoolId);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(curveLpToken, "Curve LP Token Contract");

        // make deposit and note down virtual asset.id (interaction nonce)
        // make deposit for a pool at index `lastPoolId`
        _deposit(withdrawalAmount);

        // withdraw using correct interaction but incorrect pool
        (incorrectCurveLpToken, , , , , ) = IConvexBooster(BOOSTER).poolInfo(anotherPoolId);
        vm.label(incorrectCurveLpToken, "Incorrect Curve LP Token Contract");

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, incorrectCurveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            withdrawalAmount,
            INTERACTION_NONCE,
            0,
            BENEFICIARY
        );
    }

    function testInvalidOutputEth() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint256 withdrawalAmount = 10;
        uint256 lastPoolId = IConvexBooster(BOOSTER).poolLength() - 1;

        (curveLpToken, , , , , ) = IConvexBooster(BOOSTER).poolInfo(lastPoolId);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(curveLpToken, "Curve LP Token Contract");

        // make deposit and note down virtual asset.id (interaction nonce)
        _deposit(withdrawalAmount);

        vm.expectRevert(InvalidAssetType.selector);
        bridge.convert(
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            withdrawalAmount,
            INTERACTION_NONCE,
            0,
            BENEFICIARY
        );
    }

    function testNonExistingInteraction() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint256 withdrawalAmount = 10;
        uint256 lastPoolId = IConvexBooster(BOOSTER).poolLength() - 1;

        uint256 nonExistingInteractionNonce = INTERACTION_NONCE - 1;

        (curveLpToken, , , , , ) = IConvexBooster(BOOSTER).poolInfo(lastPoolId);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(curveLpToken, "Curve LP Token Contract");

        // make deposit and note down virtual asset.id (interaction nonce)
        _deposit(withdrawalAmount);

        vm.expectRevert(UnknownVirtualAsset.selector);
        bridge.convert(
            AztecTypes.AztecAsset(nonExistingInteractionNonce, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            withdrawalAmount,
            nonExistingInteractionNonce,
            0,
            BENEFICIARY
        );
    }

    function testConvertInvalidCaller() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        address invalidCaller = address(123);
        uint256 depositAmount = 10;
        uint256 lastPoolId = IConvexBooster(BOOSTER).poolLength() - 1;
        (curveLpToken, , , , , ) = IConvexBooster(BOOSTER).poolInfo(lastPoolId);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(curveLpToken, "Curve LP Token Contract");

        vm.prank(invalidCaller);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            depositAmount,
            INTERACTION_NONCE,
            0,
            BENEFICIARY
        );
    }

    function testPoolLoading(
        uint96 _depositAmount,
        uint16 _poolId1,
        uint16 _poolId2,
        uint16 _poolId3,
        uint16 _poolId4
    ) public {
        vm.assume(_depositAmount > 1);

        uint256 poolLength = IConvexBooster(BOOSTER).poolLength();

        _setupTestPoolIds(poolLength, _poolId1, _poolId2, _poolId3, _poolId4, 112); // Pool id 112 intentionally selected to guarantee that loading of new pools is tested

        for (uint256 i = 0; i < poolIdsToTest.length; i++) {
            vm.mockCall(BOOSTER, abi.encodeWithSelector(IConvexBooster(BOOSTER).poolLength.selector), abi.encode(100));
            _setUpBridge(i);
            vm.clearMockedCalls();

            _deposit(_depositAmount);

            (curveLpToken, convexLpToken, gauge, crvRewards, stash, ) = IConvexBooster(BOOSTER).poolInfo(i);

            assertEq(bridge.lastPoolLength(), poolLength);
            (
                uint256 pid,
                address poolCurveLpToken,
                address poolConvexLpToken,
                address poolCrvRewards,
                bool exists
            ) = bridge.pools(curveLpToken);
            assertEq(pid, i);
            assertEq(poolCurveLpToken, curveLpToken);
            assertEq(poolConvexLpToken, convexLpToken);
            assertEq(poolCrvRewards, crvRewards);
            assertTrue(exists);
        }
    }

    function testStakeLpTokens(
        uint96 _depositAmount,
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

            _deposit(_depositAmount);
        }
    }

    function testStakeLpTokensClaimSubsidy(
        uint96 _depositAmount,
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
            _setupSubsidy();

            skip(1 days);
            _deposit(_depositAmount);
            rewind(1 days);

            SUBSIDY.withdraw(BENEFICIARY);
            assertGt(BENEFICIARY.balance, 0, "Subsidy was not claimed");
        }
    }

    function testZeroTotalInputValue(
        uint16 _poolId1,
        uint16 _poolId2,
        uint16 _poolId3,
        uint16 _poolId4,
        uint16 _poolId5
    ) public {
        uint256 depositAmount = 0;
        uint256 poolLength = IConvexBooster(BOOSTER).poolLength();

        _setupTestPoolIds(poolLength, _poolId1, _poolId2, _poolId3, _poolId4, _poolId5);

        for (uint256 i = 0; i < poolIdsToTest.length; i++) {
            if (invalidPoolIds[i]) {
                continue;
            }

            _setUpBridge(i);

            // Mock initial balance of CURVE LP Token for Rollup Processor
            deal(curveLpToken, rollupProcessor, depositAmount);
            // Transfer CURVE LP Tokens from RollUpProcessor to the bridge
            IERC20(curveLpToken).transfer(address(bridge), depositAmount);

            vm.expectRevert(ErrorLib.InvalidInputAmount.selector);
            bridge.convert(
                AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
                emptyAsset,
                AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
                emptyAsset,
                depositAmount,
                INTERACTION_NONCE,
                0,
                BENEFICIARY
            );
        }
    }

    function testUnidenticalStakedWithdrawnAmount(
        uint16 _poolId1,
        uint16 _poolId2,
        uint16 _poolId3,
        uint16 _poolId4,
        uint16 _poolId5
    ) public {
        uint64 withdrawalAmount = 10;
        // deposit amount is greater than withdrawal amount -> can't close the interaction
        uint256 depositAmount = withdrawalAmount + 1;
        // deposit LpTokens first so the totalSupply of minted tokens match (no other workaround)
        uint256 poolLength = IConvexBooster(BOOSTER).poolLength();

        _setupTestPoolIds(poolLength, _poolId1, _poolId2, _poolId3, _poolId4, _poolId5);

        for (uint256 i = 0; i < poolIdsToTest.length; i++) {
            if (invalidPoolIds[i]) {
                continue;
            }

            _setUpBridge(i);

            // set up interaction
            _deposit(depositAmount);

            vm.expectRevert(
                abi.encodeWithSelector(IncorrectInteractionValue.selector, depositAmount, withdrawalAmount)
            );
            bridge.convert(
                AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
                emptyAsset,
                AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
                emptyAsset,
                withdrawalAmount,
                INTERACTION_NONCE,
                0,
                BENEFICIARY
            );
        }
    }

    function testWithdrawLpTokens(
        uint64 _withdrawalAmount,
        uint16 _poolId1,
        uint16 _poolId2,
        uint16 _poolId3,
        uint16 _poolId4,
        uint16 _poolId5
    ) public {
        vm.assume(_withdrawalAmount > 1);
        uint256 poolLength = IConvexBooster(BOOSTER).poolLength();

        _setupTestPoolIds(poolLength, _poolId1, _poolId2, _poolId3, _poolId4, _poolId5);

        for (uint256 i = 0; i < poolIdsToTest.length; i++) {
            if (invalidPoolIds[i]) {
                continue;
            }

            _setUpBridge(i);

            // set up interaction
            _deposit(_withdrawalAmount);

            _withdraw(_withdrawalAmount);
        }
    }

    function _withdraw(uint64 _withdrawalAmount) internal {
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            _withdrawalAmount,
            INTERACTION_NONCE,
            0,
            BENEFICIARY
        );
        assertEq(outputValueA, _withdrawalAmount);
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
        assertEq(IERC20(CRV_TOKEN).balanceOf(address(bridge)), 0, "CRV Rewards must have been claimed");
        assertEq(IERC20(CVX_TOKEN).balanceOf(address(bridge)), 0, "CVX Rewards must have been claimed");
        (, , bool interactionNonceExists) = bridge.interactions(INTERACTION_NONCE);
        assertFalse(interactionNonceExists, "Interaction Nonce still exists.");
        assertEq(IERC20(minter).balanceOf(address(bridge)), 0);
        assertEq(IERC20(curveLpToken).balanceOf(address(bridge)), _withdrawalAmount);
        IERC20(curveLpToken).transferFrom(address(bridge), rollupProcessor, _withdrawalAmount);
        assertEq(IERC20(curveLpToken).balanceOf(rollupProcessor), _withdrawalAmount);
    }

    function testWithdrawLpTokensWithRewards(
        uint64 _withdrawalAmount,
        uint16 _poolId1,
        uint16 _poolId2,
        uint16 _poolId3,
        uint16 _poolId4
    ) public {
        vm.assume(_withdrawalAmount > 401220753522760);
        // deposit LpTokens first so the totalSupply of minted tokens match (no other workaround)
        uint256 poolLength = IConvexBooster(BOOSTER).poolLength();

        delete rewardsGreater; // clear array on test start

        _setupTestPoolIds(poolLength, _poolId1, _poolId2, _poolId3, _poolId4, 112); // Pool id 112 intentionally selected -> to prevent possibility that all selected pools yield zero CRV and CVX rewards in the specified time frame.

        for (uint256 i = 0; i < poolIdsToTest.length; i++) {
            if (invalidPoolIds[i]) {
                continue;
            }

            _setUpBridge(i);

            // set up an interaction
            _deposit(_withdrawalAmount);

            _withdrawWithRewards(_withdrawalAmount, i);
        }
        assertGt(rewardsGreater.length, 0);
    }

    function _withdrawWithRewards(uint64 _withdrawalAmount, uint256 _poolId) internal {
        uint256 rewardsCRVBefore = IERC20(CRV_TOKEN).balanceOf(address(bridge));
        uint256 rewardsCVXBefore = IERC20(CVX_TOKEN).balanceOf(address(bridge));

        skip(8 days);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            _withdrawalAmount,
            INTERACTION_NONCE,
            1,
            BENEFICIARY
        );
        rewind(8 days);

        uint256 rewardsCRVAfter = IERC20(CRV_TOKEN).balanceOf(address(bridge));
        uint256 rewardsCVXAfter = IERC20(CVX_TOKEN).balanceOf(address(bridge));

        if (rewardsCRVAfter > rewardsCRVBefore && rewardsCVXAfter > rewardsCVXBefore) {
            rewardsGreater.push(_poolId);
        }

        assertEq(outputValueA, _withdrawalAmount);
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
        (, , bool interactionNonceExists) = bridge.interactions(INTERACTION_NONCE);
        assertFalse(interactionNonceExists, "Interaction Nonce still exists.");

        assertEq(IERC20(curveLpToken).balanceOf(address(bridge)), _withdrawalAmount);
        IERC20(curveLpToken).transferFrom(address(bridge), rollupProcessor, _withdrawalAmount);
        assertEq(IERC20(curveLpToken).balanceOf(rollupProcessor), _withdrawalAmount);
    }

    function testWithdrawLpTokensClaimSubsidy(
        uint64 _withdrawalAmount,
        uint16 _poolId1,
        uint16 _poolId2,
        uint16 _poolId3,
        uint16 _poolId4,
        uint16 _poolId5
    ) public {
        vm.assume(_withdrawalAmount > 1);
        uint256 poolLength = IConvexBooster(BOOSTER).poolLength();

        _setupTestPoolIds(poolLength, _poolId1, _poolId2, _poolId3, _poolId4, _poolId5);

        for (uint256 i = 0; i < poolIdsToTest.length; i++) {
            if (invalidPoolIds[i]) {
                continue;
            }

            _setUpBridge(i);
            _setupSubsidy();

            // set up interaction
            skip(1 days);
            _deposit(_withdrawalAmount);

            // claim subsidy at deposit
            SUBSIDY.withdraw(BENEFICIARY);
            assertGt(BENEFICIARY.balance, 0, "Subsidy was not claimed");

            _withdrawClaimSubsidy(_withdrawalAmount);
        }
    }

    function _withdrawClaimSubsidy(uint64 _withdrawalAmount) internal {
        skip(1 days);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            _withdrawalAmount,
            INTERACTION_NONCE,
            0,
            BENEFICIARY
        );
        rewind(2 days);

        assertEq(outputValueA, _withdrawalAmount);
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
        assertEq(IERC20(CRV_TOKEN).balanceOf(address(bridge)), 0, "CRV Rewards must have been claimed");
        assertEq(IERC20(CVX_TOKEN).balanceOf(address(bridge)), 0, "CVX Rewards must have been claimed");
        (, , bool interactionNonceExists) = bridge.interactions(INTERACTION_NONCE);
        assertFalse(interactionNonceExists, "Interaction Nonce still exists.");
        assertEq(IERC20(minter).balanceOf(address(bridge)), 0);
        assertEq(IERC20(curveLpToken).balanceOf(address(bridge)), _withdrawalAmount);

        IERC20(curveLpToken).transferFrom(address(bridge), rollupProcessor, _withdrawalAmount);
        assertEq(IERC20(curveLpToken).balanceOf(rollupProcessor), _withdrawalAmount);

        // Claim subsidy at withdrawal
        SUBSIDY.withdraw(BENEFICIARY);
        assertGt(BENEFICIARY.balance, 0, "Subsidy was not claimed");
    }

    /**
    @notice Mocking of Curve LP token balance.
    @notice Depositing Curve LP tokens.
    @notice Sets up an interaction.
    @param _depositAmount Number of Curve LP tokens to stake.
    */
    function _deposit(uint256 _depositAmount) internal {
        // Mock initial balance of CURVE LP Token for Rollup Processor
        deal(curveLpToken, rollupProcessor, _depositAmount);

        // transfer CURVE LP Tokens from RollUpProcessor to the bridge
        IERC20(curveLpToken).transfer(address(bridge), _depositAmount);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            _depositAmount,
            INTERACTION_NONCE,
            0,
            BENEFICIARY
        );

        assertEq(outputValueA, _depositAmount);
        assertEq(outputValueB, 0, "Output value B is not 0.");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
    }

    function _setUpBridge(uint256 _poolId) internal {
        bridge = new ConvexStakingBridge(rollupProcessor);
        (curveLpToken, convexLpToken, gauge, crvRewards, stash, ) = IConvexBooster(BOOSTER).poolInfo(_poolId);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(curveLpToken, "Curve LP Token Contract");
        vm.label(convexLpToken, "Convex Token Contract");
        vm.label(crvRewards, "CrvRewards Contract");
        vm.label(stash, "Stash Contract");
        vm.label(gauge, "Gauge Contract");
    }

    function _setupSubsidy() internal {
        // Set ETH balance of bridge and BENEFICIARY to 0 for clarity (somebody sent ETH to that address on mainnet)
        vm.deal(address(bridge), 0);
        vm.deal(BENEFICIARY, 0);

        uint256[] memory criterias = new uint256[](2);
        uint32[] memory gasUsage = new uint32[](2);
        uint32[] memory minGasPerMinute = new uint32[](2);

        AztecTypes.AztecAsset memory curveLpToken = AztecTypes.AztecAsset(
            1,
            curveLpToken,
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory virtualAsset = AztecTypes.AztecAsset(
            INTERACTION_NONCE,
            address(0),
            AztecTypes.AztecAssetType.VIRTUAL
        );

        criterias[0] = bridge.computeCriteria(curveLpToken, emptyAsset, virtualAsset, emptyAsset, 0);
        criterias[1] = bridge.computeCriteria(virtualAsset, emptyAsset, curveLpToken, emptyAsset, 0);

        gasUsage[0] = 1000000;
        gasUsage[1] = 375000;

        minGasPerMinute[0] = 690;
        minGasPerMinute[1] = 260;

        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criterias[0], minGasPerMinute[0]);
        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criterias[1], minGasPerMinute[1]);

        SUBSIDY.registerBeneficiary(BENEFICIARY);
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

    function _setUpInvalidPoolIds() internal {
        for (uint256 pid = 0; pid < invalidPids.length; pid++) {
            invalidPoolIds[invalidPids[pid]] = true;
        }
    }
}
