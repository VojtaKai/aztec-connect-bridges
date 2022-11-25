// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @notice ERC20 token deployed for a specific pool to represent pool specific Convex LP token.
 * @dev RCT mirrors balance of Convex LP tokens. Balances of RCT and Convex LP token are before deposit and after withdrawal identical.
 * @dev RCT can only be minted for the owner (the bridge) by the owner and is fully owned by the bridge.
 * @dev RCT is an ERC20 upgradable token which allows initialization after the time it was deployed.
 * @dev RCT implementation is deployed on bridge deployment.
 * @dev RCT is a proxied contract and is called via a clone that is created for each loaded pool.
 * @dev Clone is tied to the RCT implementation by calling the `initialize` function.
 */
contract RepresentingConvexToken is ERC20Upgradeable, OwnableUpgradeable {
    function initialize(string memory _tokenName, string memory _tokenSymbol) public initializer {
        __ERC20_init(_tokenName, _tokenSymbol);
        _transferOwnership(_msgSender());
    }

    function mint(uint256 _amount) public onlyOwner {
        _mint(_msgSender(), _amount);
    }

    function burn(uint256 _amount) public onlyOwner {
        _burn(_msgSender(), _amount);
    }
}
