// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {IConvexDeposit} from "../../../interfaces/convex/IConvexDeposit.sol";

contract ConvexStakingBridgeTest is BridgeTestBase {
    address private CURVE_LP_TOKEN;
    address private CONVEX_TOKEN;
    address private constant DEPOSIT = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private STAKER;
    address private GAUGE;
    address private STASH;
    address private CRV_REWARDS;
    address private MINTER;
    address private constant CRV_TOKEN = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address private constant CVX_TOKEN = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    address private rollupProcessor;

    uint private constant INTERACTION_NONCE = 2 ** 30;

    ConvexStakingBridge private bridge;

    uint[] public invalidPids = [48]; // define invalid pids
    mapping(uint => bool) public invalidPoolPids;

    uint[] private rewardsGreater;

    error InvalidAssetType();
    error UnknownVirtualAsset();
    error IncorrectInteractionValue(uint stakedValue, uint valueToWithdraw);

    function setUp() public {
        rollupProcessor = address(this);
        STAKER = IConvexDeposit(DEPOSIT).staker();
        MINTER = IConvexDeposit(DEPOSIT).minter();

        _setUpInvalidPoolPids();

        // labels
        vm.label(address(this), "Test Contract");
        vm.label(address(msg.sender), "Test Contract Msg Sender");
        vm.label(DEPOSIT, "Deposit");
        vm.label(STAKER, "Staker Contract Address");
        vm.label(MINTER, "Minter");
        vm.label(CRV_TOKEN, "Reward boosted CRV Token");
        vm.label(CVX_TOKEN, "Reward CVX Token");
    }


    function testInvalidInput() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        address INVALID_CURVE_LP_TOKEN = address(123);
        uint depositAmount = 10;
        
        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(INVALID_CURVE_LP_TOKEN, "Invalid Curve LP Token Address");

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(1, INVALID_CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            depositAmount,
            INTERACTION_NONCE,
            0,
            address(11)
        );
    }

    function testInvalidInputEth() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint depositAmount = 10e18;

        vm.label(address(bridge), "Bridge");

        vm.expectRevert(InvalidAssetType.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert{value: depositAmount}(
            AztecTypes.AztecAsset(1, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            depositAmount,
            INTERACTION_NONCE,
            0,
            address(11)
        );
    }

    function testInvalidOutput() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint withdrawalAmount = 10;
        address invalidLpToken = address(123);
        uint lastPoolPid = IConvexDeposit(DEPOSIT).poolLength() - 1;
        
        (CURVE_LP_TOKEN,,,,,) = IConvexDeposit(DEPOSIT).poolInfo(lastPoolPid);


        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");

        // make deposit and create an interaction 
        _deposit(withdrawalAmount);
        
        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, invalidLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            withdrawalAmount,
            INTERACTION_NONCE,
            0,
            address(11)
        );
    }

    function testInvalidOutput2() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint withdrawalAmount = 10;
        address invalidLpToken = address(123);
        uint lastPoolPid = IConvexDeposit(DEPOSIT).poolLength() - 1;
        uint anotherPoolPid = lastPoolPid - 1;
        // valid curve lp token of another pool
        address INCORRECT_CURVE_LP_TOKEN;
        
        (CURVE_LP_TOKEN,,,,,) = IConvexDeposit(DEPOSIT).poolInfo(lastPoolPid);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");

        // make deposit and note down virtual asset.id (interaction nonce)
        // make deposit for a pool at index `lastPoolPid`
        _deposit(withdrawalAmount);

        // withdraw using correct interaction but incorrect pool
        (INCORRECT_CURVE_LP_TOKEN,,,,,) = IConvexDeposit(DEPOSIT).poolInfo(anotherPoolPid);
        vm.label(INCORRECT_CURVE_LP_TOKEN, "Incorrect Curve LP Token Contract");
        
        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, INCORRECT_CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            withdrawalAmount,
            INTERACTION_NONCE,
            0,
            address(11)
        );
    }

    function testInvalidOutputEth() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint withdrawalAmount = 10;
        address invalidLpToken = address(123);
        uint lastPoolPid = IConvexDeposit(DEPOSIT).poolLength() - 1;
        
        (CURVE_LP_TOKEN,,,,,) = IConvexDeposit(DEPOSIT).poolInfo(lastPoolPid);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");

        // make deposit and note down virtual asset.id (interaction nonce)
        _deposit(withdrawalAmount);
        
        vm.expectRevert(InvalidAssetType.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            withdrawalAmount,
            INTERACTION_NONCE,
            0,
            address(11)
        );
    }

    function testNonExistingInteraction() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint withdrawalAmount = 10;
        address invalidLpToken = address(123);
        uint lastPoolPid = IConvexDeposit(DEPOSIT).poolLength() - 1;

        uint nonExistingInteractionNonce = INTERACTION_NONCE - 1;
        
        (CURVE_LP_TOKEN,,,,,) = IConvexDeposit(DEPOSIT).poolInfo(lastPoolPid);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");

        // make deposit and note down virtual asset.id (interaction nonce)
        _deposit(withdrawalAmount);
        
        vm.expectRevert(UnknownVirtualAsset.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(nonExistingInteractionNonce, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            withdrawalAmount,
            nonExistingInteractionNonce,
            0,
            address(11)
        );
    }

    function testInteractionPoolMismatch() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        uint withdrawalAmount = 10;
        address invalidLpToken = address(123);
        uint lastPoolPid = IConvexDeposit(DEPOSIT).poolLength() - 1;
        uint changedPoolPid = lastPoolPid - 1;
        
        (CURVE_LP_TOKEN,,,,,) = IConvexDeposit(DEPOSIT).poolInfo(lastPoolPid);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");

        // make deposit and note down virtual asset.id (interaction nonce)
        // make deposit for a pool at index `lastPoolPid`
        _deposit(withdrawalAmount);

        // order of pools or contracts within them might have changed
        (CURVE_LP_TOKEN,,,,,) = IConvexDeposit(DEPOSIT).poolInfo(changedPoolPid);
        vm.label(CURVE_LP_TOKEN, "Changed Curve LP Token Contract");

        // START - represents valid deposit in another pool
        deal(CURVE_LP_TOKEN, rollupProcessor, withdrawalAmount);
        IERC20(CURVE_LP_TOKEN).transfer(address(bridge), withdrawalAmount);

        uint outputValueA;
        uint outputValueB;
        bool isAsync;

        (outputValueA, outputValueB, isAsync) = bridge.convert(
            AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(INTERACTION_NONCE - 10, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            withdrawalAmount,
            INTERACTION_NONCE - 10,
            0,
            address(11)
        );
        // END - represents valid deposit in another pool

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        (outputValueA, outputValueB, isAsync) = bridge.convert(
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            withdrawalAmount,
            INTERACTION_NONCE,
            0,
            address(11)
        );
    }

    function testConvertInvalidCaller() public {
        bridge = new ConvexStakingBridge(rollupProcessor);
        address invalidCaller = address(123);
        uint depositAmount = 10;
        uint lastPoolPid = IConvexDeposit(DEPOSIT).poolLength() - 1;
        (CURVE_LP_TOKEN,,,,,) = IConvexDeposit(DEPOSIT).poolInfo(lastPoolPid);
        
        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");
        
        vm.prank(invalidCaller);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            depositAmount,
            INTERACTION_NONCE,
            0,
            address(11)
        );
    }

    function testStakeLpTokens(uint96 depositAmount) public {
        vm.assume(depositAmount > 1);

        uint poolLength = IConvexDeposit(DEPOSIT).poolLength();

        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }

            _setUpBridge(i);

            _deposit(depositAmount);
        }
    }

    function testZeroTotalInputValue() public {
        uint depositAmount = 0;
        uint poolLength = IConvexDeposit(DEPOSIT).poolLength();

        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }

            _setUpBridge(i);

            // Mock initial balance of CURVE LP Token for Rollup Processor
            deal(CURVE_LP_TOKEN, rollupProcessor, depositAmount);
            // Transfer CURVE LP Tokens from RollUpProcessor to the bridge
            IERC20(CURVE_LP_TOKEN).transfer(address(bridge), depositAmount);

            vm.expectRevert(ErrorLib.InvalidInputAmount.selector);
            (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
                AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
                emptyAsset,
                AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
                emptyAsset,
                depositAmount,
                INTERACTION_NONCE,
                0,
                address(11)
            );
        }
    }

    function testUnidenticalStakedWithdrawnAmount() public {
        uint64 withdrawalAmount = 10;
        // deposit amount is greater than withdrawal amount -> can't close the interaction
        uint depositAmount = withdrawalAmount + 1;
        // deposit LpTokens first so the totalSupply of minted tokens match (no other workaround)
        uint poolLength = IConvexDeposit(DEPOSIT).poolLength();

        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }

            _setUpBridge(i);
                
            // set up interaction
            _deposit(depositAmount);
            
            vm.expectRevert(abi.encodeWithSelector(IncorrectInteractionValue.selector, depositAmount, withdrawalAmount));
            (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
                AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
                emptyAsset,
                AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
                emptyAsset,
                withdrawalAmount,
                INTERACTION_NONCE,
                0,
                address(11)
            );
        }
    }

    function testWithdrawLpTokens(uint64 withdrawalAmount) public {
        vm.assume(withdrawalAmount > 1);
        uint poolLength = IConvexDeposit(DEPOSIT).poolLength();

        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }

            _setUpBridge(i);
                
            // set up interaction
            _deposit(withdrawalAmount);

            (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
                AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
                emptyAsset,
                AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
                emptyAsset,
                withdrawalAmount,
                INTERACTION_NONCE,
                0,
                address(11)
            );
            assertEq(outputValueA, withdrawalAmount);
            assertEq(outputValueB, 0, "Output value B is not 0"); // I am not really returning these two, so it actually returns a default..
            assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
            assertEq(IERC20(CRV_TOKEN).balanceOf(address(bridge)), 0, "CRV Rewards must have been claimed");
            assertEq(IERC20(CVX_TOKEN).balanceOf(address(bridge)), 0, "CVX Rewards must have been claimed");
            (,,bool interactionNonceExists) = bridge.interactions(INTERACTION_NONCE);
            assertFalse(interactionNonceExists, "Interaction Nonce still exists.");
            assertEq(IERC20(MINTER).balanceOf(address(bridge)), 0);
            assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(address(bridge)), withdrawalAmount);
            IERC20(CURVE_LP_TOKEN).transferFrom(address(bridge), rollupProcessor, withdrawalAmount);
            assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(rollupProcessor), withdrawalAmount);
        }
    }

    function testWithdrawLpTokensWithRewards(uint64 withdrawalAmount) public {
        vm.assume(withdrawalAmount > 401220753522760);
        // deposit LpTokens first so the totalSupply of minted tokens match (no other workaround)
        uint poolLength = IConvexDeposit(DEPOSIT).poolLength();

        delete rewardsGreater; // clear array before every run

        for (uint i=0; i < poolLength; i++) {
            if (invalidPoolPids[i]) {
                continue;
            }

            _setUpBridge(i);
                
            // set up an interaction
            _deposit(withdrawalAmount);

            uint rewardsCRVBefore = IERC20(CRV_TOKEN).balanceOf(address(bridge));
            uint rewardsCVXBefore = IERC20(CVX_TOKEN).balanceOf(address(bridge));

            skip(8 days);
            (uint outputValueA, uint outputValueB, bool isAsync) = bridge.convert(
                AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
                emptyAsset,
                AztecTypes.AztecAsset(1, CURVE_LP_TOKEN, AztecTypes.AztecAssetType.ERC20),
                emptyAsset,
                withdrawalAmount,
                INTERACTION_NONCE,
                1,
                address(11)
            );
            rewind(8 days);

            uint rewardsCRVAfter = IERC20(CRV_TOKEN).balanceOf(address(bridge));
            uint rewardsCVXAfter = IERC20(CVX_TOKEN).balanceOf(address(bridge));

            if (rewardsCRVAfter > rewardsCRVBefore && rewardsCVXAfter > rewardsCVXBefore) {
                rewardsGreater.push(i);
            }

            assertEq(outputValueA, withdrawalAmount);
            assertEq(outputValueB, 0, "Output value B is not 0"); // I am not really returning these two, so it actually returns a default..
            assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
            (,,bool interactionNonceExists) = bridge.interactions(INTERACTION_NONCE);
            assertFalse(interactionNonceExists, "Interaction Nonce still exists.");

            assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(address(bridge)), withdrawalAmount);
            IERC20(CURVE_LP_TOKEN).transferFrom(address(bridge), rollupProcessor, withdrawalAmount);
            assertEq(IERC20(CURVE_LP_TOKEN).balanceOf(rollupProcessor), withdrawalAmount);
        }
        assertGt(rewardsGreater.length, 0);
        delete rewardsGreater; // clear array after every run
    }

    

    /**
    @notice Mocking of Curve LP Token balance.
    @notice Depositing Curve LP Tokens.
    @notice Sets up an interaction.
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
            AztecTypes.AztecAsset(INTERACTION_NONCE, address(0), AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            depositAmount,
            INTERACTION_NONCE,
            0,
            address(11)
        );

        assertEq(outputValueA, depositAmount);
        assertEq(outputValueB, 0, "Output value B is not 0.");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
    }

    function _setUpBridge(uint poolPid) internal {
        bridge = new ConvexStakingBridge(rollupProcessor);
        (CURVE_LP_TOKEN, CONVEX_TOKEN, GAUGE, CRV_REWARDS, STASH,) = IConvexDeposit(DEPOSIT).poolInfo(poolPid);
        
        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(CURVE_LP_TOKEN, "Curve LP Token Contract");
        vm.label(CONVEX_TOKEN, "Convex Token Contract");
        vm.label(CRV_REWARDS, "CrvRewards Contract");
        vm.label(STASH, "Stash Contract");
        vm.label(GAUGE, "Gauge Contract");
    }

    function _setUpInvalidPoolPids() internal {
        for (uint pid = 0; pid < invalidPids.length; pid++) {
            invalidPoolPids[invalidPids[pid]] = true;
        }
    }
}
