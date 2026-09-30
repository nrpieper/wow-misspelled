--[[
Offline tests for Misspelled. They load the real addon code and the enUS dictionary against a
few stubbed WoW APIs, so they check the logic, not how things look in the game client.

Run from the repository root with Lua 5.1 and Lua BitOp (WoW provides its "bit" library):
	lua5.1 tests/run.lua
Debian/Ubuntu: apt install lua5.1 lua-bitop
--]]

local ok, bitlib = pcall(require, "bit")
if not ok then
	print("Lua BitOp is required (WoW provides it as the global 'bit'): apt install lua-bitop, or luarocks install luabitop")
	os.exit(1)
end
bit = bitlib

-------------------------------------------------------------------------
-- WoW API stubs
-------------------------------------------------------------------------

local SECRET = setmetatable({}, {__tostring = function() return "<secret>" end})
function issecretvalue(value) return value == SECRET end

local noop = function() end

--Any method a test doesn't care about is a no-op.
local function FakeObject(methods)
	local object = {}
	return setmetatable(object, {__index = function(_, key)
		return methods[key] or noop
	end})
end

--Font strings measure every visible character as 7 pixels wide.
local CHAR_WIDTH = 7
local function VisibleText(s)
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]+:", ""):gsub("|r", "")
	s = s:gsub("|H.-|h", ""):gsub("|h", "")
	return s
end

--Like the client, a font string has a font only from its template, SetFont or SetFontObject,
--and SetText fails without one.
local function FakeFontString(template)
	local text = ""
	local hasFont = template ~= nil
	return FakeObject({
		SetFont = function() hasFont = true; return true end,
		SetFontObject = function() hasFont = true end,
		SetText = function(_, s)
			if not hasFont then error("FontString:SetText(): Font not set", 2) end
			text = s or ""
		end,
		GetText = function() return text end,
		GetUnboundedStringWidth = function() return #VisibleText(text) * CHAR_WIDTH end,
		GetStringWidth = function() return #VisibleText(text) * CHAR_WIDTH end,
		GetStringHeight = function() return 12 end,
		GetFont = function() if hasFont then return "Fonts\\ARIALN.TTF", 14, "" end end,
	})
end

local function FakeFrame(parent)
	local shown = true
	local enabled = true
	local height = 0
	local scripts = {}
	local frame
	frame = FakeObject({
		GetParent = function() return parent end,
		CreateFontString = function(_, _, _, template) return FakeFontString(template) end,
		CreateTexture = function() return FakeFrame(frame) end,
		Show = function(self)
			local wasShown = shown
			shown = true
			if not wasShown and scripts.OnShow then scripts.OnShow(self) end
		end,
		Hide = function(self)
			local wasShown = shown
			shown = false
			if wasShown and scripts.OnHide then scripts.OnHide(self) end
		end,
		SetShown = function(_, value) shown = value and true or false end,
		IsShown = function() return shown end,
		SetScript = function(_, name, fn) scripts[name] = fn end,
		GetScript = function(_, name) return scripts[name] end,
		GetChecked = function() return false end,
		SetEnabled = function(_, value) enabled = value and true or false end,
		IsEnabled = function() return enabled end,
		SetHeight = function(_, h) height = h end,
		GetHeight = function() return height end,
		GetEffectiveScale = function() return 1 end,
		--A click runs OnClick only on an enabled button, as in the client.
		Click = function(self) if enabled and scripts.OnClick then scripts.OnClick(self, "LeftButton") end end,
	})
	return frame
end

function CreateFrame(frameType, name, parent, template)
	local frame = FakeFrame(parent)
	if template == "UICheckButtonTemplate" then
		rawset(frame, "Text", FakeFontString("GameFontNormalSmall"))
	end
	if name then _G[name] = frame end
	return frame
end

