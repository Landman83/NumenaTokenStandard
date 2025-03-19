// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Contract used to store layout for the VestingEscrowWallet storage
 */
contract VestingEscrowWalletStorage {
    // Address of the treasury wallet
    address public treasuryWallet;

    // Unassigned tokens
    uint256 public unassignedTokens;

    // Array of beneficiaries
    address[] public beneficiaries;

    // Mapping from beneficiary to their schedules
    mapping(address => Schedule[]) public schedules;

    // Mapping from template name to template
    mapping(bytes32 => Template) public templates;

    // Mapping from user address and template name to index in schedules array
    mapping(address => mapping(bytes32 => uint256)) public userToTemplateIndex;

    // Structure to store vesting schedule
    struct Schedule {
        bytes32 templateName;
        uint256 numberOfTokens;
        uint256 duration;
        uint256 frequency;
        uint256 startTime;
        uint256 claimedTokens;
    }

    // Structure to store template
    struct Template {
        uint256 numberOfTokens;
        uint256 duration;
        uint256 frequency;
    }

    // Treasury key
    bytes32 internal constant TREASURY = 0x74726561737572790000000000000000000000000000000000000000000000; // "treasury"
}
