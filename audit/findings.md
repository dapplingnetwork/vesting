# Findings

# Potential Findings

## High

### [H-1]. Beneficiares can claim more tokens than expected.

**Description:** the `VestingContract:claim` trusts on the calculation of the allTime `ReleasableShares` of a beneficiary so as to claim `shares` on `GGPVault`, calculation that is not constrained to vesting's `endTime`;

- All time `ReleasableShares` calculation.

```javascript
  function claim() external {
    require(vesting.isActive, "No active vesting");
    require(block.timestamp >= vesting.cliffTime, "Cliff period not reached");

@>  uint256 releasableShares = getReleasableShares(msg.sender);


@>  if(releasableShares > 0) {
      releasableAssets += seafiVault.redeem(releasableShares, msg.sender, address(this));
    }
  }
```

```javascript
  function getReleasableShares(){
    uint256 totalUnlockedShares =
              (vesting.totalShares * (timeElapsed * totalIntervals / totalTime)) / totalIntervals;
  }
```

**Impact:** Potential Drain of funds.
**Proof Of Concept:**

```javascript
  function test_CanClaimEvenWhenVestingEndTimeExceeds() public {
    _vest();
    (,,,, uint256 endTimeAfterClaim,,,) = vestingContract.vestingInfo(beneficiary);
    vm.warp(block.timestamp + endTimeAfterClaim + 1000);

    vm.prank(beneficiary);
    vestingContract.claim();
  }
```

**Recommneded Mitigation:**

Limit `getReleasableShares` calculation until `endTime`.

## Low

### [L-1]. Unable to `VestingContract::cancelVesting` if vesting claimed

**Description:** Vestings can be cancelled if there's enough funds to claim otherwise it reverts, not being possible to set the `isActive` state to false. Besides, it's not possible to start a new vesting if there's an active one.

```javascript
  function cancelVesting(address beneficiary) external onlyRole(DEFAULT_ADMIN_ROLE) {
    Vesting storage vesting = vestingInfo[beneficiary];

    uint256 vestedAmount = vesting.vestedAmount;
    uint256 remainingShares = vesting.totalShares - vesting.releasedShares;

    require(remainingShares > 0 || vestedAmount > 0, "No assets to withdraw");
    //impl
  }
```

**Impact:** Unable to initiate a new vesting process.

**Proof of concept:**

```javascript
  function test_CannotCancelVestingOnceClaimed() public {
    _vest(beneficiary, 1_000 ether);

    vm.warp(block.timestamp + 365 days);

    vm.prank(beneficiary);
    vestingContract.claim();

    vm.expectRevert(bytes("No assets to withdraw"));
    vestingContract.cancelVesting(beneficiary);
  }
```

---

### [L-2]. floating `pragma` vulnerabilitiy

**Description:** floating pragma version might introduce new feature that might alter the behavior of the contract

```javascript
   pragma solidity ^0.8.22;
```

**Impact:** disrupt contract's behavior.

**Recommended Mitigation:**
Use a specific version of solidity pragma instead of floating points

```diff
-  pragma solidity ^0.8.22;
+  pragma solidity 0.8.22;
```

### [L-3]. The `getReleasableShares` function allows the yield calculation for vestings already expired.

**Description:** affects the `claim` function. Also, users might get confused that if their vesting is not `cancelled` but `ended`, They will still assume as valid yield.

**Impact:** checkout `[H-1]`

## Informational

### [I-1]. GPP's are transfered from the multisig wallet, not from investor's holdings.

### [I-2]. The receiver is the contract itself so beneficiaries won't own received xGGPs.

# Gas

### [G-1] Perform a single storage write

**Description:** Each individual assignment to vesting triggers a separate storage write (expensive operations for each 32-bytes slot).

```javascript
vesting.totalShares = shares;
vesting.vestedAmount = vestedAmount;
vesting.startTime = startTime;
vesting.endTime = endTime;
vesting.cliffTime = cliffTime;
vesting.vestingIntervals = totalIntervals;
vesting.isActive = true;
```

**Optimization:**
Cache vesting in memory and perform a single storage write

```diff
+   Vesting storage _vesting = vestingInfo[beneficiary];
    //impl
+   vesting[beneficiary]=_vesting.
```

### [G-2] Simplify `getReleasableShares::totalUnlockedShares` calculation formula

**Description:** the current formula for `totalUnlockedShares` contains more operations involved.

```diff
 function getReleasableShares(address beneficiary){
-  uint256 totalUnlockedShares =
-            (vesting.totalShares * (timeElapsed * totalIntervals / totalTime)) / totalIntervals;
+  uint256 totalUnlockedShares = (vesting.totalShares * timeElapsed  / totalTime);
 }
```

# Denied-Findings

- function `stakeOnBehalfOf`it's not aligned with gradually investment approach: `SingleDeposit`

### Reentrancies

- at `claim()`, beneficiaries might be `contracts`, can they force reentrancies on `redeem`?
  - No,OZ ERC4726 only performs `_update` balances on `GGPToken` address;
  - No, No Hooks executed on transfer
- at `stakeOnBehalfOf`, beneficiaries might be `contracts`, can they force reentrancies on `deposit`?
  - No,OZ ERC4726 only performs `_update` balances on `GGPToken` address;
  - No, No Hooks executed on transfer
