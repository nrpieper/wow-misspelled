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