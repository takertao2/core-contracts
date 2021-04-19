// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;
/*
 _    _ __     __ _____   _    _  _       ______   _____ __          __       _____  
| |  | |\ \   / /|  __ \ | |  | || |     |  ____| / ____|\ \        / //\    |  __ \ 
| |__| | \ \_/ / | |__) || |  | || |     | |__   | (___   \ \  /\  / //  \   | |__) |
|  __  |  \   /  |  _  / | |  | || |     |  __|   \___ \   \ \/  \/ // /\ \  |  ___/ 
| |  | |   | |   | | \ \ | |__| || |____ | |____  ____) |   \  /\  // ____ \ | |     
|_|  |_|   |_|   |_|  \_\ \____/ |______||______||_____/     \/  \//_/    \_\|_| 

 */
import "../interfaces/BEP20.sol";

contract GoldenRupee is BEP20("Golden Rupee", "gRUPEE") {
    /// @dev Creates `_amount` token to `_to`. Must only be called by the owner.
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}
