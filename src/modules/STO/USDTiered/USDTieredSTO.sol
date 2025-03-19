// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../STO.sol";
import "../../../interfaces/IPolymathRegistry.sol";
import "../../../interfaces/IOracle.sol";
import "./USDTieredSTOStorage.sol";

/**
 * @title STO module for standard capped crowdsale
 */
contract USDTieredSTO is USDTieredSTOStorage, STO {
    using SafeMath for uint256;

    string internal constant POLY_ORACLE = "PolyUsdOracle";
    string internal constant ETH_ORACLE = "EthUsdOracle";

    ////////////
    // Events //
    ////////////

    event SetAllowBeneficialInvestments(bool _allowed);
    event SetNonAccreditedLimit(address _investor, uint256 _limit);
    event TokenPurchase(
        address indexed _purchaser,
        address indexed _beneficiary,
        uint256 _tokens,
        uint256 _usdAmount,
        uint256 _tierPrice,
        uint256 _tier
    );
    event FundsReceived(
        address indexed _purchaser,
        address indexed _beneficiary,
        uint256 _usdAmount,
        FundRaiseType _fundRaiseType,
        uint256 _receivedValue,
        uint256 _spentValue,
        uint256 _rate
    );
    event ReserveTokenMint(address indexed _owner, address indexed _wallet, uint256 _tokens, uint256 _latestTier);
    event SetAddresses(address indexed _wallet, IERC20[] _usdTokens);
    event SetLimits(uint256 _nonAccreditedLimitUSD, uint256 _minimumInvestmentUSD);
    event SetTimes(uint256 _startTime, uint256 _endTime);
    event SetTiers(
        uint256[] _ratePerTier,
        uint256[] _ratePerTierDiscountPoly,
        uint256[] _tokensPerTierTotal,
        uint256[] _tokensPerTierDiscountPoly
    );
    event SetTreasuryWallet(address _oldWallet, address _newWallet);

    ///////////////
    // Modifiers //
    ///////////////

    modifier validETH() {
        require(_getOracle(bytes32("ETH"), bytes32("USD")) != address(0), "Invalid Oracle");
        require(fundRaiseTypes[uint8(FundRaiseType.ETH)], "ETH not allowed");
        _;
    }

    modifier validPOLY() {
        require(_getOracle(bytes32("POLY"), bytes32("USD")) != address(0), "Invalid Oracle");
        require(fundRaiseTypes[uint8(FundRaiseType.POLY)], "POLY not allowed");
        _;
    }

    modifier validSC(address _usdToken) {
        require(fundRaiseTypes[uint8(FundRaiseType.SC)] && usdTokenEnabled[_usdToken], "USD not allowed");
        _;
    }

    ///////////////////////
    // STO Configuration //
    ///////////////////////

    constructor(address _securityToken, address _polyAddress) Module(_securityToken, _polyAddress) {
    }

    /**
     * @notice Function used to intialize the contract variables
     * @param _startTime Unix timestamp at which offering get started
     * @param _endTime Unix timestamp at which offering get ended
     * @param _ratePerTier Rate (in USD) per tier (* 10**18)
     * @param _ratePerTierDiscountPoly Discounted rate (in USD) per tier (* 10**18)
     * @param _tokensPerTierTotal Tokens available in each tier
     * @param _tokensPerTierDiscountPoly Tokens available at discounted rate in each tier
     * @param _nonAccreditedLimitUSD Limit in USD (* 10**18) for non-accredited investors
     * @param _minimumInvestmentUSD Minimun investment in USD (* 10**18)
     * @param _fundRaiseTypes Types of currency used to collect the funds
     * @param _wallet Ethereum account address to hold the funds
     * @param _treasuryWallet Ethereum account address to receive unsold tokens
     * @param _usdTokens Contract address of the stable coins
     */
    function configure(
        uint256 _startTime,
        uint256 _endTime,
        uint256[] memory _ratePerTier,
        uint256[] memory _ratePerTierDiscountPoly,
        uint256[] memory _tokensPerTierTotal,
        uint256[] memory _tokensPerTierDiscountPoly,
        uint256 _nonAccreditedLimitUSD,
        uint256 _minimumInvestmentUSD,
        FundRaiseType[] memory _fundRaiseTypes,
        address payable _wallet,
        address _treasuryWallet,
        IERC20[] memory _usdTokens
    )
        public
        onlyFactory
    {
        require(_startTime >= block.timestamp, "Start time should be in the future");
        require(_endTime > _startTime, "End time should be greater than start time");
        require(_ratePerTier.length > 0, "No tiers provided");
        require(_ratePerTier.length == _tokensPerTierTotal.length, "Mismatch between rates and tokens");
        require(_ratePerTier.length == _ratePerTierDiscountPoly.length, "Mismatch between rates and discount rates");
        require(_ratePerTier.length == _tokensPerTierDiscountPoly.length, "Mismatch between rates and discount tokens");
        require(_wallet != address(0), "Zero address is not permitted for wallet");
        require(_treasuryWallet != address(0), "Zero address is not permitted for treasury wallet");
        require(_fundRaiseTypes.length > 0, "No fund raise types provided");
        require(_minimumInvestmentUSD > 0, "Minimum investment should be greater than 0");
        
        startTime = _startTime;
        endTime = _endTime;
        wallet = _wallet;
        treasuryWallet = _treasuryWallet;
        minimumInvestmentUSD = _minimumInvestmentUSD;
        nonAccreditedLimitUSD = _nonAccreditedLimitUSD;
        
        // Set fund raise types
        _setFundRaiseType(_fundRaiseTypes);
        
        // Set USD tokens
        for (uint256 i = 0; i < _usdTokens.length; i++) {
            usdTokens.push(_usdTokens[i]);
            usdTokenEnabled[address(_usdTokens[i])] = true;
        }
        
        // Set tiers
        for (uint256 i = 0; i < _ratePerTier.length; i++) {
            require(_ratePerTier[i] > 0, "Rate per tier should be greater than 0");
            require(_tokensPerTierTotal[i] > 0, "Tokens per tier should be greater than 0");
            require(_tokensPerTierDiscountPoly[i] <= _tokensPerTierTotal[i], "Discounted tokens should be less than total tokens");
            
            Tier memory tier = Tier({
                rate: _ratePerTier[i],
                rateDiscountPoly: _ratePerTierDiscountPoly[i],
                tokenTotal: _tokensPerTierTotal[i],
                tokensDiscountPoly: _tokensPerTierDiscountPoly[i],
                mintedTotal: 0,
                mintedDiscountPoly: 0
            });
            tiers.push(tier);
        }
        
        // Set oracle keys
        oracleKeys[bytes32("ETH")][bytes32("USD")] = ETH_ORACLE;
        oracleKeys[bytes32("POLY")][bytes32("USD")] = POLY_ORACLE;
        
        emit SetTiers(_ratePerTier, _ratePerTierDiscountPoly, _tokensPerTierTotal, _tokensPerTierDiscountPoly);
        emit SetAddresses(_wallet, _usdTokens);
        emit SetLimits(_nonAccreditedLimitUSD, _minimumInvestmentUSD);
        emit SetTimes(_startTime, _endTime);
        emit SetTreasuryWallet(address(0), _treasuryWallet);
    }

    /**
     * @notice Fallback function to allow ETH payments directly to the contract
     */
    receive() external payable {
        buyWithETH(msg.sender);
    }

    /**
     * @notice For backward compatibility
     */
    fallback() external payable {
        buyWithETH(msg.sender);
    }

    /**
     * @notice Low level token purchase with ETH
     * @param _beneficiary Address receiving the tokens
     */
    function buyWithETH(address _beneficiary) public payable validETH whenNotPaused {
        require(msg.value > 0, "No ETH sent");
        if (!allowBeneficialInvestments) {
            require(_beneficiary == msg.sender, "Beneficiary address doesn't match sender");
        }
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Offering is closed/Not yet started");
        require(_canBuy(_beneficiary), "Unauthorized");
        
        uint256 usdAmount = getUSDTokenAmount(FundRaiseType.ETH, msg.value);
        require(usdAmount >= minimumInvestmentUSD, "Investment too small");
        
        uint256 investorInvestedUSDAmount = investorInvestedUSD[_beneficiary].add(usdAmount);
        uint256 investorLimit = getOverrideOrDefault(_beneficiary);
        if (investorLimit != 0) {
            require(investorInvestedUSDAmount <= investorLimit, "Investor limit reached");
        }
        
        investorInvestedUSD[_beneficiary] = investorInvestedUSDAmount;
        investorInvested[_beneficiary][uint8(FundRaiseType.ETH)] = investorInvested[_beneficiary][uint8(FundRaiseType.ETH)].add(msg.value);
        fundsRaisedUSD = fundsRaisedUSD.add(usdAmount);
        
        uint256 spentUSD = 0;
        uint256 spentValue = 0;
        uint256 refund = 0;
        (spentUSD, spentValue, refund) = _buyTokens(_beneficiary, usdAmount, FundRaiseType.ETH, msg.value);
        
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }
        payable(wallet).transfer(spentValue);
        
        emit FundsReceived(msg.sender, _beneficiary, spentUSD, FundRaiseType.ETH, msg.value, spentValue, getRate(FundRaiseType.ETH));
    }

    /**
     * @notice Low level token purchase with POLY
     * @param _beneficiary Address receiving the tokens
     * @param _investedPOLY Amount of POLY invested
     */
    function buyWithPOLY(address _beneficiary, uint256 _investedPOLY) public validPOLY whenNotPaused {
        require(_investedPOLY > 0, "No POLY sent");
        if (!allowBeneficialInvestments) {
            require(_beneficiary == msg.sender, "Beneficiary address doesn't match sender");
        }
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Offering is closed/Not yet started");
        require(_canBuy(_beneficiary), "Unauthorized");
        
        uint256 usdAmount = getUSDTokenAmount(FundRaiseType.POLY, _investedPOLY);
        require(usdAmount >= minimumInvestmentUSD, "Investment too small");
        
        uint256 investorInvestedUSDAmount = investorInvestedUSD[_beneficiary].add(usdAmount);
        uint256 investorLimit = getOverrideOrDefault(_beneficiary);
        if (investorLimit != 0) {
            require(investorInvestedUSDAmount <= investorLimit, "Investor limit reached");
        }
        
        investorInvestedUSD[_beneficiary] = investorInvestedUSDAmount;
        investorInvested[_beneficiary][uint8(FundRaiseType.POLY)] = investorInvested[_beneficiary][uint8(FundRaiseType.POLY)].add(_investedPOLY);
        fundsRaisedUSD = fundsRaisedUSD.add(usdAmount);
        
        uint256 spentUSD = 0;
        uint256 spentValue = 0;
        uint256 refund = 0;
        (spentUSD, spentValue, refund) = _buyTokens(_beneficiary, usdAmount, FundRaiseType.POLY, _investedPOLY);
        
        if (refund > 0) {
            require(polyToken.transfer(msg.sender, refund), "Transfer failed");
        }
        require(polyToken.transferFrom(msg.sender, wallet, spentValue), "Transfer failed");
        
        emit FundsReceived(msg.sender, _beneficiary, spentUSD, FundRaiseType.POLY, _investedPOLY, spentValue, getRate(FundRaiseType.POLY));
    }

    /**
     * @notice Purchase tokens using stable coin
     * @param _beneficiary Address where security tokens will be sent
     * @param _investedSC Amount of stable coin invested
     * @param _usdToken Stable coin address
     */
    function buyWithUSD(address _beneficiary, uint256 _investedSC, IERC20 _usdToken) external validSC(address(_usdToken)) whenNotPaused {
        require(_investedSC > 0, "No stable coins sent");
        if (!allowBeneficialInvestments) {
            require(_beneficiary == msg.sender, "Beneficiary address doesn't match sender");
        }
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Offering is closed/Not yet started");
        require(_canBuy(_beneficiary), "Unauthorized");
        
        uint256 usdAmount = getUSDTokenAmount(FundRaiseType.SC, _investedSC);
        require(usdAmount >= minimumInvestmentUSD, "Investment too small");
        
        uint256 investorInvestedUSDAmount = investorInvestedUSD[_beneficiary].add(usdAmount);
        uint256 investorLimit = getOverrideOrDefault(_beneficiary);
        if (investorLimit != 0) {
            require(investorInvestedUSDAmount <= investorLimit, "Investor limit reached");
        }
        
        investorInvestedUSD[_beneficiary] = investorInvestedUSDAmount;
        investorInvested[_beneficiary][uint8(FundRaiseType.SC)] = investorInvested[_beneficiary][uint8(FundRaiseType.SC)].add(_investedSC);
        fundsRaisedUSD = fundsRaisedUSD.add(usdAmount);
        stableCoinsRaised[address(_usdToken)] = stableCoinsRaised[address(_usdToken)].add(_investedSC);
        
        uint256 spentUSD = 0;
        uint256 spentValue = 0;
        uint256 refund = 0;
        (spentUSD, spentValue, refund) = _buyTokens(_beneficiary, usdAmount, FundRaiseType.SC, _investedSC);
        
        if (refund > 0) {
            require(_usdToken.transfer(msg.sender, refund), "Transfer failed");
        }
        require(_usdToken.transferFrom(msg.sender, wallet, spentValue), "Transfer failed");
        
        emit FundsReceived(msg.sender, _beneficiary, spentUSD, FundRaiseType.SC, _investedSC, spentValue, getRate(FundRaiseType.SC));
    }

    /**
     * @notice Internal function to process token purchase
     * @param _beneficiary Address receiving the tokens
     * @param _usdAmount USD value of investment
     * @param _fundRaiseType Type of currency used for investment
     * @param _investedAmount Amount of tokens invested
     * @return spentUSD USD value spent
     * @return spentValue Amount of investment spent
     * @return refund Amount to refund
     */
    function _buyTokens(
        address _beneficiary, 
        uint256 _usdAmount, 
        FundRaiseType _fundRaiseType, 
        uint256 _investedAmount
    ) 
        internal 
        returns(uint256 spentUSD, uint256 spentValue, uint256 refund) 
    {
        uint256 tierPrice;
        uint256 tokensToMint;
        uint256 tokensToMintWithDiscountPoly;
        uint256 tier;
        
        (tierPrice, tokensToMint, tokensToMintWithDiscountPoly, tier) = _calculateTier(_usdAmount, _fundRaiseType);
        
        if (tokensToMint == 0) {
            refund = _investedAmount;
            return (0, 0, refund);
        }
        
        // Calculate refund if needed
        if (tokensToMint < _usdAmount.mul(10**18).div(tierPrice)) {
            spentUSD = tokensToMint.mul(tierPrice).div(10**18);
            spentValue = spentUSD.mul(_investedAmount).div(_usdAmount);
            refund = _investedAmount.sub(spentValue);
        } else {
            spentUSD = _usdAmount;
            spentValue = _investedAmount;
        }
        
        // Update investor count
        if (investorCount.add(1) > investorCount && investorInvestedUSD[_beneficiary] == spentUSD) {
            investorCount = investorCount.add(1);
        }
        
        // Mint tokens
        securityToken.issue(_beneficiary, tokensToMint, "");
        
        // Update tier data
        tiers[tier].mintedTotal = tiers[tier].mintedTotal.add(tokensToMint);
        tiers[tier].minted[uint8(_fundRaiseType)] = tiers[tier].minted[uint8(_fundRaiseType)].add(tokensToMint);
        
        if (_fundRaiseType == FundRaiseType.POLY && tokensToMintWithDiscountPoly > 0) {
            tiers[tier].mintedDiscountPoly = tiers[tier].mintedDiscountPoly.add(tokensToMintWithDiscountPoly);
        }
        
        emit TokenPurchase(msg.sender, _beneficiary, tokensToMint, spentUSD, tierPrice, tier);
        
        return (spentUSD, spentValue, refund);
    }

    /**
     * @notice Calculate tier, price, and tokens to mint
     * @param _usdAmount USD value of investment
     * @param _fundRaiseType Type of currency used for investment
     * @return tierPrice Price per token in current tier
     * @return tokensToMint Number of tokens to mint
     * @return tokensToMintWithDiscountPoly Number of tokens to mint at discount
     * @return tierIndex Current tier index
     */
    function _calculateTier(
        uint256 _usdAmount, 
        FundRaiseType _fundRaiseType
    ) 
        internal 
        returns(
            uint256 tierPrice, 
            uint256 tokensToMint, 
            uint256 tokensToMintWithDiscountPoly, 
            uint256 tierIndex
        ) 
    {
        uint256 remainingUSD = _usdAmount;
        uint256 totalTokens = 0;
        uint256 totalTokensWithDiscount = 0;
        
        for (uint256 i = currentTier; i < tiers.length; i++) {
            Tier storage tier = tiers[i];
            uint256 tierRemaining = tier.tokenTotal.sub(tier.mintedTotal);
            
            if (tierRemaining == 0) {
                currentTier = i + 1;
                continue;
            }
            
            uint256 tierPrice = tier.rate;
            uint256 maxTokens = remainingUSD.mul(10**18).div(tierPrice);
            uint256 tokensForTier = Math.min(maxTokens, tierRemaining);
            
            if (_fundRaiseType == FundRaiseType.POLY && tier.rateDiscountPoly > 0) {
                uint256 discountTierRemaining = tier.tokensDiscountPoly.sub(tier.mintedDiscountPoly);
                
                if (discountTierRemaining > 0) {
                    uint256 discountTierPrice = tier.rateDiscountPoly;
                    uint256 maxDiscountTokens = remainingUSD.mul(10**18).div(discountTierPrice);
                    uint256 discountTokensForTier = Math.min(maxDiscountTokens, discountTierRemaining);
                    
                    if (discountTokensForTier > tokensForTier) {
                        discountTokensForTier = tokensForTier;
                    }
                    
                    totalTokensWithDiscount = totalTokensWithDiscount.add(discountTokensForTier);
                    tokensForTier = tokensForTier.sub(discountTokensForTier);
                    remainingUSD = remainingUSD.sub(discountTokensForTier.mul(discountTierPrice).div(10**18));
                }
            }
            
            totalTokens = totalTokens.add(tokensForTier);
            remainingUSD = remainingUSD.sub(tokensForTier.mul(tierPrice).div(10**18));
            
            if (tokensForTier < tierRemaining) {
                return (tierPrice, totalTokens.add(totalTokensWithDiscount), totalTokensWithDiscount, i);
            }
            
            currentTier = i + 1;
        }
        
        return (tiers[tiers.length - 1].rate, totalTokens.add(totalTokensWithDiscount), totalTokensWithDiscount, tiers.length - 1);
    }

    /**
     * @notice Return the total no. of tokens sold
     * @return uint256 Total number of tokens sold
     */
    function getTokensSold() external view returns (uint256) {
        if (isFinalized)
            return totalTokensSold;
        return getTokensMinted();
    }

    /**
     * @notice Return the total no. of tokens minted
     * @return tokensMinted Total number of tokens minted
     */
    function getTokensMinted() public view returns (uint256 tokensMinted) {
        for (uint256 i = 0; i < tiers.length; i++) {
            tokensMinted = tokensMinted.add(tiers[i].mintedTotal);
        }
    }

    /**
     * @notice Return the total no. of tokens sold for the given fund raise type
     * @param _fundRaiseType The fund raising currency (e.g. ETH, POLY, SC) to calculate sold tokens for
     * @return tokensSold Total number of tokens sold for ETH
     */
    function getTokensSoldFor(FundRaiseType _fundRaiseType) external view returns (uint256 tokensSold) {
        for (uint256 i = 0; i < tiers.length; i++) {
            tokensSold = tokensSold.add(tiers[i].minted[uint8(_fundRaiseType)]);
        }
    }

    /**
     * @notice Return array of minted tokens in each fund raise type for given tier
     * @param _tier The tier to return minted tokens for
     * @return uint256[] array of minted tokens in each fund raise type
     */
    function getTokensMintedByTier(uint256 _tier) external view returns(uint256[] memory) {
        uint256[] memory tokensMinted = new uint256[](3);
        tokensMinted[0] = tiers[_tier].minted[uint8(FundRaiseType.ETH)];
        tokensMinted[1] = tiers[_tier].minted[uint8(FundRaiseType.POLY)];
        tokensMinted[2] = tiers[_tier].minted[uint8(FundRaiseType.SC)];
        return tokensMinted;
    }

    /**
     * @notice Return the total no. of tokens sold in a given tier
     * @param _tier The tier to calculate sold tokens for
     * @return uint256 Total number of tokens sold in the tier
     */
    function getTokensSoldByTier(uint256 _tier) external view returns (uint256) {
        uint256 tokensSold;
        tokensSold = tokensSold.add(tiers[_tier].minted[uint8(FundRaiseType.ETH)]);
        tokensSold = tokensSold.add(tiers[_tier].minted[uint8(FundRaiseType.POLY)]);
        tokensSold = tokensSold.add(tiers[_tier].minted[uint8(FundRaiseType.SC)]);
        return tokensSold;
    }

    /**
     * @notice Return the total no. of tiers
     * @return uint256 Total number of tiers
     */
    function getNumberOfTiers() external view returns (uint256) {
        return tiers.length;
    }

    /**
     * @notice Return the usd tokens accepted by the STO
     * @return address[] usd tokens
     */
    function getUsdTokens() external view returns (IERC20[] memory) {
        return usdTokens;
    }

    /**
     * @notice Return the permissions flag that are associated with STO
     * @return allPermissions Array of permission flags
     */
    function getPermissions() public view override returns(bytes32[] memory allPermissions) {
        allPermissions = new bytes32[](2);
        allPermissions[0] = OPERATOR;
        allPermissions[1] = ADMIN;
        return allPermissions;
    }

    /**
     * @notice Return the STO details
     * @return startTime Unixtimestamp at which offering gets start
     * @return endTime Unixtimestamp at which offering ends
     * @return currentTier Currently active tier
     * @return cap Array of Number of tokens this STO will be allowed to sell at different tiers
     * @return rate Array Rate at which tokens are sold at different tiers
     * @return fundsRaisedUSD Amount of funds raised in USD
     * @return investorCount Number of individual investors this STO have
     * @return tokensSold Number of tokens sold
     * @return fundRaiseTypes Array of bools to show if funding is allowed in ETH, POLY, SC respectively
     */
    function getSTODetails() external view returns(
        uint256 startTime,
        uint256 endTime,
        uint256 currentTier,
        uint256[] memory cap,
        uint256[] memory rate,
        uint256 fundsRaisedUSD,
        uint256 investorCount,
        uint256 tokensSold,
        bool[] memory fundRaiseTypes
    ) {
        uint256[] memory _cap = new uint256[](tiers.length);
        uint256[] memory _rate = new uint256[](tiers.length);
        for(uint256 i = 0; i < tiers.length; i++) {
            _cap[i] = tiers[i].tokenTotal;
            _rate[i] = tiers[i].rate;
        }
        bool[] memory _fundRaiseTypes = new bool[](3);
        _fundRaiseTypes[0] = fundRaiseTypes[uint8(FundRaiseType.ETH)];
        _fundRaiseTypes[1] = fundRaiseTypes[uint8(FundRaiseType.POLY)];
        _fundRaiseTypes[2] = fundRaiseTypes[uint8(FundRaiseType.SC)];
        return (
            startTime,
            endTime,
            currentTier,
            _cap,
            _rate,
            fundsRaisedUSD,
            investorCount,
            getTokensSold(),
            _fundRaiseTypes
        );
    }

    /**
     * @notice This function returns the signature of configure function
     * @return bytes4 Configure function signature
     */
    function getInitFunction() public pure override returns(bytes4) {
        return this.configure.selector;
    }

    /**
     * @notice Get oracle address for a currency pair
     * @param _currency Base currency
     * @param _denominatedCurrency Denominated currency
     * @return oracleAddress Address of the oracle
     */
    function _getOracle(bytes32 _currency, bytes32 _denominatedCurrency) internal view returns(address oracleAddress) {
        oracleAddress = customOracles[_currency][_denominatedCurrency];
        if (oracleAddress == address(0))
            oracleAddress = IPolymathRegistry(securityToken.polymathRegistry()).getAddress(oracleKeys[_currency][_denominatedCurrency]);
    }
}
