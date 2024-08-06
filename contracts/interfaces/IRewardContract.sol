// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.20;

interface IRewardContract {
    function getTotalReward() external view returns (uint256);
    function getRewardToken() external view returns (address);
    function withdrawReward(uint256 amount) external;
}