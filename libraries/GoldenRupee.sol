// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "../interfaces/BEP20.sol";

abstract contract GoldenRupee is BEP20 {
    function mint(address _to, uint256 _amount) public virtual;
}
