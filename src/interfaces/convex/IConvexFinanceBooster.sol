// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface IConvexFinanceBooster {
    // Deposit lp tokens and stake
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);

    // Deposit all lp tokens and stake
    function depositAll(uint256 _pid, bool _stake) external returns(bool);

    // Withdraw lp tokens
    function withdraw(uint256 _pid, uint256 _amount) external returns(bool);

    // Withdraw all lp tokens
    function withdrawAll(uint256 _pid) external returns(bool);

    // Number of Curve pools available
    function poolLength() external view returns (uint256);

    // Pool information 
    function poolInfo(uint256) external view returns(address,address,address,address,address, bool);
}
