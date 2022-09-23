// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {ICurveLpToken} from "../../../interfaces/convex/ICurveLpToken.sol";

contract ConvexStakingBridgeTest is BridgeTestBase {
    // ICurveLpToken private constant CURVE_LP_TOKEN = ICurveLpToken(0xe7A3b38c39F97E977723bd1239C3470702568e7B);
    address private constant CURVE_LP_TOKEN = 0xe7A3b38c39F97E977723bd1239C3470702568e7B;
    address private constant CONVEX_TOKEN = 0xbE665430e4C439aF6C92ED861939E60A963C6d0c;
    address private constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private constant STAKER = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;
    address private constant GAUGE = 0x9f57569EaA61d427dEEebac8D9546A745160391C;
    address private constant STASH = 0x8c8A5557F5ca466a93419042cdb407686545b1a8;
    address private constant CRV_REWARDS = 0x14F02f3b47B407A7a0cdb9292AA077Ce9E124803;

    address private rollupProcessor;

    ConvexStakingBridge private bridge;

    error invalidTotalInputValue();

    function setUp() public {
        rollupProcessor = address(this);
        bridge = new ConvexStakingBridge(rollupProcessor);

        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");
        vm.label(CONVEX_TOKEN, "Convex Token Contract");
        vm.label(STAKER, "Staker Contract Address");
        vm.label(address(this), "Test Contract");
        vm.label(address(bridge), "Bridge");
        vm.label(address(msg.sender), "Test Contract Msg Sender");
        vm.label(BOOSTER, "Booster");
        vm.label(CRV_REWARDS, "CrvRewards Contract");
        vm.label(STASH, "Stash Contract");
        vm.label(GAUGE, "Gauge Contract");
    }

    function testBridge() public {
        assertTrue(true);
    }

    function testStakeLpTokens(uint96 depositAmount) public {
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: CURVE_LP_TOKEN,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 100,
            erc20Address: address(bridge),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(CURVE_LP_TOKEN, address(bridge), depositAmount);

        if (depositAmount == 0) {
            vm.expectRevert(invalidTotalInputValue.selector);
        }
   
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
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
        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);
        assertEq(bridge.balanceOf(address(bridge)), 0);
        assertEq(bridge.balanceOf(rollupProcessor), outputValueA);
    }

    function testWithdrawLpTokens(uint64 withdrawalAmount) public {
        // deposit LpTokens first so the totalSupply of minted tokens match (no other workaround)
        _deposit(withdrawalAmount);

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 100,
            erc20Address: address(bridge),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: CURVE_LP_TOKEN,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // deal(inputAssetA.erc20Address, address(bridge), withdrawalAmount);
        deal(CONVEX_TOKEN, address(bridge), withdrawalAmount);

        // transfer CSB Token from RollUpProcessor to the bridge
        IERC20(inputAssetA.erc20Address).transfer(address(bridge), withdrawalAmount);
        
        if (withdrawalAmount == 0) {
            vm.expectRevert(invalidTotalInputValue.selector);
        }

        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
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
        assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(rollupProcessor), 0);
    }

    function _deposit(uint depositAmount) internal {
        // 1. mock number of Curve LP Tokens to stake
        deal(CURVE_LP_TOKEN, address(bridge), depositAmount);

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: CURVE_LP_TOKEN,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 100,
            erc20Address: address(bridge),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        if (depositAmount == 0) {
            vm.expectRevert(invalidTotalInputValue.selector);
        }
   
        // 2. stake tokens
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
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

        // 3. Check the total supply of SPB token is equal to the amount of LUSD deposited
        assertEq(bridge.totalSupply(), depositAmount);

        // 4. Transfer SPB back to RollupProcessor
        IERC20(address(bridge)).transferFrom(address(bridge), rollupProcessor, outputValueA);

        // 5. Check the SPB balance of rollupProcessor is equal to the amount of LUSD deposited
        assertEq(outputValueA, depositAmount);
        assertEq(bridge.balanceOf(rollupProcessor), depositAmount);
    }
}