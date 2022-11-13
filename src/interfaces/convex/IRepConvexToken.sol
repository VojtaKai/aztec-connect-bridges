// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface IRepConvexToken {
    function mint(uint256 amount) external;

    function burn(uint256 amount) external;

    function approve(address spender, uint256 amount) external returns (bool);
}
