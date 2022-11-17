// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ConvexStakingBridge} from "../../bridges/convex/ConvexStakingBridge.sol";
import {IConvexBooster} from "../../interfaces/convex/IConvexBooster.sol";

contract ConvexStakingBridgeDeployment is BaseDeployment {
    IConvexBooster public constant BOOSTER = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ConvexStakingBridge public bridge;

    function deployAndList() public {
        deploy();
        uint256 addressId = listBridge(address(bridge), 1000000);

        // list every single pool curve lp token
        _listAllAssets();

        emit log_named_uint("Convex staking bridge address id", addressId);
    }

    function deploy() public {
        emit log("Deploying Convex staking bridge");

        vm.broadcast();
        bridge = new ConvexStakingBridge(ROLLUP_PROCESSOR);
        emit log_named_address("Convex staking bridge deployed to", address(bridge));
    }

    function _listAllAssets() internal {
        uint256 poolLength = BOOSTER.poolLength();
        for (uint256 i = 0; i < poolLength; i++) {
            (address curveLpToken, , , , , ) = BOOSTER.poolInfo(i);
            listAsset(curveLpToken, 100000);
            listAsset(bridge.deployedClones(curveLpToken), 100000);
        }
    }
}
