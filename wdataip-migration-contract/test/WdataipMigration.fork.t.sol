// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WdataipMigration} from "../src/WdataipMigration.sol";

/// @notice Sanity check against the real wIP and WDATAIP tokens on BSC mainnet.
/// @dev Skipped unless the BSC_RPC environment variable is set. Run with:
///      BSC_RPC=<url> forge test --match-path test/WdataipMigration.fork.t.sol -vvv
contract WdataipMigrationForkTest is Test {
    address internal constant WIP = 0x4d6394bC3031F751EdcE368C189b0E060b527107;
    address internal constant WDATAIP = 0xA37EDed373c5cdF88644db7C6b89f222e756aFB2;

    WdataipMigration internal migration;
    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");

    function setUp() public {
        string memory rpc = vm.envOr("BSC_RPC", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc);
        migration = new WdataipMigration(IERC20(WIP), IERC20(WDATAIP), owner);
    }

    function test_fork_realTokensMigrate1to1() public {
        if (address(migration) == address(0)) {
            vm.skip(true);
            return;
        }

        uint256 amount = 1_000 ether;

        // Fund the user with real wIP and the contract with real WDATAIP.
        deal(WIP, user, amount, true);
        deal(WDATAIP, address(migration), amount, true);

        vm.prank(user);
        IERC20(WIP).approve(address(migration), amount);

        uint256 userWdataipBefore = IERC20(WDATAIP).balanceOf(user);
        vm.prank(user);
        migration.migrate(amount);

        assertEq(IERC20(WIP).balanceOf(user), 0);
        assertEq(IERC20(WDATAIP).balanceOf(user) - userWdataipBefore, amount);
        assertEq(IERC20(WIP).balanceOf(address(migration)), amount);
        assertEq(migration.availableWdataip(), 0);
    }
}
