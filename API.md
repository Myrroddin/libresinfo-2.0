# LibResInfo-2.0 API Documentation

LibResInfo-2.0 is a CLEU-free resurrection tracking library for World of Warcraft addons.

The library tracks:

- single-target resurrection casts
- mass resurrection casts
- resurrection targets becoming alive
- self-resurrection availability
- fastest resurrection resolution per target

---

## Table of Contents

- [Callback Registration](#callback-registration)
- [Public APIs](#public-apis)
  - [GetFastestCasterForUnit(unit)](#getfastestcasterforunitunit)
  - [IsUnitBeingResurrected(unit)](#isunitbeingresurrectedunit)
  - [UnitCanSelfResurrect(unit)](#unitcanselfresurrectunit)
  - [GetResurrectionCastInfo(unit)](#getresurrectioncastinfounit)
  - [GetCasterInfo(unit)](#getcasterinfounit)
  - [GetTargetInfo(unit)](#gettargetinfounit)
  - [GetAllCastersForUnit(unit)](#getallcastersforunitunit)
- [Callbacks](#callbacks)
  - [ResCast_Started](#rescast_started)
  - [ResCast_Stopped](#rescast_stopped)
  - [ResCast_Finished](#rescast_finished)
  - [MassResCast_Started](#massrescast_started)
  - [MassResCast_Stopped](#massrescast_stopped)
  - [MassResCast_Finished](#massrescast_finished)
  - [FastestRes_Changed](#fastestres_changed)
  - [ResTargetGUID_Resolved](#restargetguid_resolved)
  - [ResTargetGUID_IsAlive](#restargetguid_isalive)
  - [UnitSelfRes_Available](#unitselfres_available)
  - [UnitSelfRes_Consumed](#unitselfres_consumed)
- [Table Structures](#table-structures)
  - [ResCastInfo](#rescastinfo)
  - [ResTargetInfo](#restargetinfo)
  - [SelfResOptionInfo](#selfresoptioninfo)
- [Unknown Targets](#unknown-targets)
- [Mass Resurrection](#mass-resurrection)
- [Callback Tables](#callback-tables)
- [API Validation](#api-validation)

---

## Callback Registration

LibResInfo-2.0 embeds CallbackHandler-1.0 methods directly onto the addon object.
CallbackHandler passes the callback name as the first argument to callback handlers. The callback argument tables below begin after the callback name argument.

Example

Example

```lua
function MyAddon:ResCast_Started(callbackName, casterGUID, targetGUID, casterInfo, targetInfo)
    print(callbackName)
    --> "ResCast_Started"
end
```

```lua
local MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibResInfo-2.0")
```

Register callbacks normally:

```lua
MyAddon:RegisterCallback("ResCast_Started")
```

Unregister callbacks normally:

```lua
MyAddon:UnregisterCallback("ResCast_Started")
MyAddon:UnregisterAllResInfoCallbacks()
```

---

## Public APIs

---

### GetFastestCasterForUnit(unit)

Returns the fastest active resurrection caster for a unit.

Arguments

| Name | Type   | Description                |
|------|--------|----------------------------|
| unit | string | unitID, GUID, or unit name |

Returns

| Return     | Type                          | Description         |
|------------|-------------------------------|---------------------|
| casterGUID | string or false               | Fastest caster GUID |
| resType    | `"SINGLE"` \| `"MASS"` \| nil | Resurrection type   |

Example

```lua
local casterGUID, resType = MyAddon:GetFastestCasterForUnit("player")
```

---

### IsUnitBeingResurrected(unit)

Returns whether a unit is currently being resurrected.

Arguments

| Name | Type   | Description                |
|---   |--------|----------------------------|
| unit | string | unitID, GUID, or unit name |

Returns

| Return             | Type    |
|--------------------|---------|
| isBeingResurrected | boolean |

Example

```lua
if MyAddon:IsUnitBeingResurrected("player") then
    print("Incoming resurrection")
end
```

---

### UnitCanSelfResurrect(unit)

Returns whether a unit currently has one or more self-resurrection options available.

Arguments

| Name | Type   | Description                |
|------|--------|----------------------------|
| unit | string | unitID, GUID, or unit name |

Returns

| Return     | Type                             | Description                                                                          |
|------------|----------------------------------|--------------------------------------------------------------------------------------|
| canSelfRes | boolean                          | Whether the unit has at least one self-resurrection option                           |
| optionInfo | SelfResOptionInfo, table, or nil | A single SelfResOptionInfo table, multiple option tables keyed by option key, or nil |

Example

```lua
local canSelfRes, optionInfo = MyAddon:UnitCanSelfResurrect("player")
```

---

### GetResurrectionCastInfo(unit)

Returns active resurrection cast information for a caster.

Arguments

| Name | Type   | Description                |
|------|--------|----------------------------|
| unit | string | unitID, GUID, or unit name |

Returns

| Return     | Type            | Description                                                 |
|------------|-----------------|-------------------------------------------------------------|
| endTime    | number or false | Absolute cast end time in seconds comparable to `GetTime()` |
| targetGUID | string or nil   | Target GUID for single-target res casts, otherwise `nil`    |
| resType    | string or nil   | `"SINGLE"` \| `"MASS"` \| `nil`                             |

Example

```lua
local endTime, targetGUID, resType = MyAddon:GetResurrectionCastInfo("raid1")
```

---

### GetCasterInfo(unit)

Returns the active resurrection cast table for a caster.

Arguments

| Name | Type   | Description                |
|------|--------|----------------------------|
| unit | string | unitID, GUID, or unit name |

Returns

| Return     | Type               |
|------------|--------------------|
| casterInfo | ResCastInfo or nil |

Example

```lua
local casterInfo = MyAddon:GetCasterInfo("raid1")
```

---

### GetTargetInfo(unit)

Returns the active resurrection target table for a target.

Arguments

| Name | Type   | Description                |
|------|--------|----------------------------|
| unit | string | unitID, GUID, or unit name |

Returns

| Return     | Type                 |
|------------|----------------------|
| targetInfo | ResTargetInfo or nil |

Example

```lua
local targetInfo = MyAddon:GetTargetInfo("player")
```

---

### GetAllCastersForUnit(unit)

Returns all active resurrection casters for a target.

Arguments

| Name | Type   | Description                |
|------|--------|----------------------------|
| unit | string | unitID, GUID, or unit name |

Returns

| Return  | Type         |
|---------|--------------|
| casters | table or nil |

Example

```lua
local casters = MyAddon:GetAllCastersForUnit("player")
```

Example table:

```lua
{
    ["Player-1-00000001"] = "SINGLE",
    ["Player-1-00000002"] = "MASS",
}
```

---

## Callbacks

---

### ResCast_Started

Fired when a single-target resurrection cast begins.

Arguments

| # | Name       | Type          |
|---|------------|---------------|
| 1 | casterGUID | string        |
| 2 | targetGUID | string        |
| 3 | casterInfo | ResCastInfo   |
| 4 | targetInfo | ResTargetInfo |

Notes

- `targetGUID` may temporarily be `"UNKNOWN"`.

---

### ResCast_Stopped

Fired when a single-target resurrection cast stops before completion.

This includes:

- interrupted
- failed
- cancelled

Arguments

| # | Name       | Type                 |
|---|------------|----------------------|
| 1 | casterGUID | string               |
| 2 | targetGUID | string               |
| 3 | casterInfo | ResCastInfo or nil   |
| 4 | targetInfo | ResTargetInfo or nil |

---

### ResCast_Finished

Fired when a single-target resurrection cast successfully completes. This does not indicate that the target is alive.

Arguments

| # | Name       | Type          |
|---|------------|---------------|
| 1 | casterGUID | string        |
| 2 | targetGUID | string        |
| 3 | casterInfo | ResCastInfo   |
| 4 | targetInfo | ResTargetInfo |

---

### MassResCast_Started

Fired when a mass resurrection cast begins.

Arguments

| # | Name       | Type        |
|---|------------|-------------|
| 1 | casterGUID | string      |
| 2 | casterInfo | ResCastInfo |

---

### MassResCast_Stopped

Fired when a mass resurrection cast stops before completion.

Arguments

| # | Name       | Type               |
|---|------------|--------------------|
| 1 | casterGUID | string             |
| 2 | casterInfo | ResCastInfo or nil |

---

### MassResCast_Finished

Fired when a mass resurrection cast successfully completes. This does not indicate that any target is alive.

Arguments

| # | Name       | Type        |
|---|------------|-------------|
| 1 | casterGUID | string      |
| 2 | casterInfo | ResCastInfo |

---

### FastestRes_Changed

Fired when the fastest resurrection changes for a target.

Arguments

| # | Name       | Type          |
|---|------------|---------------|
| 1 | targetGUID | string        |
| 2 | targetInfo | ResTargetInfo |

Notes

- Fired only when the fastest result changes.

---

### ResTargetGUID_Resolved

Fired when an `"UNKNOWN"` targetGUID becomes resolved to a valid GUID.

Arguments

| # | Name       | Type          |
|---|------------|---------------|
| 1 | casterGUID | string        |
| 2 | targetGUID | string        |
| 3 | casterInfo | ResCastInfo   |
| 4 | targetInfo | ResTargetInfo |

---

### ResTargetGUID_IsAlive

Fired when a completed resurrection target becomes alive.

Arguments

| # | Name       | Type   |
|---|------------|--------|
| 1 | targetGUID | string |

---

### UnitSelfRes_Available

Fired when a unit gains a self-resurrection option.

Arguments

| # | Name       | Type              |
|---|------------|-------------------|
| 1 | unitGUID   | string            |
| 2 | optionInfo | SelfResOptionInfo |

---

### UnitSelfRes_Consumed

Fired when a self-resurrection option is consumed or removed.

Arguments

| # | Name               | Type              |
|---|--------------------|-------------------|
| 1 | unitGUID           | string            |
| 2 | consumedOptionInfo | SelfResOptionInfo |
| 3 | remainingInfo      | table or nil      |

Notes

- `remainingInfo` is nil if no self-resurrection options remain.

---

## Table Structures

---

### ResCastInfo

| Field      | Type    | Description                                      |
|------------|---------|--------------------------------------------------|
| castGUID   | string  | GUID of the spellcast                            |
| casterGUID | string  | GUID of the caster                               |
| castTime   | number  | in seconds                                       |
| spellID    | integer | EX: 2006 for Resurrection                        |
| targetGUID | string  | GUID of the target or `"UNKNOWN"`                |
| textureID  | integer | FileID of the spell's icon                       |
| endTime    | number  | When the spellcast ends, compared to `GetTime()` |

---

### ResTargetInfo

| Field             | Type          | Description                       |
|-------------------|---------------|-----------------------------------|
| targetGUID        | string        | GUID of the target or `"UNKNOWN"` |
| fastestCasterGUID | string or nil | GUID of the fastest caster        |
| fastestResType    | string or nil | `"SINGLE"` \| `"MASS"` \| `nil`   |

Additional caster tables may also exist on this table, keyed by caster GUID.

---

### SelfResOptionInfo

| Field          | Type           | Description                                                   |
|----------------|----------------|---------------------------------------------------------------|
| unitGUID       | string         | GUID of the unit being checked                                |
| spellID        | integer or nil | EX: 47883 for Soulstone Resurrection Rank 7                   |
| itemID         | integer or nil | EX: 19290 for Darkmoon Card: Twisting Nether                  |
| auraInstanceID | integer or nil | Blizzard aura instance ID for the self-res aura               |
| expirationTime | number or nil  | Absolute expiration time in seconds comparable to `GetTime()` |

Only populated fields are present.

---

## Unknown Targets

Single-target resurrection casts may temporarily use:

```lua
"UNKNOWN"
```

as the targetGUID until Blizzard exposes enough information to resolve the target.

---

## Mass Resurrection

Mass resurrection casts do not expose target GUIDs.

---

## Callback Tables

Callback info tables should be treated as read-only.

---

## API Validation

Public APIs validate incoming unit arguments.

Supported values:

- unitID
- GUID
- unit name
- name-realm

Invalid argument types, empty strings, and `"UNKNOWN"` raise Lua errors. Valid but unresolved unit names return the API's normal "not found" result.
