// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./Wallet.sol";
import "./VestingEscrowWalletStorage.sol";

/**
 * @title Wallet for core vesting escrow functionality
 */
contract VestingEscrowWallet is VestingEscrowWalletStorage, Wallet {


    // States used to represent the status of the schedule
    enum State {CREATED, STARTED, COMPLETED}

    // Emit when new schedule is added
    event AddSchedule(
        address indexed _beneficiary,
        bytes32 _templateName,
        uint256 _startTime
    );
    // Emit when schedule is modified
    event ModifySchedule(
        address indexed _beneficiary,
        bytes32 _templateName,
        uint256 _startTime
    );
    // Emit when all schedules are revoked for user
    event RevokeAllSchedules(address indexed _beneficiary);
    // Emit when schedule is revoked
    event RevokeSchedule(address indexed _beneficiary, bytes32 _templateName);
    // Emit when tokes are deposited to wallet
    event DepositTokens(uint256 _numberOfTokens, address _sender);
    // Emit when all unassigned tokens are sent to treasury
    event SendToTreasury(uint256 _numberOfTokens, address _sender);
    // Emit when is sent tokes to user
    event SendTokens(address indexed _beneficiary, uint256 _numberOfTokens);
    // Emit when template is added
    event AddTemplate(bytes32 _name, uint256 _numberOfTokens, uint256 _duration, uint256 _frequency);
    // Emit when template is removed
    event RemoveTemplate(bytes32 _name);
    // Emit when the treasury wallet gets changed
    event TreasuryWalletChanged(address _newWallet, address _oldWallet);

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
     * @notice This function returns the signature of the configure function
     * @return bytes4 Function signature
     */
    function getInitFunction() public pure override returns (bytes4) {
        return this.configure.selector;
    }

    /**
     * @notice Used to initialize the treasury wallet address
     * @param _treasuryWallet Address of the treasury wallet
     */
    function configure(address _treasuryWallet) public onlyFactory {
        _setWallet(_treasuryWallet);
    }

    /**
     * @notice Used to change the treasury wallet address
     * @param _newTreasuryWallet Address of the treasury wallet
     */
    function changeTreasuryWallet(address _newTreasuryWallet) public {
        _onlySecurityTokenOwner();
        _setWallet(_newTreasuryWallet);
    }

    /**
     * @notice Internal function to set the treasury wallet
     * @param _newTreasuryWallet Address of the new treasury wallet
     */
    function _setWallet(address _newTreasuryWallet) internal {
        emit TreasuryWalletChanged(_newTreasuryWallet, treasuryWallet);
        treasuryWallet = _newTreasuryWallet;
    }

    /**
     * @notice Used to deposit tokens from treasury wallet to the vesting escrow wallet
     * @param _numberOfTokens Number of tokens that should be deposited
     */
    function depositTokens(uint256 _numberOfTokens) external withPerm(ADMIN) {
        _depositTokens(_numberOfTokens);
    }

    /**
     * @notice Internal function to deposit tokens
     * @param _numberOfTokens Number of tokens to deposit
     */
    function _depositTokens(uint256 _numberOfTokens) internal {
        require(_numberOfTokens > 0, "Should be > 0");
        require(
            securityToken.transferFrom(msg.sender, address(this), _numberOfTokens),
            "Failed transferFrom"
        );
        unassignedTokens = unassignedTokens + _numberOfTokens;
        emit DepositTokens(_numberOfTokens, msg.sender);
    }

    /**
     * @notice Sends unassigned tokens to the treasury wallet
     * @param _amount Amount of tokens that should be send to the treasury wallet
     */
    function sendToTreasury(uint256 _amount) public withPerm(OPERATOR) {
        require(_amount > 0, "Amount cannot be zero");
        require(_amount <= unassignedTokens, "Amount is greater than unassigned tokens");
        unassignedTokens = unassignedTokens - _amount;
        require(securityToken.transfer(getTreasuryWallet(), _amount), "Transfer failed");
        emit SendToTreasury(_amount, msg.sender);
    }

    /**
     * @notice Returns the treasury wallet address
     * @return address Treasury wallet address
     */
    function getTreasuryWallet() public view returns(address) {
        if (treasuryWallet == address(0)) {
            address wallet = IDataStore(getDataStore()).getAddress(TREASURY);
            if (wallet != address(0))
                return wallet;
            return securityToken.owner();
        }
        return treasuryWallet;
    }

    /**
     * @notice Used to add a vesting schedule for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @param _templateName Name of the template used for schedule creation
     * @param _numberOfTokens Number of tokens should be assigned to schedule
     * @param _duration Duration of the vesting
     * @param _frequency Frequency of the vesting
     * @param _startTime Start time of the vesting
     */
    function addSchedule(
        address _beneficiary,
        bytes32 _templateName,
        uint256 _numberOfTokens,
        uint256 _duration,
        uint256 _frequency,
        uint256 _startTime
    )
        public
        withPerm(ADMIN)
    {
        _addSchedule(_beneficiary, _templateName, _numberOfTokens, _duration, _frequency, _startTime);
    }

    /**
     * @notice Internal function to add a vesting schedule for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @param _templateName Name of the template used for schedule creation
     * @param _numberOfTokens Number of tokens should be assigned to schedule
     * @param _duration Duration of the vesting
     * @param _frequency Frequency of the vesting
     * @param _startTime Start time of the vesting
     */
    function _addSchedule(
        address _beneficiary,
        bytes32 _templateName,
        uint256 _numberOfTokens,
        uint256 _duration,
        uint256 _frequency,
        uint256 _startTime
    )
        internal
    {
        require(_beneficiary != address(0), "Invalid address");
        require(_templateName != bytes32(0), "Invalid template name");
        require(_startTime >= block.timestamp, "Invalid startTime");
        _validateTemplate(_numberOfTokens, _duration, _frequency);
        require(unassignedTokens >= _numberOfTokens, "Insufficient tokens");
        require(!_isTemplateExists(_templateName), "Template already exists");

        unassignedTokens = unassignedTokens.sub(_numberOfTokens);
        templates[_templateName] = Template(_numberOfTokens, _duration, _frequency);

        Schedule memory schedule = Schedule({
            templateName: _templateName,
            numberOfTokens: _numberOfTokens,
            duration: _duration,
            frequency: _frequency,
            startTime: _startTime,
            claimedTokens: 0
        });

        userToTemplateIndex[_beneficiary][_templateName] = schedules[_beneficiary].length;
        schedules[_beneficiary].push(schedule);

        if (schedules[_beneficiary].length == 1) {
            beneficiaries.push(_beneficiary);
        }

        emit AddSchedule(_beneficiary, _templateName, _startTime);
    }

    /**
     * @notice Used to add a vesting schedule from template for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @param _templateName Name of the template used for schedule creation
     * @param _startTime Start time of the vesting
     */
    function addScheduleFromTemplate(
        address _beneficiary,
        bytes32 _templateName,
        uint256 _startTime
    )
        public
        withPerm(ADMIN)
    {
        _addScheduleFromTemplate(_beneficiary, _templateName, _startTime);
    }

    /**
     * @notice Internal function to add a vesting schedule from template for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @param _templateName Name of the template used for schedule creation
     * @param _startTime Start time of the vesting
     */
    function _addScheduleFromTemplate(
        address _beneficiary,
        bytes32 _templateName,
        uint256 _startTime
    )
        internal
    {
        require(_isTemplateExists(_templateName), "Template doesn't exist");
        Template memory template = templates[_templateName];
        _addSchedule(
            _beneficiary,
            _templateName,
            template.numberOfTokens,
            template.duration,
            template.frequency,
            _startTime
        );
    }

    /**
     * @notice Used to add a template
     * @param _name Name of the template
     * @param _numberOfTokens Number of tokens for the template
     * @param _duration Duration of the vesting
     * @param _frequency Frequency of the vesting
     */
    function addTemplate(
        bytes32 _name,
        uint256 _numberOfTokens,
        uint256 _duration,
        uint256 _frequency
    )
        public
        withPerm(ADMIN)
    {
        require(_name != bytes32(0), "Invalid template name");
        require(!_isTemplateExists(_name), "Template already exists");
        _validateTemplate(_numberOfTokens, _duration, _frequency);
        require(unassignedTokens >= _numberOfTokens, "Insufficient tokens");

        unassignedTokens = unassignedTokens.sub(_numberOfTokens);
        templates[_name] = Template(_numberOfTokens, _duration, _frequency);

        emit AddTemplate(_name, _numberOfTokens, _duration, _frequency);
    }

    /**
     * @notice Used to remove a template
     * @param _name Name of the template
     */
    function removeTemplate(bytes32 _name) public withPerm(ADMIN) {
        require(_isTemplateExists(_name), "Template doesn't exist");
        uint256 numberOfTokens = templates[_name].numberOfTokens;
        delete templates[_name];
        unassignedTokens = unassignedTokens.add(numberOfTokens);
        emit RemoveTemplate(_name);
    }

    /**
     * @notice Used to revoke all schedules for a beneficiary
     * @param _beneficiary Address of the beneficiary
     */
    function revokeAllSchedules(address _beneficiary) public withPerm(ADMIN) {
        _revokeAllSchedules(_beneficiary);
    }

    /**
     * @notice Internal function to revoke all schedules for a beneficiary
     * @param _beneficiary Address of the beneficiary
     */
    function _revokeAllSchedules(address _beneficiary) internal {
        require(_beneficiary != address(0), "Invalid address");
        require(schedules[_beneficiary].length > 0, "No schedules found");

        for (uint256 i = 0; i < schedules[_beneficiary].length; i++) {
            Schedule memory schedule = schedules[_beneficiary][i];
            uint256 claimedTokens = schedule.claimedTokens;
            uint256 numberOfTokens = schedule.numberOfTokens;
            if (claimedTokens < numberOfTokens) {
                unassignedTokens = unassignedTokens.add(numberOfTokens.sub(claimedTokens));
            }
        }

        delete schedules[_beneficiary];
        emit RevokeAllSchedules(_beneficiary);
    }

    /**
     * @notice Used to revoke a schedule for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @param _templateName Name of the template
     */
    function revokeSchedule(address _beneficiary, bytes32 _templateName) public withPerm(ADMIN) {
        _checkSchedule(_beneficiary, _templateName);
        uint256 index = userToTemplateIndex[_beneficiary][_templateName];
        Schedule memory schedule = schedules[_beneficiary][index];
        uint256 claimedTokens = schedule.claimedTokens;
        uint256 numberOfTokens = schedule.numberOfTokens;
        if (claimedTokens < numberOfTokens) {
            unassignedTokens = unassignedTokens.add(numberOfTokens.sub(claimedTokens));
        }

        // Move the last element to the deleted spot
        schedules[_beneficiary][index] = schedules[_beneficiary][schedules[_beneficiary].length - 1];
        // Update the moved element's index
        userToTemplateIndex[_beneficiary][schedules[_beneficiary][index].templateName] = index;
        // Remove the last element
        schedules[_beneficiary].pop();
        // Delete the mapping
        delete userToTemplateIndex[_beneficiary][_templateName];

        emit RevokeSchedule(_beneficiary, _templateName);
    }

    /**
     * @notice Used to modify a schedule for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @param _templateName Name of the template
     * @param _startTime New start time of the vesting
     */
    function modifySchedule(
        address _beneficiary,
        bytes32 _templateName,
        uint256 _startTime
    )
        public
        withPerm(ADMIN)
    {
        _modifySchedule(_beneficiary, _templateName, _startTime);
    }

    /**
     * @notice Internal function to modify a schedule for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @param _templateName Name of the template
     * @param _startTime New start time of the vesting
     */
    function _modifySchedule(
        address _beneficiary,
        bytes32 _templateName,
        uint256 _startTime
    )
        internal
    {
        _checkSchedule(_beneficiary, _templateName);
        require(_startTime >= block.timestamp, "Invalid startTime");
        uint256 index = userToTemplateIndex[_beneficiary][_templateName];
        schedules[_beneficiary][index].startTime = _startTime;
        emit ModifySchedule(_beneficiary, _templateName, _startTime);
    }

    /**
     * @notice Used to push available tokens to a beneficiary
     * @param _beneficiary Address of the beneficiary
     */
    function pushAvailableTokens(address _beneficiary) public {
        require(_beneficiary != address(0), "Invalid address");
        _sendTokens(_beneficiary);
    }

    /**
     * @notice Used to push available tokens to multiple beneficiaries
     * @param _beneficiaries Array of beneficiary addresses
     */
    function pushAvailableTokensMulti(address[] memory _beneficiaries) public {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            pushAvailableTokens(_beneficiaries[i]);
        }
    }

    /**
     * @notice Used to pull available tokens for the caller
     */
    function pullAvailableTokens() public {
        _sendTokens(msg.sender);
    }

    /**
     * @notice Returns the state of a schedule
     * @param _beneficiary Address of the beneficiary
     * @param _index Index of the schedule
     * @return state State of the schedule
     */
    function getScheduleState(address _beneficiary, uint256 _index) public view returns(State state) {
        require(_beneficiary != address(0), "Invalid address");
        require(_index < schedules[_beneficiary].length, "Invalid index");
        Schedule memory schedule = schedules[_beneficiary][_index];
        if (schedule.startTime > block.timestamp) {
            return State.CREATED;
        } else if (schedule.claimedTokens >= schedule.numberOfTokens) {
            return State.COMPLETED;
        } else {
            return State.STARTED;
        }
    }

    /**
     * @notice Returns the available tokens for a schedule
     * @param _beneficiary Address of the beneficiary
     * @param _index Index of the schedule
     * @return uint256 Available tokens
     */
    function getAvailableTokens(address _beneficiary, uint256 _index) public view returns(uint256) {
        return _getAvailableTokens(_beneficiary, _index);
    }

    /**
     * @notice Internal function to get the available tokens for a schedule
     * @param _beneficiary Address of the beneficiary
     * @param _index Index of the schedule
     * @return uint256 Available tokens
     */
    function _getAvailableTokens(address _beneficiary, uint256 _index) internal view returns(uint256) {
        require(_beneficiary != address(0), "Invalid address");
        require(_index < schedules[_beneficiary].length, "Invalid index");
        Schedule memory schedule = schedules[_beneficiary][_index];
        if (schedule.startTime > block.timestamp) {
            return 0;
        }
        uint256 elapsedTime = block.timestamp.sub(schedule.startTime);
        if (elapsedTime >= schedule.duration) {
            return schedule.numberOfTokens.sub(schedule.claimedTokens);
        }
        uint256 periodCount = schedule.duration.div(schedule.frequency);
        uint256 amountPerPeriod = schedule.numberOfTokens.div(periodCount);
        uint256 periods = elapsedTime.div(schedule.frequency);
        uint256 availableTokens = amountPerPeriod.mul(periods);
        if (availableTokens <= schedule.claimedTokens) {
            return 0;
        }
        return availableTokens.sub(schedule.claimedTokens);
    }

    /**
     * @notice Used to bulk add vesting schedules for each of the beneficiary
     * @param _beneficiaries Array of the beneficiary's addresses
     * @param _templateNames Array of the template names
     * @param _numberOfTokens Array of number of tokens should be assigned to schedules
     * @param _durations Array of the vesting duration
     * @param _frequencies Array of the vesting frequency
     * @param _startTimes Array of the vesting start time
     */
    function addScheduleMulti(
        address[] memory _beneficiaries,
        bytes32[] memory _templateNames,
        uint256[] memory _numberOfTokens,
        uint256[] memory _durations,
        uint256[] memory _frequencies,
        uint256[] memory _startTimes
    )
        public
        withPerm(ADMIN)
    {
        require(
            _beneficiaries.length == _templateNames.length &&
            _beneficiaries.length == _numberOfTokens.length &&
            _beneficiaries.length == _durations.length &&
            _beneficiaries.length == _frequencies.length &&
            _beneficiaries.length == _startTimes.length,
            "Arrays sizes mismatch"
        );
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            _addSchedule(_beneficiaries[i], _templateNames[i], _numberOfTokens[i], _durations[i], _frequencies[i], _startTimes[i]);
        }
    }

    /**
     * @notice Used to bulk add vesting schedules from template for each of the beneficiary
     * @param _beneficiaries Array of beneficiary's addresses
     * @param _templateNames Array of the template names were used for schedule creation
     * @param _startTimes Array of the vesting start time
     */
    function addScheduleFromTemplateMulti(
        address[] memory _beneficiaries,
        bytes32[] memory _templateNames,
        uint256[] memory _startTimes
    )
        public
        withPerm(ADMIN)
    {
        require(_beneficiaries.length == _templateNames.length && _beneficiaries.length == _startTimes.length, "Arrays sizes mismatch");
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            _addScheduleFromTemplate(_beneficiaries[i], _templateNames[i], _startTimes[i]);
        }
    }

    /**
     * @notice Used to bulk revoke vesting schedules for each of the beneficiaries
     * @param _beneficiaries Array of the beneficiary's addresses
     */
    function revokeSchedulesMulti(address[] memory _beneficiaries) public withPerm(ADMIN) {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            _revokeAllSchedules(_beneficiaries[i]);
        }
    }

    /**
     * @notice Used to bulk modify vesting schedules for each of the beneficiaries
     * @param _beneficiaries Array of the beneficiary's addresses
     * @param _templateNames Array of the template names
     * @param _startTimes Array of the vesting start time
     */
    function modifyScheduleMulti(
        address[] memory _beneficiaries,
        bytes32[] memory _templateNames,
        uint256[] memory _startTimes
    )
        public
        withPerm(ADMIN)
    {
        require(
            _beneficiaries.length == _templateNames.length &&
            _beneficiaries.length == _startTimes.length,
            "Arrays sizes mismatch"
        );
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            _modifySchedule(_beneficiaries[i], _templateNames[i], _startTimes[i]);
        }
    }

    /**
     * @notice Check if a schedule exists for a beneficiary
     * @param _beneficiary Address of the beneficiary
     * @param _templateName Name of the template
     */
    function _checkSchedule(address _beneficiary, bytes32 _templateName) internal view {
        require(_beneficiary != address(0), "Invalid address");
        uint256 index = userToTemplateIndex[_beneficiary][_templateName];
        require(
            index < schedules[_beneficiary].length &&
            schedules[_beneficiary][index].templateName == _templateName,
            "Schedule not found"
        );
    }

    /**
     * @notice Check if a template exists
     * @param _name Name of the template
     * @return bool True if the template exists
     */
    function _isTemplateExists(bytes32 _name) internal view returns(bool) {
        return templates[_name].numberOfTokens > 0;
    }

    /**
     * @notice Validate a template
     * @param _numberOfTokens Number of tokens for the template
     * @param _duration Duration of the vesting schedule
     * @param _frequency Frequency of the vesting schedule
     */
    function _validateTemplate(uint256 _numberOfTokens, uint256 _duration, uint256 _frequency) internal view {
        require(_numberOfTokens > 0, "Zero amount");
        require(_duration % _frequency == 0, "Invalid frequency");
        uint256 periodCount = _duration.div(_frequency);
        require(_numberOfTokens % periodCount == 0, "Invalid token amount");
        uint256 amountPerPeriod = _numberOfTokens.div(periodCount);
        require(amountPerPeriod % securityToken.granularity() == 0, "Invalid granularity");
    }

    /**
     * @notice Send tokens to a beneficiary for all schedules
     * @param _beneficiary Address of the beneficiary
     */
    function _sendTokens(address _beneficiary) internal {
        for (uint256 i = 0; i < schedules[_beneficiary].length; i++) {
            _sendTokensPerSchedule(_beneficiary, i);
        }
    }

    /**
     * @notice Send tokens to a beneficiary for a specific schedule
     * @param _beneficiary Address of the beneficiary
     * @param _index Index of the schedule
     */
    function _sendTokensPerSchedule(address _beneficiary, uint256 _index) internal {
        uint256 amount = _getAvailableTokens(_beneficiary, _index);
        if (amount > 0) {
            schedules[_beneficiary][_index].claimedTokens = schedules[_beneficiary][_index].claimedTokens.add(amount);
            require(securityToken.transfer(_beneficiary, amount), "Transfer failed");
            emit SendTokens(_beneficiary, amount);
        }
    }

    /**
     * @notice Return the permissions flag that are associated with VestingEscrowWallet
     * @return bytes32[] Array of permission flags
     */
    function getPermissions() public view override returns(bytes32[] memory) {
        bytes32[] memory allPermissions = new bytes32[](2);
        allPermissions[0] = ADMIN;
        allPermissions[1] = OPERATOR;
        return allPermissions;
    }
}

