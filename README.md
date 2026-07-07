# LibResInfo-2.0

LibResInfo-2.0 is a CLEU-free resurrection tracking library for World of Warcraft addons.

The library tracks:

- single-target resurrection casts
- mass resurrection casts
- resurrection targets becoming alive
- self-resurrection availability
- fastest resurrection resolution per target

Supported clients:

- Classic Era
- TBC Classic
- Wrath Classic
- Mists Classic
- Retail

---

## Features

- No COMBAT_LOG_EVENT_UNFILTERED dependency
- GUID-first tracking
- Fastest resurrection detection
- Multiple simultaneous resurrection casters per target
- Self-resurrection tracking
- CallbackHandler-1.0 support
- Ace3-style embedding

---

## Installation

### .pkgmeta

AddOns should embed the child folder:

```yaml
externals:
  Libs/LibResInfo-2.0:
    url: https://github.com/Myrroddin/libresinfo-2.0.git/LibResInfo-2.0
```

### TOC

```toc
## OptionalDeps: LibStub, CallbackHandler-1.0, LibResInfo-2.0

LibResInfo-2.0\lib.xml
```

---

## Basic Example

```lua
local MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibResInfo-2.0")

function MyAddon:OnEnable()
    self:RegisterCallback("ResCast_Started")
    self:RegisterCallback("ResTargetGUID_IsAlive")
end

function MyAddon:ResCast_Started(_, casterGUID, targetGUID)
    print(casterGUID, "started resurrecting", targetGUID)
end

function MyAddon:ResTargetGUID_IsAlive(_, targetGUID)
    print(targetGUID, "is now alive")
end
```

---

## Public APIs

LibResInfo-2.0 embeds the following APIs directly onto the addon object.

### Unit-Specific APIs

- `GetAllCastersForUnit`
- `GetCasterInfo`
- `GetResurrectionCastInfo`
- `GetTargetInfo`
- `IsUnitBeingResurrected`
- `UnitCanSelfResurrect`
- `UnitHasResWaiting`

### Mass Resurrection APIs

- `IsMassResBeingCast`

---

## Callbacks

LibResInfo-2.0 embeds CallbackHandler-1.0 methods directly onto the addon object.

```lua
MyAddon:RegisterCallback("ResCast_Started")
MyAddon:UnregisterCallback("ResCast_Started")
MyAddon:UnregisterAllResInfoCallbacks()
```

Available callbacks:

### Single-Target Resurrection

- `ResCast_Finished`
- `ResCast_Started`
- `ResCast_Stopped`
- `ResTargetGUID_IsAlive`
- `ResTargetGUID_Resolved`
- `ResTargetGUID_WaitingTimeExpired`

### Mass Resurrection

- `MassResCast_Finished`
- `MassResCast_Started`
- `MassResCast_Stopped`

### Fastest Resurrection

- `FastestRes_Changed`

### Self-Resurrection

- `UnitSelfRes_Available`
- `UnitSelfRes_Consumed`

---

## Notes

- `targetGUID` may temporarily be `"UNKNOWN"` if Blizzard does not expose enough information to resolve the target immediately.
- Mass resurrection spells do not expose target GUIDs.
- Callback info tables should be treated as read-only.
- Completed resurrection targets may enter a waiting state until their resurrection popup expires.
- `UnitHasResWaiting()` can be used to query this waiting state.

---

## Documentation

See [API.md](./API.md) for complete API and callback documentation.

## Bug Reports

Report a bug: [GitHub Bug Report Form](https://github.com/Myrroddin/libresinfo-2.0/issues/new?template=bug_report.yml)
