// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IOracle {
    /**
    * @notice Returns address of oracle currency (0x0 for ETH)
    * @return currency Address of the currency
    */
    function getCurrencyAddress() external view returns(address currency);

    /**
    * @notice Returns symbol of oracle currency (0x0 for ETH)
    * @return symbol Symbol of the currency
    */
    function getCurrencySymbol() external view returns(bytes32 symbol);

    /**
    * @notice Returns denomination of price
    * @return denominatedCurrency Denomination of the price
    */
    function getCurrencyDenominated() external view returns(bytes32 denominatedCurrency);

    /**
    * @notice Returns price - should throw if not valid
    * @return price Current price
    */
    function getPrice() external returns(uint256 price);
}
