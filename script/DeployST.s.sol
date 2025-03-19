// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/tokens/STFactory.sol";
import "../src/modules/TransferManager/LTM/LockUpTransferManagerFactory.sol";
import "../src/modules/Experimental/TransferManager/KYCTransferManagerFactory.sol";
import "../src/modules/Experimental/Burn/TrackedRedemptionFactory.sol";
import "../src/modules/Checkpoint/Dividend/ERC20/ERC20DividendCheckpointFactory.sol";
import "../src/modules/Checkpoint/Voting/PLCR/PLCRVotingCheckpointFactory.sol";
import "../src/modules/Checkpoint/Voting/Transparent/WeightedVoteCheckpointFactory.sol";
import "../src/modules/STO/Capped/CappedSTOFactory.sol";
import "../src/modules/STO/USDTiered/USDTieredSTOFactory.sol";
import "../src/modules/Wallet/VestingEscrowWalletFactory.sol";
import "../src/interfaces/ISecurityToken.sol";
import "../src/interfaces/IPolymathRegistry.sol";
import "../src/interfaces/IERC20.sol";

contract DeploySTScript is Script {
    // Constants
    bytes32 constant LOCKUP_NAME = "REG_D_LOCKUP";
    uint256 constant LOCKUP_PERIOD = 6 minutes; // 6 minutes lockup as requested
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // Mainnet USDC address - replace for testnet
    
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Get addresses from registry (or deploy them if needed in a real environment)
        address polymathRegistry = vm.envAddress("POLYMATH_REGISTRY");
        address transferManagerFactory = vm.envAddress("GTM_FACTORY");
        address dataStoreFactory = vm.envAddress("DATASTORE_FACTORY");
        address securityTokenLogic = vm.envAddress("ST_LOGIC");
        
        // Token deployment parameters
        string memory name = "Numena Security Token";
        string memory symbol = "NST";
        uint8 decimals = 18;
        string memory tokenDetails = "Regulation D 506(c) Compliant Security Token";
        bool divisible = true;
        address treasuryWallet = vm.envAddress("TREASURY_WALLET");
        address issuer = vm.envAddress("ISSUER_ADDRESS");
        
        // Deploy STFactory if it doesn't exist yet
        STFactory stFactory;
        address stFactoryAddress = vm.envAddress("ST_FACTORY_ADDRESS");
        if (stFactoryAddress == address(0)) {
            // Initialize the contract with correct parameters
            bytes memory initializationData = abi.encodeWithSignature("initialize(string,string,uint8,bool)", name, symbol, decimals, divisible);
            stFactory = new STFactory(
                polymathRegistry,
                transferManagerFactory,
                dataStoreFactory,
                "1.0.0", // Version
                securityTokenLogic,
                initializationData
            );
        } else {
            stFactory = STFactory(stFactoryAddress);
        }
        
        // Deploy security token
        address securityToken = stFactory.deployToken(
            name, 
            symbol, 
            decimals, 
            tokenDetails, 
            issuer, 
            divisible, 
            treasuryWallet
        );
        
        console.log("Security Token deployed at:", securityToken);
        ISecurityToken token = ISecurityToken(securityToken);
        
        // 1. Deploy and configure LockUpTransferManager with 6-minute lockup
        LockUpTransferManagerFactory ltmFactory;
        address ltmFactoryAddress = vm.envAddress("LTM_FACTORY_ADDRESS");
        if (ltmFactoryAddress == address(0)) {
            ltmFactory = new LockUpTransferManagerFactory(polymathRegistry);
        } else {
            ltmFactory = LockUpTransferManagerFactory(ltmFactoryAddress);
        }
        
        // Add LockUpTransferManager module to security token
        bytes memory ltmSetupData = ""; // No setup data needed for initialization
        address ltmModule = token.addModule(
            address(ltmFactory),
            ltmSetupData,
            0, // Budget unused
            0, // Budget unused
            false // Archived set to false
        );
        
        console.log("LockUpTransferManager deployed at:", ltmModule);
        
        // Set up the lockup type with 6-minute period - single release at end
        uint256 lockupAmount = 1000 * (10 ** uint256(decimals)); // Example amount to lock
        uint256 startTime = block.timestamp;
        uint256 lockUpPeriodSeconds = 6 minutes;
        uint256 releaseFrequencySeconds = 6 minutes; // Set equal to lockup period for single release
        
        // Call function on the module
        (bool success,) = ltmModule.call(
            abi.encodeWithSignature(
                "addNewLockUpType(uint256,uint256,uint256,uint256,bytes32)",
                lockupAmount,
                startTime,
                lockUpPeriodSeconds,
                releaseFrequencySeconds,
                LOCKUP_NAME
            )
        );
        require(success, "Failed to set up lockup");
        
        // 2. Deploy and configure KYCTransferManager
        KYCTransferManagerFactory kycFactory;
        address kycFactoryAddress = vm.envAddress("KYC_FACTORY_ADDRESS");
        if (kycFactoryAddress == address(0)) {
            kycFactory = new KYCTransferManagerFactory(polymathRegistry);
        } else {
            kycFactory = KYCTransferManagerFactory(kycFactoryAddress);
        }
        
        // Add KYCTransferManager module to security token
        bytes memory kycSetupData = ""; // No setup data needed for initialization
        address kycModule = token.addModule(
            address(kycFactory),
            kycSetupData,
            0, // Budget unused
            0, // Budget unused
            false // Archived set to false
        );
        
        console.log("KYCTransferManager deployed at:", kycModule);
        
        // 3. Deploy and configure Burn functionality
        TrackedRedemptionFactory burnFactory;
        address burnFactoryAddress = vm.envAddress("BURN_FACTORY_ADDRESS");
        if (burnFactoryAddress == address(0)) {
            burnFactory = new TrackedRedemptionFactory(polymathRegistry);
        } else {
            burnFactory = TrackedRedemptionFactory(burnFactoryAddress);
        }
        
        // Add TrackedRedemption (Burn) module to security token
        bytes memory burnSetupData = ""; // No setup data needed for initialization
        address burnModule = token.addModule(
            address(burnFactory),
            burnSetupData,
            0, // Budget unused
            0, // Budget unused
            false // Archived set to false
        );
        
        console.log("TrackedRedemption (Burn) module deployed at:", burnModule);
        
        // 4. Deploy and configure Dividend modules - ERC20 only
        ERC20DividendCheckpointFactory erc20DividendFactory;
        address erc20DividendFactoryAddress = vm.envAddress("ERC20_DIVIDEND_FACTORY_ADDRESS");
        if (erc20DividendFactoryAddress == address(0)) {
            erc20DividendFactory = new ERC20DividendCheckpointFactory(polymathRegistry);
        } else {
            erc20DividendFactory = ERC20DividendCheckpointFactory(erc20DividendFactoryAddress);
        }
        
        // Add ERC20DividendCheckpoint module to security token
        bytes memory erc20DividendSetupData = ""; // No setup data needed for initialization
        address erc20DividendModule = token.addModule(
            address(erc20DividendFactory),
            erc20DividendSetupData,
            0, // Budget unused
            0, // Budget unused
            false // Archived set to false
        );
        
        console.log("ERC20DividendCheckpoint module deployed at:", erc20DividendModule);
        
        // 5. Deploy and configure Voting modules
        
        // 5.1 PLCR Voting Checkpoint
        PLCRVotingCheckpointFactory plcrVotingFactory;
        address plcrVotingFactoryAddress = vm.envAddress("PLCR_VOTING_FACTORY_ADDRESS");
        if (plcrVotingFactoryAddress == address(0)) {
            plcrVotingFactory = new PLCRVotingCheckpointFactory(polymathRegistry);
        } else {
            plcrVotingFactory = PLCRVotingCheckpointFactory(plcrVotingFactoryAddress);
        }
        
        // Add PLCRVotingCheckpoint module to security token
        bytes memory plcrVotingSetupData = ""; // No setup data needed for initialization
        address plcrVotingModule = token.addModule(
            address(plcrVotingFactory),
            plcrVotingSetupData,
            0, // Budget unused
            0, // Budget unused
            false // Archived set to false
        );
        
        console.log("PLCRVotingCheckpoint module deployed at:", plcrVotingModule);
        
        // 5.2 Weighted Vote Checkpoint
        WeightedVoteCheckpointFactory weightedVoteFactory;
        address weightedVoteFactoryAddress = vm.envAddress("WEIGHTED_VOTE_FACTORY_ADDRESS");
        if (weightedVoteFactoryAddress == address(0)) {
            weightedVoteFactory = new WeightedVoteCheckpointFactory(polymathRegistry);
        } else {
            weightedVoteFactory = WeightedVoteCheckpointFactory(weightedVoteFactoryAddress);
        }
        
        // Add WeightedVoteCheckpoint module to security token
        bytes memory weightedVoteSetupData = ""; // No setup data needed for initialization
        address weightedVoteModule = token.addModule(
            address(weightedVoteFactory),
            weightedVoteSetupData,
            0, // Budget unused
            0, // Budget unused
            false // Archived set to false
        );
        
        console.log("WeightedVoteCheckpoint module deployed at:", weightedVoteModule);
        
        // 6. Deploy and configure STO modules
        
        // 6.1 Capped STO - USDC only
        CappedSTOFactory cappedSTOFactory;
        address cappedSTOFactoryAddress = vm.envAddress("CAPPED_STO_FACTORY_ADDRESS");
        if (cappedSTOFactoryAddress == address(0)) {
            cappedSTOFactory = new CappedSTOFactory(polymathRegistry);
        } else {
            cappedSTOFactory = CappedSTOFactory(cappedSTOFactoryAddress);
        }
        
        // Capped STO configuration parameters
        uint256 stoStartTime = block.timestamp + 10 minutes; // Start in 10 minutes
        uint256 stoEndTime = stoStartTime + 30 days; // Last for 30 days
        uint256 cap = 1000000 * (10 ** uint256(decimals)); // Cap of 1 million tokens
        uint256 rate = 100; // 1 token per 100 USDC (adjusted for USDC's 6 decimals)
        address fundsReceiver = vm.envAddress("FUNDS_RECEIVER");
        bool treasury = true; // Use treasury as funds receiver if specified
        
        // Encode setup parameters for Capped STO
        bytes memory cappedSTOSetupData = abi.encodeWithSignature(
            "configure(uint256,uint256,uint256,uint256,address,bool)",
            stoStartTime,
            stoEndTime,
            cap,
            rate,
            fundsReceiver,
            treasury
        );
        
        // Add CappedSTO module to security token
        address cappedSTOModule = token.addModule(
            address(cappedSTOFactory),
            cappedSTOSetupData,
            0, // Budget unused
            0, // Budget unused
            false // Archived set to false
        );
        
        console.log("CappedSTO module deployed at:", cappedSTOModule);
        
        // 6.2 USDTiered STO - USDC only
        USDTieredSTOFactory usdTieredSTOFactory;
        address usdTieredSTOFactoryAddress = vm.envAddress("USD_TIERED_STO_FACTORY_ADDRESS");
        if (usdTieredSTOFactoryAddress == address(0)) {
            usdTieredSTOFactory = new USDTieredSTOFactory(polymathRegistry);
        } else {
            usdTieredSTOFactory = USDTieredSTOFactory(usdTieredSTOFactoryAddress);
        }
        
        // USDTiered STO configuration
        uint256 usdStartTime = block.timestamp + 15 minutes; // Start in 15 minutes
        uint256 usdEndTime = usdStartTime + 60 days; // Last for 60 days
        
        // Set up tiers - example with 3 tiers
        uint256[] memory rates = new uint256[](3);
        rates[0] = 100; // 1 token = 100 USDC (Tier 1 - early investors)
        rates[1] = 120; // 1 token = 120 USDC (Tier 2)
        rates[2] = 150; // 1 token = 150 USDC (Tier 3 - late investors)
        
        uint256[] memory tokensPerTier = new uint256[](3);
        tokensPerTier[0] = 300000 * (10 ** uint256(decimals)); // 300K tokens in tier 1
        tokensPerTier[1] = 300000 * (10 ** uint256(decimals)); // 300K tokens in tier 2
        tokensPerTier[2] = 400000 * (10 ** uint256(decimals)); // 400K tokens in tier 3
        
        // Setup data for USDTiered STO
        bytes memory usdTieredSTOSetupData = abi.encodeWithSignature(
            "configure(uint256,uint256,uint256[],uint256[],address,bool)",
            usdStartTime,
            usdEndTime,
            rates,
            tokensPerTier,
            fundsReceiver,
            true // Use treasury
        );
        
        // Add USDTieredSTO module to security token
        address usdTieredSTOModule = token.addModule(
            address(usdTieredSTOFactory),
            usdTieredSTOSetupData,
            0, // Budget unused
            0, // Budget unused
            false // Archived set to false
        );
        
        console.log("USDTieredSTO module deployed at:", usdTieredSTOModule);
        
        // Configure USDTieredSTO to accept USDC
        (bool usdcSuccess,) = usdTieredSTOModule.call(
            abi.encodeWithSignature(
                "addFundRaiseType(uint8,address,uint256)",
                1, // Fund raise type for stable coins
                USDC_ADDRESS, // USDC token address
                10 ** 6 // USDC has 6 decimals
            )
        );
        require(usdcSuccess, "Failed to add USDC as payment method");
        
        // Disable ETH payments
        (bool disableEthSuccess,) = usdTieredSTOModule.call(
            abi.encodeWithSignature(
                "removeFundRaiseType(uint8)",
                0 // Fund raise type for ETH
            )
        );
        require(disableEthSuccess, "Failed to disable ETH payments");
        
        // 7. Deploy and configure Wallet module (VestingEscrowWallet)
        VestingEscrowWalletFactory vestingWalletFactory;
        address vestingWalletFactoryAddress = vm.envAddress("VESTING_WALLET_FACTORY_ADDRESS");
        if (vestingWalletFactoryAddress == address(0)) {
            vestingWalletFactory = new VestingEscrowWalletFactory(polymathRegistry);
        } else {
            vestingWalletFactory = VestingEscrowWalletFactory(vestingWalletFactoryAddress);
        }
        
        // Add VestingEscrowWallet module to security token
        bytes memory vestingWalletSetupData = ""; // No setup data needed for initialization
        address vestingWalletModule = token.addModule(
            address(vestingWalletFactory),
            vestingWalletSetupData,
            0, // Budget unused
            0, // Budget unused
            false // Archived set to false
        );
        
        console.log("VestingEscrowWallet module deployed at:", vestingWalletModule);
        
        vm.stopBroadcast();
    }
}