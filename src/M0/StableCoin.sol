// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {MEarnerManager} from "evm-m-extensions/projects/earnerManager/MEarnerManager.sol";

contract StableCoin is MEarnerManager {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address mToken_, address swapFacility_) MEarnerManager(mToken_, swapFacility_) {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        address admin,
        address earnerManager,
        address feeRecipient_,
        address pauser
    ) public override initializer {
        MEarnerManager.initialize(name, symbol, admin, earnerManager, feeRecipient_, pauser);
    }
}
