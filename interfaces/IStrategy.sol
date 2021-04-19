// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

interface IStrategy {
    // Total want tokens managed by stragety
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // Main want token compounding function
    function earn() external;

    // Transfer want tokens masterchef -> strategy
    function deposit(address _userAddress, uint256 _wantAmt) external returns (uint256);

    // Transfer want tokens strategy -> masterchef
    function withdraw(address _userAddress, uint256 _wantAmt) external returns (uint256);

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external;
}
