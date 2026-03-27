# LibResInfo-2.0 API and Callbacks

All APIs and callbacks are embedded on the addon object.

```lua
local MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibResInfo-2.0")

local info = MyAddon:GetIncomingResInfo("player")
```

---

## Table of Contents

- [APIs](#apis)
  - [GetIncomingResInfo](#getincomingresinfounit)
  - [UnitHasIncomingRes](#unithasincomingresunit)
- [Callbacks](#callbacks)
  - [LRI2_ResStarted](#lri2_resstartedcallback-infotable)
  - [LRI2_ResPending](#lri2_respendingcallback-infotable)
  - [LRI2_ResSuccess](#lri2_ressuccesscallback-infotable)
  - [LRI2_ResExpired](#lri2_resexpiredcallback-infotable)
- [Info Table](#info-table)

---

## APIs

---

### `GetIncomingResInfo(unit)`

Returns res information about the unit.

Arguments

- `unit` *(string)*
  A valid unitID (e.g. `"player"`, `"target"`, `"party1"`)

Returns

- `infoTable` *(table|nil)*
  Returns nil if no resurrection is active.

Example

```lua
local info = MyAddon:GetIncomingResInfo("player")

if info then
    print(info.spellID)
end
```

---

### `UnitHasIncomingRes(unit)`

Returns whether the unit has an incoming resurrection.

Arguments

- `unit` *(string)*

Returns

- `hasRes` *(boolean)*

Example

```lua
if MyAddon:UnitHasIncomingRes("target") then
    -- do something
end
```

---

## Callbacks

Callbacks are registered using:

```lua
MyAddon:RegisterCallback("LRI2_ResPending")
```

---

### `LRI2_ResStarted(callback, infoTable)`

Fired when a resurrection cast is detected.

- Confidence: MEDIUM (inferred)

---

### `LRI2_ResPending(callback, infoTable)`

Fired when the game confirms a resurrection is pending.

- Confidence: HIGH

---

### `LRI2_ResSuccess(callback, infoTable)`

Fired when a resurrection successfully completes.

---

### `LRI2_ResExpired(callback, infoTable)`

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

#### `casterGUID`

- `string` → known caster
- `false` → unknown or external caster

---

#### `isFastest`

Indicates whether this resurrection will resolve first for the target.

---

#### `baseTexture` / `overrideTexture`

- `baseTexture` → original spell icon
- `overrideTexture` → modified icon (if applicable)

If no modification exists, `overrideTexture` will be `nil`.

---

#### `confidence`

- `"MEDIUM"` → inferred from observed spellcasting and timing
- `"HIGH"` → confirmed by game-provided resurrection state

---

## Notes

- All returned tables are copies (safe to read, do not modify)
- Data is best-effort and may be incomplete depending on game limitations
