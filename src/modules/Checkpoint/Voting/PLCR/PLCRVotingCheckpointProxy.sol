// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../../../Pausable.sol";
import "./PLCRVotingCheckpointStorage.sol";
import "../../../../storage/modules/ModuleStorage.sol";
import "../../../../proxy/OwnedUpgradeabilityProxy.sol";
import "../../../../storage/modules/Checkpoint/Voting/VotingCheckpointStorage.sol";

/**
 * @title Voting module for governance
 */
contract PLCRVotingCheckpointProxy is PLCRVotingCheckpointStorage, VotingCheckpointStorage, ModuleStorage, Pausable, OwnedUpgradeabilityProxy {
    /**
     * @notice Constructor
     * @param _version Version string
     * @param _securityToken Address of the security token
     * @param _polyAddress Address of the polytoken
     * @param _implementation representing the address of the new implementation to be set
     */
    constructor(
        string memory _version,
        address _securityToken,
        address _polyAddress,
        address _implementation
    )
        ModuleStorage(_securityToken, _polyAddress)
    {
        require(_implementation != address(0), "Implementation address should not be 0x");
        _upgradeTo(_version, _implementation);
    }
}
