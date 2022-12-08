// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {Authority} from "solmate/src/auth/Auth.sol";

contract BadgeAuthority is Authority {
    function canCall(
        address,
        address,
        bytes4
    ) public view override returns (bool) {
        return true;
    }
}