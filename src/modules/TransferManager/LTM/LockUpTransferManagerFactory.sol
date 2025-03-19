// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./LockUpTransferManagerProxy.sol";
import "../../UpgradableModuleFactory.sol";
import "./LockUpTransferManager.sol";

/**
 * @title Factory for deploying LockUpTransferManager module
 */
contract LockUpTransferManagerFactory is UpgradableModuleFactory {

    /**
     * @notice Constructor
     * @param _polymathRegistry Address of the Polymath registry
     */
    constructor(
        address _polymathRegistry
    )
        UpgradableModuleFactory("3.0.0", 0, address(0), _polymathRegistry, false)
    {
        name = "LockUpTransferManager";
        title = "LockUp Transfer Manager";
        description = "Manage transfers using lock ups over time";
        typesData.push(2);
        tagsData.push("LockUp");
        tagsData.push("Transfer Restriction");
        compatibleSTVersionRange["lowerBound"] = VersionUtils.pack(uint8(3), uint8(0), uint8(0));
        compatibleSTVersionRange["upperBound"] = VersionUtils.pack(uint8(3), uint8(0), uint8(0));
    }

    /**
     * @notice Used to launch the Module with the help of factory
     * @param _data Initialization data for the module
     * @return address Contract address of the Module
     */
    function deploy(
        bytes calldata _data
    )
        external
        override
        returns(address)
    {
        address lockUpTransferManager = address(new LockUpTransferManagerProxy(
            logicContracts[latestUpgrade].version, 
            msg.sender, 
            polymathRegistry.getAddress("PolyToken"), 
            logicContracts[latestUpgrade].logicContract
        ));
        _initializeModule(lockUpTransferManager, _data);
        return lockUpTransferManager;
    }
}