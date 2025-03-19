// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Contract used to store layout for the GeneralPermissionManager storage
 */
contract GeneralPermissionManagerStorage {

    // Mapping used to hold the permissions on the modules provided to delegate, module add => delegate add => permission bytes32 => bool
    mapping (address => mapping (address => mapping (bytes32 => bool))) public perms;
    // Mapping hold the delegate details
    mapping (address => bytes32) public delegateDetails;
    // Array to track all delegates
    address[] public allDelegates;

}
