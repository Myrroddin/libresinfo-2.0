# LibResInfo-2.0

LibResInfo-2.0 is a lightweight library that provides information about resurrection activity in your group.

It detects when a unit is being resurrected, when the resurrection becomes pending, when it succeeds, and when it expires.

The library is event-driven and designed to work across multiple WoW clients without relying on COMBAT_LOG_EVENT_UNFILTERED.

---

## Features

- GUID-based tracking (unitIDs are observational only)
- No reliance on CLEU
- Table-based API and callback payloads
- Safe for multiple addons (no shared mutable state)
- Lifecycle-safe callbacks via CallbackHandler-1.0

---

## Quick Example

```lua
local MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibResInfo-2.0")

function MyAddon:OnEnable()
    self:RegisterCallback("LRI2_ResPending")
end

function MyAddon:LRI2_ResPending(event, info)
    if info.targetGUID == UnitGUID("player") then
        print("You are being resurrected.")
    end
end
```

---

## API

### GetIncomingResInfo(unit)

Returns a table describing the resurrection state of a unit, or nil if none exists.

```lua
local info = LibStub("LibResInfo-2.0"):GetIncomingResInfo("player")
```

---

### UnitHasIncomingRes(unit)

Returns true if the unit has an incoming resurrection.

```lua
if LibStub("LibResInfo-2.0"):UnitHasIncomingRes("target") then
    -- do something
end
```

---

## Callback Events

Callbacks are registered using:

```lua
self:RegisterCallback("EVENT_NAME")
```

### Events

- `LRI2_ResStarted`
- `LRI2_ResPending`
- `LRI2_ResSuccess`
- `LRI2_ResExpired`

---

## Callback Payload

All callbacks receive:

```lua
eventName, infoTable
```

### infoTable fields

| Field           | Description |
|----------------|------------|
| state          | Internal state (`CASTING`, `PENDING`, `SUCCESS`) |
| targetGUID     | GUID of the target |
| casterGUID     | GUID of the caster (if known) |
| spellID        | Spell or item ID (if known) |
| castStartTime  | Cast start time (seconds) |
| castEndTime    | Cast end time (seconds) |
| expiresAt      | Expiration timestamp (seconds) |
| confidence     | Detection confidence (`LOW`, `MEDIUM`, `HIGH`) |

---

## Notes

- All returned data is a copy and safe to read.
- Do not rely on modifying returned tables.
- Some fields may be nil depending on client and event timing.
- Information is best-effort and inferred from available APIs.

---

## Documentation

More detailed documentation and design notes will be provided in:

`wiki.md`

---

## Credits

- Phanx — original LibResInfo-1.0