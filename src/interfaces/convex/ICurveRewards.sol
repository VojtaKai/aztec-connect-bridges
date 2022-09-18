// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface ICurveRewards {
    function balanceOf(address account) external view returns (uint256);
}
