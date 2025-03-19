/**
 * DISCLAIMER: Under certain conditions, the function pushDividendPayment
 * may fail due to block gas limits.
 * If the total number of investors that ever held tokens is greater than ~15,000 then
 * the function may fail. If this happens investors can pull their dividends, or the Issuer
 * can use pushDividendPaymentToAddresses to provide an explict address list in batches
 */
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import ".././ICheckpoint.sol";
import "../../../storage/modules/Checkpoint/Dividend/DividendCheckpointStorage.sol";
import "../../Module.sol";

/**
 * @title Checkpoint module for issuing ether dividends
 * @dev abstract contract
 */
contract DividendCheckpoint is DividendCheckpointStorage, ICheckpoint, Module {
    using SafeMath for uint256;
    uint256 internal constant e18 = uint256(10) ** uint256(18);

    event SetDefaultExcludedAddresses(address[] _excluded);
    event SetWithholding(address[] _investors, uint256[] _withholding);
    event SetWithholdingFixed(address[] _investors, uint256 _withholding);
    event SetWallet(address indexed _oldWallet, address indexed _newWallet);
    event UpdateDividendDates(uint256 indexed _dividendIndex, uint256 _maturity, uint256 _expiry);

    function _validDividendIndex(uint256 _dividendIndex) internal view {
        require(_dividendIndex < dividends.length, "Invalid dividend");
        require(!dividends[_dividendIndex].reclaimed, "Dividend reclaimed");
        /*solium-disable-next-line security/no-block-members*/
        require(block.timestamp >= dividends[_dividendIndex].maturity, "Dividend maturity in future");
        /*solium-disable-next-line security/no-block-members*/
        require(block.timestamp < dividends[_dividendIndex].expiry, "Dividend expiry in past");
    }

    /**
     * @notice Function used to intialize the contract variables
     * @param _wallet Ethereum account address to receive reclaimed dividends and tax
     */
    function configure(
        address payable _wallet
    ) public onlyFactory {
        _setWallet(_wallet);
    }

    /**
    * @notice Init function i.e generalise function to maintain the structure of the module contract
    * @return bytes4 Function selector
    */
    function getInitFunction() public pure returns(bytes4) {
        return this.configure.selector;
    }

    /**
     * @notice Function used to change wallet address
     * @param _wallet Ethereum account address to receive reclaimed dividends and tax
     */
    function changeWallet(address payable _wallet) external {
        _onlySecurityTokenOwner();
        _setWallet(_wallet);
    }

    function _setWallet(address payable _wallet) internal {
        emit SetWallet(wallet, _wallet);
        wallet = _wallet;
    }

    /**
     * @notice Return the default excluded addresses
     * @return List of excluded addresses
     */
    function getDefaultExcluded() external view returns(address[] memory) {
        return excluded;
    }

    /**
     * @notice Returns the treasury wallet address
     * @return Treasury wallet address
     */
    function getTreasuryWallet() public view returns(address payable) {
        if (wallet == address(0)) {
            address payable treasuryWallet = payable(IDataStore(getDataStore()).getAddress(TREASURY));
            require(address(treasuryWallet) != address(0), "Invalid address");
            return treasuryWallet;
        }
        else
            return wallet;
    }

    /**
     * @notice Creates a checkpoint on the security token
     * @return Checkpoint ID
     */
    function createCheckpoint() public withPerm(OPERATOR) returns(uint256) {
        return securityToken.createCheckpoint();
    }

    /**
     * @notice Function to clear and set list of excluded addresses used for future dividends
     * @param _excluded Addresses of investors
     */
    function setDefaultExcluded(address[] memory _excluded) public withPerm(ADMIN) {
        require(_excluded.length <= EXCLUDED_ADDRESS_LIMIT, "Too many excluded addresses");
        for (uint256 j = 0; j < _excluded.length; j++) {
            require(_excluded[j] != address(0), "Invalid address");
            for (uint256 i = j + 1; i < _excluded.length; i++) {
                require(_excluded[j] != _excluded[i], "Duplicate exclude address");
            }
        }
        excluded = _excluded;
        emit SetDefaultExcludedAddresses(_excluded);
    }

    /**
     * @notice Function to set withholding tax rates for investors
     * @param _investors Addresses of investors
     * @param _withholding Withholding tax for individual investors (multiplied by 10**16)
     */
    function setWithholding(address[] memory _investors, uint256[] memory _withholding) public withPerm(ADMIN) {
        require(_investors.length == _withholding.length, "Array length mismatch");
        for (uint256 i = 0; i < _investors.length; i++) {
            require(_investors[i] != address(0), "Invalid address");
            require(_withholding[i] <= 10 ** 18, "Invalid withholding tax");
            withholdingTax[_investors[i]] = _withholding[i];
        }
        emit SetWithholding(_investors, _withholding);
    }

    /**
     * @notice Function to set withholding tax rates for investors
     * @param _investors Addresses of investors
     * @param _withholding Withholding tax for all investors (multiplied by 10**16)
     */
    function setWithholdingFixed(address[] memory _investors, uint256 _withholding) public withPerm(ADMIN) {
        require(_withholding <= 10 ** 18, "Invalid withholding tax");
        for (uint256 i = 0; i < _investors.length; i++) {
            require(_investors[i] != address(0), "Invalid address");
            withholdingTax[_investors[i]] = _withholding;
        }
        emit SetWithholdingFixed(_investors, _withholding);
    }

    /**
     * @notice Calculate amount of dividends claimable
     * @param _dividendIndex Dividend to calculate
     * @param _payee Investor to calculate
     * @return claim Amount of dividend to claim
     * @return withheld Amount of tax withheld
     */
    function calculateDividend(uint256 _dividendIndex, address _payee) public view returns(uint256 claim, uint256 withheld) {
        require(_dividendIndex < dividends.length, "Invalid dividend");
        Dividend storage dividend = dividends[_dividendIndex];
        if (dividend.dividendExcluded[_payee] || dividend.claimed[_payee]) {
            return (0, 0);
        }
        uint256 balance = securityToken.balanceOfAt(_payee, dividend.checkpointId);
        claim = balance.mul(dividend.amount).div(dividend.totalSupply);
        withheld = claim.mul(withholdingTax[_payee]).div(10 ** 18);
    }

    /**
     * @notice Calculate amount of dividends claimable for multiple dividends
     * @param _dividendIndices Indices of the dividends to calculate
     * @param _payee Investor to calculate
     * @return claims Array of dividend amounts to claim
     * @return withheld Array of tax amounts to withhold
     */
    function calculateDividendWithCheckpoints(uint256[] memory _dividendIndices, address _payee) public view returns(uint256[] memory claims, uint256[] memory withheld) {
        claims = new uint256[](_dividendIndices.length);
        withheld = new uint256[](_dividendIndices.length);
        for (uint256 i = 0; i < _dividendIndices.length; i++) {
            (claims[i], withheld[i]) = calculateDividend(_dividendIndices[i], _payee);
        }
    }

    /**
     * @notice Update dividend dates
     * @param _dividendIndex Dividend to update
     * @param _maturity Updated maturity date
     * @param _expiry Updated expiry date
     */
    function updateDividendDates(uint256 _dividendIndex, uint256 _maturity, uint256 _expiry) public withPerm(ADMIN) {
        require(_dividendIndex < dividends.length, "Invalid dividend");
        require(_expiry > _maturity, "Invalid expiry");
        /*solium-disable-next-line security/no-block-members*/
        require(_maturity >= block.timestamp, "Invalid maturity");
        require(!dividends[_dividendIndex].reclaimed, "Dividend reclaimed");
        dividends[_dividendIndex].maturity = _maturity;
        dividends[_dividendIndex].expiry = _expiry;
        emit UpdateDividendDates(_dividendIndex, _maturity, _expiry);
    }

    /**
     * @notice Get the index according to the checkpoint id
     * @param _checkpointId Checkpoint id to query
     * @return uint256 Index of the checkpoint
     */
    function getCheckpointIndex(uint256 _checkpointId) internal view returns(uint256) {
        uint256 count = securityToken.getCheckpointTimes().length;
        for (uint256 i = 0; i < count; i++) {
            if (securityToken.getCheckpointTimes()[i] == _checkpointId)
                return i;
        }
        revert("Checkpoint not found");
    }

    /**
     * @notice Retrieves the data of the dividend
     * @param _dividendIndex Dividend to retrieve
     * @return created Creation timestamp
     * @return maturity Maturity timestamp
     * @return expiry Expiry timestamp
     * @return amount Amount of tokens to distribute
     * @return claimedAmount Amount of tokens that have been claimed
     * @return name Name of the dividend
     */
    function getDividendsData(uint256 _dividendIndex) external view returns(
        uint256 created,
        uint256 maturity,
        uint256 expiry,
        uint256 amount,
        uint256 claimedAmount,
        bytes32 name)
    {
        created = dividends[_dividendIndex].created;
        maturity = dividends[_dividendIndex].maturity;
        expiry = dividends[_dividendIndex].expiry;
        amount = dividends[_dividendIndex].amount;
        claimedAmount = dividends[_dividendIndex].claimedAmount;
        name = dividends[_dividendIndex].name;
    }

    /**
     * @notice Retrieves list of investors, their claim status and whether they are excluded
     * @param _dividendIndex Dividend to withdraw from
     * @return investors List of investors
     * @return resultClaimed Whether investor has claimed
     * @return resultExcluded Whether investor is excluded
     * @return resultWithheld Amount of withheld tax (estimate if not claimed)
     * @return resultAmount Amount of claim (estimate if not claimeed)
     * @return resultBalance Investor balance
     */
    function getDividendProgress(uint256 _dividendIndex) external view returns (
        address[] memory investors,
        bool[] memory resultClaimed,
        bool[] memory resultExcluded,
        uint256[] memory resultWithheld,
        uint256[] memory resultAmount,
        uint256[] memory resultBalance)
    {
        require(_dividendIndex < dividends.length, "Invalid dividend");
        //Get list of Investors
        Dividend storage dividend = dividends[_dividendIndex];
        uint256 checkpointId = dividend.checkpointId;
        investors = securityToken.getInvestorsAt(checkpointId);
        resultClaimed = new bool[](investors.length);
        resultExcluded = new bool[](investors.length);
        resultWithheld = new uint256[](investors.length);
        resultAmount = new uint256[](investors.length);
        resultBalance = new uint256[](investors.length);
        for (uint256 i; i < investors.length; i++) {
            resultClaimed[i] = dividend.claimed[investors[i]];
            resultExcluded[i] = dividend.dividendExcluded[investors[i]];
            resultBalance[i] = securityToken.balanceOfAt(investors[i], dividend.checkpointId);
            if (!resultExcluded[i]) {
                if (resultClaimed[i]) {
                    resultWithheld[i] = dividend.withheld[investors[i]];
                    resultAmount[i] = resultBalance[i].mul(dividend.amount).div(dividend.totalSupply).sub(resultWithheld[i]);
                } else {
                    (uint256 claim, uint256 withheld) = calculateDividend(_dividendIndex, investors[i]);
                    resultWithheld[i] = withheld;
                    resultAmount[i] = claim.sub(withheld);
                }
            }
        }
    }

    /**
     * @notice Retrieves list of investors, their balances, and their current withholding tax percentage
     * @param _checkpointId Checkpoint Id to query for
     * @return investors List of investors
     * @return balances Investor balances
     * @return withholdings Investor withheld percentages
     */
    function getCheckpointData(uint256 _checkpointId) external view returns (address[] memory investors, uint256[] memory balances, uint256[] memory withholdings) {
        require(_checkpointId <= securityToken.currentCheckpointId(), "Invalid checkpoint");
        investors = securityToken.getInvestorsAt(_checkpointId);
        balances = new uint256[](investors.length);
        withholdings = new uint256[](investors.length);
        for (uint256 i; i < investors.length; i++) {
            balances[i] = securityToken.balanceOfAt(investors[i], _checkpointId);
            withholdings[i] = withholdingTax[investors[i]];
        }
    }

    /**
     * @notice Checks whether an address is excluded from claiming a dividend
     * @param _investor Address to check
     * @param _dividendIndex Dividend to check
     * @return bool Whether the address is excluded
     */
    function isExcluded(address _investor, uint256 _dividendIndex) external view returns (bool) {
        require(_dividendIndex < dividends.length, "Invalid dividend");
        return dividends[_dividendIndex].dividendExcluded[_investor];
    }

    /**
     * @notice Checks whether an address has claimed a dividend
     * @param _investor Address to check
     * @param _dividendIndex Dividend to check
     * @return bool Whether the address has claimed
     */
    function isClaimed(address _investor, uint256 _dividendIndex) external view returns (bool) {
        require(_dividendIndex < dividends.length, "Invalid dividend");
        return dividends[_dividendIndex].claimed[_investor];
    }

    /**
     * @notice Return the permissions flag that are associated with this module
     * @return bytes32[] Array of permission flags
     */
    function getPermissions() public view returns(bytes32[] memory) {
        bytes32[] memory allPermissions = new bytes32[](2);
        allPermissions[0] = ADMIN;
        allPermissions[1] = OPERATOR;
        return allPermissions;
    }
}
