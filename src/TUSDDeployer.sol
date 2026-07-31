// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TUSD} from "./TUSD.sol";

/// @title TUSDDeployer
/// @notice Creates one versioned deterministic tUSD deployment with its factory.
/// @dev The token is created inside this constructor so the local fixture has
///      one top-level deployment transaction. Anvil requires increasing block
///      timestamps for separate transactions, while the sealed fixture trace
///      deliberately requires every deployment transaction to retain the
///      fixed genesis timestamp.
contract TUSDDeployer {
    bytes32 public constant TUSD_SALT = keccak256("tokscale.giwa.tusd.v1");

    event TUSDDeployed(address indexed token, bytes32 indexed salt);

    TUSD public immutable token;

    constructor() {
        address predicted = predictTokenAddress();
        token = new TUSD{salt: TUSD_SALT}();
        assert(address(token) == predicted);
        emit TUSDDeployed(address(token), TUSD_SALT);
    }

    function predictTokenAddress() public view returns (address) {
        bytes32 initCodeHash = keccak256(type(TUSD).creationCode);
        bytes32 hash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), TUSD_SALT, initCodeHash));
        return address(uint160(uint256(hash)));
    }
}
