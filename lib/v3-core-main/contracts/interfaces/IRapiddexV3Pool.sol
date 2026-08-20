// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './pool/IRapiddexV3PoolImmutables.sol';
import './pool/IRapiddexV3PoolState.sol';
import './pool/IRapiddexV3PoolDerivedState.sol';
import './pool/IRapiddexV3PoolActions.sol';
import './pool/IRapiddexV3PoolOwnerActions.sol';
import './pool/IRapiddexV3PoolEvents.sol';

/// @title The interface for a Rapiddex V3 Pool
/// @notice A Rapiddex pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IRapiddexV3Pool is
    IRapiddexV3PoolImmutables,
    IRapiddexV3PoolState,
    IRapiddexV3PoolDerivedState,
    IRapiddexV3PoolActions,
    IRapiddexV3PoolOwnerActions,
    IRapiddexV3PoolEvents
{

}
