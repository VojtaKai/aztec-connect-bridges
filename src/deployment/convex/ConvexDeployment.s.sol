// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ConvexStakingBridge} from "../../bridges/convex/ConvexStakingBridge.sol";
import {IConvexBooster} from "../../interfaces/convex/IConvexBooster.sol";
import {IConvexStakingBridge} from "../../interfaces/convex/IConvexStakingBridge.sol";

contract ConvexStakingBridgeDeployment is BaseDeployment {
    IConvexBooster private constant BOOSTER = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    uint256[] private poolIds = [10, 110]; // e.g. [10, 110] for pools 10 and 110
    address[] private curveLpTokens = [0xe7A3b38c39F97E977723bd1239C3470702568e7B]; // e.g. [0xe7A3b38c39F97E977723bd1239C3470702568e7B] for pool 112

    function deployAndList() public {
        address bridge = deploy();
        uint256 addressId = listBridge(bridge, 1000000);

        // list all pool Curve LP tokens
        _listAllAssets();

        emit log_named_uint("Convex staking bridge address id", addressId);
    }

    function deploy() public returns (address) {
        emit log("Deploying Convex staking bridge");

        vm.broadcast();
        ConvexStakingBridge bridge = new ConvexStakingBridge(ROLLUP_PROCESSOR);
        emit log_named_address("Convex staking bridge deployed to", address(bridge));

        return address(bridge);
    }

    function loadPoolsAndListTokens() public {
        address bridgeAddr = 0x81F3A97eAF582AdE8E32a4F1ED85A63AA84e7296; // Adjust bridge address
        // Note: Insert pool ids in the poolIds variable at the top of the contract to have the pools loaded and their RCT tokens listed
        for (uint256 i = 0; i < poolIds.length; i++) {
            IConvexStakingBridge(bridgeAddr).loadPool(poolIds[i]);
            _listToken(bridgeAddr, poolIds[i]);
        }
    }

    /**
     * @notice List RCT tokens by specifying pool ids
     */
    function listTokensByPoolId() public {
        // Warning: Pools have to be already loaded for the listing to be successful
        address bridgeAddr = 0x0000000000000000000000000000000000000000; // Adjust bridge address
        // Note: Insert pool ids in the poolIds variable at the top of the contract to have the RCT tokens listed
        for (uint256 i = 0; i < poolIds.length; i++) {
            _listToken(bridgeAddr, poolIds[i]);
        }
    }

    /**
     * @notice List RCT tokens by specifying Curve LP tokens
     */
    function listTokensByCurveLpToken() public {
        // Warning: Pools have to be already loaded for the listing to be successful
        // Note: Insert Curve LP token address in the curveLpTokens variable at the top of the contract to have the corresponding RCT tokens listed
        address bridgeAddr = 0x0000000000000000000000000000000000000000; // Adjust bridge address

        for (uint256 i = 0; i < curveLpTokens.length; i++) {
            uint256 poolId = _findPoolIdByCurveLpToken(curveLpTokens[i]);
            _listToken(bridgeAddr, poolId);
        }
    }

    function _listAllAssets() internal {
        uint256 poolLength = BOOSTER.poolLength();
        for (uint256 pid = 0; pid < poolLength; pid++) {
            (address curveLpToken,,,,,) = BOOSTER.poolInfo(pid);
            listAsset(curveLpToken, 100000);
        }
    }

    function _listToken(address _bridgeAddr, uint256 _poolId) internal {
        (address curveLpToken,,,,,) = BOOSTER.poolInfo(_poolId);
        address rctToken = IConvexStakingBridge(_bridgeAddr).deployedClones(curveLpToken);
        listAsset(rctToken, 100000);
    }

    function _findPoolIdByCurveLpToken(address _curveLpToken) internal view returns (uint256 poolId) {
        uint256 poolLength = BOOSTER.poolLength();

        for (uint256 pid = 0; pid < poolLength; pid++) {
            (address curveLpToken,,,,,) = BOOSTER.poolInfo(pid);
            if (_curveLpToken == curveLpToken) {
                poolId = pid;
                return poolId;
            }
        }
    }
}
