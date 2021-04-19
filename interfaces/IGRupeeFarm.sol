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

interface IGRupeeFarm {
    function add(
        uint256 _allocPoint,
        address _want,
        bool _withUpdate,
        address _strategy
    ) external;

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external;
}
