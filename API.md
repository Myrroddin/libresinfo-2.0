# LibResInfo-2.0 API and Callbacks

All APIs and callbacks are embedded on the addon object.

```lua
local MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibResInfo-2.0")

local info = MyAddon:GetIncomingResInfo("player")
```

---

## Table of Contents

- APIs
  - GetIncomingResInfo
  - GetUnitIDFromGUID
- Callbacks
  - LRI2_UnitResStarted
  - LRI2_UnitResPending
  - LRI2_UnitResSuccess
  - LRI2_UnitResExpired
- Info Table

---

## APIs

---

### `GetIncomingResInfo(unitOrGUID)`

Returns res information about the unit.

Arguments

- unitOrGUID (string)
  A valid unitID (e.g. "player", "target", "party1")
  or a unitGUID

Returns

- infoTable (table or nil)
  Returns nil if no resurrection is active.

Example

```lua
local info = MyAddon:GetIncomingResInfo("player")

if info then
    print(info.spellID)
end
```

---

### `GetUnitIDFromGUID(guid)`

Returns a valid unitID for the given GUID if one is currently known and valid.

Arguments

- guid (string)

Returns

- unit (string or nil)
  A valid unitID if available, otherwise nil.

Example

```lua
local unit = MyAddon:GetUnitIDFromGUID(guid)

if unit then
    print(UnitName(unit))
end
```

---

## Callbacks

Callbacks are registered using:

```lua
MyAddon:RegisterCallback("LRI2_UnitResPending")
```

---

### `LRI2_UnitResStarted(callback, infoTable)`

Fired when a resurrection cast is detected.

- Confidence: MEDIUM (inferred)

---

### `LRI2_UnitResPending(callback, infoTable)`

Fired when the game confirms a resurrection is pending.

- Confidence: HIGH

---

### `LRI2_UnitResSuccess(callback, infoTable)`

Fired when a resurrection successfully completes.

---

### `LRI2_UnitResExpired(callback, infoTable)`

Fired when a resurrection expires (not accepted in time).

---

## Info Table

All APIs and callbacks return the same structure.

```lua
info = {
    state = "CASTING" | "PENDING" | "SUCCESS" | "EXPIRED",

    targetGUID = string,
    casterGUID = string|false,

    spellID = number|nil,

    castStartTime = number|nil,
    castEndTime = number|nil,

    expiresAt = number|nil,

    confidence = "MEDIUM" | "HIGH",

    isFastest = boolean,

    baseTexture = number|nil,
    overrideTexture = number|nil,
}
```

---

### Field Notes

casterGUID

- string → known caster
- false → unknown or external caster

---

isFastest

Indicates whether this resurrection will resolve first for the target.

---

baseTexture / overrideTexture

- baseTexture → original spell icon
- overrideTexture → modified icon (if applicable)

If no modification exists, overrideTexture will be nil.

---

confidence

- "MEDIUM" → inferred from observed spellcasting and timing
- "HIGH" → confirmed by game-provided resurrection state

---

## Notes

- All returned tables are copies (safe to read, do not modify)
- Data is best-effort and may be incomplete depending on game limitations
