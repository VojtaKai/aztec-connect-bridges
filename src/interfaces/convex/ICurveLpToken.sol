// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface ICurveLpToken {
    function transferFrom(address from, address to, uint value) external returns (bool);
    
    function add_liquidity(uint amounts, uint minMintAmount, address receiver) external returns (uint); 

    function approve(address _spender, uint value) external returns(bool);

    function balanceOf(address account) external view returns (uint256);
}
