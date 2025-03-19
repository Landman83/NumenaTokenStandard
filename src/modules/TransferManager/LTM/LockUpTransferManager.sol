// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../TransferManager/TransferManager.sol";
import "./LockUpTransferManagerStorage.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract LockUpTransferManager is LockUpTransferManagerStorage, TransferManager {

    event AddLockUpToUser(
        address indexed _userAddress,
        bytes32 indexed _lockupName
    );

    event RemoveLockUpFromUser(
        address indexed _userAddress,
        bytes32 indexed _lockupName
    );

    event ModifyLockUpType(
        uint256 _lockupAmount,
        uint256 _startTime,
        uint256 _lockUpPeriodSeconds,
        uint256 _releaseFrequencySeconds,
        bytes32 indexed _lockupName
    );

    event AddNewLockUpType(
        bytes32 indexed _lockupName,
        uint256 _lockupAmount,
        uint256 _startTime,
        uint256 _lockUpPeriodSeconds,
        uint256 _releaseFrequencySeconds
    );

    event RemoveLockUpType(bytes32 indexed _lockupName);

    /**
     * @notice Constructor
     * @param _securityToken Address of the security token
     * @param _polyAddress Address of the polytoken
     */
    constructor(address _securityToken, address _polyAddress)
        Module(_securityToken, _polyAddress)
    {
    }

    /**
     * @notice Used to verify the transfer transaction and prevent locked up tokens from being transferred
     * @param _from Address of the sender
     * @param _amount The amount of tokens to transfer
     * @return Result indicating if transfer is valid, invalid, or NA
     */
    function executeTransfer(address _from, address /*_to*/, uint256 _amount, bytes calldata /*_data*/) 
        external 
        override 
        returns(Result) 
    {
        (Result success,) = _verifyTransfer(_from, _amount);
        return success;
    }

    /**
     * @notice Used to verify the transfer transaction and prevent locked up tokens from being transferred
     * @param _from Address of the sender
     * @param _amount The amount of tokens to transfer
     * @return Result indicating if transfer is valid, invalid, or NA
     * @return bytes32 Reason code
     */
    function verifyTransfer(
        address _from,
        address /* _to*/,
        uint256 _amount,
        bytes memory /* _data */
    )
        public
        view
        override
        returns(Result, bytes32)
    {
        return _verifyTransfer(_from, _amount);
    }

    /**
     * @notice Internal function to verify transfer
     * @param _from Address of the sender
     * @param _amount The amount of tokens to transfer
     * @return Result indicating if transfer is valid, invalid, or NA
     * @return bytes32 Reason code
     */
    function _verifyTransfer(address _from, uint256 _amount) internal view returns(Result, bytes32) {
        if (paused()) {
            return (Result.NA, bytes32(0));
        }
        
        uint256 lockedAmount = getLockedTokenToUser(_from);
        if (lockedAmount == 0) {
            return (Result.NA, bytes32(0));
        }
        
        uint256 balance = securityToken.balanceOf(_from);
        if (balance.sub(_amount) >= lockedAmount) {
            return (Result.NA, bytes32(0));
        }
        
        return (Result.INVALID, bytes32(uint256(uint160(address(this))) << 96));
    }

    /**
     * @notice Used to add a new lockup type
     * @param _lockupAmount Amount to be locked
     * @param _startTime When this lockup starts
     * @param _lockUpPeriodSeconds Total period of lockup (seconds)
     * @param _releaseFrequencySeconds How often to release a tranche of tokens (seconds)
     * @param _lockupName Name of the lockup
     */
    function addNewLockUpType(
        uint256 _lockupAmount,
        uint256 _startTime,
        uint256 _lockUpPeriodSeconds,
        uint256 _releaseFrequencySeconds,
        bytes32 _lockupName
    )
        external
        withPerm(ADMIN)
    {
        require(_lockupName != bytes32(0), "Invalid name");
        require(lockups[_lockupName].lockupAmount == 0, "Already exists");
        require(_releaseFrequencySeconds != 0, "Invalid frequency");
        require(_lockUpPeriodSeconds != 0, "Invalid period");
        require(_lockUpPeriodSeconds >= _releaseFrequencySeconds, "Invalid frequency");
        require(_lockUpPeriodSeconds % _releaseFrequencySeconds == 0, "Invalid frequency");
        
        lockups[_lockupName] = LockUp(
            _lockupAmount,
            _startTime,
            _lockUpPeriodSeconds,
            _releaseFrequencySeconds
        );
        
        lockupArray.push(_lockupName);
        
        emit AddNewLockUpType(
            _lockupName,
            _lockupAmount,
            _startTime,
            _lockUpPeriodSeconds,
            _releaseFrequencySeconds
        );
    }

    /**
     * @notice Used to remove a lockup type
     * @param _lockupName Name of the lockup to remove
     */
    function removeLockUpType(bytes32 _lockupName) external withPerm(ADMIN) {
        require(lockups[_lockupName].lockupAmount != 0, "Lockup not found");
        require(lockupToUsers[_lockupName].length == 0, "Users attached");
        
        uint256 lockupIndex;
        uint256 arrayLength = lockupArray.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            if (lockupArray[i] == _lockupName) {
                lockupIndex = i;
                break;
            }
        }
        
        if (lockupIndex != arrayLength - 1) {
            lockupArray[lockupIndex] = lockupArray[arrayLength - 1];
        }
        
        lockupArray.pop();
        delete lockups[_lockupName];
        
        emit RemoveLockUpType(_lockupName);
    }

    /**
     * @notice Used to modify a lockup type
     * @param _lockupAmount Amount to be locked
     * @param _startTime When this lockup starts
     * @param _lockUpPeriodSeconds Total period of lockup (seconds)
     * @param _releaseFrequencySeconds How often to release a tranche of tokens (seconds)
     * @param _lockupName Name of the lockup to modify
     */
    function modifyLockUpType(
        uint256 _lockupAmount,
        uint256 _startTime,
        uint256 _lockUpPeriodSeconds,
        uint256 _releaseFrequencySeconds,
        bytes32 _lockupName
    )
        external
        withPerm(ADMIN)
    {
        require(lockups[_lockupName].lockupAmount != 0, "Lockup not found");
        require(_releaseFrequencySeconds != 0, "Invalid frequency");
        require(_lockUpPeriodSeconds != 0, "Invalid period");
        require(_lockUpPeriodSeconds >= _releaseFrequencySeconds, "Invalid frequency");
        require(_lockUpPeriodSeconds % _releaseFrequencySeconds == 0, "Invalid frequency");
        
        lockups[_lockupName] = LockUp(
            _lockupAmount,
            _startTime,
            _lockUpPeriodSeconds,
            _releaseFrequencySeconds
        );
        
        emit ModifyLockUpType(
            _lockupAmount,
            _startTime,
            _lockUpPeriodSeconds,
            _releaseFrequencySeconds,
            _lockupName
        );
    }

    /**
     * @notice Used to add a lockup to a user
     * @param _userAddress Address of the user
     * @param _lockupName Name of the lockup to add
     */
    function addLockUpByName(address _userAddress, bytes32 _lockupName) external withPerm(ADMIN) {
        require(lockups[_lockupName].lockupAmount != 0, "Lockup not found");
        require(userToLockupIndex[_userAddress][_lockupName] == 0, "Already locked");
        
        userToLockups[_userAddress].push(_lockupName);
        userToLockupIndex[_userAddress][_lockupName] = userToLockups[_userAddress].length;
        
        lockupToUsers[_lockupName].push(_userAddress);
        lockupToUserIndex[_lockupName][_userAddress] = lockupToUsers[_lockupName].length;
        
        emit AddLockUpToUser(_userAddress, _lockupName);
    }

    /**
     * @notice Used to add a lockup to multiple users
     * @param _userAddresses Addresses of the users
     * @param _lockupName Name of the lockup to add
     */
    function addLockUpByNameMulti(address[] calldata _userAddresses, bytes32 _lockupName) external withPerm(ADMIN) {
        require(lockups[_lockupName].lockupAmount != 0, "Lockup not found");
        
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            if (userToLockupIndex[_userAddresses[i]][_lockupName] == 0) {
                userToLockups[_userAddresses[i]].push(_lockupName);
                userToLockupIndex[_userAddresses[i]][_lockupName] = userToLockups[_userAddresses[i]].length;
                
                lockupToUsers[_lockupName].push(_userAddresses[i]);
                lockupToUserIndex[_lockupName][_userAddresses[i]] = lockupToUsers[_lockupName].length;
                
                emit AddLockUpToUser(_userAddresses[i], _lockupName);
            }
        }
    }

    /**
     * @notice Used to remove a lockup from a user
     * @param _userAddress Address of the user
     * @param _lockupName Name of the lockup to remove
     */
    function removeLockUpFromUser(address _userAddress, bytes32 _lockupName) external withPerm(ADMIN) {
        require(userToLockupIndex[_userAddress][_lockupName] != 0, "No lockup found");
        
        // Remove lockup from user's list
        uint256 userIndex = userToLockupIndex[_userAddress][_lockupName] - 1;
        uint256 userLockupCount = userToLockups[_userAddress].length;
        
        if (userIndex != userLockupCount - 1) {
            bytes32 lastLockup = userToLockups[_userAddress][userLockupCount - 1];
            userToLockups[_userAddress][userIndex] = lastLockup;
            userToLockupIndex[_userAddress][lastLockup] = userIndex + 1;
        }
        
        userToLockups[_userAddress].pop();
        delete userToLockupIndex[_userAddress][_lockupName];
        
        // Remove user from lockup's list
        uint256 lockupIndex = lockupToUserIndex[_lockupName][_userAddress] - 1;
        uint256 lockupUserCount = lockupToUsers[_lockupName].length;
        
        if (lockupIndex != lockupUserCount - 1) {
            address lastUser = lockupToUsers[_lockupName][lockupUserCount - 1];
            lockupToUsers[_lockupName][lockupIndex] = lastUser;
            lockupToUserIndex[_lockupName][lastUser] = lockupIndex + 1;
        }
        
        lockupToUsers[_lockupName].pop();
        delete lockupToUserIndex[_lockupName][_userAddress];
        
        emit RemoveLockUpFromUser(_userAddress, _lockupName);
    }

    /**
     * @notice Used to remove a lockup from multiple users
     * @param _userAddresses Addresses of the users
     * @param _lockupName Name of the lockup to remove
     */
    function removeLockUpFromUserMulti(address[] calldata _userAddresses, bytes32 _lockupName) external withPerm(ADMIN) {
        for (uint256 i = 0; i < _userAddresses.length; i++) {
            if (userToLockupIndex[_userAddresses[i]][_lockupName] != 0) {
                // Remove lockup from user's list
                uint256 userIndex = userToLockupIndex[_userAddresses[i]][_lockupName] - 1;
                uint256 userLockupCount = userToLockups[_userAddresses[i]].length;
                
                if (userIndex != userLockupCount - 1) {
                    bytes32 lastLockup = userToLockups[_userAddresses[i]][userLockupCount - 1];
                    userToLockups[_userAddresses[i]][userIndex] = lastLockup;
                    userToLockupIndex[_userAddresses[i]][lastLockup] = userIndex + 1;
                }
                
                userToLockups[_userAddresses[i]].pop();
                delete userToLockupIndex[_userAddresses[i]][_lockupName];
                
                // Remove user from lockup's list
                uint256 lockupIndex = lockupToUserIndex[_lockupName][_userAddresses[i]] - 1;
                uint256 lockupUserCount = lockupToUsers[_lockupName].length;
                
                if (lockupIndex != lockupUserCount - 1) {
                    address lastUser = lockupToUsers[_lockupName][lockupUserCount - 1];
                    lockupToUsers[_lockupName][lockupIndex] = lastUser;
                    lockupToUserIndex[_lockupName][lastUser] = lockupIndex + 1;
                }
                
                lockupToUsers[_lockupName].pop();
                delete lockupToUserIndex[_lockupName][_userAddresses[i]];
                
                emit RemoveLockUpFromUser(_userAddresses[i], _lockupName);
            }
        }
    }

    /**
     * @notice Get the amount of tokens locked for a user
     * @param _userAddress Address of the user
     * @return Amount of tokens locked
     */
    function getLockedTokenToUser(address _userAddress) public view returns(uint256) {
        uint256 totalLocked = 0;
        bytes32[] memory userLockups = userToLockups[_userAddress];
        
        for (uint256 i = 0; i < userLockups.length; i++) {
            LockUp memory lockup = lockups[userLockups[i]];
            uint256 releaseFrequency = lockup.releaseFrequencySeconds;
            uint256 lockupPeriod = lockup.lockUpPeriodSeconds;
            uint256 startTime = lockup.startTime;
            uint256 lockupAmount = lockup.lockupAmount;
            
            if (block.timestamp < startTime) {
                totalLocked = totalLocked.add(lockupAmount);
            } else if (block.timestamp < startTime.add(lockupPeriod)) {
                uint256 releasedAmount = lockupAmount.mul(block.timestamp.sub(startTime)).div(lockupPeriod);
                releasedAmount = releasedAmount.div(releaseFrequency).mul(releaseFrequency);
                totalLocked = totalLocked.add(lockupAmount.sub(releasedAmount));
            }
        }
        
        return totalLocked;
    }

    /**
     * @notice Get all lockup names
     * @return Array of lockup names
     */
    function getAllLockups() external view returns(bytes32[] memory) {
        return lockupArray;
    }

    /**
     * @notice Get all lockups for a user
     * @param _user Address of the user
     * @return Array of lockup names
     */
    function getLockupsNamesToUser(address _user) external view returns(bytes32[] memory) {
        return userToLockups[_user];
    }

    /**
     * @notice Get all users for a lockup
     * @param _lockupName Name of the lockup
     * @return Array of user addresses
     */
    function getUsersByLockup(bytes32 _lockupName) external view returns(address[] memory) {
        return lockupToUsers[_lockupName];
    }

    /**
     * @notice Check if arrays have the same length
     * @param _length1 Length of first array
     * @param _length2 Length of second array
     */
    function _checkLengthOfArray(uint256 _length1, uint256 _length2) internal pure {
        require(_length1 == _length2, "Length mismatch");
    }

    /**
     * @notice Return the amount of tokens for a given user as per the partition
     * @param _partition Identifier
     * @param _tokenHolder Whom token amount need to query
     * @param _additionalBalance It is the `_value` that transfer during transfer/transferFrom function call
     * @return Amount of tokens
     */
    function getTokensByPartition(bytes32 _partition, address _tokenHolder, uint256 _additionalBalance) 
        external 
        view 
        override 
        returns(uint256)
    {
        uint256 currentBalance = (msg.sender == address(securityToken)) ? 
            (securityToken.balanceOf(_tokenHolder) + _additionalBalance) : 
            securityToken.balanceOf(_tokenHolder);
            
        uint256 lockedBalance = Math.min(getLockedTokenToUser(_tokenHolder), currentBalance);
        
        if (paused()) {
            return (_partition == UNLOCKED ? currentBalance : 0);
        } else {
            if (_partition == LOCKED)
                return lockedBalance;
            else if (_partition == UNLOCKED)
                return currentBalance - lockedBalance;
        }
        return 0;
    }

    /**
     * @notice This function returns the signature of configure function
     * @return bytes4 Function signature
     */
    function getInitFunction() public pure override returns (bytes4) {
        return bytes4(0);
    }

    /**
     * @notice Returns the permissions flag that are associated with Percentage transfer Manager
     * @return Array of permission flags
     */
    function getPermissions() public view override returns(bytes32[] memory) {
        bytes32[] memory allPermissions = new bytes32[](1);
        allPermissions[0] = ADMIN;
        return allPermissions;
    }
}