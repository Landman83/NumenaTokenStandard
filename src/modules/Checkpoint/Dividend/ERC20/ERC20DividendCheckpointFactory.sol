// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./ERC20DividendCheckpointProxy.sol";
import "../../../UpgradableModuleFactory.sol";

/**
 * @title Factory for deploying ERC20DividendCheckpoint module
 */
contract ERC20DividendCheckpointFactory is UpgradableModuleFactory {

    /**
     * @notice Constructor
     * @param _polymathRegistry Address of the Polymath registry
     */
    constructor(
        address _polymathRegistry
    )
        UpgradableModuleFactory("3.0.0", 0, address(0), _polymathRegistry, false)
    {
        name = "ERC20DividendCheckpoint";
        title = "ERC20 Dividend Checkpoint";
        description = "Create ERC20 dividends for token holders at a specific checkpoint";
        typesData.push(4);
        tagsData.push("ERC20");
        tagsData.push("Dividend");
        tagsData.push("Checkpoint");
        compatibleSTVersionRange["lowerBound"] = VersionUtils.pack(uint8(3), uint8(0), uint8(0));
        compatibleSTVersionRange["upperBound"] = VersionUtils.pack(uint8(3), uint8(0), uint8(0));
    }

    /**
     * @notice Used to launch the Module with the help of factory
     * @param _data Initialization data for the module
     * @return address Contract address of the Module
     */
    function deploy(bytes calldata _data) external override returns(address) {
        address erc20DividendCheckpoint = address(new ERC20DividendCheckpointProxy(
            logicContracts[latestUpgrade].version,
            msg.sender,
            polymathRegistry.getAddress("PolyToken"),
            logicContracts[latestUpgrade].logicContract
        ));
        _initializeModule(erc20DividendCheckpoint, _data);
        return erc20DividendCheckpoint;
    }
}