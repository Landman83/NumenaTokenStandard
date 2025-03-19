// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../TransferManager/TransferManager.sol";
import "../../../interfaces/ISecurityToken.sol";

/**
 * @title Transfer Manager module for core transfer validation functionality
 */
contract KYCTransferManager is TransferManager {

    bytes32 public constant KYC_NUMBER = "KYC_NUMBER"; //We will standardize what key to use for what.
    bytes32 public constant KYC_ARRAY = "KYC_ARRAY";

    /**
     * @notice Constructor
     * @param _securityToken Address of the security token
     * @param _polyAddress Address of the polytoken
     */
    constructor (address _securityToken, address _polyAddress)
        Module(_securityToken, _polyAddress)
    {
    }

    /**
     * @notice This function returns the signature of configure function
     * @return bytes4 Configure function signature
     */
    function getInitFunction() public pure override returns (bytes4) {
        return bytes4(0);
    }

    /**
     * @notice Execute transfer validation
     * @param _from Address of the sender
     * @param _to Address of the receiver
     * @param _amount Amount of tokens to transfer
     * @param _data Additional data attached to the transfer
     * @return Result indicating if transfer is valid, invalid, or NA
     */
    function executeTransfer(address _from, address _to, uint256 _amount, bytes calldata _data)
        external
        override
        returns (Result)
    {
        (Result success,) = verifyTransfer(_from, _to, _amount, _data);
        return success;
    }

    /**
     * @notice Verify if a transfer is valid
     * @param _from Address of the sender
     * @param _to Address of the receiver
     * @param _amount Amount of tokens to transfer
     * @param _data Additional data attached to the transfer
     * @return Result indicating if transfer is valid, invalid, or NA
     * @return bytes32 Reason code
     */
    function verifyTransfer(address /*_from*/, address _to, uint256 /*_amount*/, bytes memory /* _data */) 
        public 
        view 
        override 
        returns(Result, bytes32) 
    {
        if (!paused() && checkKYC(_to)) {
            return (Result.VALID, bytes32(uint256(uint160(address(this))) << 96));
        }
        return (Result.NA, bytes32(0));
    }

    /**
     * @notice Modify KYC status for an investor
     * @param _investor Address of the investor
     * @param _kycStatus New KYC status
     */
    function modifyKYC(address _investor, bool _kycStatus) public onlyRole(ADMIN) {
        _modifyKYC(_investor, _kycStatus);
    }

    /**
     * @notice Internal function to modify KYC status
     * @param _investor Address of the investor
     * @param _kycStatus New KYC status
     */
    function _modifyKYC(address _investor, bool _kycStatus) internal {
        IDataStore dataStore = getDataStore();
        bytes32 key = _getKYCKey(_investor);
        uint256 kycNumber = dataStore.getUint256(key); //index in address array + 1
        uint256 kycTotal = dataStore.getAddressArrayLength(KYC_ARRAY);
        if(_kycStatus) {
            require(kycNumber == 0, "KYC exists");
            dataStore.setUint256(key, kycTotal + 1);
            dataStore.insertAddress(KYC_ARRAY, _investor);
        } else {
            require(kycNumber != 0, "KYC does not exist");
            address lastAddress = dataStore.getAddressArrayElement(KYC_ARRAY, kycTotal - 1);
            dataStore.deleteAddress(KYC_ARRAY, kycNumber - 1);

            //Corrects the index of last element as delete functions move last element to index.
            dataStore.setUint256(_getKYCKey(lastAddress), kycNumber);
        }
        //Alternatively, we can just emit an event and not maintain the KYC array on chain.
        //I am maintaining the array to showcase how it can be done in cases where it might be needed.
    }

    /**
     * @notice Get all addresses with KYC
     * @return Array of addresses with KYC
     */
    function getKYCAddresses() public view returns(address[] memory) {
        IDataStore dataStore = getDataStore();
        return dataStore.getAddressArray(KYC_ARRAY);
    }

    /**
     * @notice Check if an investor has KYC
     * @param _investor Address of the investor
     * @return kyc True if investor has KYC
     */
    function checkKYC(address _investor) public view returns (bool kyc) {
        bytes32 key = _getKYCKey(_investor);
        IDataStore dataStore = getDataStore();
        if (dataStore.getUint256(key) > 0)
            kyc = true;
    }

    /**
     * @notice Generate a unique key for KYC storage
     * @param _identity Address of the investor
     * @return bytes32 Unique key
     */
    function _getKYCKey(address _identity) internal pure returns(bytes32) {
        return bytes32(keccak256(abi.encodePacked(KYC_NUMBER, _identity)));
    }

    /**
     * @notice Return the permissions flag that are associated with this module
     * @return bytes32 array of permissions
     */
    function getPermissions() public view override returns(bytes32[] memory) {
        bytes32[] memory allPermissions = new bytes32[](1);
        allPermissions[0] = ADMIN;
        return allPermissions;
    }
}