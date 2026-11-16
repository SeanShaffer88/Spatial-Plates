# Spatial Plates use-case, risk, and test matrix

**Review scope:** the addon in this repository, including config/profile persistence, data collection, nameplate frames, options UI, slash commands, and optional integrations. This is a bounded threat/usage analysis, not proof of absence of defects.

## Assumptions and boundaries

1. Spatial Plates runs only in the WoW client and stores state in the declared `SpatialPlatesDB` SavedVariable. It does not intentionally access the network, files outside WoW's normal font/texture lookup, or external services.
2. All nameplate and unit API values are treated as optional, possibly nil, malformed, erroring, or secret. Where `issecretvalue` is available and itself works, unreadable values fail closed. If the client omits or breaks that primitive, non-secret status cannot be established; data fields therefore need a live-client verification.
3. `## Interface: 16001` remains provisional and must be checked against the exact Forever client build. API signatures/events may vary by build.
4. Spatial overlays are informational only. No health, power, aura, cooldown, damage, healing, threat, combat-log, targeting, or decision automation is in scope.
5. “Same map” is intentionally map-level. `C_Map.GetBestMapForUnit` does not prove that two players are in the same subzone.
6. “Friends” means friend-list membership, not friendly faction. If the client cannot answer friend-list membership, that filter intentionally excludes units.
7. Custom-parent functions are explicitly user-configured executable callbacks. They are invoked under `pcall`, but their internal behavior is outside this addon's control.
8. Preset-to-addon mappings are visual approximations and are not integrations with the other addon.
9. Tests in `tests/run.lua` use mock APIs; they cannot establish actual WoW client behavior, taint behavior, performance on live nameplates, or interface compatibility.

## Users and contexts considered

- **Solo player / friend group:** wants nearby friendly-player context without raid frames.
- **Party healer / raid lead / group member:** many concurrent plates, movement, roster changes, combat lockdown, and limited screen space.
- **Nameplate-suite user:** Plater, ThreatPlates, ElvUI, TukUI, KuiNameplates, NeatPlates, or a custom parent frame; the suite may load before or after this addon.
- **Accessibility/customization user:** small screen, low vision, high-contrast preference, color-vision differences, custom fonts, reduced clutter, or no external UI suite.
- **Addon maintainer / profile sharer:** edits options, exports/imports strings, keeps account-wide or per-character values, and upgrades between addon versions.
- **Restricted/older client:** missing optional APIs/events, secret values, API errors, older options-panel/color-picker behavior, or different interface number.
- **Abuse/misuse scenario:** pasted hostile/malformed profile strings, invalid custom function names, extreme settings, external frames with unusual behavior, repeated nameplate token reuse, or corrupted SavedVariables.

## Use-case / risk / test matrix

