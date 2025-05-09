// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./DataStoreProxy.sol";

contract DataStoreFactory {

    address public implementation;

    constructor(address _implementation) {
        require(_implementation != address(0), "Address should not be 0x");
        implementation = _implementation;
    }

    function generateDataStore(address _securityToken) public returns (address) {
        DataStoreProxy dsProxy = new DataStoreProxy(implementation);
        return address(dsProxy);
    }
}
