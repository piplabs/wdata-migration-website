// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title WdataipMigration
/// @notice One-way 1:1 migration from wIP to WDATAIP on BNB Smart Chain.
/// @dev Users deposit `wip` and receive an equal amount of `wdataip` from this contract's
///      pre-funded balance. No minting is performed: the contract must be funded with
///      `wdataip` via a separate transaction before migrations can succeed. Both tokens use
///      18 decimals, so the swap is a raw-amount 1:1 transfer.
contract WdataipMigration is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice The legacy token deposited by users (wIP).
    /// @dev Lowercase getter name (`wip()`) is the intended public ABI for frontend integration.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IERC20 public immutable wip;

    /// @notice The new token dispensed to users (WDATAIP).
    /// @dev Lowercase getter name (`wdataip()`) is the intended public ABI for frontend integration.
    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    IERC20 public immutable wdataip;

    /// @notice Emitted when a user migrates `amount` of wIP into WDATAIP.
    event Migrated(address indexed user, uint256 amount);

    /// @notice Emitted when the owner rescues `amount` of `token` to `to`.
    event Rescued(address indexed token, address indexed to, uint256 amount);

    /// @notice Thrown when an amount argument is zero.
    error ZeroAmount();

    /// @notice Thrown when an address argument is the zero address.
    error ZeroAddress();

    /// @notice Thrown when the two token addresses are identical.
    error IdenticalTokens();

    /// @notice Thrown when the contract holds less WDATAIP than the requested migration amount.
    /// @param available The WDATAIP balance currently held by this contract.
    /// @param required The WDATAIP amount needed to cover the migration.
    error WDATAIPInsufficientReserves(uint256 available, uint256 required);

    /// @param _wip The legacy wIP token address.
    /// @param _wdataip The new WDATAIP token address.
    /// @param _owner The initial owner (holds the rescue privilege via Ownable2Step).
    constructor(IERC20 _wip, IERC20 _wdataip, address _owner) Ownable(_owner) {
        if (address(_wip) == address(0) || address(_wdataip) == address(0)) {
            revert ZeroAddress();
        }
        if (address(_wip) == address(_wdataip)) revert IdenticalTokens();
        wip = _wip;
        wdataip = _wdataip;
    }

    /// @notice Migrate `amount` of wIP into an equal amount of WDATAIP.
    /// @dev The caller must approve this contract to spend `amount` of wIP first. Reverts if
    ///      this contract does not hold enough WDATAIP to cover the 1:1 payout.
    /// @param amount The amount of wIP to deposit (and WDATAIP to receive), in wei (18 decimals).
    function migrate(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 available = wdataip.balanceOf(address(this));
        if (available < amount) revert WDATAIPInsufficientReserves(available, amount);
        wip.safeTransferFrom(msg.sender, address(this), amount);
        wdataip.safeTransfer(msg.sender, amount);
        emit Migrated(msg.sender, amount);
    }

    /// @notice Withdraw `amount` of any `token` held by this contract to `to`.
    /// @dev Owner-only. Covers both wIP (accumulated from migrations) and unmigrated WDATAIP
    ///      liquidity, as well as any tokens sent here by mistake.
    /// @param token The token to withdraw.
    /// @param to The recipient.
    /// @param amount The amount to withdraw.
    function rescue(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        token.safeTransfer(to, amount);
        emit Rescued(address(token), to, amount);
    }

    /// @notice The amount of WDATAIP currently available to pay out migrations.
    function availableWdataip() external view returns (uint256) {
        return wdataip.balanceOf(address(this));
    }
}
