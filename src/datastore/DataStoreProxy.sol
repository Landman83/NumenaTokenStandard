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
    * @param _securityToken Address of the security token
    * @param _implementation representing the address of the new implementation to be set
    */
    constructor(
        address _securityToken,
        address _implementation
    )
    {
        require(_implementation != address(0) && _securityToken != address(0),
            "Address should not be 0x"
        );
        securityToken = ISecurityToken(_securityToken);
        __implementation = _implementation;
    }

    /**
    * @notice Internal function to provide the address of the implementation contract
    * @return Address of the implementation
    */
    function _implementation() internal view override returns(address) {
        return __implementation;
    }
}
