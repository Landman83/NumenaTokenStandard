// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../STO.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./CappedSTOStorage.sol";

/**
 * @title STO module for standard capped crowdsale
 */
contract CappedSTO is CappedSTOStorage, STO, ReentrancyGuard {


    /**
    * Event for token purchase logging
    * @param purchaser who paid for the tokens
    * @param beneficiary who got the tokens
    * @param value weis paid for purchase
    * @param amount amount of tokens purchased
    */
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    event SetAllowBeneficialInvestments(bool _allowed);

    constructor(address _securityToken, address _polyToken) Module(_securityToken, _polyToken) {
    }

    //////////////////////////////////
    /**
    * @notice fallback function ***DO NOT OVERRIDE***
    */
    receive() external payable {
        buyTokens(msg.sender);
    }

    /**
     * @notice For backward compatibility
     */
    fallback() external payable {
        buyTokens(msg.sender);
    }

    /**
     * @notice Function used to intialize the contract variables
     * @param _startTime Unix timestamp at which offering get started
     * @param _endTime Unix timestamp at which offering get ended
     * @param _cap Maximum No. of token base units for sale
     * @param _rate Token units a buyer gets multiplied by 10^18 per wei / base unit of POLY
     * @param _fundRaiseTypes Type of currency used to collect the funds
     * @param _fundsReceiver Ethereum account address to hold the funds
     */
    function configure(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cap,
        uint256 _rate,
        FundRaiseType[] memory _fundRaiseTypes,
        address payable _fundsReceiver
    )
        public
        onlyFactory
    {
        require(endTime == 0, "Already configured");
        require(_rate > 0, "Rate of token should be greater than 0");
        require(_fundsReceiver != address(0), "Zero address is not permitted");
        /*solium-disable-next-line security/no-block-members*/
        require(_startTime >= block.timestamp && _endTime > _startTime, "Date parameters are not valid");
        require(_cap > 0, "Cap should be greater than 0");
        require(_fundRaiseTypes.length == 1, "It only selects single fund raise type");
        startTime = _startTime;
        endTime = _endTime;
        cap = _cap;
        rate = _rate;
        wallet = _fundsReceiver;
        _setFundRaiseType(_fundRaiseTypes);
    }

    /**
     * @notice This function returns the signature of configure function
     * @return bytes4 Function signature
     */
    function getInitFunction() public pure override returns(bytes4) {
        return this.configure.selector;
    }

    /**
     * @notice Function to set allowBeneficialInvestments (allow beneficiary to be different to funder)
     * @param _allowBeneficialInvestments Boolean to allow or disallow beneficial investments
     */
    function changeAllowBeneficialInvestments(bool _allowBeneficialInvestments) public withPerm(OPERATOR) {
        require(_allowBeneficialInvestments != allowBeneficialInvestments, "Does not change value");
        allowBeneficialInvestments = _allowBeneficialInvestments;
        emit SetAllowBeneficialInvestments(allowBeneficialInvestments);
    }

    /**
      * @notice Low level token purchase ***DO NOT OVERRIDE***
      * @param _beneficiary Address performing the token purchase
      */
    function buyTokens(address _beneficiary) public payable whenNotPaused nonReentrant {
        if (!allowBeneficialInvestments) {
            require(_beneficiary == msg.sender, "Beneficiary address does not match msg.sender");
        }

        require(fundRaiseTypes[uint8(FundRaiseType.ETH)], "Mode of investment is not ETH");

        uint256 weiAmount = msg.value;
        uint256 refund = _processTx(_beneficiary, weiAmount);
        weiAmount = weiAmount - refund;

        _forwardFunds(refund);
    }

    /**
      * @notice low level token purchase
      * @param _investedPOLY Amount of POLY invested
      */
    function buyTokensWithPoly(uint256 _investedPOLY) public whenNotPaused nonReentrant {
        require(fundRaiseTypes[uint8(FundRaiseType.POLY)], "Mode of investment is not POLY");
        uint256 refund = _processTx(msg.sender, _investedPOLY);
        _forwardPoly(msg.sender, wallet, _investedPOLY - refund);
    }

    /**
    * @notice Checks whether the cap has been reached.
    * @return bool Whether the cap was reached
    */
    function capReached() public view returns(bool) {
        return totalTokensSold >= cap;
    }

    /**
     * @notice Return the total no. of tokens sold
     * @return uint256 Number of tokens sold
     */
    function getTokensSold() external view returns (uint256) {
        return totalTokensSold;
    }

    /**
     * @notice Return the permissions flag that are associated with STO
     * @return bytes32[] Array of permission flags
     */
    function getPermissions() public view override returns(bytes32[] memory) {
        bytes32[] memory allPermissions = new bytes32[](1);
        allPermissions[0] = OPERATOR;
        return allPermissions;
    }

    /**
     * @notice Return the STO details
     * @return startTime Unixtimestamp at which offering gets start
     * @return endTime Unixtimestamp at which offering ends
     * @return cap Number of token base units this STO will be allowed to sell to investors
     * @return rate Token units a buyer gets(multiplied by 10^18) per wei / base unit of POLY
     * @return fundsRaised Amount of funds raised
     * @return investorCount Number of individual investors this STO have
     * @return tokensSold Amount of tokens get sold
     * @return isPolyFundRaiseType Boolean value to justify whether the fund raise type is POLY or not
     */
    function getSTODetails() public view returns(
        uint256 startTime, 
        uint256 endTime, 
        uint256 cap, 
        uint256 rate, 
        uint256 fundsRaised, 
        uint256 investorCount, 
        uint256 tokensSold, 
        bool isPolyFundRaiseType
    ) {
        return (
            startTime, 
            endTime, 
            cap, 
            rate, 
            (fundRaiseTypes[uint8(FundRaiseType.POLY)]) ? fundsRaised[uint8(FundRaiseType.POLY)] : fundsRaised[uint8(FundRaiseType.ETH)], 
            investorCount, 
            totalTokensSold, 
            (fundRaiseTypes[uint8(FundRaiseType.POLY)])
        );
    }

    // -----------------------------------------
    // Internal interface (extensible)
    // -----------------------------------------
    /**
      * Processing the purchase as well as verify the required validations
      * @param _beneficiary Address performing the token purchase
      * @param _investedAmount Value in wei involved in the purchase
      * @return refund Amount to be refunded
    */
    function _processTx(address _beneficiary, uint256 _investedAmount) internal returns(uint256 refund) {
        _preValidatePurchase(_beneficiary, _investedAmount);
        // calculate token amount to be created
        uint256 tokens;
        (tokens, refund) = _getTokenAmount(_investedAmount);
        _investedAmount = _investedAmount - refund;

        // update state
        if (fundRaiseTypes[uint8(FundRaiseType.POLY)]) {
            fundsRaised[uint8(FundRaiseType.POLY)] = fundsRaised[uint8(FundRaiseType.POLY)] + _investedAmount;
        } else {
            fundsRaised[uint8(FundRaiseType.ETH)] = fundsRaised[uint8(FundRaiseType.ETH)] + _investedAmount;
        }
        totalTokensSold = totalTokensSold + tokens;

        _processPurchase(_beneficiary, tokens);
        emit TokenPurchase(msg.sender, _beneficiary, _investedAmount, tokens);
    }

    /**
    * @notice Validation of an incoming purchase.
      Use require statements to revert state when conditions are not met. Use super to concatenate validations.
    * @param _beneficiary Address performing the token purchase
    * @param _investedAmount Value in wei involved in the purchase
    */
    function _preValidatePurchase(address _beneficiary, uint256 _investedAmount) internal view {
        require(_beneficiary != address(0), "Beneficiary address should not be 0x");
        require(_investedAmount != 0, "Amount invested should not be equal to 0");
        require(_canBuy(_beneficiary), "Unauthorized");
        /*solium-disable-next-line security/no-block-members*/
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Offering is closed/Not yet started");
    }

    /**
    * @notice Source of tokens.
      Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
    * @param _beneficiary Address performing the token purchase
    * @param _tokenAmount Number of tokens to be emitted
    */
    function _deliverTokens(address _beneficiary, uint256 _tokenAmount) internal {
        securityToken.issue(_beneficiary, _tokenAmount, "");
    }

    /**
    * @notice Executed when a purchase has been validated and is ready to be executed. Not necessarily emits/sends tokens.
    * @param _beneficiary Address receiving the tokens
    * @param _tokenAmount Number of tokens to be purchased
    */
    function _processPurchase(address _beneficiary, uint256 _tokenAmount) internal {
        if (investors[_beneficiary] == 0) {
            investorCount = investorCount + 1;
        }
        investors[_beneficiary] = investors[_beneficiary] + _tokenAmount;

        _deliverTokens(_beneficiary, _tokenAmount);
    }

    /**
    * @notice Overrides to extend the way in which ether is converted to tokens.
    * @param _investedAmount Value in wei to be converted into tokens
    * @return tokens Number of tokens that can be purchased with the specified _investedAmount
    * @return refund Remaining amount that should be refunded to the investor
    */
    function _getTokenAmount(uint256 _investedAmount) internal view returns(uint256 tokens, uint256 refund) {
        tokens = _investedAmount * rate;
        tokens = tokens / (uint256(10) ** 18);
        if (totalTokensSold + tokens > cap) {
            tokens = cap - totalTokensSold;
        }
        uint256 granularity = securityToken.granularity();
        tokens = tokens / granularity;
        tokens = tokens * granularity;
        require(tokens > 0, "Cap reached");
        refund = _investedAmount - ((tokens * (uint256(10) ** 18)) / rate);
    }

    /**
    * @notice Determines how ETH is stored/forwarded on purchases.
    * @param _refund Amount to be refunded
    */
    function _forwardFunds(uint256 _refund) internal {
        payable(wallet).transfer(msg.value - _refund);
        payable(msg.sender).transfer(_refund);
    }

    /**
     * @notice Internal function used to forward the POLY raised to beneficiary address
     * @param _beneficiary Address of the funds reciever
     * @param _to Address who wants to ST-20 tokens
     * @param _fundsAmount Amount invested by _to
     */
    function _forwardPoly(address _beneficiary, address _to, uint256 _fundsAmount) internal {
        polyToken.transferFrom(_beneficiary, _to, _fundsAmount);
    }
}
