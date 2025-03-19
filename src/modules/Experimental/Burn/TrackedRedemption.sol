// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../Burn/IBurn.sol";
import "../../Module.sol";

/**
 * @title Burn module for burning tokens and keeping track of burnt amounts
 */
contract TrackedRedemption is IBurn, Module {
    using SafeMath for uint256;

    mapping(address => uint256) public redeemedTokens;

    event Redeemed(address indexed _investor, uint256 _value);

    /**
     * @notice Constructor
     * @param _securityToken Address of the security token
     * @param _polyToken Address of the polytoken
     */
    constructor(address _securityToken, address _polyToken) Module(_securityToken, _polyToken) {
    }

    /**
     * @notice This function returns the signature of configure function
     * @return bytes4 Function signature
     */
    function getInitFunction() public pure override returns(bytes4) {
        return bytes4(0);
    }

    /**
     * @notice To redeem tokens and track redemptions
     * @param _value The number of tokens to redeem
     */
    function redeemTokens(uint256 _value) public {
        securityToken.redeemFrom(msg.sender, _value, "");
        redeemedTokens[msg.sender] = redeemedTokens[msg.sender].add(_value);
        emit Redeemed(msg.sender, _value);
    }

    /**
     * @notice Returns the permissions flag that are associated with TrackedRedemption
     * @return allPermissions Array of permission flags
     */
    function getPermissions() public view override returns(bytes32[] memory allPermissions) {
        allPermissions = new bytes32[](0);
        return allPermissions;
    }
}
