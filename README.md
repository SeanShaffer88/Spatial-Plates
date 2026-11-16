# Spatial Plates

A lightweight, purely informational World of Warcraft addon (Classic Forever) that adds a small spatial-semantics overlay to **friendly player nameplates** — approximate distance in yards, same-map/map-name indicator, indoors/outdoors, and underwater status — so healers, raid leads, and party members can understand where friendly players are without staring at raid frames.

> **Informational only.** The addon code does not call health, power, aura, cooldown, damage, healing, threat, or combat-log APIs; it does not automate decisions or hook insecure combat functions. Secret/unreadable spatial values are omitted or the last readable display is frozen in combat. Calls are guarded and the addon is designed to fail closed where possible, but no Lua addon can guarantee zero errors or taint on every client build; use the live-client checklist before release.

## Installation

1. Download or clone this repository.
2. In the client’s active WoW installation, create an addon folder named **`SpatialPlates`** (no hyphen) inside `Interface/AddOns`:
   - Windows Classic: `World of Warcraft\_classic_\Interface\AddOns\SpatialPlates`
   - Windows Classic Era: `World of Warcraft\_classic_era_\Interface\AddOns\SpatialPlates`
   - macOS: use the matching client folder under `~/Documents/Blizzard Entertainment/World of Warcraft/`, then `Interface/AddOns/SpatialPlates`.
3. Copy the addon files directly into `SpatialPlates`, so `SpatialPlates.toc` is at `.../AddOns/SpatialPlates/SpatialPlates.toc` next to `Config.lua`, `Presets.lua`, `Appearance.lua`, and `Core.lua`. If you extracted the GitHub source archive, rename its `Spatial-Plates` or `Spatial-Plates-main` directory to `SpatialPlates` (do not leave an extra nested folder).
4. Fully restart the game, select the intended client/version, open **AddOns** on the character-select screen, and enable **Spatial Plates**. If it is listed as out of date, enable **Load out of date AddOns**; `## Interface: 16001` may not match your client.
5. Type `/splates` in game to see commands, or `/splates config` to open the options panel.

## TOC Interface version — please verify

`SpatialPlates.toc` currently uses:

```
## Interface: 16001
```

**Verify this against your client.** If your Forever client reports a different interface number (check `Interface\FrameXML\...` or the client version in the login screen), update the `## Interface:` line to match. The addon code itself does not depend on a specific interface number — it only uses documented, guarded APIs.

## Usage

- Overlays appear **only** on friendly player nameplates (not enemies, not NPCs, not yourself).
- By default the overlay sits **above** the nameplate and shows `12y | Same map`.
- Distance appears only when readable **and** you and the unit are on the same map.
- The location field compares `C_Map.GetBestMapForUnit`: same map displays `Same map`, otherwise it displays the unit's map name. This API is **not subzone-granular**, so the addon does not claim the players share a subzone; the field hides cleanly when map data is unavailable.
- Indoors/outdoors shows only when a supported environment API answers; otherwise it hides.
- Underwater shows only when `UnitIsSubmerged` confirms the unit is submerged.
- Bearing is not offered in the UI because this client exposes no safe non-secret bearing API. Older imported profiles requesting bearing are ignored, with at most one debug notice.

### Slash commands

| Command | Effect |
|---|---|
| `/spatialplates` / `/splates` | Show help |
| `/splates toggle` | Enable/disable the addon |
| `/splates distance [on\|off]` | Toggle distance field |
| `/splates map [on\|off]` (alias: `/splates subzone`) | Toggle same-map/map-name field |
| `/splates indoors [on\|off]` | Toggle indoors/outdoors field |
| `/splates underwater [on\|off]` | Toggle underwater field |
| `/splates bearing` | Explain that bearing is unavailable on this client |
| `/splates filter <all\|party\|raid\|guild\|friends>` | Set friendly filter |
| `/splates theme <name>` | Apply a theme preset |
| `/splates theme auto` | Re-detect loaded replacement addon and force-apply its matching preset |
| `/splates config` | Open options panel |
| `/splates export` | Print export string |
| `/splates import <string>` | Import a profile string |
| `/splates reset` | Reset profile to defaults |
| `/splates debug [on\|off]` | Toggle debug output |
| `/splates scope <account\|char>` | Account-wide vs per-character profile |

### Options panel

`/splates config` opens a panel exposing every appearance setting with a live preview:

- **Fields & filter:** enable/disable each field; filter (all/party/raid/guild/friends). The friends filter uses the friend-list query API and fails closed (shows none) if the API cannot verify membership; friendly faction alone does not count as a friend-list entry.
- **Font:** built-in fonts or custom font path, size, outline (none/outline/thick), color, alpha.
- **Text templates:** editable format strings per field (`{d}`, `{zone}`, `{env}`, `{water}`, `{dir}`) plus a combined template.
- **Background / border:** enable, color, alpha, texture, edge size, inset / edge file.
- **Layout:** anchor (9 positions), offsets X/Y, scale, width, height, padding, strata, frame level, clamp to screen.
- **Visibility rules:** hide in/out of combat, hide when nameplate hidden / unit not visible, hide beyond max distance, hide in instances / open world.
- **Color rules:** custom / class / reaction / per-field colors.
- **Theme presets:** Default, Minimal, Plater-like, ThreatPlates-like, ElvUI-like, TukUI-like, Classic-like, High Contrast (visual only — no other addon required).
- **Automatic theme matching:** enabled by default. On loading a supported nameplate replacement, Spatial Plates selects a matching visual preset: Plater → Plater-like, ThreatPlates → ThreatPlates-like, ElvUI → ElvUI-like, TukUI → TukUI-like, KuiNameplates → Minimal, and NeatPlates → Classic-like. It checks addon-loaded state only, does not inspect or modify their frames, and remembers which addon was matched so later reloads do not overwrite your appearance edits. Disable **Auto-match loaded nameplate addon theme** in options to turn this off. The options panel shows the last matched addon and preset. Use the **Detect / apply matching theme** button or `/splates theme auto` to force a fresh match at any time, even when automatic matching is disabled. Detection works whether the supported addon loads before or after Spatial Plates.
- **Import/export:** export the profile as a compact `SP1:...` string; import it back (malformed strings are rejected safely).
- **Profile scope:** account-wide or per-character (stored in `SpatialPlatesDB`).

