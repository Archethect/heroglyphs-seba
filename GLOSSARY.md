# Seba yield funding

Terms for validator funding and the proposed native-token YieldManager V2. Legacy manager terms retain their historical
units; do not reinterpret old amounts as V2 principal.

## Language

**Leg**: One independently accounted exposure: rETH or ysyBOLD. A leg has one custody token and one native principal
unit. _Avoid_: Shared portfolio, interchangeable strategy balance

**Native principal basis**: The recognized value protected at entry, measured in ETH for rETH or yBOLD for ysyBOLD,
reduced when its claim closes. It is neither a guaranteed payout nor a fixed count of custody tokens. _Avoid_:
Guaranteed principal, deposited ETH when only tokens were deposited

**Custody tokens**: The actual rETH or ysyBOLD held to back a leg's claims and unharvested carry. _Avoid_: ETH balance,
principal units

**Supporter position**: A nontransferable owner claim in one leg, with its own native principal basis and 30-day unlock.
Treasury-owned positions are still supporter positions. _Avoid_: Protocol principal, fungible vault share

**Protocol capital**: Seba-owned invested rewards or explicitly imported legacy protocol assets, accounted separately
from all supporter positions. _Avoid_: Treasury deposits, supporter principal

**Bucket**: The protocol-owned or supporter-owned accounting compartment within a leg, with separate basis and token
backing. _Avoid_: Separate strategy, common NAV

**Recognized yield**: Native value above protected principal currently reflected in the external protocol's accounting
and available for donation. Unreported or future-unlocking value is not promised to be stripped from returned tokens.
_Avoid_: All future yield, guaranteed interest

**Carry**: Accounted custody tokens above a bucket's conservative principal reserve, not yet delivered as validator
yield. _Avoid_: Completed donation, free principal

**Completed donation**: An actual sBOLD top-up delivered to the existing pybSeba system, counted once. _Avoid_:
Harvested inventory, pending conversion

**Economic deficit**: A bucket's recognized native backing below its remaining nominal principal basis, despite intact
custody-token accounting. _Avoid_: Custody shortage, automatic write-down

**Custody shortage**: Actual custody tokens below the sum of the leg's accounted backing, requiring reconciliation
rather than ordinary cross-bucket payouts. _Avoid_: Market loss, stale price

**Repair**: An explicit token contribution to a named bucket without creating new principal claims. _Avoid_: New
deposit, automatic subsidy

**Recovery settlement**: A funded, fixed native-token allocation against snapshotted principal claims, paid through
their original claim records. _Avoid_: Direct treasury reimbursement, guaranteed ETH exit

**Future investment weights**: Percentages assigning only new protocol investment cash between legs; they do not
rebalance existing positions or pending assignments. _Avoid_: Portfolio rebalance, supporter allocation weights
