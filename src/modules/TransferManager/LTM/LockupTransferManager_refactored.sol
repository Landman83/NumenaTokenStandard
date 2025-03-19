import "./LockUpTransferManagerStorage.sol";
import "openzeppelin-solidity/contracts/math/Math.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import "../../TransferManager/TransferManager.sol";

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "./SafeMath.sol";
import "./IERC20.sol";

contract LockUpTransferManager {
    using SafeMath for uint256;

    address public securityToken;
    address public polyAddress;
    bool public paused;
    
    struct LockUp {
        uint256 lockupAmount;
        uint256 startTime;
        uint256 lockUpPeriodSeconds;
        uint256 releaseFrequencySeconds;
    }

    mapping(bytes32 => LockUp) public lockups;
    mapping(address => bytes32[]) public userToLockups;
    mapping(bytes32 => address[]) public lockupToUsers;
    mapping(address => mapping(bytes32 => uint256)) public userToLockupIndex;
    mapping(bytes32 => mapping(address => uint256)) public lockupToUserIndex;
    bytes32[] public lockupArray;

    event AddLockUpToUser(address indexed userAddress, bytes32 indexed lockupName);
    event RemoveLockUpFromUser(address indexed userAddress, bytes32 indexed lockupName);
    event ModifyLockUpType(uint256 lockupAmount, uint256 startTime, uint256 lockUpPeriodSeconds, uint256 releaseFrequencySeconds, bytes32 indexed lockupName);
    event AddNewLockUpType(bytes32 indexed lockupName, uint256 lockupAmount, uint256 startTime, uint256 lockUpPeriodSeconds, uint256 releaseFrequencySeconds);
    event RemoveLockUpType(bytes32 indexed lockupName);

    constructor(address _securityToken, address _polyAddress) {
        securityToken = _securityToken;
        polyAddress = _polyAddress;
        paused = false;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not an admin");
        _;
    }

    function executeTransfer(address _from, address, uint256 _amount, bytes calldata) external returns (Result) {
        (Result success,) = _verifyTransfer(_from, _amount);
        return success;
    }

    function verifyTransfer(address _from, address, uint256 _amount, bytes memory) public view returns (Result, bytes32) {
        return _verifyTransfer(_from, _amount);
    }

    function _verifyTransfer(address _from, uint256 _amount) internal view returns (Result, bytes32) {
        if (!paused && _from != address(0) && userToLockups[_from].length != 0) {
            return _checkIfValidTransfer(_from, _amount);
        }
        return (Result.NA, bytes32(0));
    }

    function addNewLockUpType(uint256 _lockupAmount, uint256 _startTime, uint256 _lockUpPeriodSeconds, uint256 _releaseFrequencySeconds, bytes32 _lockupName) external onlyAdmin {
        _addNewLockUpType(_lockupAmount, _startTime, _lockUpPeriodSeconds, _releaseFrequencySeconds, _lockupName);
    }

    function getAllLockupData() external view returns (bytes32[] memory lockupNames, uint256[] memory lockupAmounts, uint256[] memory startTimes, uint256[] memory lockUpPeriodSeconds, uint256[] memory releaseFrequencySeconds, uint256[] memory unlockedAmounts) {
        uint256 length = lockupArray.length;
        lockupAmounts = new uint256[](length);
        startTimes = new uint256[](length);
        lockUpPeriodSeconds = new uint256[](length);
        releaseFrequencySeconds = new uint256[](length);
        unlockedAmounts = new uint256[](length);
        lockupNames = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            (lockupAmounts[i], startTimes[i], lockUpPeriodSeconds[i], releaseFrequencySeconds[i], unlockedAmounts[i]) = getLockUp(lockupArray[i]);
            lockupNames[i] = lockupArray[i];
        }
    }

    function getLockUp(bytes32 _lockupName) public view returns (uint256 lockupAmount, uint256 startTime, uint256 lockUpPeriodSeconds, uint256 releaseFrequencySeconds, uint256 unlockedAmount) {
        if (lockups[_lockupName].lockupAmount != 0) {
            return (lockups[_lockupName].lockupAmount, lockups[_lockupName].startTime, lockups[_lockupName].lockUpPeriodSeconds, lockups[_lockupName].releaseFrequencySeconds, _getUnlockedAmountForLockup(_lockupName));
        }
        return (0, 0, 0, 0, 0);
    }

    function getLockedTokenToUser(address _userAddress) public view returns (uint256) {
        require(_userAddress != address(0), "Invalid address");
        bytes32[] memory userLockupNames = userToLockups[_userAddress];
        uint256 totalRemainingLockedAmount = 0;
        for (uint256 i = 0; i < userLockupNames.length; i++) {
            uint256 remainingLockedAmount = lockups[userLockupNames[i]].lockupAmount.sub(_getUnlockedAmountForLockup(userLockupNames[i]));
            totalRemainingLockedAmount = totalRemainingLockedAmount.add(remainingLockedAmount);
        }
        return totalRemainingLockedAmount;
    }

    function _checkIfValidTransfer(address _userAddress, uint256 _amount) internal view returns (Result, bytes32) {
        uint256 totalRemainingLockedAmount = getLockedTokenToUser(_userAddress);
        uint256 currentBalance = IERC20(securityToken).balanceOf(_userAddress);
        if ((currentBalance.sub(_amount)) >= totalRemainingLockedAmount) {
            return (Result.NA, bytes32(0));
        }
        return (Result.INVALID, bytes32(uint256(uint160(address(this))) << 96));
    }

    function _getUnlockedAmountForLockup(bytes32 _lockupName) internal view returns (uint256) {
        if (lockups[_lockupName].startTime > block.timestamp) {
            return 0;
        } else if (lockups[_lockupName].startTime.add(lockups[_lockupName].lockUpPeriodSeconds) <= block.timestamp) {
            return lockups[_lockupName].lockupAmount;
        } else {
            uint256 noOfPeriods = (lockups[_lockupName].lockUpPeriodSeconds).div(lockups[_lockupName].releaseFrequencySeconds);
            uint256 elapsedPeriod = (block.timestamp.sub(lockups[_lockupName].startTime)).div(lockups[_lockupName].releaseFrequencySeconds);
            uint256 unLockedAmount = (lockups[_lockupName].lockupAmount.mul(elapsedPeriod)).div(noOfPeriods);
            return unLockedAmount;
        }
    }
}
```