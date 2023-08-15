// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

struct Beneficiary {
    address recip;
    address token;
    uint128 amount;
    uint8 decimals;
    bool isLinear;
    bool cancellable;
}