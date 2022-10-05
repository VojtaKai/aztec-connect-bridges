// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {IConvexFinanceBooster} from "../../../interfaces/convex/IConvexFinanceBooster.sol";


contract ConvexStakingBridgeE2ETest is BridgeTestBase {
    address private CURVE_LP_TOKEN;
    address private CONVEX_TOKEN;
    address private constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private STAKER;
    address private GAUGE;
    address private STASH;
    address private CRV_REWARDS;

    // The reference to the stability pool bridge
    ConvexStakingBridge private bridge;

    mapping(uint => bool) public invalidPoolPids;

    // To store the id of the stability pool bridge after being added
    uint256 private id;

    event Balance(uint balance);
    event BridgeCallData(uint bridgeCallData);
    event Show(uint balance);

    function setUp() public {
        STAKER = IConvexFinanceBooster(BOOSTER).staker();
        _setUpInvalidPoolPids(48);

        // labels
        vm.label(address(ROLLUP_PROCESSOR), "Rollup Processor");
        vm.label(address(this), "E2E Test Contract");
        vm.label(msg.sender, "MSG sender");
        vm.label(BOOSTER, "Booster");
        vm.label(STAKER, "Staker Contract Address");
    }

    function testStakeWithdrawFlow(uint96 depositAmount) public {
        vm.assume(depositAmount > 1);

        uint poolLength = IConvexFinanceBooster(BOOSTER).poolLength();
        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }
            if (i != 112) {
                continue;
            }
            _setUpBridge(i);

            vm.startPrank(MULTI_SIG);
            // Add the new bridge and set its initial gasLimit
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);
            // Add Assets and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedAsset(address(bridge), 100000); // CSB Token
            ROLLUP_PROCESSOR.setSupportedAsset(CURVE_LP_TOKEN, 100000);
            vm.stopPrank();

            // Fetch the id of the stability pool bridge
            id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

            // get Aztec assets
            AztecTypes.AztecAsset memory curveLpAsset = getRealAztecAsset(CURVE_LP_TOKEN);
            AztecTypes.AztecAsset memory csbAsset = getRealAztecAsset(address(bridge));

            // Mint depositAmount of CURVE LP Tokens for RollUp Processor
            deal(CURVE_LP_TOKEN, address(ROLLUP_PROCESSOR), depositAmount);

            // Compute deposit calldata
            uint256 bridgeCallData = encodeBridgeCallData(
                id,
                curveLpAsset,
                emptyAsset,
                csbAsset,
                emptyAsset,
                0
            );
            
            (uint outputValueA, uint outputValueB, bool isAsync) = sendDefiRollup(bridgeCallData, depositAmount);
            assertEq(outputValueA, depositAmount); // number of staked tokens match deposited LP Tokens
            assertEq(outputValueB, 0, "Output value B is not 0"); // I am not really returning these two, so it actually returns a default..
            assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
            assertEq(bridge.balanceOf(address(ROLLUP_PROCESSOR)), depositAmount); // New CSB Tokens minted

            // withdrawal
            bridgeCallData = encodeBridgeCallData(
                id,
                csbAsset,
                emptyAsset,
                curveLpAsset,
                emptyAsset,
                0
            );

            (outputValueA, outputValueB, isAsync) = sendDefiRollup(bridgeCallData, depositAmount);
            assertEq(outputValueA, depositAmount); // number of staked tokens match deposited LP Tokens
            assertEq(outputValueB, 0, "Output value B is not 0"); // I am not really returning these two, so it actually returns a default..
            assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
            assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(address(ROLLUP_PROCESSOR)), depositAmount); // New CSB Tokens minted
            assertEq(bridge.balanceOf(address(ROLLUP_PROCESSOR)), 0);
        }
    }

    function _setUpBridge(uint poolPid) internal {
        bridge = new ConvexStakingBridge(address(ROLLUP_PROCESSOR));
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
