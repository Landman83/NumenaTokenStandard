// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../../proxy/OwnedUpgradeabilityProxy.sol";
import "../../../Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../../../storage/modules/STO/STOStorage.sol";
import "../../../storage/modules/ModuleStorage.sol";
import "./CappedSTOStorage.sol";

/**
 * @title CappedSTO module Proxy
 */
contract CappedSTOProxy is CappedSTOStorage, STOStorage, ModuleStorage, Pausable, ReentrancyGuard, OwnedUpgradeabilityProxy {

    /**
    * @notice Constructor
    * @param _version Implementation version
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
        require(
            _implementation != address(0),
            "Implementation address should not be 0x"
        );
        _upgradeTo(_version, _implementation);
    }

}
