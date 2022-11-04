// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {IConvexBooster} from "../../../interfaces/convex/IConvexBooster.sol";


contract ConvexStakingBridgeE2ETest is BridgeTestBase {
    address private curveLpToken;
    address private convexLpToken;
    address private constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private staker;
    address private gauge;
    address private stash;
    address private crvRewards;
    address private constant BENEFICIARY = address(777);

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

    function setUp() public {
        staker = IConvexBooster(BOOSTER).staker();
        _setUpInvalidPoolPids(48);

        // labels
        vm.label(address(ROLLUP_PROCESSOR), "Rollup Processor");
        vm.label(address(this), "E2E Test Contract");
        vm.label(msg.sender, "MSG sender");
        vm.label(BOOSTER, "Booster");
        vm.label(staker, "Staker Contract Address");
        vm.label(BENEFICIARY, "Beneficiary");
    }

    /**
    @notice Tests staking and withdrawing by constructing bridgeCallData and passing it directly
    to RollupProcessor function that initializes the interaction with the bridge.
    @notice Compound test for all available Curve LP tokens.
    @dev Each interaction with a bridge gets a new nonce. Starts at 0 and increments by 32.
    @dev Virtual asset on output ignores virtual asset definition. It sets the virtual asset's ID to always be equal to interaction nonce.
    @dev Virtual asset on input takes on ID of the defined virtual asset.
    */
    function testStakeWithdrawFlow(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1);

        uint poolLength = IConvexBooster(BOOSTER).poolLength();
        uint j = 0;
        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }

            _setUpBridge(i);
            _setupSubsidy();

            vm.startPrank(MULTI_SIG);
            // Add the new bridge and set its initial gasLimit
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);
            // Add Assets and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedAsset(curveLpToken, 100000);
            vm.stopPrank();

            // Fetch the id of the convex staking bridge
            bridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

            // get Aztec assets
            AztecTypes.AztecAsset memory curveLpAsset = getRealAztecAsset(curveLpToken);
            // define virtual asset (when as input only - read NatSpec)
            AztecTypes.AztecAsset memory virtualAsset = AztecTypes.AztecAsset(INIT_ID + (STEP * j), address(0), AztecTypes.AztecAssetType.VIRTUAL);          

            // Mint depositAmount of CURVE LP tokens for RollUp Processor
            deal(curveLpToken, address(ROLLUP_PROCESSOR), _depositAmount);

            // Compute deposit calldata
            uint256 bridgeCallData = encodeBridgeCallData(
                bridgeId,
                curveLpAsset,
                emptyAsset,
                virtualAsset,
                emptyAsset,
                0
            );
            
            // move time forward to have claimable amount on beneficiary
            skip(1 days);
            (uint outputValueA, uint outputValueB, bool isAsync) = sendDefiRollup(bridgeCallData, _depositAmount);

            assertEq(outputValueA, _depositAmount); // number of staked tokens match deposited LP Tokens
            assertEq(outputValueB, 0, "Output value B is not 0");
            assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
            assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");

            // Compute withdrawal calldata
            bridgeCallData = encodeBridgeCallData(
                bridgeId,
                virtualAsset,
                emptyAsset,
                curveLpAsset,
                emptyAsset,
                0
            );

            skip(1 days); // move time forward to have claimable amount on beneficiary
            (outputValueA, outputValueB, isAsync) = sendDefiRollup(bridgeCallData, _depositAmount);
            rewind(2 days); // move time back to original for the next bridge run

            assertEq(outputValueA, _depositAmount); // number of withdrawn tokens match deposited LP Tokens
            assertEq(outputValueB, 0, "Output value B is not 0");
            assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
            assertEq(IERC20(curveLpToken).balanceOf(address(bridge)), 0); // Curve LP tokens owned by bridge
            assertEq(IERC20(curveLpToken).balanceOf(address(ROLLUP_PROCESSOR)), _depositAmount); // Curve LP tokens owned by RollUp

            assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");

            j++;
        }
    }

    function _setupSubsidy() internal {
         // Set ETH balance of bridge and BENEFICIARY to 0 for clarity (somebody sent ETH to that address on mainnet)
        vm.deal(address(bridge), 0);
        vm.deal(BENEFICIARY, 0);

        uint256[] memory criterias = new uint256[](2);
        uint32[] memory gasUsage = new uint32[](2);
        uint32[] memory minGasPerMinute = new uint32[](2);

        AztecTypes.AztecAsset memory curveLpToken = AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20);
        AztecTypes.AztecAsset memory virtualAsset = AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.VIRTUAL);

        // different criteria for deposit and withdrawal
        criterias[0] = bridge.computeCriteria(curveLpToken, emptyAsset, virtualAsset, emptyAsset, 0);
        criterias[1] = bridge.computeCriteria(virtualAsset, emptyAsset, curveLpToken, emptyAsset, 0);

        gasUsage[0] = 1000000;
        gasUsage[1] = 375000;

        minGasPerMinute[0] = 690;
        minGasPerMinute[1] = 260;

        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criterias[0], minGasPerMinute[0]);
        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criterias[1], minGasPerMinute[1]);

        SUBSIDY.registerBeneficiary(BENEFICIARY);

        // Set the rollupBeneficiary on BridgeTestBase so that it gets included in the proofData
        setRollupBeneficiary(BENEFICIARY);
    }

    function _setUpBridge(uint _poolPid) internal {
        bridge = new ConvexStakingBridge(address(ROLLUP_PROCESSOR));
        (curveLpToken, convexLpToken, gauge, crvRewards, stash,) = IConvexBooster(BOOSTER).poolInfo(_poolPid);
        
        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(curveLpToken, "Curve LP Token Contract");
        vm.label(convexLpToken, "Convex Token Contract");
        vm.label(crvRewards, "CrvRewards Contract");
        vm.label(stash, "Stash Contract");
        vm.label(gauge, "Gauge Contract");
    }

    function _setUpInvalidPoolPids(uint _pid) internal {
        invalidPoolPids[_pid] = true;
    }
}
