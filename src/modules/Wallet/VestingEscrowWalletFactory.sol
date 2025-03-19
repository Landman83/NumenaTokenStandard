// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./VestingEscrowWalletProxy.sol";
import "../UpgradableModuleFactory.sol";

/**
 * @title Factory for deploying VestingEscrowWallet module
 */
contract VestingEscrowWalletFactory is UpgradableModuleFactory {

    /**
     * @notice Constructor
     * @param _setupCost Setup cost of the module
     * @param _logicContract Contract address that contains the logic related to `description`
     * @param _polymathRegistry Address of the Polymath registry
     * @param _isCostInPoly true = cost in Poly, false = USD
     */
    constructor (
        uint256 _setupCost,
        address _logicContract,
        address _polymathRegistry,
        bool _isCostInPoly
    )
        UpgradableModuleFactory("3.0.0", _setupCost, _logicContract, _polymathRegistry, _isCostInPoly)
    {
        name = "VestingEscrowWallet";
        title = "Vesting Escrow Wallet";
        description = "Manage vesting schedules to employees / affiliates";
        typesData.push(7);
        tagsData.push("Vesting");
        tagsData.push("Escrow");
        tagsData.push("Transfer Restriction");
        compatibleSTVersionRange["lowerBound"] = VersionUtils.pack(uint8(3), uint8(0), uint8(0));
        compatibleSTVersionRange["upperBound"] = VersionUtils.pack(uint8(3), uint8(0), uint8(0));
    }

    /**
     * @notice Used to launch the Module with the help of factory
     * @param _data Data used for the initialization of the module factory variables
     * @return address Contract address of the Module
     */
    function deploy(bytes calldata _data) external override returns(address) {
        address vestingEscrowWallet = address(new VestingEscrowWalletProxy(
            logicContracts[latestUpgrade].version, 
            msg.sender, 
            polymathRegistry.getAddress("PolyToken"), 
            logicContracts[latestUpgrade].logicContract
        ));
        _initializeModule(vestingEscrowWallet, _data);
        return vestingEscrowWallet;
    }
}
