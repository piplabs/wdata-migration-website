// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WdataipMigration} from "../src/WdataipMigration.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Drives random sequences of migrate / rescue / donate against the migration contract and
///         tracks ghost sums, so the invariant test can assert exact reserve accounting. Assumes
///         standard fee-free 18-decimal tokens (the real wIP/WDATAIP assumption).
contract Handler is Test {
    WdataipMigration public immutable migration;
    MockERC20 public immutable wip;
    MockERC20 public immutable wdataip;
    address public immutable owner;

    uint256 public ghostMigrated; // wIP pulled in == WDATAIP paid out
    uint256 public ghostWipRescued;
    uint256 public ghostWdataipRescued;
    uint256 public ghostWipDonated;
    uint256 public ghostWdataipDonated;

    constructor(WdataipMigration _m, MockERC20 _wip, MockERC20 _wd, address _owner) {
        migration = _m;
        wip = _wip;
        wdataip = _wd;
        owner = _owner;
    }

    // A user migrates a bounded amount that the reserve can currently cover (so the call succeeds).
    function migrate(uint256 amount, uint256 userSeed) external {
        uint256 reserve = migration.availableWdataip();
        if (reserve == 0) return;
        amount = bound(amount, 1, reserve);
        address u = address(uint160(uint256(keccak256(abi.encode("user", userSeed)))));
        wip.mint(u, amount);
        vm.prank(u);
        wip.approve(address(migration), amount);
        vm.prank(u);
        migration.migrate(amount);
        ghostMigrated += amount;
    }

    function rescueWip(uint256 amount) external {
        uint256 bal = wip.balanceOf(address(migration));
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(owner);
        migration.rescue(IERC20(address(wip)), owner, amount);
        ghostWipRescued += amount;
    }

    function rescueWdataip(uint256 amount) external {
        uint256 bal = wdataip.balanceOf(address(migration));
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(owner);
        migration.rescue(IERC20(address(wdataip)), owner, amount);
        ghostWdataipRescued += amount;
    }

    function donateWip(uint256 amount) external {
        amount = bound(amount, 1, 1_000 ether);
        wip.mint(address(this), amount);
        wip.transfer(address(migration), amount);
        ghostWipDonated += amount;
    }

    function donateWdataip(uint256 amount) external {
        amount = bound(amount, 1, 1_000 ether);
        wdataip.mint(address(this), amount);
        wdataip.transfer(address(migration), amount);
        ghostWdataipDonated += amount;
    }
}

contract WdataipMigrationInvariantTest is Test {
    WdataipMigration internal migration;
    MockERC20 internal wip;
    MockERC20 internal wdataip;
    Handler internal handler;

    address internal owner = makeAddr("owner");
    uint256 internal constant INITIAL_FUNDING = 1_000_000 ether;

    function setUp() public {
        wip = new MockERC20("Wrapped IP", "wIP");
        wdataip = new MockERC20("Wrapped DATAIP", "WDATAIP");
        migration = new WdataipMigration(IERC20(address(wip)), IERC20(address(wdataip)), owner);
        wdataip.mint(address(migration), INITIAL_FUNDING);

        handler = new Handler(migration, wip, wdataip, owner);
        targetContract(address(handler));
    }

    /// @notice wIP held == everything migrated in + donated - rescued out.
    function invariant_wipBalanceAccounting() public view {
        assertEq(
            wip.balanceOf(address(migration)),
            handler.ghostMigrated() + handler.ghostWipDonated() - handler.ghostWipRescued()
        );
    }

    /// @notice WDATAIP reserve == initial funding + donations - migrated out - rescued out, and
    ///         availableWdataip() always tracks the live balance.
    function invariant_wdataipReserveAccounting() public view {
        uint256 expected = INITIAL_FUNDING + handler.ghostWdataipDonated() - handler.ghostMigrated()
            - handler.ghostWdataipRescued();
        assertEq(wdataip.balanceOf(address(migration)), expected);
        assertEq(migration.availableWdataip(), expected);
    }
}
