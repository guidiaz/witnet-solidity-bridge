// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;

import "../../contracts/impls/centralized/WitnetRequestBoard.sol";

/**
 * @title Witnet Requests Board Version 1
 * @notice Contract to bridge requests to Witnet
 * @dev This contract enables posting requests that Witnet bridges will insert into the Witnet network
  * The result of the requests will be posted back to this contract by the bridge nodes too.
  * The contract has been created for testing purposes
 * @author Witnet Foundation
 */
contract WitnetRequestBoardTestHelper is WitnetRequestBoard {

  address public witnet;
  

  // Data fields to be accessed in the context of a proxy delegate-call, must be declared as `immutable`:
  bool public immutable upgradable;

  constructor (address[] memory _committee, bool _upgradable) {
    witnet = msg.sender;
    upgradable = _upgradable;
    setReporters(_committee);
  }

  /// @dev Posts a data request into the WRB, with immediate mock result.
  /// @param _requestAddress The request contract address which includes the request bytecode.
  /// @return _id The unique identifier of the data request.
  function postDataRequest(address _requestAddress)
    public payable override returns(uint256 _id)
  {
    _id = super.postDataRequest(_requestAddress);
    __data().requests[_id].dr.txhash = uint256(keccak256("hello"));
    __data().requests[_id].result = "hello";
  }

  /// @dev Retrieves hash of the data request transaction in Witnet
  /// @param _id The unique identifier of the data request.
  /// @return The hash of the DataRequest transaction in Witnet
  function readDrTxHash(uint256 _id) external view override returns(uint256) {
    return __dataRequest(_id).txhash;
  }

  /// @dev Retrieves the result (if already available) of one data request from the WRB.
  /// @param _id The unique identifier of the data request.
  /// @return The result of the DR
  function readResult(uint256 _id) external view override returns (bytes memory) {
    return __data().requests[_id].result;
  }

  /// @dev Verifies if the contract is upgradable
  /// @return true if the contract upgradable
  /* solhint-disable-next-line no-unused-vars*/
  function isUpgradable() public view override returns (bool) {
    return upgradable;
  }

  /// @dev Estimate the amount of reward we need to insert for a given gas price.
  /// @return The rewards to be included for the given gas price as inclusionReward, resultReward, blockReward.
  function estimateGasCost(uint256) external pure override returns(uint256){
    return 0;
  }
}
