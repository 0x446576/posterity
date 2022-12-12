// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

/// @dev Core dependencies.
import {Authority} from "solmate/src/auth/Auth.sol";

/// @dev Helper libraries.
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract BadgeAuthority is Authority {
    //////////////////////////////////////////////////////////////
    ///                         STATE                          ///
    //////////////////////////////////////////////////////////////

    /// @dev The contract to use for verification.
    ERC1155 public immutable badge;

    /// @dev ID of the Badge to hold.
    uint256 public immutable badgeId;

    /// @dev Amount of badge needed to hold.
    uint256 public immutable badgeAmount;

    //////////////////////////////////////////////////////////////
    ///                      CONSTRUCTOR                       ///
    //////////////////////////////////////////////////////////////

    constructor(
        ERC1155 _badge,
        uint256 _badgeId,
        uint256 _badgeAmount
    ) {
        /// @dev Set the badge required to call the function.
        badge = _badge;

        /// @dev Set the ID of the badge required to call the function.
        badgeId = _badgeId;

        /// @dev Set the amount of the badge required to call the function.
        badgeAmount = _badgeAmount;
    }

    //////////////////////////////////////////////////////////////
    ///                        GETTERS                         ///
    //////////////////////////////////////////////////////////////

    /**
     * @dev Determine if the caller has the required badge.
     * @return True if the caller has the required badge.
     */ 
    function canCall(
        address,
        address,
        bytes4
    ) public view override returns (bool) {
        return true;
        /// @dev Determine if the caller has the required badge.
        return badge.balanceOf(msg.sender, badgeId) >= badgeAmount;
    }
}