### Custom parent frame (optional)

If you use a nameplate addon that exposes a global function returning the frame for a unit, set:

```
SpatialPlatesDB.customParentFunc = "MyAddon_GetNameplateFrame"
```

or use the options panel field **Custom parent func**. The function is called as `MyAddon_GetNameplateFrame(unit)` and must return a frame. If it is absent or returns nothing, Spatial Plates falls back to the default nameplate. No other addon is ever required.

### Auto-detection (optional, off by default)

Enable **Auto-detect nameplate addons** in the options panel to allow read-only checks of known global names (Plater, KuiNameplates, etc.). Detection is best-effort and guarded when absent; Spatial Plates does not write bookkeeping fields to another addon's frames and only parents its own overlay as a child.

## Safety & secret-value rules

- **No combat APIs.** The addon never calls health/power/aura/cooldown/threat APIs and never parses the combat log.
- **Guarded reads.** Every spatial call (`UnitDistanceSquared`, `C_Map.*`, `UnitIsSubmerged`, etc.) is wrapped in `pcall` + type checks + `issecretvalue` checks (when available). Unreadable values hide the field.
- **In-combat freeze.** If a value becomes secret/unreadable while in combat, the last known non-secret display is frozen instead of cleared. Nothing is computed on secrets.
- **Throttled updates.** A ticker (default 0.3s, configurable 0.1–2.0s) refreshes tracked friendly nameplates. Font, backdrop, size, and color are reapplied only after a profile revision; unchanged text and anchor points are also left alone.
- **Cleanup.** `NAME_PLATE_UNIT_REMOVED` hides, detaches, and drops the addon's references to the overlay; repeated token reuse is covered by mock tests, with actual client lifecycle still requiring smoke testing.
- **Debug mode** prints only *why* a field hid (e.g. `distance hidden: different map`), never secret values.

## Files

| File | Purpose |
|---|---|
| `SpatialPlates.toc` | Addon metadata, SavedVariables, load order |
| `Config.lua` | Defaults, `SpatialPlatesDB`, validation, export/import codec, slash commands, options panel |
| `Presets.lua` | Theme presets (partial profile tables) |
| `Appearance.lua` | Data-driven appearance application + text formatting |
| `Core.lua` | Nameplate detection, eligibility, field computation, visibility, ticker, cleanup |

Load order in the TOC is `Config.lua → Presets.lua → Appearance.lua → Core.lua`. All top-level code only defines tables/functions; initialization happens on `ADDON_LOADED`.

## Testing

Run the local mocked suite and static check from the repository root:

```sh
lua tests/run.lua
python3 tests/check_static.py
```

The Lua suite uses a deliberately small fake WoW API; it has no third-party Lua test framework dependency. The static script checks the TOC/load order and scans addon Lua sources for prohibited combat-data/secure-hook API names.

## In-client testing checklist

Mocked Lua tests and static checks can verify control flow, but they do not reproduce the WoW client. **A live Classic Forever client smoke test has not been run in this workspace.** Before release, verify the current interface number and run the checks below in the target client, especially friend-list API behavior and repeated nameplate-token reuse.

1. **Loads cleanly:** `/reload` in and out of combat — no Lua errors.
2. **Friendly only:** overlays appear on friendly players only — not enemies, not NPCs, not yourself.
3. **Distance:** appears when readable and same-map; hidden otherwise (e.g. different map, or API unavailable).
4. **Map location:** shows `Same map` / map name (not subzone-level); hides cleanly when map data is unavailable.
5. **No combat APIs:** grep the code — no health/power/aura/cooldown/threat/combat-log usage.
6. **Cleanup / token reuse:** enter and leave nameplate range repeatedly; verify overlays return after `NAME_PLATE_UNIT_REMOVED` and reused nameplate tokens do not cause duplicate-frame errors.
7. **Persistence:** change settings, `/reload` — settings survive.
8. **In-combat safety:** in combat with unreadable values — no errors, no computation, frozen or hidden fields.
9. **Live appearance:** change font, color, anchor, offsets, scale, background, border, preset — overlays update without reload.
10. **Export/import:** `/splates export`, `/reload`, `/splates import <string>` — round-trips; malformed strings are rejected with a message.
11. **Custom parent:** set `customParentFunc` to a valid global function — overlay attaches there; set it to a bogus name — falls back safely.
12. **Presets and auto-match:** apply `Plater-like`, `ThreatPlates-like`, `ElvUI-like`, `TukUI-like`, `Classic-like`, `High Contrast` — no errors or dependencies. With auto-match enabled, load a supported replacement addon and verify its matching preset is selected; verify a reload preserves later appearance edits. Also try the Detect / apply button and `/splates theme auto` with automatic matching disabled.
13. **Friends filter:** set `/splates filter friends`; confirm an actual friend-list member remains and a friendly player not on the friend list is excluded. If the client lacks the friend-list membership API, confirm the filter fails closed rather than showing all friendly players.

## License

MIT — see `LICENSE`.
