// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {WdataipMigration} from "../src/WdataipMigration.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract WdataipMigrationTest is Test {
    WdataipMigration internal migration;
    MockERC20 internal wip;
    MockERC20 internal wdataip;

    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");
    address internal recipient = makeAddr("recipient");

    uint256 internal constant FUNDING = 1_000_000 ether;

    event Migrated(address indexed user, uint256 amount);
    event Rescued(address indexed token, address indexed to, uint256 amount);

    function setUp() public {
        wip = new MockERC20("Wrapped IP", "wIP");
        wdataip = new MockERC20("Wrapped DATAIP", "WDATAIP");
        migration = new WdataipMigration(IERC20(address(wip)), IERC20(address(wdataip)), owner);

        // Pre-fund the migration contract with WDATAIP, as an external TX would.
        wdataip.mint(address(migration), FUNDING);
    }

    function _fundAndApprove(address who, uint256 amount) internal {
        wip.mint(who, amount);
        vm.prank(who);
        wip.approve(address(migration), amount);
    }

    // --- constructor ---

    function test_constructor_setsImmutablesAndOwner() public view {
        assertEq(address(migration.wip()), address(wip));
        assertEq(address(migration.wdataip()), address(wdataip));
        assertEq(migration.owner(), owner);
        assertEq(migration.availableWdataip(), FUNDING);
    }

    function test_constructor_revertsOnZeroToken() public {
        vm.expectRevert(WdataipMigration.ZeroAddress.selector);
        new WdataipMigration(IERC20(address(0)), IERC20(address(wdataip)), owner);

        vm.expectRevert(WdataipMigration.ZeroAddress.selector);
        new WdataipMigration(IERC20(address(wip)), IERC20(address(0)), owner);
    }

    function test_constructor_revertsOnIdenticalTokens() public {
        vm.expectRevert(WdataipMigration.IdenticalTokens.selector);
        new WdataipMigration(IERC20(address(wip)), IERC20(address(wip)), owner);
    }

    function test_constructor_revertsOnZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new WdataipMigration(IERC20(address(wip)), IERC20(address(wdataip)), address(0));
    }

    // --- migrate ---

    function test_migrate_happyPath() public {
        uint256 amount = 100 ether;
        _fundAndApprove(user, amount);

        vm.expectEmit(true, false, false, true, address(migration));
        emit Migrated(user, amount);

        vm.prank(user);
        migration.migrate(amount);

        assertEq(wip.balanceOf(user), 0);
        assertEq(wdataip.balanceOf(user), amount);
        assertEq(wip.balanceOf(address(migration)), amount);
        assertEq(wdataip.balanceOf(address(migration)), FUNDING - amount);
    }

    function test_migrate_revertsOnZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(WdataipMigration.ZeroAmount.selector);
        migration.migrate(0);
    }

    function test_migrate_revertsWithoutApproval() public {
        wip.mint(user, 100 ether);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(migration), 0, 100 ether)
        );
        migration.migrate(100 ether);
    }

    function test_migrate_revertsWhenUnderfunded() public {
        uint256 amount = FUNDING + 1;
        _fundAndApprove(user, amount);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(WdataipMigration.WDATAIPInsufficientReserves.selector, FUNDING, amount)
        );
        migration.migrate(amount);
    }

    function test_migrate_revertsWhenFullyDrained() public {
        // Drain all WDATAIP reserves so the contract holds nothing.
        vm.prank(owner);
        migration.rescue(IERC20(address(wdataip)), recipient, FUNDING);
        assertEq(migration.availableWdataip(), 0);

        uint256 amount = 1 ether;
        _fundAndApprove(user, amount);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(WdataipMigration.WDATAIPInsufficientReserves.selector, 0, amount)
        );
        migration.migrate(amount);

        // wIP is never pulled when reserves are insufficient.
        assertEq(wip.balanceOf(user), amount);
        assertEq(wip.balanceOf(address(migration)), 0);
    }

    function test_migrate_drainsExactlyAvailable() public {
        _fundAndApprove(user, FUNDING);
        vm.prank(user);
        migration.migrate(FUNDING);

        assertEq(migration.availableWdataip(), 0);
        assertEq(wdataip.balanceOf(user), FUNDING);
    }

    // --- rescue ---

    function test_rescue_ownerPullsBothTokens() public {
        // Generate some wIP in the contract via a migration first.
        uint256 amount = 250 ether;
        _fundAndApprove(user, amount);
        vm.prank(user);
        migration.migrate(amount);

        // Rescue the accumulated wIP.
        vm.expectEmit(true, true, false, true, address(migration));
        emit Rescued(address(wip), recipient, amount);
        vm.prank(owner);
        migration.rescue(IERC20(address(wip)), recipient, amount);
        assertEq(wip.balanceOf(recipient), amount);

        // Rescue remaining WDATAIP liquidity.
        uint256 remaining = migration.availableWdataip();
        vm.prank(owner);
        migration.rescue(IERC20(address(wdataip)), recipient, remaining);
        assertEq(wdataip.balanceOf(recipient), remaining);
        assertEq(migration.availableWdataip(), 0);
    }

    function test_rescue_revertsForNonOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        migration.rescue(IERC20(address(wdataip)), recipient, 1 ether);
    }

    function test_rescue_revertsOnZeroRecipient() public {
        vm.prank(owner);
        vm.expectRevert(WdataipMigration.ZeroAddress.selector);
        migration.rescue(IERC20(address(wdataip)), address(0), 1 ether);
    }

    function test_rescue_revertsOnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(WdataipMigration.ZeroAmount.selector);
        migration.rescue(IERC20(address(wdataip)), recipient, 0);
    }

    // --- Ownable2Step ---

    function test_ownership_isTwoStep() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        migration.transferOwnership(newOwner);
        // Ownership does not change until accepted.
        assertEq(migration.owner(), owner);
        assertEq(migration.pendingOwner(), newOwner);

        vm.prank(newOwner);
        migration.acceptOwnership();
        assertEq(migration.owner(), newOwner);
        assertEq(migration.pendingOwner(), address(0));
    }

    function test_ownership_onlyPendingCanAccept() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        migration.transferOwnership(newOwner);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        migration.acceptOwnership();
    }

    // --- fuzz ---

    function testFuzz_migrate(uint256 amount) public {
        amount = bound(amount, 1, FUNDING);
        _fundAndApprove(user, amount);

        vm.prank(user);
        migration.migrate(amount);

        // 1:1 conservation.
        assertEq(wdataip.balanceOf(user), amount);
        assertEq(wip.balanceOf(address(migration)), amount);
        assertEq(wdataip.balanceOf(address(migration)), FUNDING - amount);
    }

    function testFuzz_migrate_multipleUsers(uint256 a, uint256 b) public {
        a = bound(a, 1, FUNDING / 2);
        b = bound(b, 1, FUNDING / 2);
        address user2 = makeAddr("user2");

        _fundAndApprove(user, a);
        vm.prank(user);
        migration.migrate(a);

        _fundAndApprove(user2, b);
        vm.prank(user2);
        migration.migrate(b);

        // Total WDATAIP dispensed equals total wIP collected, never exceeding funding.
        uint256 totalOut = wdataip.balanceOf(user) + wdataip.balanceOf(user2);
        assertEq(totalOut, a + b);
        assertEq(wip.balanceOf(address(migration)), a + b);
        assertEq(wdataip.balanceOf(address(migration)), FUNDING - (a + b));
        assertLe(totalOut, FUNDING);
    }

    function testFuzz_rescue(uint256 amount, address to) public {
        vm.assume(to != address(0) && to != address(migration));
        amount = bound(amount, 1, FUNDING);

        vm.prank(owner);
        migration.rescue(IERC20(address(wdataip)), to, amount);

        assertEq(wdataip.balanceOf(to), amount);
        assertEq(migration.availableWdataip(), FUNDING - amount);
    }
}
