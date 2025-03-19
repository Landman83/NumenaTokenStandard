// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../proxy/Proxy.sol";
import "./DataStoreStorage.sol";

/**
 * @title DataStoreProxy Proxy
 */
contract DataStoreProxy is DataStoreStorage, Proxy {

    /**
    * @notice Constructor
    * @param _implementationAddress representing the address of the new implementation to be set
    */
    constructor(
        address _implementationAddress
    )
    {
        require(
            _implementationAddress != address(0),
            "Implementation address should not be 0x"
        );
        _setImplementation(_implementationAddress);
    }

    /**
    * @notice Internal function to provide the address of the implementation contract
    * @return Address of the implementation
    */
    function _implementation() internal view override returns(address) {
        return __implementation;
    }

    /**
     * @notice Sets the implementation address
     * @param _implementationAddress Address of the new implementation
     */
    function _setImplementation(address _implementationAddress) internal {
        __implementation = _implementationAddress;
    }
}
