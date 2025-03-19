// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Interface for managing permissions
 */
interface IPermissionManager {

    /**
     * @notice Used to check the permission
     * @param _delegate Address of the delegate
     * @param _module Address of the module
     * @param _perm Permission flag
     * @return hasPermission Whether the delegate has the requested permission Permission allowed or not
     */
    function checkPermission(address _delegate, address _module, bytes32 _perm) external view returns(bool);

    /**
     * @notice Used to get the permission flag related the module
     * @param _module Address of the module
     * @return bytes32[] List of permission flags
     */
    function getPermissions(address _module) external view returns(bytes32[] memory);

    /**
     * @notice Returns list of delegates with specific permission for a module
     * @param _module Address of the module
     * @param _perm Permission flag
     * @return delegates List of delegate addresses
     */
    function getAllDelegatesWithPerm(address _module, bytes32 _perm) external view returns(address[] memory delegates);

    /**
     * @notice Used to check if permission is available at the permission manager level
     * @param _module Address of the module
     * @param _perm Permission flag
     * @return hasPermission Whether permission exists or not
     */
    function checkPerm(address _module, bytes32 _perm) external view returns(bool);

    /**
    * @notice Used to add a delegate
    * @param _delegate Ethereum address of the delegate
    * @param _details Details about the delegate i.e `Belongs to financial firm`
    */
    function addDelegate(address _delegate, bytes32 _details) external;

    /**
    * @notice Used to delete a delegate
    * @param _delegate Ethereum address of the delegate
    */
    function deleteDelegate(address _delegate) external;

    /**
    * @notice Used to check if an address is a delegate or not
    * @param _potentialDelegate the address of potential delegate
    * @return bool
    */
    function checkDelegate(address _potentialDelegate) external view returns(bool);

    /**
    * @notice Used to provide/change the permission to the delegate corresponds to the module contract
    * @param _delegate Ethereum address of the delegate
    * @param _module Ethereum contract address of the module
    * @param _perm Permission flag
    * @param _valid Bool flag use to switch on/off the permission
    */
    function changePermission(address _delegate, address _module, bytes32 _perm, bool _valid) external;

    /**
    * @notice Used to change one or more permissions for a single delegate at once
    * @param _delegate Ethereum address of the delegate
    * @param _modules Multiple module matching the multiperms, needs to be same length
    * @param _perms Multiple permission flag needs to be changed
    * @param _valids Bool array consist the flag to switch on/off the permission
    */
    function changePermissionMulti(
        address _delegate,
        address[] calldata _modules,
        bytes32[] calldata _perms,
        bool[] calldata _valids
    ) external;

    // This function is commented out because it's already defined above
    /*
    * @notice Used to return all delegates with a given permission and module
    * @param _module Ethereum contract address of the module
    * @param _perm Permission flag
    * @return delegates List of delegate addresses
    */
    // function getAllDelegatesWithPerm(address _module, bytes32 _perm) external view returns(address[] memory delegates);

    /**
    * @notice Used to return all permission of a single or multiple module
    * @dev possible that function get out of gas is there are lot of modules and perm related to them
    * @param _delegate Ethereum address of the delegate
    * @param _types uint8[] of types
    * @return address[] the address array of Modules this delegate has permission
    * @return bytes32[] the permission array of the corresponding Modules
    */
    function getAllModulesAndPermsFromTypes(address _delegate, uint8[] calldata _types) external view returns(
        address[] memory,
        bytes32[] memory
    );

    /**
    * @notice Used to get the Permission flag related the `this` contract
    * @return Array of permission flags
    */
    function getPermissions() external view returns(bytes32[] memory);

    /**
    * @notice Used to get all delegates
    * @return address[]
    */
    function getAllDelegates() external view returns(address[] memory);
}
