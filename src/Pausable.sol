// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Utility contract to allow pausing and unpausing of certain functions
 */
contract Pausable {
    event Pause(address indexed account);
    event Unpause(address indexed account);

    bool public paused = false;

    /**
     * @notice Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    /**
     * @notice Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        require(paused, "Contract is not paused");
        _;
    }

    /**
     * @notice Called by the owner to pause, triggers stopped state
     */
    function _pause() internal whenNotPaused {
        paused = true;
        emit Pause(msg.sender);
    }

    /**
     * @notice Called by the owner to unpause, returns to normal state
     */
    function _unpause() internal whenPaused {
        paused = false;
        emit Unpause(msg.sender);
    }
}
