// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ConvexStakingBridge} from "../../bridges/convex/ConvexStakingBridge.sol";
import {IConvexBooster} from "../../interfaces/convex/IConvexBooster.sol";

contract ConvexStakingBridgeDeployment is BaseDeployment {
    IConvexBooster private constant BOOSTER = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ConvexStakingBridge private bridge;

    uint256[] private poolIds = [69]; // e.g. [10, 110] for pools 10 and 110
    address[] private curveLpTokens; // e.g. [0xe7A3b38c39F97E977723bd1239C3470702568e7B] for pool 112

    event ShowBridgeAddress(address bridge);

    function deployAndList() public {
        deploy();
        uint256 addressId = listBridge(address(bridge), 1000000);

        // list all pool Curve LP tokens
        _listAllAssets();

        emit log_named_uint("Convex staking bridge address id", addressId);
    }

    function deploy() public {
        emit log("Deploying Convex staking bridge");

        vm.broadcast();
        bridge = new ConvexStakingBridge(ROLLUP_PROCESSOR);
        emit log_named_address("Convex staking bridge deployed to", address(bridge));
    }

    function loadPools() public {
        // Insert pool ids in the poolIds variable at the top of the contract to have the pools loaded and their RCT tokens listed
        bridge = new ConvexStakingBridge(ROLLUP_PROCESSOR);
        emit ShowBridgeAddress(address(bridge));

        for (uint256 i = 0; i < poolIds.length; i++) {
            bridge.loadPool(poolIds[i]);
            _listToken(poolIds[i]);
        }
    }


    function listTokensByPoolId() public {
        // Insert pool ids in the poolIds variable at the top of the contract to have the RCT tokens listed
        bridge = new ConvexStakingBridge(ROLLUP_PROCESSOR);

        for (uint256 i = 0; i < poolIds.length; i++) {
            (address curveLpToken, , , , , ) = BOOSTER.poolInfo(poolIds[i]);
            address rctToken = bridge.deployedClones(curveLpToken);
            listAsset(rctToken, 100000);
        }
    }

    function listTokensByCurveLpToken() public {
        // insert Curve LP tokens in the curveLpTokens variable at the top of the contract to have the matching RCT tokens listed
        bridge = new ConvexStakingBridge(ROLLUP_PROCESSOR);

        for (uint256 i = 0; i < curveLpTokens.length; i++) {
            address rctToken = bridge.deployedClones(curveLpTokens[i]);
            listAsset(rctToken, 100000);
        }
    }

    function _listAllAssets() internal {
        uint256 poolLength = BOOSTER.poolLength();
        for (uint256 pid = 0; pid < poolLength; pid++) {
            (address curveLpToken, , , , , ) = BOOSTER.poolInfo(pid);
            listAsset(curveLpToken, 100000);
        }
    }

    function _listToken(uint256 _poolId) internal {
        (address curveLpToken, , , , , ) = BOOSTER.poolInfo(_poolId);
        address rctToken = bridge.deployedClones(curveLpToken);
        listAsset(rctToken, 100000);
    }
}
