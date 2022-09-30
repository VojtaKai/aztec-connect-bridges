// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {StabilityPoolBridge} from "../../../bridges/liquity/StabilityPoolBridge.sol";

contract ConvexStakingBridgeE2ETest is BridgeTestBase {
    IERC20 public constant LUSD = IERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);

    // The reference to the stability pool bridge
    StabilityPoolBridge private bridge;
    ConvexStakingBridge private bridge2;
    address private stabilityPool;

    // To store the id of the stability pool bridge after being added
    uint256 private id;

    function setUp() public {}


    function testTruth1() public {
        bridge = new StabilityPoolBridge(address(ROLLUP_PROCESSOR), address(0));
        assertTrue(1 > 0);
    }

    function testTruth2() public {
        bridge2 = new ConvexStakingBridge(address(ROLLUP_PROCESSOR));
        assertTrue(1 > 0);
    }
}
