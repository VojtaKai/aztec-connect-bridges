// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface ICurveLpToken {
    function approve(address _spender, uint256 value) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}
