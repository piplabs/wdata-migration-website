// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WdataipMigration} from "../src/WdataipMigration.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Adversarial / edge-case tests beyond the happy-path unit suite: non-standard tokens
///         (fee-on-transfer, reentrant, non-18-decimals), owner front-running, balance edges, and
///         donation immunity. These document the contract's trust assumptions and attack surface.
contract WdataipMigrationSecurityTest is Test {
    WdataipMigration internal migration;
    MockERC20 internal wip;
    MockERC20 internal wdataip;

    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");
    address internal attacker = makeAddr("attacker");
    address internal recipient = makeAddr("recipient");

    uint256 internal constant FUNDING = 1_000_000 ether;

    function setUp() public {
        wip = new MockERC20("Wrapped IP", "wIP");
        wdataip = new MockERC20("Wrapped DATAIP", "WDATAIP");
        migration = new WdataipMigration(IERC20(address(wip)), IERC20(address(wdataip)), owner);
        wdataip.mint(address(migration), FUNDING);
    }

    function _fundAndApprove(address who, uint256 amount) internal {
        wip.mint(who, amount);
        vm.prank(who);
        wip.approve(address(migration), amount);
    }

    // --- Fee-on-transfer assumption -------------------------------------------------------------
    // The contract does a raw 1:1 transfer; it never measures actual amount received. These tests
    // pin the BREAKAGE so it's understood and so a fork test can assert the real tokens are fee-free.

    /// @notice Fee-on-transfer wIP: the contract receives less wIP than `amount` but still pays out
    ///         the full `amount` of WDATAIP -> its WDATAIP reserve bleeds faster than wIP accrues.
    function test_feeOnTransfer_wip_bleedsReserve() public {
        FeeOnTransferERC20 feeWip = new FeeOnTransferERC20("Fee wIP", "fwIP", 100); // 1%
        WdataipMigration m = new WdataipMigration(IERC20(address(feeWip)), IERC20(address(wdataip)), owner);
        wdataip.mint(address(m), FUNDING);

        uint256 amount = 1000 ether;
        feeWip.mint(user, amount);
        vm.prank(user);
        feeWip.approve(address(m), amount);

        vm.prank(user);
        m.migrate(amount);

        // User paid 1000 wIP (1% burned in transfer) but received the full 1000 WDATAIP.
        assertEq(wdataip.balanceOf(user), amount, "user got full 1:1 WDATAIP");
        // Contract only received 990 wIP, yet dispensed 1000 WDATAIP -> 10 WDATAIP net loss.
        assertEq(feeWip.balanceOf(address(m)), amount - (amount * 100 / 10_000), "contract under-collects wIP");
        assertEq(m.availableWdataip(), FUNDING - amount, "reserve drops by full amount");
        // => over many migrations the reserve is drained by the fee delta. REQUIRES fee-free wIP.
    }

    /// @notice Fee-on-transfer WDATAIP: the user receives LESS than `amount` -> 1:1 conservation
    ///         breaks for the user. REQUIRES fee-free WDATAIP.
    function test_feeOnTransfer_wdataip_userShortfall() public {
        FeeOnTransferERC20 feeWd = new FeeOnTransferERC20("Fee WDATAIP", "fWD", 100); // 1%
        WdataipMigration m = new WdataipMigration(IERC20(address(wip)), IERC20(address(feeWd)), owner);
        feeWd.mint(address(m), FUNDING);

        uint256 amount = 1000 ether;
        _fundAndApprove(user, amount);
        // approve against the right contract
        vm.prank(user);
        wip.approve(address(m), amount);

        vm.prank(user);
        m.migrate(amount);

        // User received only 990 WDATAIP for 1000 wIP — short by the 1% fee.
        assertEq(feeWd.balanceOf(user), amount - (amount * 100 / 10_000), "user short-changed by fee");
        assertLt(feeWd.balanceOf(user), amount, "not 1:1 for the user");
    }

    // --- Reentrancy ------------------------------------------------------------------------------

    /// @notice A malicious wIP that re-enters migrate() during its transferFrom is blocked by
    ///         ReentrancyGuard — the whole call reverts.
    function test_reentrancy_isBlocked() public {
        ReentrantERC20 evilWip = new ReentrantERC20("Evil wIP", "ewIP");
        WdataipMigration m = new WdataipMigration(IERC20(address(evilWip)), IERC20(address(wdataip)), owner);
        wdataip.mint(address(m), FUNDING);

        uint256 amount = 1 ether;
        evilWip.mint(user, amount);
        vm.prank(user);
        evilWip.approve(address(m), amount);
        // Arm the token to re-enter migrate() on its next transfer into the migration contract.
        evilWip.arm(address(m), amount);

        vm.prank(user);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        m.migrate(amount);
    }

    // --- Decimals assumption ---------------------------------------------------------------------

    /// @notice With a non-18-decimals token the swap is still raw-amount 1:1, which is a VALUE
    ///         mismatch. Documents that both tokens must be 18 decimals for 1:1 to be meaningful.
    function test_decimalsMismatch_isRawAmount() public {
        SixDecimalERC20 sixWip = new SixDecimalERC20("6dec wIP", "6wIP");
        WdataipMigration m = new WdataipMigration(IERC20(address(sixWip)), IERC20(address(wdataip)), owner);
        wdataip.mint(address(m), FUNDING);

        uint256 amount = 1_000_000; // 1.0 token at 6 decimals
        sixWip.mint(user, amount);
        vm.prank(user);
        sixWip.approve(address(m), amount);

        vm.prank(user);
        m.migrate(amount);

        // 1.0 wIP (6dp) becomes 0.000000000001 WDATAIP (18dp) by raw amount — clearly wrong value.
        assertEq(wdataip.balanceOf(user), amount, "raw 1:1 regardless of decimals");
        assertEq(sixWip.decimals(), 6);
        assertEq(wdataip.decimals(), 18);
    }

    // --- Owner front-running ---------------------------------------------------------------------

    /// @notice Owner rescuing the WDATAIP reserve after a user has approved but before they migrate
    ///         makes the migrate revert; the user's wIP is NOT pulled (checks before effects).
    function test_ownerRescueFrontRun_reverts_andWipUntouched() public {
        uint256 amount = 500 ether;
        _fundAndApprove(user, amount);

        // Owner front-runs by draining the entire reserve.
        vm.prank(owner);
        migration.rescue(IERC20(address(wdataip)), recipient, FUNDING);
        assertEq(migration.availableWdataip(), 0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(WdataipMigration.WDATAIPInsufficientReserves.selector, 0, amount));
        migration.migrate(amount);

        // User keeps their wIP; nothing was pulled.
        assertEq(wip.balanceOf(user), amount, "wIP not pulled on failed migrate");
        assertEq(wip.balanceOf(address(migration)), 0);
    }

    // --- Balance edge ----------------------------------------------------------------------------

    /// @notice Approving more than the wIP balance still reverts on the actual transfer.
    function test_migrate_revertsWhenWipBalanceTooLow() public {
        uint256 amount = 100 ether;
        wip.mint(user, amount - 1); // one wei short
        vm.prank(user);
        wip.approve(address(migration), amount);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user, amount - 1, amount)
        );
        migration.migrate(amount);
    }

    // --- Donation immunity -----------------------------------------------------------------------

    /// @notice Tokens sent directly to the contract (not via migrate) only increase reserves /
    ///         rescuable balance — accounting uses live balanceOf, so nothing breaks.
    function test_donation_increasesReserve_noBreakage() public {
        // Anyone donates WDATAIP directly.
        wdataip.mint(attacker, 5 ether);
        vm.prank(attacker);
        wdataip.transfer(address(migration), 5 ether);
        assertEq(migration.availableWdataip(), FUNDING + 5 ether, "donation counts toward reserve");

        // Migration still works 1:1.
        uint256 amount = 10 ether;
        _fundAndApprove(user, amount);
        vm.prank(user);
        migration.migrate(amount);
        assertEq(wdataip.balanceOf(user), amount);

        // A stray wIP donation is rescuable and doesn't affect WDATAIP accounting.
        wip.mint(attacker, 3 ether);
        vm.prank(attacker);
        wip.transfer(address(migration), 3 ether);
        uint256 stuckWip = wip.balanceOf(address(migration)); // read BEFORE prank (a call would consume it)
        vm.prank(owner);
        migration.rescue(IERC20(address(wip)), recipient, stuckWip);
        assertEq(wip.balanceOf(recipient), amount + 3 ether, "owner can rescue migrated + donated wIP");
    }
}

