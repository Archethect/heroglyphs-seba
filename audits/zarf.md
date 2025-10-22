# Seba audit


## Overview

* Repository: [Archethect/hero_boost](https://github.com/Archethect/hero_boost)
* Commit: [dd9a114eafc8aef443f4e42975f8575d300ca4fc](https://github.com/Archethect/hero_boost/tree/dd9a114eafc8aef443f4e42975f8575d300ca4fc)
* Scope
```
├── interfaces
│   ├── IEthToBoldRouter.sol
│   ├── IEUSDUSDCBeefyYieldVault.sol
│   ├── IPoap.sol
│   ├── IPYBSeba.sol
│   ├── ISebaPool.sol
│   ├── IYieldManager.sol
│   └── IYieldVault.sol
├── PYBSeba.sol
├── SebaPool.sol
├── EthToBoldRouter.sol
├── EUSDUSDCBeefyYieldVault.sol
├── YieldManager.sol
├── EthToBoldRouter.sol
├── EUSDUSDCBeefyYieldVault.sol
└── vendor
    ├── beefy
    │   └── IBeefyVault.sol
    ├── chainlink
    │   └── AggregatorV3Interface.sol
    ├── cowswap
    │   ├── IEthFlow.sol
    │   └── IGPv2Settlement.sol
    ├── curve
    │   └── ICurvePool.sol
    ├── liquity
    │   └── ISBOLD.sol
    ├── uniswap_v3
    │   ├── IQuoter.sol
    │   └── ISwapRouter.sol
    └── various
        └── IWETH.sol

```

This audit was conducted with the primary objective of ensuring the robustness of the protocol, specifically focusing on the security of user funds (i.e., preventing scenarios where funds could be stolen or become irretrievable). To save time, the scope of this audit was limited to the identification of critical, high, and medium severity issues. Low-severity issues, notes, and optimizations were not included in this review.

The key areas of focus were:

* ERC4626-related attack vectors
* Cowswap intent for ETH → BOLD conversions
* BOLD → sBOLD conversion process
* Correct separation of principal and yield
* Robustness of yield vault flows (e.g., ETH ↔ Beefy shares)
* Guaranteeing users can retrieve their deposited funds
* Access control mechanisms


## Issues

### Vulnerability: Yield Theft via Front-Running `topup` Transactions

Severity: Medium (low likelihood, high impact)

#### Description
The protocol's design intentionally allows for a "revolving door" share market in the `PYBSeba` vault: when a graduated validator redeems their shares, the supplyCap is not reduced, making those shares available for purchase by outside
investors.

This design, however, creates a state where the vault can be empty (totalSupply is 0) but still open for deposits (supplyCap > 0). This state is vulnerable to a sandwich attack. An attacker can monitor the network
for a pending `topup()` transaction from the `YieldManager` and execute the following:

1. Front-run: Deposit a minimal amount (1 wei) into the empty vault, becoming the sole shareholder.
2. Allow `topup`: The `YieldManager`'s `topup()` transaction executes. Because it adds assets without minting shares, it acts as a "blind donation," attributing the entire value of the topped-up yield to the attacker's single share.
3. Back-run: The attacker redeems their share, claiming their initial deposit plus the entire yield amount from the topup.

#### Likelihood
The likelihood of this attack is considered low as it requires a a completely empty vault (i.e. all the shares have been redeemed by the graduated validators).

#### Impact
The impact is high. A successful attack results in the direct theft of all protocol funds being added through the topup function and will not be accredited to the shares distributed to future graduated validators.

#### Recommendation
The conflict arises from two intended design choices: the "revolving door" `supplyCap` and the "blind donation" `topup` function. Either of the following options could be considered

* Prevent the attack completely by ensuring the vault can never enter the vulnerable "empty but open" state by overriding the internal `_burn` function (called by `withdraw` and `redeem`) to decrease the `supplyCap` as shares are burned. This is the most secure approach. However, it removes the intended feature for outsiders to buy vacated shares. The vault effectively becomes a closed system where share "slots," once redeemed, are destroyed.
* Maintain the current functionality, allowing non-validators to participate, but it requires accepting the vulnerability as a known risk: any `topup` transaction made while the vault is empty will likely result in the complete loss of those funds to a front-runner and not be accraccredited to future graduated validators.
