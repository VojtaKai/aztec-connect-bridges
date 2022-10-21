// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {IConvexDeposit} from "../../../interfaces/convex/IConvexDeposit.sol";


contract ConvexStakingBridgeE2ETest is BridgeTestBase {
    address private CURVE_LP_TOKEN;
    address private CONVEX_TOKEN;
    address private constant DEPOSIT = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private STAKER;
    address private GAUGE;
    address private STASH;
    address private CRV_REWARDS;

    // The reference to the stability pool bridge
    ConvexStakingBridge private bridge;

    mapping(uint => bool) public invalidPoolPids;

    // Interaction nonce
    uint private constant INTERACTION_NONCE = 32;
    uint private constant INTERACTION_NONCE_STEP = 64;

    event VirtualAssetId(uint id);

    // To store the id of the stability pool bridge after being added
    uint256 private id;

    event Balance(uint balance);
    event BridgeCallData(uint bridgeCallData);
    event Show(uint balance);
    event ShowInteractions(bool exists);

    function setUp() public {
        STAKER = IConvexDeposit(DEPOSIT).staker();
        _setUpInvalidPoolPids(48);

        // labels
        vm.label(address(ROLLUP_PROCESSOR), "Rollup Processor");
        vm.label(address(this), "E2E Test Contract");
        vm.label(msg.sender, "MSG sender");
        vm.label(DEPOSIT, "Deposit");
        vm.label(STAKER, "Staker Contract Address");
    }

    // Description of behavior of virtualAssetId and transaction nonce
    // Even though virtual asset is specified, no matter the id value, the first action on a bridge (which is in this case deposit because the virtual asset is on the output)
    // sets construct id to 0 and transaction nonce to 0 as well.
    // Second action sets virtual asset id to 32 and nonce to 32 regardless what is defined for the virtual asset (a few steps above).
    // Third action, for some misterious reason, uses for the virtual assets the defined ID (a few steps above). Nonce increments again by 32 to 64.
    // Fourth action, when the virtual asset is on output, the defined ID value is ignored again and is set to match the value of the next nonce -> id: 96, nonce: 96
    // Fifth action, when the virtual asset is on the input, the defined ID value is used again. Transaction nonce is again incremented by 32 to 128.
    // Suspicion: When virtual asset is on the output, it sets virtual asset id to match transaction nonce
    // Virtual asset on the input uses the defined values
    
    // Maybe I wont need to tweek it and only set interaction nonce to 0 for withdrawal -> if not, then first action for virtual asset always id = 0, nonce = 0, second always id = 32, nonce =32

    function testStakeWithdrawFlow(uint96 depositAmount) public {
        vm.assume(depositAmount > 1);

        uint poolLength = IConvexDeposit(DEPOSIT).poolLength();
        uint j = 0;
        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }
            // if (i != 112) {
            if (i != 1 && i != 100 && i != 112) {
                continue;
            }
            _setUpBridge(i);

            vm.startPrank(MULTI_SIG);
            // Add the new bridge and set its initial gasLimit
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);
            // Add Assets and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedAsset(CURVE_LP_TOKEN, 100000);
            vm.stopPrank();

            // Fetch the id of the stability pool bridge
            id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

            // get Aztec assets
            AztecTypes.AztecAsset memory curveLpAsset = getRealAztecAsset(CURVE_LP_TOKEN);
            // AztecTypes.AztecAsset memory virtualAsset = AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL);
            // AztecTypes.AztecAsset memory virtualAsset = _virtualAssetBuilder(j);
            // THIS DIDNT WORK -- START --
            AztecTypes.AztecAsset memory virtualAsset = AztecTypes.AztecAsset(INTERACTION_NONCE + (INTERACTION_NONCE_STEP * j), address(0), AztecTypes.AztecAssetType.VIRTUAL);
            // THIS DIDNT WORK -- END --
            // AztecTypes.AztecAsset memory virtualAsset;
            // if (i == 1) {
            //     virtualAsset = AztecTypes.AztecAsset(32, address(0), AztecTypes.AztecAssetType.VIRTUAL);
            //     emit VirtualAssetId(virtualAsset.id);
            // } else if (i == 112) {
            //     virtualAsset = AztecTypes.AztecAsset(96, address(0), AztecTypes.AztecAssetType.VIRTUAL);
            //     emit VirtualAssetId(virtualAsset.id);
            // }
            // AztecTypes.AztecAsset memory virtualAssetWithdraw = AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL);
            
            // TWEEK VIRTUAL ASSET ID
            _tweekVirtualAssetId(j, curveLpAsset, virtualAsset, depositAmount);
            

            // Mint depositAmount of CURVE LP Tokens for RollUp Processor
            deal(CURVE_LP_TOKEN, address(ROLLUP_PROCESSOR), depositAmount);

            // Compute deposit calldata
            uint256 bridgeCallData = encodeBridgeCallData(
                id,
                curveLpAsset,
                emptyAsset,
                virtualAsset,
                emptyAsset,
                0
            );
            
            (uint outputValueA, uint outputValueB, bool isAsync) = sendDefiRollup(bridgeCallData, depositAmount);
            assertEq(outputValueA, depositAmount); // number of staked tokens match deposited LP Tokens
            assertEq(outputValueB, 0, "Output value B is not 0");
            assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");

            // withdrawal
            bridgeCallData = encodeBridgeCallData(
                id,
                virtualAsset,
                emptyAsset,
                curveLpAsset,
                emptyAsset,
                0
            );

            (outputValueA, outputValueB, isAsync) = sendDefiRollup(bridgeCallData, depositAmount);
            assertEq(outputValueA, depositAmount); // number of withdrawn tokens match deposited LP Tokens
            assertEq(outputValueB, 0, "Output value B is not 0");
            assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
            assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(address(bridge)), 0); // Curve LP Tokens owned by bridge
            assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(address(ROLLUP_PROCESSOR)), depositAmount); // Curve LP Tokens owned by RollUp

            j += 1;
        }
    }

    function _tweekVirtualAssetId(uint j,  AztecTypes.AztecAsset memory curveLpAsset,  AztecTypes.AztecAsset memory virtualAsset, uint depositAmount) internal {
         if (j == 0) {
            deal(CURVE_LP_TOKEN, address(ROLLUP_PROCESSOR), depositAmount);

            uint256 bridgeCallDataUnused = encodeBridgeCallData(
                id,
                curveLpAsset,
                emptyAsset,
                virtualAsset,
                emptyAsset,
                0
            );
            sendDefiRollup(bridgeCallDataUnused, depositAmount);
        }
    }

    // function _virtualAssetBuilder(uint j) internal pure returns(AztecTypes.AztecAsset memory virtualAsset) {
    //     virtualAsset = AztecTypes.AztecAsset(INTERACTION_NONCE + (INTERACTION_NONCE_STEP * j), address(0), AztecTypes.AztecAssetType.VIRTUAL);
    // }

    function _setUpBridge(uint poolPid) internal {
        bridge = new ConvexStakingBridge(address(ROLLUP_PROCESSOR));
        (CURVE_LP_TOKEN, CONVEX_TOKEN, GAUGE, CRV_REWARDS, STASH,) = IConvexDeposit(DEPOSIT).poolInfo(poolPid);
        
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
