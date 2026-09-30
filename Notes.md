# Notes
### Bugs
Issue: Fix euro € symbol causing the whole line to be highlighted as misspelled.
Possible utf8 lib https://github.com/tst2005/lua-utf8string/blob/master/utf8string.lua
                  https://github.com/t1m1yep/utf8/blob/main/utf8.lua
                  https://github.com/blitmap/lua-utf8-simple/blob/master/utf8_simple.lua
*Might require Lua 5.3 and not be compatible with the Wow Lua env.
Wow _G.bit has the bit functions needed by some of these utf8 implementations.

**Fixed - Issue: Wow 11 - War Within, issue loading interface options (Misspellec.lua: 1417 disabled for now)
Looking to convert addon options to use AceConfig.
ref: Patch 11 settings API changes: https://warcraft.wiki.gg/wiki/Patch_11.0.2/API_changes#Settings_API_changes

### WoW Forever and Midnight (9/2026)
WoW Forever runs the Midnight (12.x) client: interface **16001**, `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`, Retail APIs (`C_AddOns`, `ChatFrameUtil`, `MenuUtil`, the Settings panel), and Midnight's addon restrictions and secret values. Verified against Blizzard's UI source for Forever (Gethe/wow-ui-source, `forever` branch, 1.60.1.70124).
- TOC: `## Interface` includes 16001, and `## Interface-Forever: 16001` is for the BigWigs packager, which builds a Forever package with `-g forever` (see `.github/workflows/release.yml`).
- `C_ChatInfo.SendChatMessage` is restricted (`HasRestrictions`). It's blocked for addon-tainted callers while `C_ChatInfo.InChatMessagingLockdown()` is true (encounters, Mythic+, PvP). `C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.*)` reports Combat, Encounter, ChallengeMode, PvPMatch, Map and Chat restrictions.
- `EditBox:GetText()` / `GetCursorPosition()` can return secret values (`SecretReturnsForAspect` Text / Cursor). Always check `issecretvalue` first.

Rules the chat code follows so it doesn't taint Blizzard's chat:
- Never hook or replace `SendChatMessage` / `C_ChatInfo.SendChatMessage`.
- Never call `SetText`, `Insert`, `HighlightText`, `SetFocus` or `SetAttribute` on a Blizzard chat edit box automatically. `SetText` runs Blizzard's `OnTextChanged` / `ParseText` under taint. The only write is picking a suggestion out of combat (`ReplaceWord`). While restricted (`CanReplaceWords`) the suggestions are greyed out with a polled `SetEnabled` function, and `ReplaceWord` does nothing.
- Only post-hooks: `HookScript`, `hooksecurefunc`. Never `SetScript` on Blizzard frames, and never write fields onto them (state lives in weak-keyed tables).
- Misspellings are underlined on Misspelled's own overlay frame (a child of the edit box).
- Never open Blizzard's shared menus (`MenuUtil`, `UIDropDownMenu`). They pool menu frames between all menus, so a menu opened by addon code taints the frames the unit frame's right-click menu reuses, and its protected actions fail: setting a raid target marker (`SetRaidTarget`, protected since 12.0) gave "Misspelled has been blocked from an action only available to the Blizzard UI". The suggestions popup is built from Misspelled's own frames.

Still to check in the live Forever client:
- Underlines line up with the words, including long messages that scroll sideways (`ComputeScroll` follows the caret, since there's no API for the edit box's scroll offset).
- Right-click on an underlined word opens the menu; in combat and encounters the suggestions are greyed out with the "paused" note, and grey out if combat starts while the menu is open.
- Chat messages and `/cast`-style slash commands still go through during a boss encounter (no ADDON_ACTION_BLOCKED).

### Tests
`lua5.1 tests/run.lua` runs offline tests (needs Lua 5.1 and Lua BitOp: `apt install lua5.1 lua-bitop`). They load the real addon code and the enUS dictionary against stubbed WoW APIs, so they check the logic, not what it looks like in game.
