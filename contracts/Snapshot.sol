// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {Authority} from "solmate/src/auth/Auth.sol";

library Snapshot {
    /// @dev The structure of a society snapshot to birth.
    struct Society {
        string name;
        string symbol;
        address deployer;
        Authority authority;
        int256 initialPrice;
        int256 decayConstant;
        int256 emissionRate;
        uint96 generationConfiguration;
        bytes32 generationMerkleRoot;
    }
}
