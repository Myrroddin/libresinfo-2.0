# LibResInfo-2.0

LibResInfo-2.0 is a lightweight library that provides information about resurrection activity for units.

It tracks when a resurrection is started, becomes pending, succeeds, and expires.

---

## Quick Example

```lua
local MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibResInfo-2.0")

function MyAddon:OnEnable()
    self:RegisterCallback("LRI2_ResPending")
end

function MyAddon:LRI2_ResPending(event, info)
    if info and info.targetGUID == UnitGUID("player") then
        print("You are being resurrected.")
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

Register for events using:

```lua
MyAddon:RegisterCallback("LRI2_ResPending")
```

Available events:

- `LRI2_ResStarted`
- `LRI2_ResPending`
- `LRI2_ResSuccess`
- `LRI2_ResExpired`

---

## Documentation

Full API and callback documentation:

[API.md](./API.md)

---
