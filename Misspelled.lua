--[[--------------------------------------------------------------------------
  Developed by Nathan Pieper - nrpieper (@) gmail (dot) com
  Misspelled is an interactive chat text spell checker for World of Warcraft

  This code freely distributed for your use in any GPL compliant project.
  Portions of this code are covered by the Gnu Public License (GPL)
  Dictionaries use the OpenOffice/HunSpell/ASpell dictionary format
  (http://wiki.services.openoffice.org/wiki/Dictionaries)
  Phonetic cache information created via the NetSpell dictionary util.
  References & Credits:
  Paul Welter & NetSpell: http://www.loresoft.com/projects/netspell
  Metaphone Algorithm http://aspell.net/metaphone/
  Edit Distance Algorithm http://en.wikipedia.org/wiki/Levenshtein_distance

--------------------------------------------------------------------------]]--


--[[
How Misspelled shows misspellings (rewritten 9/2026 for WoW Forever and Midnight)

Misspelled used to highlight a misspelled word by inserting a color code into the chat edit box
text (editbox:SetText), and hooked SendChatMessage to strip those codes out again before a
message was sent. On the modern client (Midnight 12.x, and WoW Forever, which runs the same
client) both of those taint Blizzard's chat code:
 - C_ChatInfo.SendChatMessage is a restricted API. With the hook in place every message went
   through addon code, so Blizzard blocked it (ADDON_ACTION_BLOCKED) whenever chat messaging
   lockdown was active: boss encounters, Mythic+ and PvP matches.
 - editbox:SetText from addon code runs Blizzard's OnTextChanged / ParseText under taint and
   leaves the edit box tainted, so the next message or secure slash command (/cast, /target)
   could be blocked too.

So Misspelled no longer changes the text you type and never hooks SendChatMessage. It reads
the edit box text and draws an underline under each misspelled word on its own overlay frame.
Nothing Blizzard runs is tainted, so spell checking keeps working in combat, boss encounters,
Mythic+ and PvP.

The only time Misspelled writes to the edit box is when you pick a suggestion from the
right-click menu. While any addon restriction is active (combat, encounter, Mythic+, PvP,
chat lockdown) the suggestions are still listed but greyed out, and picking one does nothing,
so the text you type is never touched. Ignore All and Add to Dictionary still work, since
they don't change the text.

Where the words are:
The overlay has to know where each word is drawn. Widths come from a hidden FontString that
uses the edit box's font. A single line EditBox scrolls sideways to keep the caret visible and
there is no API for that scroll offset, so ComputeScroll follows it from the caret position.

WIM Integration
Wim allows multiple chat windows at once, so state is kept per edit box.
Wim notifies us of text changes via WIM.RegisterWidgetTrigger.

User Dictionary Editor Added
(12/6/2009) - Used AceGUI to add the ability to remove words from the user dictionary.

(1/12/2010) - Added enGB UK English dictionary.

(5/12/2010) - Added support for PTR Patch 3.5.  Multiple ChatEditBoxes get created.  Hook into the activate routine.

(5/23/2010) - Fixed enGB dictionary load issue.

(6/24/2010) - Added itIT Italian dictionary

(7/22/2010) - The Addon Gryphonheart Items (GHI) begins it's item color tags with a (|C) capitol C character.  I added that possibility to the chat text parsing.

(9/14/2010) - Client 4 has some issues with trying to set the owner of the popmenu items.  Looks like it's not needed.

(9/7/2019) - Wow Classic: When starting you can't have friends and the global function: GetNumFriends() is nil.  Detect and skip to eliminate the error.

(4/30/2025) - Changes added to RemoveHighlighting to parse new Item Quality # colors and Global Colors UI escape sequences.
(12/18/2025) - Wow Retail 12.2.7 changes added to hook chat frames.
(9/30/2026) - WoW Forever (interface 16001) support. Highlighting moved to an overlay so Misspelled
              no longer taints chat, and keeps working in combat and boss encounters (see above).
--]]--

local _G = _G

Misspelled = LibStub("AceAddon-3.0"):NewAddon("Misspelled", "AceEvent-3.0")

local Misspelled = _G.Misspelled

local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
Misspelled.Version = GetAddOnMetadata and GetAddOnMetadata("Misspelled", "Version") or ""

local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Misspelled", true)

local string_find = string.find
local string_format = string.format
local string_gmatch = string.gmatch
local string_gsub = string.gsub
local string_lower = string.lower
local string_rep = string.rep
local string_sub = string.sub
local string_upper = string.upper
local math_max = math.max
local math_min = math.min
local tostring = tostring
local type = type
local pairs = pairs
local ipairs = ipairs

--Midnight and WoW Forever return "secret" values in restricted states. A secret can't be compared,
--measured or indexed by addon code, so anything that might be one is checked first.
local issecretvalue = _G.issecretvalue or function() return false end

local UNDERLINE_COLOR = {1, 0.25, 0.25, 0.9} --r, g, b, a of the line drawn under misspelled words
local UNDERLINE_THICKNESS = 2
local LAYOUT_INTERVAL = 0.05 --Seconds between checks for caret, size or font changes that move the words

local WORD_PATTERN = "[A-Za-z0-9_'À-ÿœæŒÆ]+"
local WIDTH_MARKER = "." --Appended when measuring text that may end in spaces (see TextWidth)

--WoW UI escape sequences (https://warcraft.wiki.gg/wiki/UI_escape_sequences) are replaced with
--# characters of the same length, so their contents aren't spell checked while byte positions
--stay the same. Whole links go first, so a link's [display text] is covered along with it.
local WowTextMarkupEscapes = {
	"|cn[^:]+:.-|r",          -- Global Colors and Item Quality colors: |cncolorname:text|r, |cnIQn:text|r
	"|[Cc]%x-|H.-|h.-|h|r",   -- Hex color coded links: |cffxxxxxx|Htype:payload|h[text]|h|r
	"|H.-|h.-|h",             -- Links without a color, with their [text]
	"|H.-|h",                 -- Any remaining link
	"|T.-|t",                 -- Textures
	"|A.-|a",                 -- Texture atlas
	"|K.-|k",                 -- Battle.net protected names
	"{.-}",                   -- Raid target icons
	"|n",                     -- Newline
}

local WordCache = {}           --Every word checked: WordCache[word] = {Correct = bool, Suggestions = table or nil}
local WordCacheCount = 0       --Counter used to track when we should clean the WordCache table to save memory
local WordCacheCountMax = 7000 --Number of entries that can live in the WordCache before we clean the cache

--Per edit box state, keyed by the edit box. Weak keys, and nothing is ever written onto
--Blizzard's frames: a field written by addon code would taint them.
local EditBoxState = setmetatable({}, {__mode = "k"})
local HookedEditBoxes = setmetatable({}, {__mode = "k"})
local BlizzardChatEditBoxes = setmetatable({}, {__mode = "k"})

local GuildNames = {}  --Parts of guild member names, for the (Guild) note in the suggestions menu
local FriendNames = {} --Parts of friend names, for the (Friend) note

--Output debug messages to the DevTool addon (https://github.com/brittyazel/DevTool)
function Misspelled:AddToInspector(data, strName)
	if DevTool and self.DEBUG then
		if type(data) == "string" then
			-- %q "quotes" the string; replacing | with || shows all color and link escape sequences
			data = string_gsub(string_format("%q", data), "[|]", "||")
		end
		DevTool:AddData(data, "Misspelled: " .. strName)
	end
end

function Misspelled:OnInitialize()
	--Enable to output debug messages created with calls to: AddToInspector(data, strName), to the addon: DevTool
	--self.DEBUG = true

	if Misspelled_DB == nil then
		Misspelled_DB = {}
	end

	--Check if the user has chosen to override the auto dictionary selection
	if Misspelled_DB.LoadDictionary == nil then
		Misspelled_DB.LoadDictionary = "enUS"
	end

	if Misspelled_DB.AutoSelectDictionary == nil then
		Misspelled_DB.AutoSelectDictionary = true
	end

	--Load the Dictionary
	local dictLoaded
	if Misspelled_DB.AutoSelectDictionary == true then
		dictLoaded = WordDict:Init()
	else
		dictLoaded = WordDict:Init(Misspelled_DB.LoadDictionary)
	end

	Misspelled:print("Misspelled: " .. L["Dictionary Loaded"] .. " - " .. dictLoaded)

	--Load user dict
	Misspelled:LoadUserDict()
	Misspelled:print("Misspelled: " .. L["User Dictionary Loaded"])

	-- Build Interface Options window
	self:CreateInterfaceOptions()

	--Watch for other chat addons: Wim, to load and then integrate.
	self:RegisterEvent("ADDON_LOADED")
end

function Misspelled:OnEnable()
	self:HookChatEditBoxes()
	self:IntegrateWIM()

	--Friends and guild members are valid words.
	self:RegisterEvent("FRIENDLIST_UPDATE", "LoadFriends")
	self:LoadFriends()

	if IsInGuild and IsInGuild() then
		--The roster arrives with GUILD_ROSTER_UPDATE after we ask the server for it.
		self:RegisterEvent("GUILD_ROSTER_UPDATE")
		if C_GuildInfo and C_GuildInfo.GuildRoster then
			C_GuildInfo.GuildRoster()
		elseif _G.GuildRoster then
			_G.GuildRoster() -- For older game clients
		end
	end
end

function Misspelled:ADDON_LOADED(event, addonName)
	if addonName == "WIM" then
		self:IntegrateWIM()
	end
end

function Misspelled:GUILD_ROSTER_UPDATE()
	self:LoadGuildRoster()
end


-------------------------------------------------------------------------
--
-- Hooking chat edit boxes
--
-------------------------------------------------------------------------

--Only post-hooks are used (HookScript, hooksecurefunc): Blizzard's own handler runs first and
--untainted, then ours. Scripts are never replaced.
function Misspelled:HookEditBox(editbox, isBlizzardChat)
	if editbox == nil or type(editbox.HookScript) ~= "function" then return end
	if isBlizzardChat then
		BlizzardChatEditBoxes[editbox] = true
	end
	if HookedEditBoxes[editbox] then return end
	HookedEditBoxes[editbox] = true

	editbox:HookScript("OnTextChanged", Misspelled.EditBox_OnTextChanged)
	editbox:HookScript("OnMouseUp", Misspelled.EditBox_OnMouseUp) -- Right-clicks show the suggestions menu
	editbox:HookScript("OnEscapePressed", Misspelled.EditBox_OnReset)
	editbox:HookScript("OnEnterPressed", Misspelled.EditBox_OnReset)
end

function Misspelled:HookChatEditBoxes()
	local numWindows = _G.NUM_CHAT_WINDOWS or 10
	for i = 1, numWindows do
		self:HookEditBox(_G["ChatFrame" .. i .. "EditBox"], true)
	end
	if type(_G.CHAT_FRAMES) == "table" then
		for _, frameName in ipairs(_G.CHAT_FRAMES) do
			self:HookEditBox(_G[frameName .. "EditBox"], true)
		end
	end
	if _G.ChatFrameEditBox then
		self:HookEditBox(_G.ChatFrameEditBox, true) -- Very old game clients
	end

	--Edit boxes created later (whisper windows, popped out chats) are hooked when first activated.
	local function OnActivateChat(editBox)
		Misspelled:HookEditBox(editBox, true)
	end
	if ChatFrameUtil and ChatFrameUtil.ActivateChat then
		hooksecurefunc(ChatFrameUtil, "ActivateChat", OnActivateChat) -- Midnight, WoW Forever
	elseif _G.ChatEdit_ActivateChat then
		hooksecurefunc("ChatEdit_ActivateChat", OnActivateChat) -- Older game clients
	end
end

function Misspelled:IntegrateWIM()
	if self.wimIntegrated or not (WIM and WIM.RegisterWidgetTrigger) then return end
	self.wimIntegrated = true

	--WIM's message boxes belong to WIM, so we only need to know when their text changes.
	WIM.RegisterWidgetTrigger("msg_box", "whisper,chat,w2w", "OnTextChanged", function(msgBox)
		Misspelled:HookEditBox(msgBox)
		Misspelled:CheckEditBox(msgBox)
	end)
end

function Misspelled.EditBox_OnTextChanged(editbox)
	Misspelled:CheckEditBox(editbox)
end

--Enter or Escape. Blizzard's handler has already run and usually cleared the text.
function Misspelled.EditBox_OnReset(editbox)
	Misspelled:HideSuggestions(editbox)
	Misspelled:CheckEditBox(editbox, true)
end

function Misspelled.EditBox_OnMouseUp(editbox, button)
	if button ~= "RightButton" then return end
	local state = EditBoxState[editbox]
	if state == nil or #state.misspelled == 0 then return end

	local entry = Misspelled:GetMisspelledWordAtMouse(editbox, state)
	if entry then
		Misspelled:ShowSuggestions(editbox, entry)
	end
end


-------------------------------------------------------------------------
--
-- Spell checking
--
-------------------------------------------------------------------------

--Returns true when the word is in the dictionary. Results are cached in WordCache.
function Misspelled:IsWordCorrect(word)
	local cached = WordCache[word]
	if cached == nil then
		--See if the dictionary contains the word, or the lower case version of the word
		local correct = WordDict:Contains(word) or WordDict:Contains(string_lower(word))
		cached = {Correct = correct and true or false}
		WordCache[word] = cached
		WordCacheCount = WordCacheCount + 1
	end
	return cached.Correct
end

--Replaces WoW UI escape sequences with # characters of the same length.
function Misspelled:MaskEscapeSequences(text)
	for _, patt in ipairs(WowTextMarkupEscapes) do
		text = string_gsub(text, patt, function(x) return string_rep("#", #x) end)
	end
	return text
end

--Finds the misspelled words in a line of chat text.
--Returns an array of {Word = word, StartPos = n, EndPos = n}, byte positions in text, in order.
--Slash commands aren't checked. Words in all upper case or with numbers in them are ignored.
--The last word isn't checked until it's finished, i.e. until some word terminator follows it.
function Misspelled:FindMisspelledWords(text)
	local found = {}
	if text == nil or text == "" then return found end
	if string_sub(text, 1, 1) == "/" then return found end

	local maskedText = self:MaskEscapeSequences(text)
	local textLength = #text

	local matchPosStart, matchPosEnd = string_find(maskedText, WORD_PATTERN)
	while matchPosStart ~= nil do
		local word = string_sub(maskedText, matchPosStart, matchPosEnd)
		if matchPosEnd < textLength
			and word ~= string_upper(word)
			and string_find(word, "%d") == nil
			and not self:IsWordCorrect(word) then
			found[#found + 1] = {Word = word, StartPos = matchPosStart, EndPos = matchPosEnd}
		end
		matchPosStart, matchPosEnd = string_find(maskedText, WORD_PATTERN, matchPosEnd + 1)
	end
	return found
end

local function GetState(editbox)
	local state = EditBoxState[editbox]
	if state == nil then
		state = {misspelled = {}, segments = {}, lines = {}, scroll = 0}
		EditBoxState[editbox] = state
	end
	return state
end

--Spell checks the text in an edit box and underlines the misspelled words.
--This only reads the edit box; its text is never changed here.
function Misspelled:CheckEditBox(editbox, force)
	local state = GetState(editbox)
	local text = editbox:GetText()
	if text == nil or issecretvalue(text) then
		self:ClearEditBox(editbox)
		return
	end
	if text == state.text and not force then return end
	state.text = text

	--Clear the WordCache table to save memory, if it's gotten very large
	if text == "" and WordCacheCount > WordCacheCountMax then
		WordCache = {}
		WordCacheCount = 0
	end

	state.misspelled = self:FindMisspelledWords(text)
	if #state.misspelled > 0 then
		self:CreateOverlay(editbox, state)
		state.overlay:Show()
		self:LayoutHighlights(editbox)
	else
		self:ClearEditBox(editbox, true)
	end
end

--Removes the underlines. The overlay is hidden too, so its OnUpdate only runs while there
--are misspelled words.
function Misspelled:ClearEditBox(editbox, keepText)
	local state = EditBoxState[editbox]
	if state == nil then return end
	state.misspelled = {}
	for i = #state.segments, 1, -1 do
		state.segments[i] = nil
	end
	for _, line in ipairs(state.lines) do
		line:Hide()
	end
	if not keepText then
		state.text = nil
	end
	if state.overlay then
		state.overlay:Hide()
	end
end

--Checks every edit box again, after the dictionary or ignored words changed.
function Misspelled:RecheckAll()
	for editbox, state in pairs(EditBoxState) do
		if state.text ~= nil then
			self:CheckEditBox(editbox, true)
		end
	end
end


-------------------------------------------------------------------------
--
-- Underlining misspelled words
--
-------------------------------------------------------------------------

--Emulates how a single line EditBox scrolls sideways to keep the caret in view:
--as little as needed, and never past the end of the text. All values are in pixels.
function Misspelled.ComputeScroll(scroll, caretX, textWidth, visibleWidth)
	if textWidth <= visibleWidth then return 0 end
	if caretX - scroll > visibleWidth then
		scroll = caretX - visibleWidth
	end
	if caretX < scroll then
		scroll = caretX
	end
	if textWidth - scroll < visibleWidth then
		scroll = textWidth - visibleWidth
	end
	if scroll < 0 then
		scroll = 0
	end
	return scroll
end

local function Overlay_OnUpdate(overlay, elapsed)
	overlay.elapsed = (overlay.elapsed or 0) + elapsed
	if overlay.elapsed < LAYOUT_INTERVAL then return end
	overlay.elapsed = 0

	local editbox = overlay:GetParent()
	local state = EditBoxState[editbox]
	if state == nil or #state.misspelled == 0 then return end

	--Words move when the caret scrolls the text, the box is resized, the chat type header
	--changes the text insets, or the chat font size changes.
	local caret = editbox:GetCursorPosition()
	if issecretvalue(caret) then return end
	local left, right = editbox:GetTextInsets()
	local _, fontSize = editbox:GetFont()
	if caret ~= state.lastCaret or editbox:GetWidth() ~= state.lastWidth or left ~= state.lastLeft
		or right ~= state.lastRight or fontSize ~= state.fontSize then
		Misspelled:LayoutHighlights(editbox)
	end
end

function Misspelled:CreateOverlay(editbox, state)
	if state.overlay then return end

	--Our own child frame on top of the edit box. It doesn't take the mouse, so clicks and
	--typing still go to the edit box.
	local overlay = CreateFrame("Frame", nil, editbox)
	overlay:SetAllPoints(editbox)
	overlay:SetScript("OnUpdate", Overlay_OnUpdate)

	--Hidden font string, used to measure the width of the text as the edit box draws it.
	--It starts with the chat font: SetText fails on a font string that has no font.
	local measure = overlay:CreateFontString(nil, "BACKGROUND", "ChatFontNormal")
	measure:SetPoint("TOPLEFT")
	measure:SetAlpha(0)

	state.overlay = overlay
	state.measure = measure
end

--Keeps the measuring font string in the edit box's font. Returns the font height.
local function ApplyFont(editbox, state)
	local font, fontSize, fontFlags = editbox:GetFont()
	if font then
		if font ~= state.font or fontSize ~= state.fontSize or fontFlags ~= state.fontFlags then
			state.measure:SetFont(font, fontSize, fontFlags or "")
			state.font, state.fontSize, state.fontFlags = font, fontSize, fontFlags
			state.markerWidth = nil
		end
	else
		local fontObject = editbox:GetFontObject()
		if fontObject and fontObject ~= state.fontObject then
			state.measure:SetFontObject(fontObject)
			state.fontObject = fontObject
			state.markerWidth = nil
		end
		local _
		_, fontSize = state.measure:GetFont()
	end
	return fontSize or 14
end

local function StringWidth(measure, s)
	measure:SetText(s)
	if measure.GetUnboundedStringWidth then
		return measure:GetUnboundedStringWidth()
	end
	return measure:GetStringWidth()
end

--Width of s drawn from the start of the line. A marker is measured on the end, so trailing
--spaces count even if the font string would trim them.
local function TextWidth(state, s)
	if s == "" then return 0 end
	if state.markerWidth == nil then
		state.markerWidth = StringWidth(state.measure, WIDTH_MARKER)
	end
	return StringWidth(state.measure, s .. WIDTH_MARKER) - state.markerWidth
end

function Misspelled:LayoutHighlights(editbox)
	local state = EditBoxState[editbox]
	if state == nil or state.overlay == nil then return end

	local segments = state.segments
	for i = #segments, 1, -1 do
		segments[i] = nil
	end

	local shown = 0
	local text = state.text
	local caret = editbox:GetCursorPosition()
	if issecretvalue(caret) then
		caret = nil
	end
	local width = editbox:GetWidth()
	local left, right, top, bottom = editbox:GetTextInsets()
	state.lastCaret, state.lastWidth, state.lastLeft, state.lastRight = caret, width, left, right

	--Word wrapping in multi-line boxes isn't worked out; right-click still finds the word by caret.
	local canDraw = #state.misspelled > 0 and text ~= nil and caret ~= nil
		and not (editbox.IsMultiLine and editbox:IsMultiLine())
	local visibleWidth = canDraw and (width - left - right) or 0

	if visibleWidth > 0 then
		local fontSize = ApplyFont(editbox, state)
		local textWidth = TextWidth(state, text)
		local caretX = TextWidth(state, string_sub(text, 1, caret))
		state.scroll = Misspelled.ComputeScroll(state.scroll, caretX, textWidth, visibleWidth)

		--Single line text is centered vertically between the top and bottom insets.
		local lineY = (bottom - top) / 2 - fontSize / 2 - 1

		for _, entry in ipairs(state.misspelled) do
			local wordEndX = TextWidth(state, string_sub(text, 1, entry.EndPos))
			local wordStartX = wordEndX - StringWidth(state.measure, entry.Word)
			local x1 = left + math_max(wordStartX - state.scroll, 0)
			local x2 = left + math_min(wordEndX - state.scroll, visibleWidth)
			if x2 - x1 >= 1 then
				shown = shown + 1
				local line = state.lines[shown]
				if line == nil then
					line = state.overlay:CreateTexture(nil, "OVERLAY")
					line:SetColorTexture(UNDERLINE_COLOR[1], UNDERLINE_COLOR[2], UNDERLINE_COLOR[3], UNDERLINE_COLOR[4])
					state.lines[shown] = line
				end
				line:ClearAllPoints()
				line:SetPoint("TOPLEFT", state.overlay, "LEFT", x1, lineY)
				line:SetSize(x2 - x1, UNDERLINE_THICKNESS)
				line:Show()
				segments[shown] = {entry = entry, x1 = x1, x2 = x2}
			end
		end
	end

	for i = shown + 1, #state.lines do
		state.lines[i]:Hide()
	end
end

--Returns the misspelled word entry under the mouse, or nil.
function Misspelled:GetMisspelledWordAtMouse(editbox, state)
	if #state.segments > 0 then
		local boxLeft = editbox:GetLeft()
		local scale = editbox:GetEffectiveScale()
		if boxLeft and scale and scale > 0 then
			local mouseX = GetCursorPosition() / scale - boxLeft
			for _, segment in ipairs(state.segments) do
				if mouseX >= segment.x1 - 2 and mouseX <= segment.x2 + 2 then
					return segment.entry
				end
			end
		end
		return nil
	end

	--No drawn positions to go by: a click also moves the caret, so use that.
	local caret = editbox:GetCursorPosition()
	if issecretvalue(caret) then return nil end
	for _, entry in ipairs(state.misspelled) do
		if caret >= entry.StartPos - 1 and caret <= entry.EndPos then
			return entry
		end
	end
	return nil
end


-------------------------------------------------------------------------
--
-- Routines for the right click misspelled suggestions popup.
--
-------------------------------------------------------------------------

--True while Blizzard restricts addons, or is likely to block a chat message that addon code
--touched: combat, boss encounters, Mythic+, PvP matches and chat messaging lockdown.
function Misspelled:IsChatEditRestricted()
	if InCombatLockdown and InCombatLockdown() then return true end

	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		return true
	end

	local restrictedActions = C_RestrictedActions
	if restrictedActions and restrictedActions.IsAddOnRestrictionActive
		and Enum and type(Enum.AddOnRestrictionType) == "table" then
		for _, restrictionType in pairs(Enum.AddOnRestrictionType) do
			if restrictedActions.IsAddOnRestrictionActive(restrictionType) then
				return true
			end
		end
	end

	--Be conservative in instanced group content (LFR, LFD, battlegrounds, arenas, keystones),
	--where chat is restricted as soon as the group forms.
	if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		return true
	end
	if IsInInstance then
		local _, instanceType = IsInInstance()
		if instanceType == "raid" or instanceType == "pvp" or instanceType == "arena" then
			return true
		end
	end
	if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive() then
		return true
	end

	return false
end

--True when picking a suggestion may change the text in this edit box right now. Blizzard's
--chat edit boxes are never changed while addons are restricted: the message would be blocked.
function Misspelled:CanReplaceWords(editbox)
	return not (BlizzardChatEditBoxes[editbox] and self:IsChatEditRestricted())
end

--Builds the entries of the suggestions popup.
function Misspelled:BuildSuggestionsMenu(editbox, entry)
	local word = entry.Word
	local cached = WordCache[word]

	--Suggestions are looked up the first time someone right-clicks the word.
	if cached.Suggestions == nil then
		cached.Suggestions = WordDict:Suggest(word) or {}
	end

	--Suggestions stay listed, so the spelling can still be read, but are greyed out whenever
	--they can't be used. Checked again while the menu is open and when one is clicked.
	local function CanReplace()
		return Misspelled:CanReplaceWords(editbox)
	end

	local items = {}
	items[#items + 1] = {text = L["Suggestions for:"] .. " " .. word, isTitle = true}
	if not CanReplace() then
		items[#items + 1] = {text = L["Fixing words is paused during combat and encounters"], isTitle = true}
	end

	for _, suggestion in ipairs(cached.Suggestions) do
		local suggestedWord = suggestion.Word
		local label = suggestedWord
		--If this suggestion is either a guild member or friend append a note.
		if self:IsGuildMember(suggestedWord) then
			label = label .. " " .. L["(Guild)"]
		elseif self:IsFriend(suggestedWord) then
			label = label .. " " .. L["(Friend)"]
		end
		items[#items + 1] = {text = label, enabled = CanReplace, func = function()
			Misspelled:ReplaceWord(editbox, entry, suggestedWord)
		end}
	end

	items[#items + 1] = {isDivider = true}
	items[#items + 1] = {text = L["Ignore All"], func = function() Misspelled:IgnoreWord(word) end}
	items[#items + 1] = {text = L["Add to Dictionary"], func = function() Misspelled:AddToUserDict(word) end}
	items[#items + 1] = {text = L["Cancel"], func = function() end}
	return items
end

--[[
The suggestions popup is built only from Misspelled's own frames. Blizzard's menus (MenuUtil,
and UIDropDownMenu before it) share one pool of menu frames between every menu. A menu opened
by addon code creates pooled frames under taint, and when the unit frame's right-click menu
reuses them, its protected actions are blocked: setting a raid target marker (SetRaidTarget)
failed with "Misspelled has been blocked from an action only available to the Blizzard UI".
--]]
local POPUP_PADDING = 8
local POPUP_ROW_HEIGHT = 18
local POPUP_DIVIDER_HEIGHT = 9
local POPUP_MIN_WIDTH = 140

local Popup

local function PopupRow_OnClick(row)
	local item = row.item
	Popup:Hide()
	if item and item.func and (item.enabled == nil or item.enabled()) then
		item.func()
	end
end

local function Popup_OnEvent(popup, event)
	if event == "GLOBAL_MOUSE_DOWN" then
		--Clicking anywhere else closes it, like Blizzard's menus.
		if not popup:IsMouseOver() then
			popup:Hide()
		end
	else
		--Combat or an addon restriction started or ended: grey suggestions out, or back in.
		--Restriction state isn't reported until ADDON_RESTRICTION_STATE_CHANGED has been dispatched.
		C_Timer.After(0, function() Misspelled:RefreshPopup() end)
	end
end

local function Popup_OnShow(popup)
	popup:RegisterEvent("GLOBAL_MOUSE_DOWN")
	popup:RegisterEvent("PLAYER_REGEN_DISABLED")
	popup:RegisterEvent("PLAYER_REGEN_ENABLED")
	if C_RestrictedActions then
		popup:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
	end
end

local function Popup_OnHide(popup)
	popup:UnregisterAllEvents()
	popup.items = nil
	popup.editbox = nil
end

local function CreatePopup()
	local popup = CreateFrame("Frame", "MisspelledSuggestionsPopup", UIParent)
	popup:SetFrameStrata("FULLSCREEN_DIALOG")
	popup:SetToplevel(true)
	popup:SetClampedToScreen(true)
	popup:EnableMouse(true)
	popup:Hide()

	local border = popup:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0.45, 0.45, 0.45, 1)
	local background = popup:CreateTexture(nil, "BORDER")
	background:SetPoint("TOPLEFT", 1, -1)
	background:SetPoint("BOTTOMRIGHT", -1, 1)
	background:SetColorTexture(0.05, 0.05, 0.05, 0.95)

	popup.rows = {}
	popup:SetScript("OnShow", Popup_OnShow)
	popup:SetScript("OnHide", Popup_OnHide)
	popup:SetScript("OnEvent", Popup_OnEvent)
	return popup
end

local function AcquirePopupRow(popup, index)
	local row = popup.rows[index]
	if row == nil then
		row = CreateFrame("Button", nil, popup)
		row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight") -- SetText fails without a font
		row.text:SetPoint("LEFT", 4, 0)
		row.text:SetJustifyH("LEFT")
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.15)
		row.line = row:CreateTexture(nil, "ARTWORK")
		row.line:SetPoint("LEFT", 4, 0)
		row.line:SetPoint("RIGHT", -4, 0)
		row.line:SetHeight(1)
		row.line:SetColorTexture(0.45, 0.45, 0.45, 1)
		row:SetScript("OnClick", PopupRow_OnClick)
		popup.rows[index] = row
	end
	return row
end

--Lays out the popup's rows, and greys out the ones that can't be used right now.
function Misspelled:RefreshPopup()
	local popup = Popup
	if popup == nil or popup.items == nil then return end

	local y = -POPUP_PADDING
	local width = POPUP_MIN_WIDTH
	for i, item in ipairs(popup.items) do
		local row = AcquirePopupRow(popup, i)
		row.item = item
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", popup, "TOPLEFT", POPUP_PADDING, y)
		row:SetPoint("RIGHT", popup, "RIGHT", -POPUP_PADDING, 0)
		if item.isDivider then
			row:SetHeight(POPUP_DIVIDER_HEIGHT)
			row.text:SetText("")
			row.line:Show()
			row:SetEnabled(false)
		else
			local enabled = not item.isTitle and (item.enabled == nil or item.enabled())
			row:SetHeight(POPUP_ROW_HEIGHT)
			row.line:Hide()
			row.text:SetFontObject(item.isTitle and GameFontNormal or (enabled and GameFontHighlight or GameFontDisable))
			row.text:SetText(item.text)
			row:SetEnabled(enabled)
			width = math_max(width, row.text:GetStringWidth() + 2 * POPUP_PADDING + 8)
		end
		row:Show()
		y = y - row:GetHeight()
	end
	for i = #popup.items + 1, #popup.rows do
		popup.rows[i]:Hide()
	end
	popup:SetSize(width, POPUP_PADDING - y)
end

function Misspelled:HideSuggestions(editbox)
	if Popup and Popup:IsShown() and (editbox == nil or Popup.editbox == editbox) then
		Popup:Hide()
	end
end

function Misspelled:ShowSuggestions(editbox, entry)
	if WordCache[entry.Word] == nil then return end
	if Popup == nil then
		Popup = CreatePopup()
	end

	Popup:Hide()
	Popup.items = self:BuildSuggestionsMenu(editbox, entry)
	Popup.editbox = editbox
	self:RefreshPopup()

	--Open at the mouse, growing upward from the chat box.
	local x, y = GetCursorPosition()
	local scale = Popup:GetEffectiveScale()
	Popup:ClearAllPoints()
	Popup:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	Popup:Show()
end

--Replaces a misspelled word with the suggestion the user picked. Does nothing while the
--suggestions are greyed out (see CanReplaceWords): the text is left exactly as typed.
function Misspelled:ReplaceWord(editbox, entry, suggestion)
	if not self:CanReplaceWords(editbox) then return end

	local text = editbox:GetText()
	if text == nil or issecretvalue(text) then return end

	--Find the word again, in case the text changed while the menu was open.
	local startPos, endPos = entry.StartPos, entry.EndPos
	if string_sub(text, startPos, endPos) ~= entry.Word then
		startPos, endPos = nil, nil
		for _, w in ipairs(self:FindMisspelledWords(text)) do
			if w.Word == entry.Word then
				startPos, endPos = w.StartPos, w.EndPos
				break
			end
		end
		if startPos == nil then return end
	end

	--If the misspelled word was capitalized, capitalize the replacement.
	local firstChar = string_sub(entry.Word, 1, 1)
	if firstChar == string_upper(firstChar) then
		suggestion = string_upper(string_sub(suggestion, 1, 1)) .. string_sub(suggestion, 2)
	end

	local newText = string_sub(text, 1, startPos - 1) .. suggestion .. string_sub(text, endPos + 1)

	--Move the cursor to the end of the new word, past a following space.
	local newCursorPos = startPos - 1 + #suggestion
	if string_sub(newText, newCursorPos + 1, newCursorPos + 1) == " " then
		newCursorPos = newCursorPos + 1
	end

	editbox:SetText(newText)
	editbox:SetCursorPosition(newCursorPos)
end

function Misspelled:IgnoreWord(word)
	--Add this word to the WordCache so it will be ignored as misspelled until you reload
	local cached = WordCache[word]
	if cached == nil then
		cached = {}
		WordCache[word] = cached
		WordCacheCount = WordCacheCount + 1
	end
	cached.Correct = true
	cached.Suggestions = {}
	self:RecheckAll()
end
-----------------------------------------------------
-- End: Right click Suggestions popup
-----------------------------------------------------



-------------------------------------------------------------------------
--
-- Routines for dealing with the user dictionary
--
-------------------------------------------------------------------------

--Returns the "sounds like" code the loaded dictionary uses for suggestions.
local function SoundsLikeCode(word)
	if WordDict.soundslike == WordDict.Const.SoundslikeAlgorithms.PHONETIC then
		return WordDict:PhoneticCode(word)
	elseif WordDict.soundslike == WordDict.Const.SoundslikeAlgorithms.GENERIC then
		return WordDict:GenericSoundsLike(word)
	end
	return ""
end

--Load the words saved in the Users dictionary into the baseWords table.
--In r18 we changed the in memory format used to store the baseWords, affixCode and PhoneticCode,
--Saved a ton of memory not using a sub-table per baseWord.
--If necessary convert the user dictionary storage to match the newer format.
function Misspelled:LoadUserDict()
	if Misspelled_DB == nil then
		Misspelled_DB = {UserDict = {}}
	end

	local affixKeys, pCode
	if Misspelled_DB.UserDict ~= nil then
		for k, v in pairs(Misspelled_DB.UserDict) do
			--If needed convert the user dictionary format to the, post r18 format.
			if type(v) == "table" then
				affixKeys = v[1]
				pCode = v[2]
				if affixKeys == nil then affixKeys = "" end
				if pCode == nil then pCode = "" end
				v = affixKeys .. "/" .. pCode
				Misspelled_DB.UserDict[k] = v
			end

			if WordDict.baseWords[k] == nil then
				WordDict.baseWords[k] = v
			end
		end
	end
end


--Add a new word to the users dictionary, and the currently loaded baseWords table.
--Store both the word and it's phonetic code.
function Misspelled:AddToUserDict(word)
	if word == nil then return end
	if #word == 0 then return end

	if Misspelled_DB.UserDict == nil then
		Misspelled_DB.UserDict = {}
	end
	--Add the new word to the UserDict saved variable
	local code = "/" .. SoundsLikeCode(word)
	Misspelled_DB.UserDict[word] = code

	--And add it to the currently loaded dictionary
	WordDict.baseWords[word] = code

	--Fixup the WordCache
	WordCache[word] = {Correct = true, Suggestions = {}}
	self:RecheckAll()
end


local Misspelled_Words_To_Delete = {}

function Misspelled:EditUserDict()
	local f = AceGUI:Create("Window")
	f:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)
	f:SetLayout("Flow")
	f:SetWidth(300)
	f:SetHeight(490)
	f:SetTitle("Misspelled - " .. L["User Dictionary"])
	f:ReleaseChildren()
	f:PauseLayout()

	Misspelled_Words_To_Delete = {}

	local i = AceGUI:Create("InlineGroup")
	i:SetLayout("List")
	i:SetFullWidth(true)
	i:SetHeight(370)
	i:SetTitle(L["Select words to remove:"])
	f:AddChild(i)

	local scroll = AceGUI:Create("ScrollFrame")
	scroll:SetLayout("Flow")
	scroll:SetFullWidth(true)
	scroll:SetHeight(370)
	i:AddChild(scroll)

	local delButton = AceGUI:Create("Button")
	delButton:SetText("Delete")
	delButton:SetCallback("OnClick", function()
		PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		--Delete selected words from the user dictionary
		Misspelled:print("Misspelled: " .. L["Removing the following words from the user dictionary"])
		for k in pairs(Misspelled_Words_To_Delete) do
			Misspelled:print(" - " .. k)
			Misspelled_DB.UserDict[k] = nil

			--Remove the word from the, in memory dictionary
			WordDict.baseWords[k] = nil
		end

		--Clear the word cache
		WordCache = {}
		WordCacheCount = 0
		Misspelled:RecheckAll()

		delButton:SetDisabled(true)
		f:Hide()
	end)
	delButton:SetDisabled(true)

	f:AddChild(delButton)

	--Check if the UserDict exist.  If not initialize it, creating a blank user dictionary.
	if Misspelled_DB == nil then
		Misspelled_DB = {UserDict = {}}
	end
	if Misspelled_DB.UserDict == nil then
		Misspelled_DB.UserDict = {}
	end

	for k in pairs(Misspelled_DB.UserDict) do
		local x = AceGUI:Create("InteractiveLabel")
		x:SetHighlight(.3, .3, .3, .5)
		x:SetFullWidth(true)
		x:SetText(k)

		x:SetCallback("OnClick", function(widget)
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
			--Check if item is selected or not
			local _, _, b = widget.label:GetTextColor()

			if b == 0 then
				--Selected, process an unselect
				widget:SetColor(1, 1, 1, 1)
				Misspelled_Words_To_Delete[widget.label:GetText()] = nil
				delButton:SetDisabled(next(Misspelled_Words_To_Delete) == nil)
			else	--Unselected, process a select
				widget:SetColor(1, .2, 0, 1)
				Misspelled_Words_To_Delete[widget.label:GetText()] = 1
				delButton:SetDisabled(false)
			end
		end)

		scroll:AddChild(x)
	end

	f:ResumeLayout()
	f:DoLayout()
	f:Show()
end

-------------------------------------------------------------------------
-- End: Routines for dealing with the user dictionary
-------------------------------------------------------------------------



-------------------------------------------------------------------------
--
-- Load Guild and Friend Roster Routine
--
-------------------------------------------------------------------------

--Adds a player's name to the loaded dictionary as valid words. Names can carry a realm, or on
--WoW Forever a surname ("Name-Realm", "First-Surname" or "First Surname"), so each part is added.
--Returns true if a new word was added.
local function AddPlayerName(fullName, names)
	if issecretvalue(fullName) or type(fullName) ~= "string" then return false end

	local added = false
	for part in string_gmatch(fullName, "[^%-%s]+") do
		names[part] = true
		if WordDict.baseWords[part] == nil and not WordDict:Contains(part) then
			WordDict.baseWords[part] = "/" .. SoundsLikeCode(part)
			added = true
		end
	end
	return added
end

--Names checked before they were added may be cached as misspelled.
local function NamesAdded()
	WordCache = {}
	WordCacheCount = 0
	Misspelled:RecheckAll()
end

function Misspelled:LoadFriends()
	if not (C_FriendList and C_FriendList.GetNumFriends) then return end

	local numFriends = C_FriendList.GetNumFriends()
	if numFriends == nil or issecretvalue(numFriends) then return end

	local added = false
	for i = 1, numFriends do
		local friendInfo = C_FriendList.GetFriendInfoByIndex(i)
		if friendInfo and AddPlayerName(friendInfo.name, FriendNames) then
			added = true
		end
	end
	if added then
		NamesAdded()
	end
end

function Misspelled:LoadGuildRoster()
	if not (IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return end

	local numGuildMembers = GetNumGuildMembers()
	if numGuildMembers == nil or issecretvalue(numGuildMembers) or numGuildMembers == 0 then return end

	local added = false
	for i = 1, numGuildMembers do
		if AddPlayerName((GetGuildRosterInfo(i)), GuildNames) then
			added = true
		end
	end
	if added then
		NamesAdded()
	end

	--The roster is only loaded once per session.
	self:UnregisterEvent("GUILD_ROSTER_UPDATE")
end

function Misspelled:IsFriend(name)
	return FriendNames[name] == true
end

function Misspelled:IsGuildMember(name)
	return GuildNames[name] == true
end

-------------------------------------------------------------------------
-- End: Load Guild and Friend Roster Routine
-------------------------------------------------------------------------

--[[ Interface Options Window ]]--
local DICTIONARIES = {"deDE", "enGB", "enUS", "esES", "frFR", "itIT", "ruRU"}

local function CreateCheckbox(parent, name, label, x, y)
	local checkbox = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	checkbox:SetSize(26, 26)
	checkbox:SetPoint("TOPLEFT", x, y)
	local text = checkbox.Text or checkbox.text or _G[name .. "Text"]
	if text then
		text:SetFontObject("GameFontHighlight")
		text:SetText(label)
	end
	return checkbox
end

function Misspelled:CreateInterfaceOptions()
	local cfgFrame = CreateFrame("Frame", nil, UIParent)
	cfgFrame.name = "Misspelled"

	local cfgFrameHeader = cfgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	cfgFrameHeader:SetPoint("TOPLEFT", 15, -15)
	cfgFrameHeader:SetText("Misspelled " .. tostring(self.Version))

	local dictCheckboxes = {}

	local function UpdateDictionaryCheckboxes()
		for dict, checkbox in pairs(dictCheckboxes) do
			checkbox:SetChecked(Misspelled_DB.LoadDictionary == dict)
			checkbox:SetEnabled(Misspelled_DB.AutoSelectDictionary ~= true)
		end
	end

	local cfgAutoSelectDict = CreateCheckbox(cfgFrame, "Misspelled_cfgAutoSelectDict", L["Auto Select Dictionary to Load"], 20, -40)
	cfgAutoSelectDict:SetChecked(Misspelled_DB.AutoSelectDictionary)
	cfgAutoSelectDict:SetScript("OnClick", function(checkbox)
		PlaySound(checkbox:GetChecked() and 856 or 857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON / OFF
		Misspelled_DB.AutoSelectDictionary = checkbox:GetChecked() and true or false
		if Misspelled_DB.LoadDictionary == nil or #Misspelled_DB.LoadDictionary == 0 then
			Misspelled_DB.LoadDictionary = "enUS"
		end
		UpdateDictionaryCheckboxes()
	end)

	--One dictionary can be picked, so these behave like radio buttons.
	for i, dict in ipairs(DICTIONARIES) do
		local checkbox = CreateCheckbox(cfgFrame, "Misspelled_cfgDict" .. dict, dict, 40, -40 - 24 * i)
		checkbox:SetScript("OnClick", function()
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
			Misspelled_DB.LoadDictionary = dict
			UpdateDictionaryCheckboxes()
		end)
		dictCheckboxes[dict] = checkbox
	end
	UpdateDictionaryCheckboxes()

	local cfgFrameReloadTip = cfgFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	cfgFrameReloadTip:SetPoint("TOPLEFT", 20, -52 - 24 * #DICTIONARIES - 20)
	cfgFrameReloadTip:SetText(L["Note: reload the game UI to load a different selected dictionary"])

	--Edit User Dictionary Button
	local cfgEditUserDict = CreateFrame("Button", "Misspelled_cfgEditUserDict", cfgFrame, "UIPanelButtonTemplate")
	cfgEditUserDict:SetPoint("TOPLEFT", cfgFrameReloadTip, "BOTTOMLEFT", 0, -16)
	cfgEditUserDict:SetText(L["Edit User Dictionary..."])
	cfgEditUserDict:SetSize(200, 24)
	cfgEditUserDict:SetScript("OnClick", function()
		Misspelled:EditUserDict()
	end)

	--Add options frame to the list of in-game addon options
	if Settings and Settings.RegisterCanvasLayoutCategory then -- Wow 11+, Midnight, WoW Forever
		local category = Settings.RegisterCanvasLayoutCategory(cfgFrame, cfgFrame.name)
		Settings.RegisterAddOnCategory(category)
		self.settingsCategory = category
	elseif InterfaceOptions_AddCategory then -- For Wow clients < v11
		InterfaceOptions_AddCategory(cfgFrame)
	end
end


-------------------------------------------------------------------------
--
-- Utility Routines
--
-------------------------------------------------------------------------

function Misspelled:print(...)
	local chatFrame = SELECTED_DOCK_FRAME or DEFAULT_CHAT_FRAME
	if chatFrame then
		chatFrame:AddMessage(...)
	end
end

-------------------------------------------------------------------------
-- End: Utility Routines
-------------------------------------------------------------------------
