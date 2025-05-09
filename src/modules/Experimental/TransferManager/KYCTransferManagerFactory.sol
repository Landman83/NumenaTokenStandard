// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./KYCTransferManager.sol";
import "./../../ModuleFactory.sol";

contract KYCTransferManagerFactory is ModuleFactory {

    /**
     * @notice Constructor
     * @param _polymathRegistry Address of the polymath registry
     */
    constructor(
        address _polymathRegistry
    )
        ModuleFactory(0, _polymathRegistry, false)
    {
        initialVersion = "3.0.0";
        name = "KYCTransferManager";
        title = "KYC Transfer Manager";
        description = "Manages KYC";
        typesData.push(2);
        typesData.push(6);
        tagsData.push("KYC");
        tagsData.push("Transfer Restriction");
        compatibleSTVersionRange["lowerBound"] = VersionUtils.pack(uint8(3), uint8(0), uint8(0));
        compatibleSTVersionRange["upperBound"] = VersionUtils.pack(uint8(3), uint8(0), uint8(0));
    }

    /**
     * @notice Used to launch the Module with the help of factory
     * @return address Contract address of the Module
     */
    function deploy(bytes calldata _data) external override returns(address) {
        address kycTransferManager = address(new KYCTransferManager(msg.sender, polymathRegistry.getAddress("PolyToken")));
        _initializeModule(kycTransferManager, _data);
        return kycTransferManager;
    }
}