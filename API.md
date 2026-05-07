# LibResInfo-2.0 API and Callbacks

All APIs and callbacks are embedded on the addon object.

```lua
local MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibResInfo-2.0")
```

---

## Table of Contents

* APIs

  * GetIncomingResInfo (placeholder)
  * GetUnitIDFromGUID (placeholder)
* Callbacks

  * LRI_FastestResUpdated
  * LRI_ResCastFinishedOnTargets
  * LRI_ResCastStopped

---

# APIs

> ⚠️ These APIs are currently placeholders and may change.

---

## `GetIncomingResInfo(unitOrGUID)`

Returns resurrection information about a unit.

### Arguments

* unitOrGUID (string)
  A unitID (e.g. `"player"`, `"target"`, `"party1"`)
  or a unit GUID.

### Returns

* infoTable (table or nil)
  Returns `nil` if no resurrection data is available.

---

## `GetUnitIDFromGUID(guid)`

Returns a valid unitID for the given GUID if one is currently known.

### Arguments

* guid (string)

### Returns

| Field | Type          | Description                                  |
| ----- | ------------- | -------------------------------------------- |
| unit  | string or nil | A valid unitID if available, otherwise `nil` |

---

# Callbacks

Callbacks are registered using:

```lua
MyAddon:RegisterCallback("LRI_FastestResUpdated")
```

---

## `LRI_FastestResUpdated(callback, returns)`

Fired when the fastest resurrection changes for one or more targets.

This includes:

* A new fastest cast begins
* A faster cast replaces a previous one
* No valid resurrection remains for a target

---

### Returns

| Field     | Type              | Description                                                      |
| --------- | ----------------- | ---------------------------------------------------------------- |
| targets   | table<string>     | List of target GUIDs affected by this update                     |
| isFastest | string or nil     | Caster GUID of the fastest resurrection, or `nil` if none exists |
| startTime | number (optional) | Cast start time in milliseconds                                  |
| endTime   | number (optional) | Cast end time in milliseconds                                    |

---

### Notes

* Fired only when the fastest result changes
* Each target has at most one fastest caster at any time

---

## `LRI_ResCastFinishedOnTargets(callback, returns)`

Fired when a resurrection cast successfully completes.

This does not indicate that the target is alive, only that the cast finished.

---

### Returns

| Field      | Type          | Description                               |
| ---------- | ------------- | ----------------------------------------- |
| casterGUID | string        | GUID of the caster whose spell completed  |
| targets    | table<string> | List of target GUIDs affected by the cast |

---

### Notes

* Fired once per completed cast
* Applies to both single-target and mass resurrection spells

---

## `LRI_ResCastStopped(callback, returns)`

Fired when a resurrection cast stops before completion.

This includes:

* interrupted
* failed
* cancelled

---

### Returns

| Field | Type         | Description                                                       |
| ----- | ------------ | ----------------------------------------------------------------- |
| state | table or nil | Current internal caster state, or `nil` if no active casts remain |

---

### Notes

* This callback reflects caster-side state changes
* Target-level updates are reported through `LRI_FastestResUpdated`

---

# Data Model Notes

---

## Per-Target Resolution

Resurrection tracking is performed independently per target.

* Multiple casters may attempt to resurrect the same target
* Only one cast is considered the fastest for that target

---

## Fastest Resolution Rules

* The fastest cast is determined by the earliest endTime
* When a cast succeeds, the race for that target ends
* No other casts are considered after a successful cast

---

## Timing

* All times are expressed in milliseconds
* Derived from:

  * `UnitCastingInfo`
  * `C_Spell.GetSpellInfo`
  * Event timing

---

## Safety

* Tables returned to callbacks should be treated as read-only
* Internal state should not be modified by consuming addons

---

# Summary

LibResInfo-2.0 provides:

* Accurate resurrection tracking
* Per-target fastest cast resolution
* Consistent and predictable callback data
* Minimal unnecessary callback firing through change detection

---