// ---------------------------------------------------------------------------------------------
// Helper tokens (test-only)
// ---------------------------------------------------------------------------------------------

/// @notice ERC20 that burns `feeBps` of every holder-to-holder transfer (mint/burn are fee-free).
contract FeeOnTransferERC20 is ERC20 {
    uint256 public immutable feeBps;
    address internal constant SINK = address(0xdEaD);

    constructor(string memory n, string memory s, uint256 _feeBps) ERC20(n, s) {
        feeBps = _feeBps;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0) || feeBps == 0) {
            super._update(from, to, value);
            return;
        }
        uint256 fee = (value * feeBps) / 10_000;
        super._update(from, to, value - fee);
        if (fee > 0) super._update(from, SINK, fee); // `super.` bypasses this override (no recursion)
    }
}

/// @notice ERC20 that re-enters `target.migrate()` once, on its next transfer INTO `target`.
contract ReentrantERC20 is ERC20 {
    address public target;
    uint256 public reenterAmount;
    bool public armed;

    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(address _target, uint256 _amount) external {
        target = _target;
        reenterAmount = _amount;
        armed = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (armed && to == target && target != address(0)) {
            armed = false; // one-shot
            WdataipMigration(target).migrate(reenterAmount); // re-enters -> ReentrancyGuard reverts
        }
    }
}

/// @notice 6-decimal ERC20 to exercise the decimals assumption.
contract SixDecimalERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
