// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./WitOracleBase.sol";
import "../WitnetUpgradableBase.sol";
import "../../interfaces/IWitOracleAdminACLs.sol";
import "../../interfaces/IWitOracleReporter.sol";

/// @title Witnet Request Board "trustable" implementation contract.
/// @notice Contract to bridge requests to Witnet Decentralized Oracle Network.
/// @dev This contract enables posting requests that Witnet bridges will insert into the Witnet network.
/// The result of the requests will be posted back to this contract by the bridge nodes too.
/// @author The Witnet Foundation
abstract contract WitOracleBaseTrustable
    is
        WitOracleBase,
        WitnetUpgradableBase,
        IWitOracleAdminACLs,
        IWitOracleReporter        
{
    using Witnet for Witnet.RadonSLA;

    /// Asserts the caller is authorized as a reporter
    modifier onlyReporters virtual {
        _require(
            WitOracleDataLib.data().reporters[msg.sender],
            "unauthorized reporter"
        ); _;
    }

    constructor(bytes32 _versionTag)
        Ownable(msg.sender)
        Payable(address(0))
        WitnetUpgradableBase(
            true, 
            _versionTag,
            "io.witnet.proxiable.board"
        )
    {} 


    // ================================================================================================================
    // --- Upgradeable ------------------------------------------------------------------------------------------------

    /// @notice Re-initialize contract's storage context upon a new upgrade from a proxy.
    /// @dev Must fail when trying to upgrade to same logic contract more than once.
    function initialize(bytes memory _initData) virtual override public {
        address _owner = owner();
        address[] memory _newReporters;

        if (_owner == address(0)) {
            // get owner (and reporters) from _initData
            bytes memory _newReportersRaw;
            (_owner, _newReportersRaw) = abi.decode(_initData, (address, bytes));
            _transferOwnership(_owner);
            _newReporters = abi.decode(_newReportersRaw, (address[]));
        } else {
            // only owner can initialize:
            _require(
                msg.sender == _owner,
                "not the owner"
            );
            // get reporters from _initData
            _newReporters = abi.decode(_initData, (address[]));
        }

        if (
            __proxiable().codehash != bytes32(0)
                && __proxiable().codehash == codehash()
        ) {
            _revert("already upgraded");
        }
        __proxiable().codehash = codehash();

        _require(address(registry).code.length > 0, "inexistent registry");
        _require(
            registry.specs() == (
                type(IWitAppliance).interfaceId
                    ^ type(IWitOracleRadonRegistry).interfaceId
            ), "uncompliant registry"
        );
        
        // Set reporters, if any
        WitOracleDataLib.setReporters(_newReporters);

        emit Upgraded(_owner, base(), codehash(), version());
    }


    // ================================================================================================================
    // --- IWitOracle -------------------------------------------------------------------------------------------------

    /// Retrieves copy of all response data related to a previously posted request, removing the whole query from storage.
    /// @dev Fails if the `_queryId` is not in 'Finalized' or 'Expired' status, or called from an address different to
    /// @dev the one that actually posted the given request.
    /// @dev If in 'Expired' status, query reward is transfer back to the requester.
    /// @param _queryId The unique query identifier.
    function fetchQueryResponse(uint256 _queryId)
        virtual override external
        returns (Witnet.QueryResponse memory)
    {
        try WitOracleDataLib.fetchQueryResponse(
            _queryId
        
        ) returns (
            Witnet.QueryResponse memory _queryResponse,
            uint72 _queryEvmExpiredReward
        ) {
            if (_queryEvmExpiredReward > 0) {
                // transfer unused reward to requester, only if the query expired:
                __safeTransferTo(
                    payable(msg.sender),
                    _queryEvmExpiredReward
                );
            }
            return _queryResponse;            
        
        } catch Error(string memory _reason) {
            _revert(_reason);

        } catch (bytes memory) {
            _revertWitOracleDataLibUnhandledException();
        }
    }

    /// Gets current status of given query.
    function getQueryStatus(uint256 _queryId) 
        virtual override
        public view
        returns (Witnet.QueryStatus)
    {
        return WitOracleDataLib.getQueryStatus(_queryId);
    }

    /// @notice Returns query's result current status from a requester's point of view:
    /// @notice   - 0 => Void: the query is either non-existent or deleted;
    /// @notice   - 1 => Awaiting: the query has not yet been reported;
    /// @notice   - 2 => Ready: the query has been succesfully solved;
    /// @notice   - 3 => Error: the query couldn't get solved due to some issue.
    /// @param _queryId The unique query identifier.
    function getQueryResponseStatus(uint256 _queryId)
        virtual override public view
        returns (Witnet.QueryResponseStatus)
    {
        return WitOracleDataLib.getQueryResponseStatus(_queryId);
    }


    // ================================================================================================================
    // --- Implements IWitOracleAdminACLs -----------------------------------------------------------------------------

    /// Tells whether given address is included in the active reporters control list.
    /// @param _queryResponseReporter The address to be checked.
    function isReporter(address _queryResponseReporter) virtual override public view returns (bool) {
        return WitOracleDataLib.isReporter(_queryResponseReporter);
    }

    /// Adds given addresses to the active reporters control list.
    /// @dev Can only be called from the owner address.
    /// @dev Emits the `ReportersSet` event. 
    /// @param _queryResponseReporters List of addresses to be added to the active reporters control list.
    function setReporters(address[] calldata _queryResponseReporters)
        virtual override public
        onlyOwner
    {
        WitOracleDataLib.setReporters(_queryResponseReporters);
    }

    /// Removes given addresses from the active reporters control list.
    /// @dev Can only be called from the owner address.
    /// @dev Emits the `ReportersUnset` event. 
    /// @param _exReporters List of addresses to be added to the active reporters control list.
    function unsetReporters(address[] calldata _exReporters)
        virtual override public
        onlyOwner
    {
        WitOracleDataLib.unsetReporters(_exReporters);
    }


    // ================================================================================================================
    // --- Implements IWitOracleReporter ------------------------------------------------------------------------------

    /// @notice Estimates the actual earnings (or loss), in WEI, that a reporter would get by reporting result to given query,
    /// @notice based on the gas price of the calling transaction. Data requesters should consider upgrading the reward on 
    /// @notice queries providing no actual earnings.
    function estimateReportEarnings(
            uint256[] calldata _queryIds, 
            bytes calldata,
            uint256 _evmGasPrice,
            uint256 _evmWitPrice
        )
        external view
        virtual override
        returns (uint256 _revenues, uint256 _expenses)
    {
        for (uint _ix = 0; _ix < _queryIds.length; _ix ++) {
            if (
                getQueryStatus(_queryIds[_ix]) == Witnet.QueryStatus.Posted
            ) {
                Witnet.QueryRequest storage __request = WitOracleDataLib.seekQueryRequest(_queryIds[_ix]);
                if (__request.gasCallback > 0) {
                    _expenses += (
                        estimateBaseFeeWithCallback(_evmGasPrice, __request.gasCallback)
                            + estimateExtraFee(
                                _evmGasPrice,
                                _evmWitPrice,
                                Witnet.RadonSLA({
                                    witNumWitnesses: __request.radonSLA.witNumWitnesses,
                                    witUnitaryReward: __request.radonSLA.witUnitaryReward,
                                    maxTallyResultSize: uint16(0)
                                })
                            )
                    );
                } else {
                    _expenses += (
                        estimateBaseFee(_evmGasPrice)
                            + estimateExtraFee(
                                _evmGasPrice, 
                                _evmWitPrice, 
                                __request.radonSLA
                            )
                    );
                }
                _expenses +=  _evmWitPrice * __request.radonSLA.witUnitaryReward;
                _revenues += __request.evmReward;
            }
        }
    }

    /// @notice Retrieves the Witnet Data Request bytecodes and SLAs of previously posted queries.
    /// @dev Returns empty buffer if the query does not exist.
    /// @param _queryIds Query identifies.
    function extractWitnetDataRequests(uint256[] calldata _queryIds)
        external view 
        virtual override
        returns (bytes[] memory _bytecodes)
    {
        return WitOracleDataLib.extractWitnetDataRequests(registry, _queryIds);
    }

    /// Reports the Witnet-provable result to a previously posted request. 
    /// @dev Will assume `block.timestamp` as the timestamp at which the request was solved.
    /// @dev Fails if:
    /// @dev - the `_queryId` is not in 'Posted' status.
    /// @dev - provided `_resultTallyHash` is zero;
    /// @dev - length of provided `_result` is zero.
    /// @param _queryId The unique identifier of the data request.
    /// @param _resultTallyHash Hash of the commit/reveal witnessing act that took place in the Witnet blockahin.
    /// @param _resultCborBytes The result itself as bytes.
    function reportResult(
            uint256 _queryId,
            bytes32 _resultTallyHash,
            bytes calldata _resultCborBytes
        )
        external override
        onlyReporters
        returns (uint256)
    {
        // results cannot be empty:
        _require(
            _resultCborBytes.length != 0, 
            "result cannot be empty"
        );
        // do actual report and return reward transfered to the reproter:
        // solhint-disable not-rely-on-time
        return __reportResultAndReward(
            _queryId,
            uint32(block.timestamp),
            _resultTallyHash,
            _resultCborBytes
        );
    }

    /// Reports the Witnet-provable result to a previously posted request.
    /// @dev Fails if:
    /// @dev - called from unauthorized address;
    /// @dev - the `_queryId` is not in 'Posted' status.
    /// @dev - provided `_resultTallyHash` is zero;
    /// @dev - length of provided `_resultCborBytes` is zero.
    /// @param _queryId The unique query identifier
    /// @param _resultTimestamp Timestamp at which the reported value was captured by the Witnet blockchain. 
    /// @param _resultTallyHash Hash of the commit/reveal witnessing act that took place in the Witnet blockahin.
    /// @param _resultCborBytes The result itself as bytes.
    function reportResult(
            uint256 _queryId,
            uint32  _resultTimestamp,
            bytes32 _resultTallyHash,
            bytes calldata _resultCborBytes
        )
        external
        override
        onlyReporters
        returns (uint256)
    {
        // validate timestamp
        _require(
            _resultTimestamp > 0,
            "bad timestamp"
        );
        // results cannot be empty
        _require(
            _resultCborBytes.length != 0, 
            "result cannot be empty"
        );
        // do actual report and return reward transfered to the reproter:
        return  __reportResultAndReward(
            _queryId,
            _resultTimestamp,
            _resultTallyHash,
            _resultCborBytes
        );
    }

    /// @notice Reports Witnet-provided results to multiple requests within a single EVM tx.
    /// @notice Emits either a WitOracleQueryResponse* or a BatchReportError event per batched report.
    /// @dev Fails only if called from unauthorized address.
    /// @param _batchResults Array of BatchResult structs, every one containing:
    ///         - unique query identifier;
    ///         - timestamp of the solving tally txs in Witnet. If zero is provided, EVM-timestamp will be used instead;
    ///         - hash of the corresponding data request tx at the Witnet side-chain level;
    ///         - data request result in raw bytes.
    function reportResultBatch(IWitOracleReporter.BatchResult[] calldata _batchResults)
        external override
        onlyReporters
        returns (uint256 _batchReward)
    {
        for (uint _i = 0; _i < _batchResults.length; _i ++) {
            if (
                getQueryStatus(_batchResults[_i].queryId)
                    != Witnet.QueryStatus.Posted
            ) {
                emit BatchReportError(
                    _batchResults[_i].queryId,
                    WitOracleDataLib.notInStatusRevertMessage(Witnet.QueryStatus.Posted)
                );
            } else if (
                uint256(_batchResults[_i].resultTimestamp) > block.timestamp
                    || _batchResults[_i].resultTimestamp == 0
                    || _batchResults[_i].resultCborBytes.length == 0
            ) {
                emit BatchReportError(
                    _batchResults[_i].queryId, 
                    string(abi.encodePacked(
                        class(),
                        ": invalid report data"
                    ))
                );
            } else {
                _batchReward += __reportResult(
                    _batchResults[_i].queryId,
                    _batchResults[_i].resultTimestamp,
                    _batchResults[_i].resultTallyHash,
                    _batchResults[_i].resultCborBytes
                );
            }
        }   
        // Transfer rewards to all reported results in one single transfer to the reporter:
        if (_batchReward > 0) {
            __safeTransferTo(
                payable(msg.sender),
                _batchReward
            );
        }
    }


    /// ================================================================================================================
    /// --- Internal methods -------------------------------------------------------------------------------------------

    function __reportResult(
            uint256 _queryId,
            uint32  _resultTimestamp,
            bytes32 _resultTallyHash,
            bytes calldata _resultCborBytes
        )
        virtual internal
        returns (uint256)
    {
        _require(
            WitOracleDataLib.getQueryStatus(_queryId) == Witnet.QueryStatus.Posted,
            "not in Posted status"
        );
        return WitOracleDataLib.reportResult(
            msg.sender,
            tx.gasprice,
            uint64(block.number),
            _queryId, 
            _resultTimestamp, 
            _resultTallyHash, 
            _resultCborBytes
        );
    }

    function __reportResultAndReward(
            uint256 _queryId,
            uint32  _resultTimestamp,
            bytes32 _resultTallyHash,
            bytes calldata _resultCborBytes
        )
        virtual internal
        returns (uint256 _evmReward)
    {
        _evmReward = __reportResult(
            _queryId, 
            _resultTimestamp, 
            _resultTallyHash, 
            _resultCborBytes
        );
        // transfer reward to reporter
        __safeTransferTo(
            payable(msg.sender),
            _evmReward
        );
    }
}