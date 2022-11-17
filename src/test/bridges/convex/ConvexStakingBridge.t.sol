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
    address private RCTImplementation;
    address private RCTClone;
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

    uint256[] public invalidPids = [48, 11, 16]; // define invalid pids // 11 and 16 pools are closed
    mapping(uint256 => bool) public invalidPoolIds;

    bool poolClosed;

    uint16[] public poolIdsToTest = new uint16[](5); // 5 test pool ids

    uint256[] private rewardsGreater;

    error InvalidAssetType();
    error UnknownAssetA();


    event ShowDepositGas(uint gas);
    event ShowWithdrawGas(uint gas);
    event ShowRctImplementationAddress(address rctImplementation);

    function setUp() public {
        rollupProcessor = address(this);
        staker = IConvexBooster(BOOSTER).staker();
        minter = IConvexBooster(BOOSTER).minter();

        _setupInvalidPoolIds();

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
        address invalidCurveLpToken = address(123);
        uint256 depositAmount = 10;

        // labels
        vm.label(invalidCurveLpToken, "Invalid Curve LP Token Address");

        
        _setupBridge(112);
        _loadPool(112);
        _setupRepresentingConvexTokenClone();

        vm.expectRevert(UnknownAssetA.selector);
        bridge.convert(
            AztecTypes.AztecAsset(1, invalidCurveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, RCTClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testInvalidInputAssetType() public {
        address invalidCurveLpToken = address(123);
        uint256 depositAmount = 10;

        // labels
        vm.label(invalidCurveLpToken, "Invalid Curve LP Token Address");

        _setupBridge(112);
        _loadPool(112);
        _setupRepresentingConvexTokenClone();

        vm.expectRevert(InvalidAssetType.selector);
        bridge.convert(
            AztecTypes.AztecAsset(1, invalidCurveLpToken, AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(100, RCTClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testInvalidInputAssetTypeEth() public {
        uint256 depositAmount = 10e18;

        _setupBridge(112);
        _loadPool(112);
        _setupRepresentingConvexTokenClone();

        vm.expectRevert(InvalidAssetType.selector);
        bridge.convert{value: depositAmount}(
            AztecTypes.AztecAsset(1, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            AztecTypes.AztecAsset(100, RCTClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testInvalidOutput() public {
        uint256 withdrawalAmount = 10;
        address invalidLpToken = address(123);
        uint256 lastPoolId = IConvexBooster(BOOSTER).poolLength() - 1;

        _setupBridge(lastPoolId);
        _loadPool(lastPoolId);
        _setupRepresentingConvexTokenClone();

        // make deposit
        _deposit(withdrawalAmount);

        vm.expectRevert(UnknownAssetA.selector);
        bridge.convert(
            AztecTypes.AztecAsset(100, RCTClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, invalidLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            withdrawalAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    // Curve LP token of another pool is tried to be withdrawn -> pool "Curve LP token - RCT" mismatch
    function testInvalidOutput2() public {
        uint256 withdrawalAmount = 10;
        uint256 lastPoolId = IConvexBooster(BOOSTER).poolLength() - 1;
        uint256 anotherPoolId = lastPoolId - 1;
        address incorrectCurveLpToken; // valid curve lp token of another already loaded pool

        _setupBridge(lastPoolId);
        // both pools are loaded
        _loadPool(lastPoolId);
        _loadPool(anotherPoolId);
        _setupRepresentingConvexTokenClone();

        // make deposit for a pool at index `lastPoolId`
        _deposit(withdrawalAmount);

        // withdraw using correct interaction but incorrect pool
        (incorrectCurveLpToken, , , , , ) = IConvexBooster(BOOSTER).poolInfo(anotherPoolId);
        vm.label(incorrectCurveLpToken, "Incorrect Curve LP Token Contract");

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(
            AztecTypes.AztecAsset(100, RCTClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, incorrectCurveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            withdrawalAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testInvalidOutputEth() public {
        uint256 withdrawalAmount = 10;
        uint256 lastPoolId = IConvexBooster(BOOSTER).poolLength() - 1;

        _setupBridge(lastPoolId);
        _loadPool(lastPoolId);
        _setupRepresentingConvexTokenClone();

        // make deposit, setup total balance in CrvRewards
        _deposit(withdrawalAmount);

        vm.expectRevert(InvalidAssetType.selector);
        bridge.convert(
            AztecTypes.AztecAsset(100, RCTClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            withdrawalAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testConvertInvalidCaller() public {
        address invalidCaller = address(123);
        uint256 depositAmount = 10;
        uint256 lastPoolId = IConvexBooster(BOOSTER).poolLength() - 1;

        _setupBridge(lastPoolId);
        _loadPool(lastPoolId);
        _setupRepresentingConvexTokenClone();

        vm.prank(invalidCaller);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, RCTClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    // pool not loaded yet, RCT not deployed yet
    function testPoolNotLoadedYet(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1);

        _setupBridge(112);
        _setupRepresentingConvexTokenClone();

        // Mock initial balance of CURVE LP Token for Rollup Processor
        deal(curveLpToken, rollupProcessor, _depositAmount); // could be removed
        // transfer CURVE LP Tokens from RollUpProcessor to the bridge
        IERC20(curveLpToken).transfer(address(bridge), _depositAmount); // could be removed

        vm.expectRevert(UnknownAssetA.selector);
        bridge.convert(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, RCTClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            _depositAmount,
            0,
            0,
            BENEFICIARY
        );
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

        _setupTestPoolIds(poolLength, _poolId1, _poolId2, _poolId3, _poolId4, 112);

        // for (uint256 i = 0; i < poolIdsToTest.length; i++) {
        for (uint256 i = 4; i < 5; i++) {
            if (invalidPoolIds[poolIdsToTest[i]]) {
                continue;
            }

            _setupBridge(poolIdsToTest[i]);
            if (poolClosed) continue;

            _loadPool(poolIdsToTest[i]);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();

            skip(1 days);
            _deposit(_depositAmount);
            rewind(1 days);

            SUBSIDY.withdraw(BENEFICIARY);
            assertGt(BENEFICIARY.balance, 0, "Subsidy was not claimed");
        }
    }

    function testWithdrawLpTokens(
        uint64 _withdrawalAmount,
        uint16 _poolId1,
        uint16 _poolId2,
        uint16 _poolId3,
        uint16 _poolId4
    ) public {
        vm.assume(_withdrawalAmount > 4012207535227600);
        // deposit LpTokens first so the totalSupply of minted tokens match (no other workaround)
        uint256 poolLength = IConvexBooster(BOOSTER).poolLength();

        delete rewardsGreater; // clear array on test start

        _setupTestPoolIds(poolLength, _poolId1, _poolId2, _poolId3, _poolId4, 112); // Pool id 112 intentionally selected -> to prevent possibility that all selected pools yield zero CRV and CVX rewards in the specified time frame.

        for (uint256 i = 0; i < poolIdsToTest.length; i++) {
        // for (uint256 i = 4; i < 5; i++) {
            if (invalidPoolIds[i]) {
                continue;
            }

            _setupBridge(poolIdsToTest[i]);
            if (poolClosed) continue;

            _loadPool(poolIdsToTest[i]);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();

            // deposit Curve LP tokens, set up totalSupply on CrvRewards
            skip(1 days);
            _deposit(_withdrawalAmount);

            _withdraw(_withdrawalAmount, poolIdsToTest[i]);
        }
        // Rewards successfully claimed check, some rewards may not have accumulated in the limited time frame
        assertGt(rewardsGreater.length, 0);
    }

    function _withdraw(uint64 _withdrawalAmount, uint256 _poolId) internal {
        // transfer representing Convex tokens to the bridge
        IERC20(RCTClone).transfer(address(bridge), _withdrawalAmount);

        uint256 rewardsCRVBefore = IERC20(CRV_TOKEN).balanceOf(address(bridge));
        uint256 rewardsCVXBefore = IERC20(CVX_TOKEN).balanceOf(address(bridge));

        uint gas1 = gasleft();

        skip(20 days);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(100, RCTClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            _withdrawalAmount,
            0,
            0,
            BENEFICIARY
        );
        rewind(21 days);

        uint gas2 = gasleft();

        emit ShowWithdrawGas(gas1 - gas2);

        uint256 rewardsCRVAfter = IERC20(CRV_TOKEN).balanceOf(address(bridge));
        uint256 rewardsCVXAfter = IERC20(CVX_TOKEN).balanceOf(address(bridge));

        if (rewardsCRVAfter > rewardsCRVBefore && rewardsCVXAfter > rewardsCVXBefore) {
            rewardsGreater.push(_poolId);
        }

        assertEq(outputValueA, _withdrawalAmount);
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");

        // Transfer Curve LP tokens from the bridge to Rollup Processor
        assertEq(IERC20(curveLpToken).balanceOf(address(bridge)), _withdrawalAmount);
        IERC20(curveLpToken).transferFrom(address(bridge), rollupProcessor, _withdrawalAmount);
        assertEq(IERC20(curveLpToken).balanceOf(rollupProcessor), _withdrawalAmount);

        // Check that representing Convex tokens were successfully burned
        assertEq(IERC20(RCTClone).balanceOf(rollupProcessor), 0);
        assertEq(IERC20(RCTClone).balanceOf(address(bridge)), 0);

        // Claim subsidy at withdrawal
        SUBSIDY.withdraw(BENEFICIARY);
        assertGt(BENEFICIARY.balance, 0, "Subsidy was not claimed");
    }

    /**
    @notice Mocking of Curve LP token balance.
    @notice Depositing Curve LP tokens.
    @notice Transfering minted representing Convex tokens to RollupProcessor
    @param _depositAmount Number of Curve LP tokens to stake.
    */
    function _deposit(uint256 _depositAmount) internal {
        // Mock initial balance of CURVE LP Token for Rollup Processor
        deal(curveLpToken, rollupProcessor, _depositAmount);

        // transfer CURVE LP Tokens from RollUpProcessor to the bridge
        IERC20(curveLpToken).transfer(address(bridge), _depositAmount);

        uint gas1 = gasleft();

        // bridge.deployedClones(curveLpToken) == cloneAddress and we move funds through it (not the implementation - not the representingConvexToken)

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, RCTClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            _depositAmount,
            0,
            0,
            BENEFICIARY
        );

        uint gas2 = gasleft();

        emit ShowDepositGas(gas1 - gas2);

        assertEq(outputValueA, _depositAmount);
        assertEq(outputValueB, 0, "Output value B is not 0.");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");

        // check balance of minted rep convex tokens
        assertEq(IERC20(RCTClone).balanceOf(address(bridge)), _depositAmount);

        // transfer representing Convex token to RollupProcessor
        IERC20(RCTClone).transferFrom(address(bridge), rollupProcessor, _depositAmount);
        assertEq(IERC20(RCTClone).balanceOf(rollupProcessor), _depositAmount);
    }

    function _setupRepresentingConvexTokenClone() internal {
        RCTImplementation = bridge.rctImplementation();
        vm.label(RCTImplementation, "Representing Convex Token Implementation");

        RCTClone = bridge.deployedClones(curveLpToken);
        vm.label(RCTClone, "Representing Convex Token Clone");
    }

    function _loadPool(uint _poolId) internal {
        bridge.loadPool(_poolId);
    }

    function _setupBridge(uint256 _poolId) internal {
        bridge = new ConvexStakingBridge(rollupProcessor);
        (curveLpToken, convexLpToken, gauge, crvRewards, stash, poolClosed) = IConvexBooster(BOOSTER).poolInfo(_poolId);

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

        uint256 criteria = bridge.computeCriteria(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, bridge.deployedClones(curveLpToken), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            0
        );

        uint32 minGasPerMinute = 350;

        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criteria, minGasPerMinute);

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

        // test pools filled with limitated poolIds
        poolIdsToTest.push(uint16(bound(_poolId1, 0, _poolLength - 1)));
        poolIdsToTest.push(uint16(bound(_poolId2, 0, _poolLength - 1)));
        poolIdsToTest.push(uint16(bound(_poolId3, 0, _poolLength - 1)));
        poolIdsToTest.push(uint16(bound(_poolId4, 0, _poolLength - 1)));
        poolIdsToTest.push(uint16(bound(_poolId5, 0, _poolLength - 1)));
    }

    function _setupInvalidPoolIds() internal {
        for (uint256 pid = 0; pid < invalidPids.length; pid++) {
            invalidPoolIds[invalidPids[pid]] = true;
        }
    }
}
