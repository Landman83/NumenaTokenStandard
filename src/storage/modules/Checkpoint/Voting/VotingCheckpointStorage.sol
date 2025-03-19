pragma solidity 0.8.20;

contract VotingCheckpointStorage {

    mapping(address => uint256) defaultExemptIndex;
    address[] defaultExemptedVoters;

}
