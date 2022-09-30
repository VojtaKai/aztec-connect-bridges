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

    error invalidTotalInputValue();
    error invalidInputOutputAssets();
    error invalidPoolPid();
    error invalidAssetType();

    function setUp() public {
        rollupProcessor = address(this);
        vm.label(address(this), "Test Contract");
        vm.label(address(msg.sender), "Test Contract Msg Sender");
        vm.label(BOOSTER, "Booster");
    }

    function testInitialERC20Params() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        assertEq(bridge.name(), "ConvexStakingBridge");
        assertEq(bridge.symbol(), "CSB");
        assertEq(uint(bridge.decimals()), 18);
    }

    function testAddInvalidPoolPid() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint pid = 120;
        bridge.addInvalidPoolPid(pid);

        assertTrue(bridge.invalidPoolPids(pid));
    }

    function testAddInvalidPoolPidInvalidCaller() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        address invalidCaller = address(123);
        uint pid = 120;

        vm.prank(invalidCaller);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.addInvalidPoolPid(pid);
    }

    function testRemoveInvalidPoolPid() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint pid = 120;

        _setUpInvalidPoolPidData(pid);

        bridge.removeInvalidPoolPid(pid);
        assertFalse(bridge.invalidPoolPids(pid));
    }

    function testRemoveInvalidPoolPidInvalidCaller() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint pid = 120;
        address invalidCaller = address(123);

        _setUpInvalidPoolPidData(pid);

        vm.prank(address(invalidCaller));
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.removeInvalidPoolPid(pid);
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
        CURVE_LP_TOKEN = 0xe7A3b38c39F97E977723bd1239C3470702568e7B;
        uint withdrawalAmount = 10;
        address invalidLpToken = address(123);

        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");

        // // mint CSB tokens
        // _deposit(withdrawalAmount);

        // // transfer CSB Tokens from RollUpProcessor to the bridge
        // IERC20(address(bridge)).transfer(address(bridge), withdrawalAmount);
        
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
        CURVE_LP_TOKEN = 0xe7A3b38c39F97E977723bd1239C3470702568e7B;
        uint withdrawalAmount = 10;
        address invalidLpToken = address(123);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");

        // // mint CSB tokens
        // _deposit(withdrawalAmount);

        // // transfer CSB Tokens from RollUpProcessor to the bridge
        // IERC20(address(bridge)).transfer(address(bridge), withdrawalAmount);
        
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
        uint poolPid = IConvexFinanceBooster(BOOSTER).poolLength() - 1;
        
        (CURVE_LP_TOKEN,,,,,) = IConvexFinanceBooster(BOOSTER).poolInfo(poolPid);
        
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
        uint poolLength = IConvexFinanceBooster(BOOSTER).poolLength();
        STAKER = IConvexFinanceBooster(BOOSTER).staker();
        vm.label(STAKER, "Staker Contract Address");
        for (uint i=0; i < poolLength; i++) {
            bridge = new ConvexStakingBridge(rollupProcessor);
            vm.label(address(bridge), "Bridge");
            (CURVE_LP_TOKEN, CONVEX_TOKEN, GAUGE, CRV_REWARDS, STASH,) = IConvexFinanceBooster(BOOSTER).poolInfo(i);
            vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");
            vm.label(CONVEX_TOKEN, "Convex Token Contract");
            vm.label(CRV_REWARDS, "CrvRewards Contract");
            vm.label(STASH, "Stash Contract");
            vm.label(GAUGE, "Gauge Contract");
            if (!bridge.invalidPoolPids(i)) {
                _deposit(depositAmount);
                assertEq(bridge.balanceOf(address(bridge)), 0);
            } else {
                // Deal depositAmount of CURVE LP tokens to the Rollup Processor 
                deal(CURVE_LP_TOKEN, rollupProcessor, depositAmount);

                // transfer CURVE LP Tokens from RollUpProcessor to the bridge
                IERC20(CURVE_LP_TOKEN).transfer(address(bridge), depositAmount);

                if (depositAmount == 0) {
                    vm.expectRevert(invalidTotalInputValue.selector);
                } else {
                    vm.expectRevert(invalidPoolPid.selector);
                }
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
    }


    function testWithdrawLpTokens(uint64 withdrawalAmount) public {
        // deposit LpTokens first so the totalSupply of minted tokens match (no other workaround)
        uint poolLength = IConvexFinanceBooster(BOOSTER).poolLength();
        STAKER = IConvexFinanceBooster(BOOSTER).staker();
        vm.label(STAKER, "Staker Contract Address");
        for (uint i=0; i < poolLength; i++) {
            bridge = new ConvexStakingBridge(rollupProcessor);
            vm.label(address(bridge), "Bridge");
            (CURVE_LP_TOKEN, CONVEX_TOKEN, GAUGE, CRV_REWARDS, STASH,) = IConvexFinanceBooster(BOOSTER).poolInfo(i);
            vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");
            vm.label(CONVEX_TOKEN, "Convex Token Contract");
            vm.label(CRV_REWARDS, "CrvRewards Contract");
            vm.label(STASH, "Stash Contract");
            vm.label(GAUGE, "Gauge Contract");
            if (!bridge.invalidPoolPids(i)) {
                
                // mint necessary CSB Tokens so they can be burned at withdrawal
                _deposit(withdrawalAmount);

                deal(CONVEX_TOKEN, address(bridge), withdrawalAmount);

                // transfer CSB Tokens from RollUpProcessor to the bridge
                IERC20(address(bridge)).transfer(address(bridge), withdrawalAmount);
                
                if (withdrawalAmount == 0) {
                    vm.expectRevert(invalidTotalInputValue.selector);
                }

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
                assertEq(outputValueB, 0, "Output value B is not 0."); // I am not really returning these two, so it actually returns a default..
                assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");

                assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(address(bridge)), withdrawalAmount);
                IERC20(CURVE_LP_TOKEN).transferFrom(address(bridge), rollupProcessor, withdrawalAmount);
                assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(rollupProcessor), withdrawalAmount);

                assertEq(IERC20(address(bridge)).balanceOf(address(bridge)), 0);
                assertEq(IERC20(address(bridge)).balanceOf(rollupProcessor), 0);
            } else {
                // Mock number of convex tokens for the bridge
                deal(CONVEX_TOKEN, address(bridge), withdrawalAmount);
                // Mock number of CSB Tokens for RollupProcessor
                deal(address(bridge), rollupProcessor, withdrawalAmount);

                // transfer CSB Tokens from RollUpProcessor to the bridge
                IERC20(address(bridge)).transfer(address(bridge), withdrawalAmount);

                if (withdrawalAmount == 0) {
                    vm.expectRevert(invalidTotalInputValue.selector);
                } else {
                    vm.expectRevert(invalidPoolPid.selector);
                }
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
            }
        }
    }

    function testInvalidPoolPidsStillInvalid(uint96 depositAmount) public {
        uint poolLength = IConvexFinanceBooster(BOOSTER).poolLength();
        STAKER = IConvexFinanceBooster(BOOSTER).staker();
        vm.label(STAKER, "Staker Contract Address");
        for (uint i=0; i < poolLength; i++) {
            bridge = new ConvexStakingBridge(rollupProcessor);
            if (!bridge.invalidPoolPids(i)) {
                continue;
            }
            bridge.removeInvalidPoolPid(i);

            // test staking
            (CURVE_LP_TOKEN, CONVEX_TOKEN, GAUGE, CRV_REWARDS, STASH,) = IConvexFinanceBooster(BOOSTER).poolInfo(i);
            vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");
            vm.label(CONVEX_TOKEN, "Convex Token Contract");
            vm.label(CRV_REWARDS, "CrvRewards Contract");
            vm.label(STASH, "Stash Contract");
            vm.label(GAUGE, "Gauge Contract");

            deal(CURVE_LP_TOKEN, rollupProcessor, depositAmount);

            // transfer CURVE LP Tokens from RollUpProcessor to the bridge
            IERC20(CURVE_LP_TOKEN).transfer(address(bridge), depositAmount);

            if (depositAmount == 0) {
                vm.expectRevert(invalidTotalInputValue.selector);
            } else {
                vm.expectRevert();
            }
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

    /**
    @notice Mocking of Curve LP Token balance.
    @notice Depositing Curve LP Tokens and their subsequent staking.  
    @notice Minting of CSB Tokens.
    @param depositAmount Number of Curve LP Tokens to stake.
    */
    function _deposit(uint depositAmount) internal {
        // deal(CURVE_LP_TOKEN, address(bridge), depositAmount);
        deal(CURVE_LP_TOKEN, rollupProcessor, depositAmount);

        // transfer CURVE LP Tokens from RollUpProcessor to the bridge
        IERC20(CURVE_LP_TOKEN).transfer(address(bridge), depositAmount);

        if (depositAmount == 0) {
            vm.expectRevert(invalidTotalInputValue.selector);
        }

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

    function _setUpInvalidPoolPidData(uint pid) internal {
        bridge.addInvalidPoolPid(pid);
        assertTrue(bridge.invalidPoolPids(pid));
    }
}