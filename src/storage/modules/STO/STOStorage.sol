// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Storage layout for the STO contract
 */
abstract contract STOStorage {
    bytes32 internal constant INVESTORFLAGS = "INVESTORFLAGS";

    mapping (uint8 => bool) public fundRaiseTypes;
    mapping (uint8 => uint256) public fundsRaised;

    // Start time of the STO
    uint256 public startTime;
    // End time of the STO
    uint256 public endTime;
    // Time STO was paused
    uint256 public pausedTime;
    // Number of individual investors
    uint256 public investorCount;
    // Address where ETH & POLY funds are delivered
    address payable public wallet;
    // Final amount of tokens sold
    uint256 public totalTokensSold;
}
