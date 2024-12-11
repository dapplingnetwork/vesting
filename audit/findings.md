# Findings

# Potential Findings

## High

### [H-1]. Claimable after Vesting's `endTime` exceeds

**Description:** the `VestingContract:claim` does not check whether `Vesting::endTime` expired, then allows the calculation of the allTime `ReleasableShares` of a beneficiary so as to claim `shares` on `GGPVault`.

- Safety checks only against `isActive` and `cliffTime` states.
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

### [L-1]. floating `pragma` vulnerabilitiy

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

### [L-2]. The `getReleasableShares` function allows the yield calculation for vestings already expired.

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

````diff
 function getReleasableShares(address beneficiary){
-  uint256 totalUnlockedShares =
-            (vesting.totalShares * (timeElapsed * totalIntervals / totalTime)) / totalIntervals;
+  uint256 totalUnlockedShares = (vesting.totalShares * timeElapsed  / totalTime);
 }
```****

# Denied-Findings

- function `stakeOnBehalfOf`it's not aligned with gradually investment approach: `SingleDeposit`

### Reentrancies

- at `claim()`, beneficiaries might be `contracts`, can they force reentrancies on `redeem`?
  - No,OZ ERC4726 only performs `_update` balances on `GGPToken` address;
  - No, No Hooks executed on transfer
- at `stakeOnBehalfOf`, beneficiaries might be `contracts`, can they force reentrancies on `deposit`?
  - No,OZ ERC4726 only performs `_update` balances on `GGPToken` address;
  - No, No Hooks executed on transfer
````
