// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface ICurveRewards {
    // Transfer ownership of staked Convex Tokens from CrvRewards contract to the bridge
    function withdraw(uint256 amount, bool claim) external returns(bool);

    function balanceOf(address account) external view returns (uint256);

    // total supply of pool's convex tokens
    function totalSupply() external view returns (uint256);
}
