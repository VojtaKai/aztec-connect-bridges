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
    address private constant STAKER = 0x989AEb4d175e16225E39E87d0D97A3360524AD80;

    address private rollupProcessor;

    ConvexStakingBridge private bridge;

    error invalidTotalInputValue();

    function setUp() public {
        rollupProcessor = address(this);
        bridge = new ConvexStakingBridge(rollupProcessor);

        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract Address");
        vm.label(CONVEX_TOKEN, "Convex Token Contract Address");
        vm.label(STAKER, "Staker Contract Address");
        vm.label(address(this), "Test Contract Address");
        vm.label(address(bridge), "Bridge Contract Address");
        vm.label(address(msg.sender), "Msg Sender address");
        vm.label(address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31), "Booster");
        vm.label(address(0x14F02f3b47B407A7a0cdb9292AA077Ce9E124803), "CrvRewards Contract Address");
        vm.label(address(0x8c8A5557F5ca466a93419042cdb407686545b1a8), "Stash Contract Address");
        vm.label(address(0x9f57569EaA61d427dEEebac8D9546A745160391C), "Gauge Contract Address");
    }

    function testBridge() public {
        assertTrue(true);
    }

    function testStakingLpTokens(uint96 depositAmount) public {
        // if (depositAmount == 0) {
        //     return;
        // }

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: CURVE_LP_TOKEN,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 100,
            erc20Address: CONVEX_TOKEN,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // deal(CURVE_LP_TOKEN, address(this), 10);      
        deal(CURVE_LP_TOKEN, address(bridge), depositAmount);   // misto 10 udelat fuzz s uint96 _depositAmount   

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

        // assertTrue(stakingSuccessful);

        // assertEq(stakingSuccessful, 1);

        assertEq(outputValueA, depositAmount);
        assertEq(outputValueB, 0, "Output value B is not 0.");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
    }

    // function testStakingLpTokensZero() public {
    //     AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
    //         id: 1,
    //         erc20Address: CURVE_LP_TOKEN,
    //         assetType: AztecTypes.AztecAssetType.ERC20
    //     });

    //     AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
    //         id: 100,
    //         erc20Address: CONVEX_TOKEN,
    //         assetType: AztecTypes.AztecAssetType.ERC20
    //     });

    //     // deal(CURVE_LP_TOKEN, address(this), 10);      
    //     deal(CURVE_LP_TOKEN, address(bridge), 0);   // misto 10 udelat fuzz s uint96 _depositAmount   

    //     vm.expectRevert(invalidTotalInputValue.selector);
    //     (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
    //         inputAssetA,
    //         emptyAsset,
    //         outputAssetA,
    //         emptyAsset,
    //         0,
    //         0,
    //         0,
    //         address(11)
    //     );

    //     // assertTrue(stakingSuccessful);

    //     // assertEq(stakingSuccessful, 1);

    //     assertEq(outputValueA, 0);
    //     assertEq(outputValueB, 0, "Output value B is not 0.");
    //     assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
    // }

    function testWithdrawingLpTokens() public {
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: CONVEX_TOKEN,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 100,
            erc20Address: CURVE_LP_TOKEN,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // deal(address(CURVE_LP_TOKEN), address(this), 10);

        bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            2,
            12345,
            0,
            address(11)
        );
    }
}