| ID | User goal / context and inputs | Main failure or abuse risk | Defensive behavior / verification |
|---|---|---|---|
| U01 | Show spatial fields for a friendly player plate; distinguish player, NPC, enemy, and self | Overlay appears on the wrong unit or stale unit token | Require readable `UnitIsPlayer`, friendly `UnitIsFriend`, and not-self; revalidate every refresh. `ELIG1`, `FRAME1` |
| U02 | Filter all / party / raid / guild | Secret, nil, wrong-type, or throwing membership result widens the set | Boolean results are checked for readability; missing/unknown APIs fail closed for restricted filters. `FILTER1` |
| U03 | Filter the actual friends list | Friendly faction is mistaken for friend-list membership; API missing or query errors | Query `C_FriendList.IsFriend` / guarded legacy `IsFriend` using full name when available; fail closed. Refresh on optional friend-list events and on ticker. `FILTER1`, `FILTER2` |
| U04 | Change filter while plates already exist | Existing overlays remain visible under a stricter filter | Recheck eligibility/filter inside `UpdateOverlay`; hide when excluded and restore when re-included. `FILTER2` |
| U05 | Show approximate distance | Nil, thrown, wrong-type, negative, secret, different-map, or extreme value causes error or misleading display | Require readable number, nonnegative value, readable same-map IDs before square root; omit field otherwise. `API1`, `VIS1` |
| U06 | Show location context | Map data is absent, malformed, a secret table/name, or differs only at map granularity | Compare map IDs only; sanitize map names; label `Same map`, never claim subzone equality. `API1`, `API2`, migration checks |
| U07 | Show indoor/outdoor and underwater | Optional API unavailable, throws, returns unexpected/secret type, or returns a false-like numeric value | Require readable boolean for indoors; require readable explicit submerged confirmation for underwater; otherwise omit. `API3` |
| U08 | Enable visibility rules (combat, instance, unit visibility, plate hidden, max distance) | Unknown distance accidentally bypasses a max-distance rule; secret values compared directly | Unknown distance hides when max-distance rule is active; combat state uncertainty is treated conservatively; all booleans are checked before comparison. `VIS1`, `API3` |
| U09 | Handle secret values in combat | Secret values reach arithmetic, string substitution, comparisons, or debug output | Check readability before arithmetic/comparison; freeze only last known non-secret fields and cached distance; debug contains reasons, not values. `API1`, `API3`, static scan |
| U10 | Leave/re-enter plate range or reuse `nameplateN` token | Named-frame collision, stale overlay, leaked references, or duplicate overlays | Overlays are unnamed; `NAME_PLATE_UNIT_REMOVED` detaches and clears state; no bookkeeping property is written to host frames. `FRAME1` |
| U11 | Use custom parent function | Missing function, throws, returns string/non-frame, hostile metatable, or changes parent | Restrict names to a global identifier; guard call/property access; require `SetPoint` and `CreateFontString`; fallback to default; never write addon metadata on host frames. `PARENT1` |
| U12 | Use optional nameplate-addon parent detection | Addon absent, incompatible object shape, or detector throws | Read-only best-effort `pcall` checks; validate returned frame; default parent fallback. Existing integration limits documented. `PARENT1` plus live verification |
| U13 | Auto-match a nameplate theme | Competing addons, late load, disabled setting, unexpected addon ID, repeated reload | Known IDs only; apply visual preset once per detected addon; manual force action; report last matched addon/theme; no other-addon frame access. `THEME1` |
| U14 | Customize font, dimensions, colors, border, background, anchor, strata | Out-of-range numbers, invalid strata, bad font/texture path, malformed color | Schema validation/clamping; allowed strata; `pcall` fallback for fonts/backdrops; live-apply revision cache. `DB1`, `STYLE1`, `UI1` |
| U15 | Use per-field text colors / class / reaction colors | Class color token mismatch, invalid class lookup, markup injection | Correctly use `UnitClass` class-file token; per-field mode generates bounded color tags from validated colors; untrusted pipes in user/API text escaped. `FMT1`, color-mode tests |
| U16 | Use templates, map names, percent signs, pipes, imported text | `gsub` percent replacement errors; WoW inline markup/link/texture injection; oversized output | Callback-based substitutions; text/template sanitization; bounded field/combined output; profile string length caps. `FMT1`, `CFG1` |
| U17 | Export/import or share profiles | Malformed, oversized, duplicate, unknown, wrong-version, wrong-type, cyclic SavedVariables | Parse into a copy; reject duplicates/unknown keys/bad versions/size overflow; canonical export whitelist and cycle/depth guard; commit only after validation. `CFG1`, DB tests |
| U18 | Use account-wide and per-character profiles | Nested color tables are shared across scopes; corrupt database causes errors | Deep copy with cycle/depth bounds; schema validation and defaults; account/character isolation tests. `DB1`, `DB2` |
| U19 | Slash-command-only use / invalid command input | Unknown options throw or user input becomes chat markup | Commands validate against allowlists; unknown actions print help; imported/custom strings are bounded/sanitized. `SLASH1`; live command test |
| U20 | Use options panel on client with missing Settings/dropdown/color-picker API | Panel registration or control callback crashes | Optional registration paths guarded; unsupported controls fail with a clear notice; fallback panel exists. `UI1`; live-client test required |
| U21 | Small display, reduced clutter, high contrast, color-vision differences | Tiny/translucent text or color-only distinctions reduce readability | Size/alpha/outline/contrast/color modes and presets are user-controlled. A visual accessibility audit remains a manual task. `STYLE1`; manual visual check |
| U22 | Run on slow machine / many friendly plates | Backdrop/font/anchor work repeats every ticker; callback integration is slow | Appearance revision cache, unchanged text/anchor cache, throttled ticker, no health/combat scans. `STYLE1`; live performance profiling remains outstanding |
| U23 | Privacy-conscious user | Unit identifiers, friend data, or profiles leave the client | No network APIs or data export other than explicit local profile string; no player names stored by core; local SavedVariables only. Static scan/manual code review |
| U24 | Malicious or malformed custom profile / invalid function name | Arbitrary keys/values, debug markup, function-name injection, recursion/stack overflow | Setter schema allowlist, validator, identifier restriction, formatter escaping, import bounds, cycle/depth protection. `DB1`, `CFG1`, `FMT1`, `PARENT1` |
| U25 | Addon load order / missing ticker or event | Startup race, unavailable optional event/ticker, no future refresh | Initialization on `ADDON_LOADED`; optional event registrations are protected; ticker falls back to OnUpdate. `TICK1`; live startup/reload test |
| U26 | Bearing request | UI suggests a feature with no safe supported API | No UI control; legacy profile value is ignored and at most one debug notice is emitted. `SLASH1`; documentation check |

## Test inventory and execution

- `lua tests/run.lua`: mocked behavior and adversarial-input checks; no external Lua test framework required.
- `python3 tests/check_static.py`: dependency-free banned-API, TOC order, and guard checks.
- `git diff --check`: whitespace / patch sanity.
- Run the documented in-game checklist in `README.md` on the exact Forever client before release. The static/mocked suite is not a substitute for it.

## Residual risks / uncertainties

- The target WoW client/API build is not available in this workspace. `Interface: 16001`, `C_FriendList.IsFriend` behavior, event names, `UnitIsIndoors`, `UnitIsSubmerged`, backdrop/color-picker UI methods, and secret-value semantics still need live confirmation.
- The test mock models WoW values/frames; it cannot prove absence of taint, protected-frame restrictions, true secret propagation, memory behavior, or visual overlap with arbitrary UI suites.
- Friend-list APIs may vary in full-name formatting, realm normalization, cross-realm identity, and whether the given unit is resolvable; the fail-closed outcome can produce false negatives.
- A configured custom parent function is user-provided code. `pcall` contains ordinary Lua errors but cannot prevent its own side effects or guarantee it returns an appropriate unprotected frame.
- Theme associations and optional Plater/Kui parent probes are approximate, version-sensitive best-effort behavior, not vendor-supported integrations.
- The map-location field is map-level only. Exact subzone, coordinate, and bearing semantics are intentionally not claimed.
- Color contrast, screen-reader support, localization, scaling at all UI scales, and clutter in large raids need human visual/accessibility testing.
- `issecretvalue` detection cannot protect a client that omits the API or misclassifies a value; uncertain/live API behavior must be assessed in the target build.
