// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/PolymathRegistry.sol";
import "../src/datastore/DataStore.sol";
import "../src/datastore/DataStoreFactory.sol";
import "../src/modules/TransferManager/GTM/GeneralTransferManager.sol";
import "../src/modules/TransferManager/GTM/GeneralTransferManagerFactory.sol";
import "../src/tokens/SecurityToken.sol";

/**
 * @title Deploy Polymath Infrastructure Script
 * @notice Deploys the core infrastructure required for the Polymath token system
 * @dev This script must be run before DeployST.s.sol to set up the necessary infrastructure
 */
contract DeployInfrastructureScript is Script {
    // Constants for registry keys
    bytes32 constant POLYMATH_REGISTRY_KEY = "PolymathRegistry";
    bytes32 constant SECURITY_TOKEN_LOGIC_KEY = "SecurityToken";
    bytes32 constant GENERAL_TRANSFER_MANAGER_LOGIC_KEY = "GeneralTransferManager";
    bytes32 constant GENERAL_TRANSFER_MANAGER_FACTORY_KEY = "GeneralTransferManagerFactory";
    bytes32 constant DATA_STORE_LOGIC_KEY = "DataStore";
    bytes32 constant DATA_STORE_FACTORY_KEY = "DataStoreFactory";

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Step 1: Deploy the PolymathRegistry
        PolymathRegistry registry = new PolymathRegistry();
        console.log("PolymathRegistry deployed at:", address(registry));
        
        // Step 2: Deploy the SecurityToken logic contract (implementation)
        SecurityToken securityTokenLogic = new SecurityToken();
        console.log("SecurityToken Logic deployed at:", address(securityTokenLogic));
        
        // Step 3: Deploy the GeneralTransferManager logic contract (implementation)
        GeneralTransferManager generalTransferManagerLogic = new GeneralTransferManager();
        console.log("GeneralTransferManager Logic deployed at:", address(generalTransferManagerLogic));
        
        // Step 4: Deploy the DataStore logic contract (implementation)
        DataStore dataStoreLogic = new DataStore();
        console.log("DataStore Logic deployed at:", address(dataStoreLogic));
        
        // Step 5: Deploy the DataStoreFactory
        DataStoreFactory dataStoreFactory = new DataStoreFactory(address(dataStoreLogic));
        console.log("DataStoreFactory deployed at:", address(dataStoreFactory));
        
        // Step 6: Deploy the GeneralTransferManagerFactory
        // Parameters:
        // - Setup cost (0 for simplicity)
        // - Logic contract address
        // - PolymathRegistry address
        // - Cost in POLY (false for simplicity)
        // - Version (1.0.0)
        GeneralTransferManagerFactory gtmFactory = new GeneralTransferManagerFactory(
            0, // Setup cost
            address(generalTransferManagerLogic),
            address(registry),
            false, // Cost in POLY
            "1.0.0" // Version
        );
        console.log("GeneralTransferManagerFactory deployed at:", address(gtmFactory));
        
        // Step 7: Register all addresses in the PolymathRegistry
        registry.changeAddress("PolymathRegistry", address(registry));
        registry.changeAddress("SecurityToken", address(securityTokenLogic));
        registry.changeAddress("GeneralTransferManager", address(generalTransferManagerLogic));
        registry.changeAddress("GeneralTransferManagerFactory", address(gtmFactory));
        registry.changeAddress("DataStore", address(dataStoreLogic));
        registry.changeAddress("DataStoreFactory", address(dataStoreFactory));
        
        console.log("Deployment completed successfully");
        console.log("Set these environment variables to use with DeployST.s.sol:");
        console.log("POLYMATH_REGISTRY=", address(registry));
        console.log("GTM_FACTORY=", address(gtmFactory));
        console.log("DATASTORE_FACTORY=", address(dataStoreFactory));
        console.log("ST_LOGIC=", address(securityTokenLogic));
        
        vm.stopBroadcast();
    }
}