# Notes
### Lua Annotations
https://luals.github.io/wiki/annotations/

### Tests
Run tests with the WowLua addon and call: `Misspelled.Tests:RunTests()`, to run all tests.

### To-Do
WordPositions should be in UTF8 position or byte poistion.

### Bugs
Issue: Fix euro € symbol causing the whole line to be highlighted as misspelled.
Possible utf8 lib https://github.com/tst2005/lua-utf8string/blob/master/utf8string.lua
                  https://github.com/t1m1yep/utf8/blob/main/utf8.lua
                  https://github.com/blitmap/lua-utf8-simple/blob/master/utf8_simple.lua

Potentially improved performance utf8 lib and tests
https://github.com/Stepets/utf8.lua/blob/master/primitives/dummy.lua
https://gist.github.com/markandgo/5776124


Wow includes two utf8 string meathods used in chat boxes: (https://warcraft.wiki.gg/wiki/Lua_functions)
strcmputf8i(string,string) - string comparison accounting for UTF-8 chars
strlenutf8(string) - returns the number of characters in a UTF8-encoded string.

LUA UTF8 to Unicode code point and back
https://web.archive.org/web/20120826142853/http://developer.coronalabs.com/code/utf-8-conversion-utility


editbox.GetUTF8CursorPosition()
SetCursorPosition - needs to be tested to see if it utf8 aware

CursorPosition is the current location of the edit cursor in the editbox text, including the UI escape sequence codes, not just the display text.

-- For All Indents And Purposes -
-- a indentation + syntax highlighting library
FAIAP.lua has cursor tracking and they implement it by first inserting a tracking token '\2', stripping color tags then finding the tracking token to return the new cursor position:
    function lib.stripWowColorsWithPos(code, pos)
        code = stringinsert(code, pos, "\2")
        code = lib.stripWowColors(code)
        pos = stringfind(code, "\2", 1, 1)
        code = stringdelete(code, pos, pos)
        return code, pos
    end

**Fixed - Issue: Wow 11 - War Within, issue loading interface options (Misspellec.lua: 1417 disabled for now)
Looking to convert addon options to use AceConfig.
ref: Patch 11 settings API changes: https://warcraft.wiki.gg/wiki/Patch_11.0.2/API_changes#Settings_API_changes