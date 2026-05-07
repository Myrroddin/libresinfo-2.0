# LibResInfo-2.0

LibResInfo-2.0 is a lightweight library that provides information about resurrection activity for units in your group

It tracks when a resurrection is started, becomes pending, succeeds, and expires.

---

## Quick Example

```lua
local MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibResInfo-2.0")

function MyAddon:OnEnable()
    self:RegisterCallback("LRI2_UnitResPending")
end

function MyAddon:LRI2_UnitResPending(callback, info)
    if info.targetGUID == UnitGUID("player") then
        print("You can now accept the resurrection.")
    end
end
```

---

## Basic Usage

```lua
local info = MyAddon:GetIncomingResInfo("player")

if info then
    print(info.spellID)
end
```

---

## Callbacks

The lib provides CallbackHandler-1.0 methods directly on the addon object.
These only affect LibResInfo-2.0 callbacks.

Callbacks fire per unit and include an info table describing the resurrection state.

```lua
MyAddon:RegisterCallback("LRI2_UnitResPending")
MyAddon:UnregisterCallback("LRI2_UnitResStarted")
MyAddon:UnregisterAllCallbacks()
```

Available callbacks:

- `LRI2_UnitResStarted`
- `LRI2_UnitResPending`
- `LRI2_UnitResSuccess`
- `LRI2_UnitResExpired`

---

## Documentation

Full API and callback documentation:

[API.md](./API.md)

---
