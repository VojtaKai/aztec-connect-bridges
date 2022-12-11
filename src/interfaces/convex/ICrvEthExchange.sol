// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface ICrvEthExchange {
    function exchange_underlying(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external returns (uint256);

    function get_dy(uint256 i, uint256 j, uint256 dx) external returns (uint256);
}
