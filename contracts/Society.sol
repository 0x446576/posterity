// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

/// @dev Core dependencies.
import {Posterity} from "./Posterity.sol";
import {Auth, Authority} from "solmate/src/auth/Auth.sol";

/// @dev Helper libraries.
import {Snapshot} from "./Snapshot.sol";
import {Bytes32AddressLib} from "solmate/src/utils/Bytes32AddressLib.sol";

contract Society {
    using Bytes32AddressLib for address;
    using Bytes32AddressLib for bytes32;

    //////////////////////////////////////////////////////////////
    ///                         STATE                          ///
    //////////////////////////////////////////////////////////////

    /// @dev Keep track of which society is being deployed.
    uint256 internal societyNumber;

    /// @dev The society that is being deployed.
    Snapshot.Society internal society;

    //////////////////////////////////////////////////////////////
    ///                         EVENTS                         ///
    //////////////////////////////////////////////////////////////

    /// @dev Announce the birth of a new society.
    event SocietyBirth(
        Posterity indexed posterity,
        uint256 indexed index,
        address indexed deployer
    );

    //////////////////////////////////////////////////////////////
    ///                        SETTERS                         ///
    //////////////////////////////////////////////////////////////

    function deploySociety(Snapshot.Society calldata snapshot)
        external
        returns (Posterity posterity, uint256 index)
    {
        /// @dev Keep track of which society is being deployed.
        unchecked {
            index = societyNumber + 1;
        }

        /// @dev Make sure the new society is not the same as the old one.
        societyNumber = index;

        /// @dev Save the state into an already warm storage slot.
        society = snapshot;

        /// @dev Deploy the posterity contract.
        posterity = new Posterity{salt: bytes32(societyNumber)}();

        /// @dev Emit an event for the new posterity contract.
        emit SocietyBirth(posterity, index, snapshot.deployer);
    }

    //////////////////////////////////////////////////////////////
    ///                        GETTERS                         ///
    //////////////////////////////////////////////////////////////

    /**
     * @dev Allows the forwarding of contract state into immutable slots.
     * @return The society that is being deployed.
     */
    function getSociety() external view returns (Snapshot.Society memory) {
        return society;
    }
}
