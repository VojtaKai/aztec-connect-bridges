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

    // The reference to the convex staking bridge
    ConvexStakingBridge private bridge;

    mapping(uint => bool) public invalidPoolPids;

    // Virtual Asset ID setting
    uint private constant INIT_ID = 0;
    uint private constant STEP = 64;

    // To store the id of the convex staking bridge after being added
    uint256 private bridgeId;

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

    /**
    @notice Tests staking and withdrawing by constructing bridgeCallData and passing it directly
    to RollupProcessor function that initializes the interaction with the bridge.
    @notice Compound test for all available Curve LP tokens.
    @dev Each interaction with a bridge gets a new nonce. Starts at 0 and increments by 32.
    @dev Virtual asset on output ignores virtual asset definition. It sets the virtual asset's ID to always be equal to interaction nonce.
    @dev Virtual asset on input takes on ID of the defined virtual asset.
    */
    function testStakeWithdrawFlow(uint96 depositAmount) public {
        vm.assume(depositAmount > 1);

        uint poolLength = IConvexDeposit(DEPOSIT).poolLength();
        uint j = 0;
        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }

            _setUpBridge(i);

            vm.startPrank(MULTI_SIG);
            // Add the new bridge and set its initial gasLimit
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);
            // Add Assets and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedAsset(CURVE_LP_TOKEN, 100000);
            vm.stopPrank();

            // Fetch the id of the convex staking bridge
            bridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

            // get Aztec assets
            AztecTypes.AztecAsset memory curveLpAsset = getRealAztecAsset(CURVE_LP_TOKEN);
            // define virtual asset (when as input only - read NatSpec)
            AztecTypes.AztecAsset memory virtualAsset = AztecTypes.AztecAsset(INIT_ID + (STEP * j), address(0), AztecTypes.AztecAssetType.VIRTUAL);          

            // Mint depositAmount of CURVE LP Tokens for RollUp Processor
            deal(CURVE_LP_TOKEN, address(ROLLUP_PROCESSOR), depositAmount);

            // Compute deposit calldata
            uint256 bridgeCallData = encodeBridgeCallData(
                bridgeId,
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

            // Compute withdrawal calldata
            bridgeCallData = encodeBridgeCallData(
                bridgeId,
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

            j++;
        }
    }

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
