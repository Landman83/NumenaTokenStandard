// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../../../proxy/OwnedUpgradeabilityProxy.sol";
import "./ERC20DividendCheckpointStorage.sol";
import "../../../../storage/modules/Checkpoint/Dividend/DividendCheckpointStorage.sol";
import "../../../../Pausable.sol";
import "../../../../storage/modules/ModuleStorage.sol";

/**
 * @title ERC20 Dividend Checkpoint module proxy
 */
contract ERC20DividendCheckpointProxy is ERC20DividendCheckpointStorage, DividendCheckpointStorage, ModuleStorage, Pausable, OwnedUpgradeabilityProxy {
    /**
    * @notice Constructor
    * @param _version Implementation version
    * @param _securityToken Address of the security token
    * @param _polyAddress Address of the polytoken
    * @param _implementation Address of the implementation to be set
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