--A chat edit box that records every write, so the tests can prove typing never changes it.
local function FakeEditBox(name)
	local box = {text = "", cursor = 0, hooks = {}, writes = {}, focus = true}
	local function record(what, ...) box.writes[#box.writes + 1] = {what, ...} end
	local methods = {
		GetName = function() return name end,
		GetText = function() return box.text end,
		GetCursorPosition = function() return box.cursor end,
		GetTextInsets = function() return 15, 13, 0, 0 end,
		GetWidth = function() return 400 end,
		GetLeft = function() return 100 end,
		GetEffectiveScale = function() return 1 end,
		GetFont = function() return "Fonts\\ARIALN.TTF", 14, "" end,
		IsMultiLine = function() return false end,
		HasFocus = function() return box.focus end,
		HookScript = function(_, script, fn)
			box.hooks[script] = box.hooks[script] or {}
			table.insert(box.hooks[script], fn)
		end,
		SetScript = function(_, script) record("SetScript", script) end,
		SetText = function(self, s) record("SetText", s); box.text = s; box.cursor = #s; self:Fire("OnTextChanged") end,
		Insert = function(_, s) record("Insert", s) end,
		SetCursorPosition = function(_, pos) record("SetCursorPosition", pos); box.cursor = pos end,
		HighlightText = function(_, startPos, endPos) record("HighlightText", startPos, endPos) end,
		SetFocus = function() record("SetFocus") end,
		SetAttribute = function(_, key) record("SetAttribute", key) end,
		--What the client does: runs the post-hooks after Blizzard's own handler.
		Fire = function(self, script, ...)
			for _, fn in ipairs(box.hooks[script] or {}) do fn(self, ...) end
		end,
		--The user typing: the client changes the text itself, then OnTextChanged fires.
		Type = function(self, s)
			box.text = box.text .. s
			box.cursor = #box.text
			self:Fire("OnTextChanged", true)
		end,
	}
	return setmetatable(box, {__index = function(_, key) return methods[key] or noop end})
end

local chatFrameEditBox = FakeEditBox("ChatFrame1EditBox")
ChatFrame1EditBox = chatFrameEditBox
NUM_CHAT_WINDOWS = 1
CHAT_FRAMES = {"ChatFrame1"}

local messages = {}
DEFAULT_CHAT_FRAME = {AddMessage = function(_, message) messages[#messages + 1] = message end}
UIParent = FakeFrame()

local originalSendChatMessage = function() end
C_ChatInfo = {SendChatMessage = originalSendChatMessage, InChatMessagingLockdown = function() return false end}
SendChatMessage = originalSendChatMessage

local inCombat = false
function InCombatLockdown() return inCombat end
function IsInGroup() return false end
function IsInInstance() return false, "none" end
LE_PARTY_CATEGORY_INSTANCE = 2

local secureHooks = {}
function hooksecurefunc(tableOrName, key, fn)
	if fn == nil then
		secureHooks[tableOrName] = key
	else
		secureHooks[key] = fn
	end
end
ChatFrameUtil = {ActivateChat = noop}

C_Timer = {After = function(_, fn) fn() end}

--Blizzard's shared menus must never be used: menus opened by addon code taint the pooled menu
--frames, and the unit frame menu then can't set raid target markers.
local function NoBlizzardMenus() error("used one of Blizzard's shared menus", 2) end
MenuUtil = {CreateContextMenu = NoBlizzardMenus}
UIDropDownMenu_Initialize, ToggleDropDownMenu, CloseDropDownMenus = NoBlizzardMenus, NoBlizzardMenus, NoBlizzardMenus
GameFontNormal, GameFontHighlight, GameFontDisable = {}, {}, {}

--The rows of Misspelled's own suggestions popup, when it's shown.
local function PopupRows()
	local popup = _G.MisspelledSuggestionsPopup
	if popup == nil or not popup:IsShown() then return nil end
	local rows = {}
	for _, row in ipairs(popup.rows) do
		if row:IsShown() then
			rows[#rows + 1] = {text = row.item.text, row = row, enabled = row:IsEnabled(), item = row.item}
		end
	end
	return rows
end
local function FindRow(rows, text)
	for _, r in ipairs(rows) do
		if r.text == text then return r end
	end
end
local function ClosePopup()
	if _G.MisspelledSuggestionsPopup then _G.MisspelledSuggestionsPopup:Hide() end
end

local mouseX = 0
function GetCursorPosition() return mouseX, 0 end

local settingsCategory
Settings = {
	RegisterCanvasLayoutCategory = function(frame, name) settingsCategory = {frame = frame, name = name}; return settingsCategory end,
	RegisterAddOnCategory = noop,
}

C_FriendList = {
	GetNumFriends = function() return 1 end,
	GetFriendInfoByIndex = function() return {name = "Zanthor-Bloodfury"} end,
}
function IsInGuild() return false end
function GetLocale() return "enUS" end
PlaySound = noop
C_AddOns = {GetAddOnMetadata = function() return "test" end}

-- Just enough of LibStub and Ace3 for the addon to load.
local localeStrings = {}
local libs = {
	["AceAddon-3.0"] = {NewAddon = function(_, name)
		return {
			name = name,
			events = {},
			RegisterEvent = function(self, event, method) self.events[event] = method or event end,
			UnregisterEvent = function(self, event) self.events[event] = nil end,
		}
	end},
	["AceLocale-3.0"] = {
		NewLocale = function() return setmetatable({}, {__newindex = function(_, k, v) localeStrings[k] = (v == true) and k or v end}) end,
		GetLocale = function() return setmetatable({}, {__index = function(_, k)
			assert(localeStrings[k], "missing locale string: " .. tostring(k))
			return localeStrings[k]
		end}) end,
	},
	["AceGUI-3.0"] = {},
}
function LibStub(name) return assert(libs[name], "unknown library " .. name) end

-------------------------------------------------------------------------
-- Load the addon, in TOC order
-------------------------------------------------------------------------

local function LoadAddonFile(path)
	local handle = assert(io.open(path, "rb"))
	local source = handle:read("*a"):gsub("^\239\187\191", "")
	handle:close()
	assert(loadstring(source, "@" .. path))()
end

LoadAddonFile("Localization/enUS.lua")
LoadAddonFile("UTF8/utf8data.lua")
LoadAddonFile("UTF8/utf8.lua")
LoadAddonFile("Dict/Dic_enUS.lua")
LoadAddonFile("WordDict.lua")
LoadAddonFile("Misspelled.lua")

Misspelled:OnInitialize()
Misspelled:OnEnable()

-------------------------------------------------------------------------
-- Tests
-------------------------------------------------------------------------

local failures, count = 0, 0
local function test(name, fn)
	count = count + 1
	local passed, err = pcall(fn)
	if passed then
		print("PASS  " .. name)
	else
		failures = failures + 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end

local function eq(actual, expected, what)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
	end
end

local function words(list)
	local out = {}
	for _, w in ipairs(list) do out[#out + 1] = w.Word .. "@" .. w.StartPos .. "-" .. w.EndPos end
	return table.concat(out, " ")
end

local function Reset(box)
	box.text, box.cursor, box.writes, box.focus = "", 0, {}, true
	box:Fire("OnEscapePressed")
	box.writes = {}
end

test("finds a misspelled word once it's finished", function()
	eq(words(Misspelled:FindMisspelledWords("Hello wrold ")), "wrold@7-11")
end)

test("doesn't check the word still being typed", function()
	eq(words(Misspelled:FindMisspelledWords("Hello wrold")), "")
end)

test("ignores slash commands, upper case words, words with numbers and raid icons", function()
	eq(words(Misspelled:FindMisspelledWords("/cast Flsh Heall ")), "")
	eq(words(Misspelled:FindMisspelledWords("OMG lol1 {sqare} {rt1} ")), "")
end)

test("doesn't check links, colors or textures", function()
	eq(words(Misspelled:FindMisspelledWords("Test |cff71d5ff|Hspell:2061:0|h[Flsh Heall]|h|r badd.")), "badd@49-52")
	eq(words(Misspelled:FindMisspelledWords("test: |cnIQ2:|Hitem:225566::::::::80:258:::::::::|h[Warpd Wing]|h|r badd.")), "badd@69-72")
	eq(words(Misspelled:FindMisspelledWords("|Hplayer:Bob|h[Bbo]|h |TInterface\\Icons\\Foo:0|t hi.")), "")
	eq(words(Misspelled:FindMisspelledWords("Off-hand: |cffa335ee|Hitem:222566::::|h[Vagabnd's Torch |A:Professions-ChatIcon-Quality-Tier5:17:17::1|a]|h|r fine.")), "")
end)

test("hooks chat edit boxes with post-hooks only and leaves SendChatMessage alone", function()
	assert(chatFrameEditBox.hooks.OnTextChanged, "OnTextChanged not hooked")
	assert(chatFrameEditBox.hooks.OnMouseUp, "OnMouseUp not hooked")
	eq(#chatFrameEditBox.writes, 0, "writes to the edit box while hooking")
	eq(C_ChatInfo.SendChatMessage, originalSendChatMessage, "C_ChatInfo.SendChatMessage")
	eq(SendChatMessage, originalSendChatMessage, "SendChatMessage")
	assert(secureHooks.ActivateChat, "ChatFrameUtil.ActivateChat not hooked")
end)

test("typing never writes to the chat edit box", function()
	Reset(chatFrameEditBox)
	for c in ("Hello wrold, how are yuo doing? ok"):gmatch(".") do
		chatFrameEditBox:Type(c)
	end
	eq(#chatFrameEditBox.writes, 0, "writes while typing")
end)

test("underline sits under the misspelled word", function()
	Reset(chatFrameEditBox)
	chatFrameEditBox:Type("Hello wrold ok")
	-- 7px per char, 15px left inset: "wrold" covers characters 7-11
	mouseX = 100 + 15 + 6 * CHAR_WIDTH + 3
	ClosePopup()
	chatFrameEditBox:Fire("OnMouseUp", "RightButton")
	local rows = PopupRows()
	assert(rows, "right-click on the word didn't open the suggestions")
	eq(rows[1].text, "Suggestions for: wrold", "title")
	eq(rows[1].enabled, false, "title clickable")

	ClosePopup()
	mouseX = 100 + 15 + 1 * CHAR_WIDTH -- over "Hello"
	chatFrameEditBox:Fire("OnMouseUp", "RightButton")
	eq(PopupRows(), nil, "suggestions for a correctly spelled word")
end)

test("scroll follows the caret like a single line edit box", function()
	eq(Misspelled.ComputeScroll(0, 100, 200, 372), 0, "text fits")
	eq(Misspelled.ComputeScroll(0, 700, 700, 372), 328, "caret at the end of long text")
	eq(Misspelled.ComputeScroll(328, 500, 700, 372), 328, "caret moves left but stays in view")
	eq(Misspelled.ComputeScroll(328, 100, 700, 372), 100, "caret moves left out of view")
	eq(Misspelled.ComputeScroll(328, 400, 500, 372), 128, "text deleted from the end")
end)

--Right-clicks "wrold" and returns the popup rows.
local function OpenSuggestionsOnWrold()
	Reset(chatFrameEditBox)
	chatFrameEditBox:Type("Hello wrold ok")
	mouseX = 100 + 15 + 7 * CHAR_WIDTH
	ClosePopup()
	chatFrameEditBox:Fire("OnMouseUp", "RightButton")
	local rows = PopupRows()
	assert(rows, "suggestions didn't open")
	assert(FindRow(rows, "world"), "'world' not suggested for 'wrold'")
	return rows
end

test("picking a suggestion out of combat replaces the word", function()
	local rows = OpenSuggestionsOnWrold()
	local choice = FindRow(rows, "world")
	eq(choice.enabled, true, "suggestion enabled")
	choice.row:Click()
	eq(chatFrameEditBox.text, "Hello world ok", "text")
	eq(chatFrameEditBox.cursor, 12, "cursor after the word and its space")
	eq(PopupRows(), nil, "popup still open after picking")
end)

test("typing and sending in combat never touches the chat edit box", function()
	inCombat = true
	Reset(chatFrameEditBox)
	for c in ("out of manna, heal me pls"):gmatch(".") do
		chatFrameEditBox:Type(c)
	end
	chatFrameEditBox.text, chatFrameEditBox.cursor = "", 0 -- Blizzard sends and clears it
	chatFrameEditBox:Fire("OnTextChanged", false)
	chatFrameEditBox:Fire("OnEnterPressed")
	inCombat = false
	eq(#chatFrameEditBox.writes, 0, "writes")
end)

test("in combat suggestions are listed but greyed out, and never change the text", function()
	inCombat = true
	local rows = OpenSuggestionsOnWrold()
	eq(rows[2].text, "Fixing words is paused during combat and encounters", "note")
	local choice = FindRow(rows, "world")
	eq(choice.enabled, false, "suggestion enabled")
	eq(FindRow(rows, "Ignore All").enabled, true, "Ignore All enabled")
	eq(FindRow(rows, "Add to Dictionary").enabled, true, "Add to Dictionary enabled")

	--Nothing happens even if it were picked: no text change, no selection.
	choice.row:Click()
	choice.item.func()
	Misspelled:ReplaceWord(chatFrameEditBox, {Word = "wrold", StartPos = 7, EndPos = 11}, "world")
	eq(chatFrameEditBox.text, "Hello wrold ok", "text")
	eq(#chatFrameEditBox.writes, 0, "writes")
	inCombat = false
end)

test("suggestions grey out if combat starts while the popup is open", function()
	local rows = OpenSuggestionsOnWrold()
	eq(FindRow(rows, "world").enabled, true, "before combat")
	inCombat = true
	local popup = _G.MisspelledSuggestionsPopup
	popup:GetScript("OnEvent")(popup, "PLAYER_REGEN_DISABLED")
	eq(FindRow(PopupRows(), "world").enabled, false, "in combat")
	inCombat = false
	popup:GetScript("OnEvent")(popup, "PLAYER_REGEN_ENABLED")
	eq(FindRow(PopupRows(), "world").enabled, true, "after combat")
end)

test("Enter or Escape closes the popup", function()
	OpenSuggestionsOnWrold()
	chatFrameEditBox:Fire("OnEscapePressed")
	eq(PopupRows(), nil, "popup open after Escape")
end)

test("chat lockdown also greys out suggestions", function()
	C_ChatInfo.InChatMessagingLockdown = function() return true end
	local rows = OpenSuggestionsOnWrold()
	eq(FindRow(rows, "world").enabled, false, "suggestion enabled")
	Misspelled:ReplaceWord(chatFrameEditBox, {Word = "wrold", StartPos = 7, EndPos = 11}, "world")
	C_ChatInfo.InChatMessagingLockdown = function() return false end
	eq(chatFrameEditBox.text, "Hello wrold ok", "text")
	eq(#chatFrameEditBox.writes, 0, "writes")
end)

test("keeps the capital letter of the misspelled word", function()
	Reset(chatFrameEditBox)
	chatFrameEditBox:Type("Wrold hi")
	Misspelled:ReplaceWord(chatFrameEditBox, {Word = "Wrold", StartPos = 1, EndPos = 5}, "world")
	eq(chatFrameEditBox.text, "World hi", "text")
end)

test("secret text is left alone", function()
	Reset(chatFrameEditBox)
	chatFrameEditBox.text = SECRET
	chatFrameEditBox:Fire("OnTextChanged", true)
	chatFrameEditBox:Fire("OnMouseUp", "RightButton")
	eq(#chatFrameEditBox.writes, 0, "writes")
end)

test("friend names, with realm or surname, are valid words", function()
	eq(words(Misspelled:FindMisspelledWords("hi Zanthor and Bloodfury ok")), "")
	eq(Misspelled:IsFriend("Zanthor"), true, "IsFriend")
end)

test("Ignore All and Add to Dictionary take effect right away, in combat too", function()
	Reset(chatFrameEditBox)
	chatFrameEditBox:Type("zzqx ok")
	eq(words(Misspelled:FindMisspelledWords("zzqx ok")), "zzqx@1-4")
	inCombat = true
	Misspelled:IgnoreWord("zzqx")
	inCombat = false
	eq(words(Misspelled:FindMisspelledWords("zzqx ok")), "")
	eq(#chatFrameEditBox.writes, 0, "writes to the edit box")

	Misspelled_DB.UserDict = {}
	Misspelled:AddToUserDict("Qwzzle")
	eq(words(Misspelled:FindMisspelledWords("Qwzzle ok")), "")
	assert(Misspelled_DB.UserDict.Qwzzle, "not saved in the user dictionary")
end)

test("options panel is registered with the Settings panel", function()
	assert(settingsCategory, "not registered")
	eq(settingsCategory.name, "Misspelled", "category name")
end)

print(string.format("\n%d of %d passed", count - failures, count))
os.exit(failures == 0 and 0 or 1)
