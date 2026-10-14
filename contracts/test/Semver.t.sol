// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Semver} from "../src/Semver.sol";

/// @notice Unit tests for the Semver base contract
contract SemverTest is Test {
    function test_version_formatsMajorMinorPatch() public {
        Semver semver = new Semver(1, 2, 3);

        assertEq(semver.version(), "1.2.3");
    }

    function test_version_zeroComponents() public {
        Semver semver = new Semver(0, 0, 0);

        assertEq(semver.version(), "0.0.0");
    }

    function test_version_largeComponents() public {
        Semver semver = new Semver(10, 20, 30);

        assertEq(semver.version(), "10.20.30");
    }
}
