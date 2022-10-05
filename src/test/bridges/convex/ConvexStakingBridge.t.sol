// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {IConvexFinanceBooster} from "../../../interfaces/convex/IConvexFinanceBooster.sol";

contract ConvexStakingBridgeTest is BridgeTestBase {
    address private CURVE_LP_TOKEN;
    address private CONVEX_TOKEN;
    address private constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private STAKER;
    address private GAUGE;
    address private STASH;
    address private CRV_REWARDS;

    address private rollupProcessor;

    ConvexStakingBridge private bridge;

    mapping(uint => bool) public invalidPoolPids;

    error invalidInputOutputAssets();
    error invalidAssetType();

    function setUp() public {
        rollupProcessor = address(this);
        STAKER = IConvexFinanceBooster(BOOSTER).staker();
        _setUpInvalidPoolPids(48);

        // labels
        vm.label(address(this), "Test Contract");
        vm.label(address(msg.sender), "Test Contract Msg Sender");
        vm.label(BOOSTER, "Booster");
        vm.label(STAKER, "Staker Contract Address");
    }

    function testInitialERC20Params() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        assertEq(bridge.name(), "ConvexStakingBridge");
        assertEq(bridge.symbol(), "CSB");
        assertEq(uint(bridge.decimals()), 18);
    }

    function testInvalidInput() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        address INVALID_CURVE_LP_TOKEN = address(123);
        uint depositAmount = 10;
        
        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(INVALID_CURVE_LP_TOKEN, "Invalid Curve LP Token Address");

        vm.expectRevert(invalidInputOutputAssets.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(1, INVALID_CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, address(bridge), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            address(11)
        );
    }

    function testInvalidInputEth() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint depositAmount = 10e18;

        vm.label(address(bridge), "Bridge");

        vm.expectRevert(invalidAssetType.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert{value: depositAmount}(
            AztecTypes.AztecAsset(1, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            AztecTypes.AztecAsset(100, address(bridge), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            address(11)
        );
    }

    function testInvalidOutput() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint withdrawalAmount = 10;
        address invalidLpToken = address(123);
        uint lastPoolPid = IConvexFinanceBooster(BOOSTER).poolLength() - 1;
        
        (CURVE_LP_TOKEN,,,,,) = IConvexFinanceBooster(BOOSTER).poolInfo(lastPoolPid);


        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");

        // mint CSB tokens
        _deposit(withdrawalAmount);

        // transfer CSB Tokens from RollUpProcessor to the bridge
        IERC20(address(bridge)).transfer(address(bridge), withdrawalAmount);
        
        vm.expectRevert(invalidInputOutputAssets.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(100, address(bridge), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, invalidLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            withdrawalAmount,
            0,
            0,
            address(11)
        );
    }

    function testInvalidOutputEth() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint withdrawalAmount = 10;
        address invalidLpToken = address(123);
        uint lastPoolPid = IConvexFinanceBooster(BOOSTER).poolLength() - 1;
        
        (CURVE_LP_TOKEN,,,,,) = IConvexFinanceBooster(BOOSTER).poolInfo(lastPoolPid);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");

        // mint CSB tokens
        _deposit(withdrawalAmount);

        // transfer CSB Tokens from RollUpProcessor to the bridge
        IERC20(address(bridge)).transfer(address(bridge), withdrawalAmount);
        
        vm.expectRevert(invalidAssetType.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(100, address(bridge), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            withdrawalAmount,
            0,
            0,
            address(11)
        );
    }

    function testConvertInvalidCaller() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        address invalidCaller = address(123);
        uint depositAmount = 10;
        uint lastPoolPid = IConvexFinanceBooster(BOOSTER).poolLength() - 1;
        (CURVE_LP_TOKEN,,,,,) = IConvexFinanceBooster(BOOSTER).poolInfo(lastPoolPid);
        
        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");
        
        vm.prank(invalidCaller);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, address(bridge), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            address(11)
        );
    }

    function testStakeLpTokens(uint96 depositAmount) public {
        vm.assume(depositAmount > 1);

        uint poolLength = IConvexFinanceBooster(BOOSTER).poolLength();

        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }

            _setUpBridge(i);

            _deposit(depositAmount);
            assertEq(bridge.balanceOf(address(bridge)), 0);
        }
    }

    function testZeroTotalInputValue() public {
        uint depositAmount = 0;
        uint poolLength = IConvexFinanceBooster(BOOSTER).poolLength();

        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }

            _setUpBridge(i);

            // Mock initial balance of CURVE LP Token for Rollup Processor
            deal(CURVE_LP_TOKEN, rollupProcessor, depositAmount);
            // transfer CURVE LP Tokens from RollUpProcessor to the bridge
            IERC20(CURVE_LP_TOKEN).transfer(address(bridge), depositAmount);

            vm.expectRevert(ErrorLib.InvalidInputAmount.selector);
            (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
                AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
                emptyAsset,
                AztecTypes.AztecAsset(100, address(bridge), AztecTypes.AztecAssetType.ERC20),
                emptyAsset,
                depositAmount,
                0,
                0,
                address(11)
            );
        }
    }

    function testWithdrawLpTokens(uint64 withdrawalAmount) public {
        vm.assume(withdrawalAmount > 1);
        // deposit LpTokens first so the totalSupply of minted tokens match (no other workaround)
        uint poolLength = IConvexFinanceBooster(BOOSTER).poolLength();

        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }
            if (i != 112) {
                continue;
            }

            _setUpBridge(i);
                
            // mint necessary CSB Tokens so they can be burned at withdrawal
            _deposit(withdrawalAmount);

            // transfer CSB Tokens from RollUpProcessor to the bridge
            IERC20(address(bridge)).transfer(address(bridge), withdrawalAmount);
            IERC20(CONVEX_TOKEN).balanceOf(address(bridge));
            IERC20(CONVEX_TOKEN).balanceOf(BOOSTER);
            IERC20(CONVEX_TOKEN).balanceOf(CRV_REWARDS);

            (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
                AztecTypes.AztecAsset(100, address(bridge), AztecTypes.AztecAssetType.ERC20),
                emptyAsset,
                AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
                emptyAsset,
                withdrawalAmount,
                0,
                0,
                address(11)
            );
            assertEq(outputValueA, withdrawalAmount);
            assertEq(outputValueB, 0, "Output value B is not 0"); // I am not really returning these two, so it actually returns a default..
            assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");

            assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(address(bridge)), withdrawalAmount);
            IERC20(CURVE_LP_TOKEN).transferFrom(address(bridge), rollupProcessor, withdrawalAmount);
            assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(rollupProcessor), withdrawalAmount);

            assertEq(IERC20(address(bridge)).balanceOf(address(bridge)), 0);
            assertEq(IERC20(address(bridge)).balanceOf(rollupProcessor), 0);
        }
    }

    /**
    @notice Mocking of Curve LP Token balance.
    @notice Depositing Curve LP Tokens and their subsequent staking.  
    @notice Minting of CSB Tokens.
    @param depositAmount Number of Curve LP Tokens to stake.
    */
    function _deposit(uint depositAmount) internal {
        // Mock initial balance of CURVE LP Token for Rollup Processor
        deal(CURVE_LP_TOKEN, rollupProcessor, depositAmount);

        // transfer CURVE LP Tokens from RollUpProcessor to the bridge
        IERC20(CURVE_LP_TOKEN).transfer(address(bridge), depositAmount);

        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, address(bridge), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            address(11)
        );

        assertEq(outputValueA, depositAmount);
        assertEq(outputValueB, 0, "Output value B is not 0."); // I am not really returning these two, so it actually returns a default..
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
        assertEq(bridge.balanceOf(address(bridge)), outputValueA);
        assertEq(bridge.totalSupply(), depositAmount);

        IERC20(address(bridge)).transferFrom(address(bridge), rollupProcessor, outputValueA);
        assertEq(bridge.balanceOf(rollupProcessor), depositAmount);
    }

    function _setUpBridge(uint poolPid) internal {
        bridge = new ConvexStakingBridge(rollupProcessor);
        (CURVE_LP_TOKEN, CONVEX_TOKEN, GAUGE, CRV_REWARDS, STASH,) = IConvexFinanceBooster(BOOSTER).poolInfo(poolPid);
        
        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");
        vm.label(CONVEX_TOKEN, "Convex Token Contract");
        vm.label(CRV_REWARDS, "CrvRewards Contract");
        vm.label(STASH, "Stash Contract");
        vm.label(GAUGE, "Gauge Contract");
    }

    function _setUpInvalidPoolPids(uint pid) internal {
        invalidPoolPids[pid] = true;
    }
}
