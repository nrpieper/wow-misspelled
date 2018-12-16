--[[--------------------------------------------------------------------------
  Developed by Nathan Pieper - nrpieper (@) gmail (dot) com
  Misspelled is an interactive chat text spell checker for World of Warcraft

  This code freely distributed for your use in any GPL compliant project.
  Portions of this code are covered by the Gnu Plublic License (GPL)
  Dictionaries use the OpenOffice/HunSpell/ASpell dictionary format
  (http://wiki.services.openoffice.org/wiki/Dictionaries)
  Phonetic cache information created via the NetSpell dictionary util.
  References & Credits:
  Paul Welter & NetSpell: http://www.loresoft.com/projects/netspell
  Metaphone Algorithm http://aspell.net/metaphone/
  Edit Distance Algorithm http://en.wikipedia.org/wiki/Levenshtein_distance

--------------------------------------------------------------------------]]--


--[[
Challenges:


Issue #1
(http://www.wowwiki.com/ItemLink)
Color tags can be destroyed or mangled as you perform edit near the start
and end of the color tag.

If you press delete with the cursor positioned, just before, a color tag,
the start of the tag (|cffffffff) and the next character are removed.  The
closing color tag (|r) is left at the end.

If you press backspace with the cursor positioned just past the (|r) end
of a color tag, the (|r) is removed along with the character just before it.

If you press delete with the cursor positioned, just before the last char,
in a color tagged string, the character and the closing (|r) are both removed.

If you press backspace with the cursor positioned, just after the first char,
in a color tagged string, the first char and the beginning color tag are both removed.

In the case of colored item links, Wow just deletes the entire item, if you
hit a delete or backspace.

Solution:
First parse the line to flag any valid item links or textures so they don't get
destroyed by the next step.
Then if there are any remaining start or end color tag, remove them.

Issue #2
The Chat Edit box's edit cursor position is relative to characters that don't display in the
chat edit text, i.e. item link tags, color tags, and texture tags.
When we add, or remove, a color tag, to highlight a misspelled word,  we should adjust the
cursor position so it acts natural.
Note: An OnCursorChanged event doesn't exist or doesn't fire for the ChatEditBox.

Solution:
Methods that insert or delete text from the ChatEditBox need to properly adjust the cursor
position as needed when, visible or hidden, characters are insertted or deletted to the left of the cursor.

Two techniques could be used.
#1: Track the number of, printable and non-printable characters inserted or deleted
    to the left of the cursor, and adjust the cursor position to compensate.

#2: Insert a tracking char byte (example: \1), at the cursor position.  After making
	inserts and deletes, find the tracking char byte, remove it and reposition the cursor
    at its location.

I have implemented technique #1.

Issue #3 WIM Integration
Wim allows multiple chat windows at once.  So we need to track WordLocations per editbox.
Wim breaks long chat messages into multiple messages.
Wim has a EditBox right click handler to insert emoticons and previous chat messages.
WIM sends chat messages using ChatThrottleLib:SendChatMessage.  This can hot SendChatMessage before Missplled and bypasses the step that cleans the highlighting.
(10/10/2009) Udpated hooks, from WIM, will be provided via WIM.RegisterPreSendFilterText(func()), to remove the need to manually hook ChatThrottleLib

User Dictionary Editor Added
(12/6/2009) - Used AceGUI to add the ability to remove words from the user dictionary.

(1/12/2010) - Added enGB UK English dictionary.

(5/12/2010) - Added support for PTR Patch 3.5.  Multiple ChatEditBoxes get created.  Hook into the activate routine.

(5/23/2010) - Fixed enGB dictionay load issue.

(6/24/2010) - Addedd itIT Italian dictionary

(7/22/2010) - The Addon Gryphonheart Items (GHI) begins it's item color tags with a (|C) capitol c.  I added that possability to the chat text parsing.

(9/14/2010) - Client 4 has some issues with trying to set the owner of the popmenu items.  Looks like it's not needed.
--]]--

local _G = _G

Misspelled = LibStub("AceAddon-3.0"):NewAddon("Misspelled", "AceEvent-3.0", "AceHook-3.0")

local Misspelled = _G.Misspelled

Misspelled.Version = "Misspelled v1.6.3"

local AceGUI = LibStub("AceGUI-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("Misspelled", true)

local table_insert = table.insert
local string_byte = string.byte
local string_find = string.find
local string_gsub = string.gsub
local string_len = string.len
local string_lower = string.lower
local string_match = string.match
local string_rep = string.rep
local string_sub = string.sub
local string_upper = string.upper
local tostring = tostring
local pairs = pairs
local ipairs = ipairs

--local SPELLED_WRONG_HIGHLIGHT =   "|cffff91c8" --The color misspelled words will get changed into.
--local SPELLED_WRONG_HIGHLIGHT =   "|cffdea1d3" --The color misspelled words will get changed into.
--local SPELLED_WRONG_HIGHLIGHT =   "|cfffefe80" --The color misspelled words will get changed into.
local SPELLED_WRONG_HIGHLIGHT =   "|cff7dc6fb" --The color misspelled words will get changed into. (Medium-Cyan-ish)

local WordCache = {}           --Stores a cache of every word checked, along with the suggestions for words misspelled
local WordCacheCount = 0       --Counter used to track when we should clean the WordCache table to save memory
local WordCacheCountMax = 7000 --Number of entries tha can live in the WordCache before we clean the cache
local WordLocations = {}       --Lookup table used by multiple functions to determin where each work starts and ends
							   --There will be a subtable for each EditBox:GetName() so we can store multiple sets of info at once.
local SkipOnTextChanged = false -- use to avoid OnTextChanged event firing after spell checking highlights chat text.
local RightClickedWord = nil   --The current word under the CursorPosition that was right-clicked
local RightClickedWordStartPos --Where that word starts
local RightClickedWordStartPos --and where that word ends
local RightClickedEditBox      --and what EditBox was right clicked
local OldLineLength            --Tracks the previous length of the ChatEditBox.text
local GuildRosterCalled = false

local Misspelled_Saved_CTL_SendChatMessage
local Misspelled_CTL_hookedversion=0

function Misspelled:OnInitialize()
	if Misspelled_DB == nil then
		Misspelled_DB = {}
	end

	--Check if the user has choosen to override the auto dictionary selection
	if Misspelled_DB.LoadDictionary == nil then
		Misspelled_DB.LoadDictionary = "enUS"
	end

	if Misspelled_DB.AutoSelectDictionary == nil then
		Misspelled_DB.AutoSelectDictionary = true
	end

	local dict = "Auto"
	if  Misspelled_DB.AutoSelectDictionary == true then
		dict = "Auto"
	else
		dict = Misspelled_DB.LoadDictionary or "Auto"
	end

	--Load the Dictionary
	local dictLoaded
	if dict == "Auto" then
		dictLoaded = WordDict:Init()
	else
		dictLoaded = WordDict:Init(dict)
	end

	Misspelled:print("Misspelled: " .. L["Dictionary Loaded"] .." - " .. dictLoaded)

	--Load user dict
	Misspelled:LoadUserDict()
	Misspelled:print("Misspelled: " .. L["User Dictionary Loaded"])

	-- Build Interface Options window
	self:CreateInterfaceOptions()

	--Watch for WIM to Load, then integrate
	Misspelled:RegisterEvent("ADDON_LOADED")

	--Guild members and Friends are valid words.
	--Wait for the GUILD_ROSTER_UPDATE event to load
	--the guild members & friends into the dictionary as valid words.

	--Register the GUILD_ROSTER_UPDATE event, so we know when we can load the
	--Guild member names into the database
	Misspelled:RegisterEvent("GUILD_ROSTER_UPDATE")


	--GuildRoster can only be called every so often.
	--If another addon triggered it first, we might miss notification.
	--Moved to OnTextChanged
	--GuildRoster()

	--Patch 3.5 has multiple ChatEditBoxes.  We need to hook in differently.
	if ChatEdit_ActivateChat ~= nil then
		Misspelled:RawHook("ChatEdit_ActivateChat", true)
	else
		Misspelled:WireUpEditBox(ChatFrameEditBox)
	end


	-- hooks for removing any misspelled word highlighting in the text before the chat message is sent
	-- The Wow client will disconnect if you attempt to send a color tags in a chat message.
	Misspelled:RawHook("SendChatMessage", true)


end


function Misspelled:WireUpEditBox(editbox)
	Misspelled:SecureHookScript(editbox, "OnEscapePressed", Misspelled.EditBox_OnEscapePressed)
	Misspelled:SecureHookScript(editbox, "OnEnterPressed", Misspelled.EditBox_OnEnterPressed)
	Misspelled:SecureHookScript(editbox, "OnTextChanged", Misspelled.EditBox_OnTextChanged)
	Misspelled:HookScript(editbox, "OnMouseUp", Misspelled.EditBox_OnMouseUp)  -- Used to hook mouse right-clicks
end

function Misspelled:GUILD_ROSTER_UPDATE()
	Misspelled:LoadGuildAndFriendRoster()
end

function Misspelled:ADDON_LOADED(event, addonName)
	if event == "ADDON_LOADED" and addonName == "WIM" then
		WIM.RegisterWidgetTrigger("msg_box", "whisper,chat,w2w", "OnEscapePressed", Misspelled.EditBox_OnEscapePressed)
		WIM.RegisterWidgetTrigger("msg_box", "whisper,chat,w2w", "OnEnterPressed", Misspelled.EditBox_OnEnterPressed)
		WIM.RegisterWidgetTrigger("msg_box", "whisper,chat,w2w", "OnTextChanged", Misspelled.EditBox_OnTextChanged)
		--WIM.RegisterWidgetTrigger("msg_box", "whisper,chat,w2w", "OnMouseUp", Misspelled.EditBox_OnMouseUp)


		--Before a chat message is sent, remove any highlighting that Misspelled might have added.
		--The Wow client will disconnect if you attempt to send a colored chat message.

		--If available use the WIM API: Wim.RegisterPreSendFilterText

		--WIM sends its chat messages via the API ChatThrottleLib,
		--ChatThrottleLib hooks the default SendChatMessage api, many times, before Misspelled can.
		--ChatThrottleLib used in many addonds, that potentially load before Misspelled.
		--So we have to hook ChatThrottleLib just to be safe.


		if(WIM.RegisterPreSendFilterText) then -- avoid error if WIM not up to date.
			WIM.RegisterPreSendFilterText(function(text)
											return Misspelled:RemoveHighlighting(text)
										  end)
		else
			if(ChatThrottleLib and Misspelled_CTL_hookedversion < ChatThrottleLib.version) then
				Misspelled_Saved_CTL_SendChatMessage=ChatThrottleLib.SendChatMessage

				function ChatThrottleLib:SendChatMessage(prio, prefix, text, ...)
					text = Misspelled:RemoveHighlighting(text)
					--print("Misspelled Hooked ChatThrottleLib_SendChatMessaged called")
					return Misspelled_Saved_CTL_SendChatMessage(ChatThrottleLib, prio, prefix, text, ...)
				end
				Misspelled_CTL_hookedversion=ChatThrottleLib.version
			end
		end
	end
end

--Patch 3.5 Hook ChatFrame.lua ChatEdit_ActivaeChat(editBox)
function Misspelled:ChatEdit_ActivateChat(editBox)
	--Make sure this editbox is hooked
	--print("EditBox to hook: " .. editBox:GetName())
	local hooked, hookHandler  = Misspelled:IsHooked(editBox, "OnTextChanged")
	if  hooked == false then
		Misspelled:WireUpEditBox(editBox)
	end

	self.hooks["ChatEdit_ActivateChat"](editBox)
end

--Before a chat message is sent, remove any highlighting that Misspelled might have added.
--The Wow client will disconnect if you attempt to send a colored chat message.
function Misspelled:SendChatMessage(message, type, language, channel, ...)
	local newText = Misspelled:RemoveHighlighting(message)

	self.hooks["SendChatMessage"](newText, type, language, channel, ...);
end

--Possible changes:
--A single new character was inserted at the end of the line (line length grew by 1)
--	  If this char is a word seperator, then spell check the line
--
--Any other change in the line, requires we recheck the entire line.
--More than a single character was pasted or linked into the line.
--	remove any highlighting and recheck the entire line.
--
--A single character was removed from the line
function Misspelled.EditBox_OnTextChanged(editbox)
	if SkipOnTextChanged == true then
		SkipOnTextChanged = false
		return
	end

	--print("Editbox name:", editbox:GetName())

	--Load the guild roster if needed
	if GuildRosterCalled == false then
		if IsInGuild() == 1 then
			GuildRoster()
		else
			Misspelled:LoadGuildAndFriendRoster()
		end
		GuildRosterCalled = true
	end


	local text = editbox:GetText()
	local pos = editbox:GetCursorPosition()

	--print ("TextChaged:", editbox:GetCursorPosition(), string.gsub(editbox:GetText(), "\124", "\124\124"))

	local newLineLength = #text

	--Check if we should clear the WordCache table to save memory, if it's gotten very large
	if newLineLength == 0 then
		if WordCacheCount > WordCacheCountMax then
			WordCache = {}
			WordCacheCount = 0
		end
	end


	--if the first char is a /, incidating some command, do no spellcheck.
	if (string_sub(text, 1, 1) == "/" ) then
		local newText = Misspelled:RemoveHighlighting(text)
		if text ~= newText then
			editbox:SetText(newText)
			if pos == 1 or pos== 0  then
			  editbox:SetCursorPosition(pos)
			end
			OldLineLength = #text
		end

		RightClickedWord = nil
		WordLocations[editbox:GetName()] = {}
		return
	end


	--If we currently just added one new char to the end of the line, see if it's a word boundry char
	--CursorPosition (pos) must be at the end of the line, and the line size must have had grown by
	--one character.
	if pos == #text and newLineLength -1 == OldLineLength then
		local lastChar = string_sub(text, -1, -1)
		if string_match(lastChar, "[ \(\)\;,\.!\?:\"]") ~= nil then
			Misspelled:SpellCheckChat(editbox)
		end
	elseif pos ~= #text then
		----We must be making some other kind of edit someplace other than at the end of the line.
		----Recheck the entire line
		Misspelled:SpellCheckChat(editbox)
	end

	--Save the new line length for use with the next round of OnTextChanged processing.
	OldLineLength = #editbox:GetText()
end

function Misspelled.EditBox_OnEscapePressed(editbox)
	RightClickedWord = nil
	WordLocations[editbox:GetName()] = {}
end

function Misspelled.EditBox_OnEnterPressed(editbox)
	RightClickedWord = nil
	WordLocations[editbox:GetName()] = {}

	--before message is sent, remove and misspelled highlighting
	local newText = Misspelled:RemoveHighlighting(editbox:GetText())
	WordLocations[editbox:GetName()] = {}
	editbox:SetText(newText)
end


--Return a string where misspelled words are highlighted
--If this string is a slash command "/", don't perform any highlighting
--We should keep track of the current edit cursor position,
--so we can report it's new position after highlighting.
function Misspelled:SpellCheckChat(editbox)
	local text = editbox:GetText()

	if #text < 2 then return end

	--Ensure we have hooked the MouseUp event
	--Should fix Chatter changing the OnMouseUp script to nil.  Bad Chatter
	local hooked, hookHandler  = Misspelled:IsHooked(editbox, "OnMouseUp")
	if  hooked == false or (hooked == true and hookHandler ~= self.OnMouseUp) then
		Misspelled:Unhook(editbox, "OnMouseUp")
		Misspelled:RawHookScript(editbox, "OnMouseUp", Misspelled.EditBox_OnMouseUp)
	end

	local newText = text

	--Watch how many characters we insert or remove from the left side of the cursor position.
	--We'll adjust it's position later to compensate for any "hidden" tags we added.
	local newCPos

	--remove any previous misspelling highlighting
	newText, newCPos = Misspelled:RemoveHighlighting(text, editbox:GetCursorPosition())

	WordLocations[editbox:GetName()] = {}

	--If this is a command, don't spellcheck or highlight
	if string_sub(text, 1, 1) == "/" then
		if newText ~= text then
			editbox:SetText(newText)
			editbox:SetCursorPosition(newCPos)
		end
	end

	--Find misspelled words & populate the WordLocations info.
	Misspelled:CheckLine(newText, editbox)

	--Use the WordLocation info to march backwords through the input text,
	--highlighting misspellings
	--tprint(WordLocations)
	local w
	for x = #WordLocations[editbox:GetName()], 1, -1 do
		w = WordLocations[editbox:GetName()][x]
		if WordCache[w.Word].Correct == false then
			--Insert highlighting
			newText = string_sub(newText, 1, w.StartPos -1) .. SPELLED_WRONG_HIGHLIGHT .. string_sub(newText, w.StartPos, w.EndPos) .. FONT_COLOR_CODE_CLOSE .. string_sub(newText, w.EndPos + 1)

			--Adjust cursor position if the cursur was to the right of the first char in the word we're highlighting.
			if newCPos >= w.EndPos then
				newCPos = newCPos + #SPELLED_WRONG_HIGHLIGHT + #FONT_COLOR_CODE_CLOSE
			elseif newCPos >= w.StartPos then
				newCPos = newCPos + #SPELLED_WRONG_HIGHLIGHT
			end
		end
	end

	--Adjust the word's WordLocation StartPos and EndPos, wherever we added highlighting.
	--The right click handler uses this position info. to detect the misspelled word that was right clicked.
	--March forward this time
	local n = 0 --NewCharsAddedCounter
	for x = 1, #WordLocations[editbox:GetName()] do
		w = WordLocations[editbox:GetName()][x]
		if WordCache[w.Word].Correct == false then
			w.StartPos = w.StartPos + n + #SPELLED_WRONG_HIGHLIGHT
			n = n + #SPELLED_WRONG_HIGHLIGHT
			w.EndPos = w.EndPos + n
			n = n + #FONT_COLOR_CODE_CLOSE
		end
	end

	if newText ~= text then
		--When we call settext, an OnSetText event will fire.
		--Execution of this even should be skipped to avoid SpellCheckChat from running twice.
		--Use a local toggle to skip this second firing
		SkipOnTextChanged = true
		editbox:SetText(newText)
		editbox:SetCursorPosition(newCPos)
	end
end



--Finds all words in the input text string, ignoring any Wow hyperlinks or textures
--Next populate the table, WordLocations, storing the following info. on each word:
--	WordLocations[x] = {["word"] = word, ["StartPos"] = pos1, ["EndPos"] = pos2}
--		x == Ordinal position of the word in the text string
--
--Next check each word to see we need to cache spell check info for the word.
--Words with numbers or words in all upper case are ignored.
--Store in the WordCache table whether the word is spell correctly, along with the
--any misspelled replacement suggestions.
--
--Trim the WordCache table if it's grown very large
function Misspelled:CheckLine(text, editbox)
	--Reset the info on where each word is located
	WordLocations[editbox:GetName()] = {}

	if text == nil then return end
	if #text == 0 then return end

	--Find if there are any links on this line, and replace them with the char: #, so they don't match as words
	--in the next phase of parsing.
	-- |[Cc].*|r
	-- |[Cc]|H.+|h.+|h|r
	-- |H.*|h
	-- |T.*|t
	-- |n newline character
	local newText = text
	newText = string_gsub(newText, "(|[Cc]%x-|H.-|h.-|h|r)", function(x) return string_rep("#", #x) end)
	newText = string_gsub(newText, "(|H.*|h)", function(x) return string_rep("#", #x) end)
	newText = string_gsub(newText, "(|T.*|t)", function(x) return string_rep("#", #x) end)
	newText = string_gsub(newText, "(|n)", function(x) return string_rep("#", #x) end)


	--March through the text, finding the words, record there start & end positions, and spell check status
	local patt = "[A-Za-z0-9_'À-ÿœæŒÆ]+"
	local pos1
	local pos2

	pos1, pos2 = string_find(newText, patt)

	local x = 0
	local word
	local correct
	while pos1 ~= nil do
		word = string_sub(newText, pos1, pos2)

		--ignore all uppercase words
		if word ~= string_upper(word) then
			--ignore words with numbers in them
			if string_match(word, "[%d]") == nil then
				x = x + 1
				WordLocations[editbox:GetName()][x] = {["Word"] = word, ["StartPos"] = pos1, ["EndPos"] = pos2}

				if WordCache[word] == nil then
					correct = false

					--Ignore words in all upper case
					if word == string_upper(word) then
						correct = true
					end

					--See if the dictionary contains the word
					if correct == false then
						correct = WordDict:Contains(word)
					end

					--Try the lower case version of the word
					if correct == false then
						correct = WordDict:Contains(string_lower(word))
					end

					--Cache the results
					WordCache[word] = {["Correct"] = correct} --, ["Suggestions"] = {}}
					WordCacheCount = WordCacheCount + 1
					--Changed to delay searching for suggestions until someone righ-clicks on a missplled word.
					--Adding UTF8 support slows the suggestion generation.
--~ 					if correct == false then
--~ 						local suggestions = {}
--~ 						suggestions = WordDict:Suggest(word)
--~ 						if #suggestions > 0 then
--~ 							WordCache[word].Suggestions = suggestions
--~ 						end
--~ 					end
				end
			end
		end

		pos1, pos2 = string_find(newText, patt, pos2+1)
	end
end



--Return a string where the highlighting has been removed from any misspelled words,
--with the goal to not distroy any Wow itemLinks or textures. (http://www.wowwiki.com/ItemLink)
--
--It's possible that a recent edit has started to distroy the color tags, either at the
--begginning or end of a highlighted misspelled word.
--Attempt to detect this and remove any dangling tags.
function Misspelled:RemoveHighlighting(text, ...)
	local newText = text

	--Track the number of characters removed from the left side of the current cursor position.
	local cPos
	if ... ~= nil then
		cPos = ...
	else
		cPos = 0
	end

	local itemLinks = {}
	local itemLinkNum = 1

	local patt, pos1, pos2
	local tokenSize
	local tempToken
	local tempText
	local charsRemoved  --Tracks the chars removed from the left of the cursor

	--Try and match Item links first.  The Addon GHI (Gryphonheart Items) colors links with a capitol C, non standard.
	patt = "|[Cc]%x+|H.-|h.-|h|r"
	pos1, pos2 = string_find(newText, patt)

	local itemLink
	while pos1 ~= nil do
		--Store the itemlink and it's relative position so it can be replaced latter
		itemLink = string_sub(newText, pos1, pos2)
		itemLinks[itemLinkNum] = itemLink

		tokenSize = #itemLink
		tempToken = "{<<" .. tostring(itemLinkNum)
		tempToken = tempToken .. string_rep(">", tokenSize - #tempToken - 1) .. "}"

		--Replace this itemlink with a temporary placeholder code
		newText = string_gsub(newText, patt, tempToken, 1)

		itemLinkNum = itemLinkNum + 1
		pos1, pos2 = string_find(newText, patt)
	end

	--Try to match, non colored Item Links
	patt = "|H.-|h"
	pos1, pos2 = string_find(newText, patt)

	while pos1 ~= nil do
		--Store the itemlink and it's relative position so it can be replaced latter
		itemLink = string_sub(newText, pos1, pos2)
		itemLinks[itemLinkNum] = itemLink

		tokenSize = #itemLink
		tempToken = "{<<" .. tostring(itemLinkNum)
		tempToken = tempToken .. string_rep(">", tokenSize - #tempToken - 1) .. "}"

		--Replace this itemlink with a temporary placeholder code
		newText = string_gsub(newText, patt, tempToken, 1)

		itemLinkNum = itemLinkNum + 1
		pos1, pos2 = string_find(newText, patt)
	end

	--Try to match and textures links.  (i.e. Raidtargets and there used when chatting with a GM)
	patt = "|T.-|t"
	pos1, pos2 = string_find(newText, patt)

	while pos1 ~= nil do
		--Store the itemlink and it's relative position so it can be replaced latter
		itemLink = string_sub(newText, pos1, pos2)
		itemLinks[itemLinkNum] = itemLink

		tokenSize = #itemLink
		tempToken = "{<<" .. tostring(itemLinkNum)
		tempToken = tempToken .. string_rep(">", tokenSize - #tempToken - 1) .. "}"

		--Replace this itemlink with a temporary placeholder code
		newText = string_gsub(newText, patt, tempToken, 1)

		itemLinkNum = itemLinkNum + 1
		pos1, pos2 = string_find(newText, patt)
	end


	--Remove the highlighting from any misspelled words where the
	--beginning and ending color tags correctly exist.
	--Adjust the cursor position as needed.
	patt = SPELLED_WRONG_HIGHLIGHT .. "(.-)|r"
	pos1, pos2 = string_find(newText, patt)
	while pos1 ~= nil do
		tempText = string_gsub(newText, patt, function(x) return x end, 1)

		if #newText - #tempText ~= 0 then
			charsRemoved = 0
			--If the cursor was to the right of the start, subtract the num of deleted chars from the cursor position
			if cPos >= pos1 then
				charsRemoved = (#newText - #tempText)
			end
			--If the cursor was to the left of the end color tag and to the right of the start, add 2
			if cPos >= pos1 and cPos < pos2 then
				charsRemoved = charsRemoved - 2
			end
			cPos = cPos - charsRemoved
		end
		newText = tempText

		pos1, pos2 = string_find(newText, patt)
	end

	--Remove any remaining orphaned beginning color tags.
	patt = "|[Cc]%x%x%x%x%x%x%x%x"
	pos1, pos2 = string_find(newText, patt)
	while pos1 ~= nil do
		tempText = string_gsub(newText, patt, "", 1)

		if #newText - #tempText ~= 0 then
			--If the cursor was to the right of the start, subtract the num of deleted chars from the cursor position
			if cPos >= pos1 then
				cPos = cPos - (#newText - #tempText)
			end
		end
		newText = tempText

		pos1, pos2 = string_find(newText, patt)
	end

	--Remove any remaining orphaned ending color tags.
	patt = "|r"
	pos1, pos2 = string_find(newText, patt)
	while pos1 ~= nil do
		tempText = string_gsub(newText, patt, "", 1)

		if #newText - #tempText ~= 0 then
			--If the cursor was to the right of the start, subtract the num of deleted chars from the cursor position
			if cPos >= pos1 then
				cPos = cPos - (#newText - #tempText)
			end
		end
		newText = tempText

		pos1, pos2 = string_find(newText, patt)
	end

	--Replace back the extracted item links
	if #itemLinks > 0 then
		for i,val in ipairs(itemLinks) do
			newText = string_gsub(newText, "{<<" .. tostring(i) .. ">-}", val)
		end
	end


	--If by chance the tracked cursor postition went negative, set it to 0
	if cPos < 0 then
		cPos = 0
	end

	--cPos should never be > #newText, unless there's some unfuond error above
	return newText, cPos
end



-------------------------------------------------------------------------
--
-- Routines for the right click misspelled suggestions popup.
--
-------------------------------------------------------------------------
function Misspelled:OnMouseUp(editbox, button)
	if button == "RightButton" then
		local badWordFound = false
		CloseDropDownMenus()

		--check if we are positioned on a misspelled word
		local pos = editbox:GetCursorPosition()
		if WordLocations[editbox:GetName()] ~= nil then
			for i, w in ipairs(WordLocations[editbox:GetName()]) do
				if	pos >= w.StartPos and pos <= w.EndPos then
					if WordCache[w.Word].Correct == false then
						--If not cached, lookup Suggestions for the misspelled word
						if WordCache[w.Word].Suggestions == nil then
							WordCache[w.Word].Suggestions = WordDict:Suggest(w.Word)
						end

						RightClickedWord = w.Word
						RightClickedWordStartPos = w.StartPos
						RightClickedWordEndPos = w.EndPos

						RightClickedEditBox = editbox

						badWordFound = true

						ToggleDropDownMenu(1, nil, MisspelledSuggestions_DropDown, "cursor")
					else
						RightClickedWord = nil
					end
					break
				end
			end
		end

		--Show where the user right clicked.
		--print("cursor position:" , ChatFrameEditBox:GetCursorPosition())

		--If we are not positioned on a bad, word call and MouseUp handler that was hooked to the box.
		if badWordFound == false then
			--print("Trigger native OnMouseUp call")
			self.hooks[editbox]["OnMouseUp"](editbox, button)
		end
	end
end

function MisspelledSuggestions_InitializeDropDown(level)
	if RightClickedWord == nil then return end
	if #RightClickedWord == 0 then return end

	info = UIDropDownMenu_CreateInfo()
	info.text = L["Suggestions for:"] .. " " .. RightClickedWord
	info.isTitle = 1
	info.notClickable = 1
	info.notCheckable = true
	UIDropDownMenu_AddButton(info)

	for i, s in ipairs(WordCache[RightClickedWord].Suggestions) do
		info = UIDropDownMenu_CreateInfo()
                --Line below causes a this == nil error in 4.0.  Looks like it's not needed.
		--info.owner = this:GetParent()

		--If the misspelled word's first
		info.text = s.Word

		--If this suggestion is either a guild member or firend append a note.
		if Misspelled:IsGuildMember(s.Word) == true then
			info.text = info.text .. " " .. L["(Guild)"]
		else
			if Misspelled:IsFriend(s.Word) == true then
				info.text = info.text .. " " .. L["(Friend)"]
			end
		end

		info.isTitle = nil
		info.notCheckable = true
		info.value = s.Word
		info.func = function() SuggestionsFrame_Click(s.Word, RightClickedEditBox) end
		--Add the above info to the optios menu as clickable item
		UIDropDownMenu_AddButton(info)
	end

	--Add a non clickable seperator
	info = UIDropDownMenu_CreateInfo()
	--info.owner = this:GetParent()
	info.text = ""
	info.isTitle = nil
	info.value = ""
	info.notClickable = 1
	info.notCheckable = true
	UIDropDownMenu_AddButton(info)

	info = UIDropDownMenu_CreateInfo()
	--info.owner = this:GetParent()
	info.text = L["Ignore All"]
	info.isTitle = nil
	info.value = RightClickedWord
	info.func = function() SuggestionsFrame_Click("###IgnoreAll", RightClickedEditBox) end
	info.notClickable = nil
	info.notCheckable = true
	UIDropDownMenu_AddButton(info)

	info = UIDropDownMenu_CreateInfo()
	--info.owner = this:GetParent()
	info.text = L["Add to Dictionary"]
	info.isTitle = nil
	info.value = RightClickedWord
	info.func = function() SuggestionsFrame_Click("###AddToDictionary", RightClickedEditBox) end
	info.notClickable = nil
	info.notCheckable = true
	UIDropDownMenu_AddButton(info)

	info = UIDropDownMenu_CreateInfo()
	--info.owner = this:GetParent()
	info.text = L["Cancel"]
	info.isTitle = nil
	info.value = nil
	info.notClickable = nil
	info.notCheckable = true
	UIDropDownMenu_AddButton(info)
end

function MisspelledSuggestions_DropDownOnLoad(self)
	UIDropDownMenu_Initialize(self, MisspelledSuggestions_InitializeDropDown, "MENU")
end

function SuggestionsFrame_Click(value, editbox)
	--value will equal the suggestion word clicked,
	--or a "special" tag, for the 'Ignore' and 'Add to Dictionary' functions

	--print("Suggestion Clicked: ", value)

	local newText = editbox:GetText()
	local newCurcorPos = nil

	local isCapitalizedRighClickedWord = false

	if string_sub(RightClickedWord, 1, 1) == string_upper(string_sub(RightClickedWord, 1, 1)) then
		isCapitalizedRighClickedWord = true
	end

	if value == "###IgnoreAll" then
		--Add this word to the WordCache so it will be ignored as misspelled until you reload
		--print("Ignore:", RightClickedWord)
		WordCache[RightClickedWord].Correct = true
		WordCache[RightClickedWord].Suggestions = {}

		--Remove the misspelled highlighting
		newText = string_sub(newText, 1, RightClickedWordStartPos - 1 - #SPELLED_WRONG_HIGHLIGHT) .. RightClickedWord .. string_sub(newText, RightClickedWordEndPos + #FONT_COLOR_CODE_CLOSE + 1)
		newCursorPos = RightClickedWordStartPos + #RightClickedWord - #SPELLED_WRONG_HIGHLIGHT - #FONT_COLOR_CODE_CLOSE + 1

	elseif value == "###AddToDictionary" then
		-- Add this word to the user dictionary
		--print("Add to UserDict", RightClickedWord)
		Misspelled:AddToUserDict(RightClickedWord)
		WordCache[RightClickedWord].Correct = true
		WordCache[RightClickedWord].Suggestions = {}

		--Remove the misspelled highlighting
		newText = string_sub(newText, 1, RightClickedWordStartPos - 1 - #SPELLED_WRONG_HIGHLIGHT) .. RightClickedWord .. string_sub(newText, RightClickedWordEndPos + #FONT_COLOR_CODE_CLOSE + 1)
		newCursorPos = RightClickedWordStartPos + #RightClickedWord - #SPELLED_WRONG_HIGHLIGHT - #FONT_COLOR_CODE_CLOSE + 1

	else
		--replace this word with the selected suggestion.
		--Remove the misspelled highlighting in the process.
		--
		--If the misspelled word was capitolized, capitolize the replacement.
		if isCapitalizedRighClickedWord == true then
			value = string_upper(string_sub(value, 1, 1)) .. string_sub(value, 2)
		end
		newText = string_sub(newText, 1, RightClickedWordStartPos - 1 - #SPELLED_WRONG_HIGHLIGHT) .. value .. string_sub(newText, RightClickedWordEndPos + #FONT_COLOR_CODE_CLOSE + 1)

		--save the cursor position just after the corrected word, so we can set it later
		newCursorPos = RightClickedWordStartPos + #value - #SPELLED_WRONG_HIGHLIGHT - #FONT_COLOR_CODE_CLOSE + 1

		--Note: if the replacement word is a different length, then the WordLocations will be messed up.
	end

	editbox:SetText(newText)

	--printable = gsub(newText, "\124", "\124\124")
    --print("New ChatText:", printable)

	--If we replaced a word, with a suggestion, move the cursor to the end of the new word.
	if newCursorPos ~= nil then
		--Check if the character to the right of the cursor is a space.  If so adjust the cursor to the right by 1 char.
		if #newText > newCursorPos then
			if string_sub(newText, newCursorPos + 1, newCursorPos + 1) == " " then
				newCursorPos = newCursorPos + 1
			end
		end

		editbox:SetCursorPosition(newCursorPos)
	end

	RightClickedWord = nil
end
-----------------------------------------------------
-- End: Right click Suggestions popup
-----------------------------------------------------



-------------------------------------------------------------------------
--
-- Routines for dealing with the user dictionary
--
-------------------------------------------------------------------------

--Load the words saved in the Users dictionary into the baseWords table.
--In r18 we changed the in memory format used to store the baseWords, affixCode and PhoneticCode,
--Saved a ton of memory not using a subtable per paseword.
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
	local pcode = WordDict:PhoneticCode(word)
	Misspelled_DB.UserDict[word] = "/" .. pcode

	--And add it to the currently loaded dictionary
	WordDict.baseWords[word] = "/" .. pcode

	--Fixup the WordCache
	WordCache[word].Correct = true
	WordCache[word].Suggestions = {}
end


local Misspelled_Words_To_Delete = {}

function Misspelled:EditUserDict()
	local gui = AceGUI

	local f = AceGUI:Create("Window")
	f:SetCallback("OnClose",function(widget, event) AceGUI:Release(widget) end )
	f:SetLayout("Flow")
	f:SetWidth(300)
	f:SetHeight(490)
	f:SetTitle("Misspelled - " .. L["User Dictionary"])
	f:ReleaseChildren()
	f:PauseLayout()


	Misspelled_Words_To_Delete = {}

	local i = gui:Create("InlineGroup")
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
		for k,v in pairs(Misspelled_Words_To_Delete) do
			Misspelled:print(" - " .. k)
			Misspelled_DB.UserDict[k] = nil

			--Remove the word from the, in memory dictionary
			WordDict.baseWords[k] = nil
		end

		--Clear the word cache
		WordCache = {}
		WordCacheCount = 0

		delButton:SetDisabled(true)
		f:Hide()
	end )
	delButton:SetDisabled(true)

	f:AddChild(delButton)


	for k, v in pairs(Misspelled_DB.UserDict) do
		local x = AceGUI:Create("InteractiveLabel")
		x:SetHighlight(.3,.3,.3,.5  )
		x:SetFullWidth(true)
		x:SetText(k)

		x:SetCallback("OnClick", function (widget, event, text)
			--print("Clicked: " .. widget.label:GetText())

			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
			--Check if item is slected or not
			local r,g,b,a = widget.label:GetTextColor()

			if b == 0 then
				--Selected, process an unselect
				widget:SetColor(1,1,1,1)
				Misspelled_Words_To_Delete[widget.label:GetText()] = nil
				local x = 0
				for k,v in pairs(Misspelled_Words_To_Delete) do
					x = x + 1
				end

				if x == 0 then
					delButton:SetDisabled(true)
				else
					delButton:SetDisabled(false)
				end
			else	--Unselected, process a select
				widget:SetColor(1,.2,0,1)
				Misspelled_Words_To_Delete[widget.label:GetText()] = 1
				delButton:SetDisabled(false)
			end
		end )

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

--Load the player's guild members and friends, as valid words into the
--loaded dictionary.
function Misspelled:LoadGuildAndFriendRoster()

	local numFriends, name
	local pcode

	--print("Misspelled: Guild Members Loading...")

	--First check your friends list
	numFriends = GetNumFriends()
	if numFriends > 0 then
		for i = 1, numFriends do
			name = GetFriendInfo(i)
			if name ~= nil then
				if #name > 0 then
					if WordDict:Contains(name) == false then
						--Look up the phonetic code for this friend name
						if WordDict.soundslike == "Phonetic" then
							pcode = WordDict:PhoneticCode(name)
						elseif WordDict.soundslike == "Generic" then
							pcode = WordDict:GenericSoundsLike(name)
						else
							pcode = ""
						end
						--Add the friend name to the loaded dictionary
						WordDict.baseWords[name] = "/" .. pcode
					end
				end
			end
		end
	end

	-- Guild members are valid words.
	if GetNumGuildMembers(true) ~= 0 then
		numFriends = GetNumGuildMembers(true)	-- true to include offline members
		if ( numFriends > 0 ) then
			for i=1, numFriends do
				name = GetGuildRosterInfo(i);
				if name ~= nil then
					if #name ~= 0 then
						if WordDict:Contains(name) == false then
							--Look up the phonetic code for this guild member name
							if WordDict.soundslike == "Phonetic" then
								pcode = WordDict:PhoneticCode(name)
							elseif WordDict.soundslike == "Generic" then
								pcode = WordDict:GenericSoundsLike(name)
							else
								pcode = ""
							end
							--Add the guild member to the loaded dictionary
							WordDict.baseWords[name] = "/" .. pcode
						end
					end
				end
			end
		end
		--print("Misspelled: Guild Members Loaded")
		Misspelled:UnregisterEvent("GUILD_ROSTER_UPDATE")
	end
end

-------------------------------------------------------------------------
-- End: Load Guild and Friend Roster Routine
-------------------------------------------------------------------------

--[[ Interface Options Window ]]--
function Misspelled:CreateInterfaceOptions()
	local cfgFrame = CreateFrame("FRAME", nil, UIParent)
	cfgFrame.name = "Misspelled"

	local cfgFrameHeader = cfgFrame:CreateFontString("OVERLAY", nil, "GameFontNormalLarge")
	cfgFrameHeader:SetPoint("TOPLEFT", 15, -15)
	cfgFrameHeader:SetText(self.Version)

	local cfgFrameReloadTip = cfgFrame:CreateFontString("OVERLAY", nil, "GameFontNormal")
	cfgFrameReloadTip:SetPoint("TOPLEFT", 20, -252)
	cfgFrameReloadTip:SetText(L["Note: Reload the game UI, to load a new dictionary"])

	local cfgAutoSelectDict = CreateFrame("CHECKBUTTON", "Misspelled_cfgAutoSelectDict", cfgFrame, "InterfaceOptionsCheckButtonTemplate")
	Misspelled_cfgAutoSelectDict:SetPoint("TOPLEFT", 20, -40)
	Misspelled_cfgAutoSelectDictText:SetText(L["Auto Select Dictionary to Load"])
	Misspelled_cfgAutoSelectDict:SetChecked(Misspelled_DB.AutoSelectDictionary )
	Misspelled_cfgAutoSelectDict:SetScript("OnClick", function(self)
		if self:GetChecked() then
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
		else
			PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end
		Misspelled_DB.AutoSelectDictionary  = not Misspelled_DB.AutoSelectDictionary
		--Toggle the sub options
		if Misspelled_DB.AutoSelectDictionary == true then
			Misspelled_cfgDictdeDE:Disable()
			Misspelled_cfgDictenGB:Disable()
			Misspelled_cfgDictenUS:Disable()
			Misspelled_cfgDictesES:Disable()
			Misspelled_cfgDictfrFR:Disable()
			Misspelled_cfgDictruRU:Disable()
			Misspelled_cfgDictitIT:Disable()
		else
			Misspelled_cfgDictdeDE:Enable()
			Misspelled_cfgDictenGB:Enable()
			Misspelled_cfgDictenUS:Enable()
			Misspelled_cfgDictesES:Enable()
			Misspelled_cfgDictfrFR:Enable()
			Misspelled_cfgDictruRU:Enable()
			Misspelled_cfgDictitIT:Enable()
			if Misspelled_DB.LoadDictionary == nil or #Misspelled_DB.LoadDictionary == 0 then
				Misspelled_DB.LoadDictionary = "enUS"
				Misspelled_cfgDictenUS:setChecked(true)
			end
		end
	end)

	local cfgDictdeDE = CreateFrame("CHECKBUTTON", "Misspelled_cfgDictdeDE", cfgFrame, "InterfaceOptionsCheckButtonTemplate")
	Misspelled_cfgDictdeDE:SetPoint("TOPLEFT", 40, -64)
	Misspelled_cfgDictdeDEText:SetText("deDE")
	Misspelled_cfgDictdeDE:SetChecked(Misspelled_DB.LoadDictionary == "deDE")
	Misspelled_cfgDictdeDE:SetScript("OnClick", function(self)
		if self:GetChecked() then
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
			Misspelled_DB.LoadDictionary = "deDE"
			Misspelled_cfgDictenGB:SetChecked(false)
			Misspelled_cfgDictenUS:SetChecked(false)
			Misspelled_cfgDictesES:SetChecked(false)
			Misspelled_cfgDictfrFR:SetChecked(false)
			Misspelled_cfgDictruRU:SetChecked(false)
			Misspelled_cfgDictitIT:SetChecked(false)
		else
			PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end
	end)

	local cfgDictenGB = CreateFrame("CHECKBUTTON", "Misspelled_cfgDictenGB", cfgFrame, "InterfaceOptionsCheckButtonTemplate")
	Misspelled_cfgDictenGB:SetPoint("TOPLEFT", 40, -88)
	Misspelled_cfgDictenGBText:SetText("enGB")
	Misspelled_cfgDictenGB:SetChecked(Misspelled_DB.LoadDictionary == "enGB")
	Misspelled_cfgDictenGB:SetScript("OnClick", function(self)
		if self:GetChecked() then
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
			Misspelled_DB.LoadDictionary = "enGB"
			Misspelled_cfgDictdeDE:SetChecked(false)
			Misspelled_cfgDictenUS:SetChecked(false)
			Misspelled_cfgDictesES:SetChecked(false)
			Misspelled_cfgDictfrFR:SetChecked(false)
			Misspelled_cfgDictruRU:SetChecked(false)
			Misspelled_cfgDictitIT:SetChecked(false)
		else
			PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end
	end)

	local cfgDictenUS = CreateFrame("CHECKBUTTON", "Misspelled_cfgDictenUS", cfgFrame, "InterfaceOptionsCheckButtonTemplate")
	Misspelled_cfgDictenUS:SetPoint("TOPLEFT", 40, -112)
	Misspelled_cfgDictenUSText:SetText("enUS")
	Misspelled_cfgDictenUS:SetChecked(Misspelled_DB.LoadDictionary == "enUS")
	Misspelled_cfgDictenUS:SetScript("OnClick", function(self)
		if self:GetChecked() then
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
			Misspelled_DB.LoadDictionary = "enUS"
			Misspelled_cfgDictdeDE:SetChecked(false)
			Misspelled_cfgDictenGB:SetChecked(false)
			Misspelled_cfgDictesES:SetChecked(false)
			Misspelled_cfgDictfrFR:SetChecked(false)
			Misspelled_cfgDictruRU:SetChecked(false)
			Misspelled_cfgDictitIT:SetChecked(false)
		else
			PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end
	end)

	local cfgDictesES = CreateFrame("CHECKBUTTON", "Misspelled_cfgDictesES", cfgFrame, "InterfaceOptionsCheckButtonTemplate")
	Misspelled_cfgDictesES:SetPoint("TOPLEFT", 40, -136)
	Misspelled_cfgDictesESText:SetText("esES")
	Misspelled_cfgDictesES:SetChecked(Misspelled_DB.LoadDictionary == "esES")
	Misspelled_cfgDictesES:SetScript("OnClick", function(self)
		if self:GetChecked() then
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
			Misspelled_DB.LoadDictionary = "esES"
			Misspelled_cfgDictdeDE:SetChecked(false)
			Misspelled_cfgDictenGB:SetChecked(false)
			Misspelled_cfgDictenUS:SetChecked(false)
			Misspelled_cfgDictfrFR:SetChecked(false)
			Misspelled_cfgDictruRU:SetChecked(false)
			Misspelled_cfgDictitIT:SetChecked(false)
		else
			PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end

	end)

	local cfgDictfrFR = CreateFrame("CHECKBUTTON", "Misspelled_cfgDictfrFR", cfgFrame, "InterfaceOptionsCheckButtonTemplate")
	Misspelled_cfgDictfrFR:SetPoint("TOPLEFT", 40, -160)
	Misspelled_cfgDictfrFRText:SetText("frFR")
	Misspelled_cfgDictfrFR:SetChecked(Misspelled_DB.LoadDictionary == "frFR")
	Misspelled_cfgDictfrFR:SetScript("OnClick", function(self)
		if self:GetChecked() then
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
			Misspelled_DB.LoadDictionary = "frFR"
			Misspelled_cfgDictdeDE:SetChecked(false)
			Misspelled_cfgDictenGB:SetChecked(false)
			Misspelled_cfgDictenUS:SetChecked(false)
			Misspelled_cfgDictesES:SetChecked(false)
			Misspelled_cfgDictruRU:SetChecked(false)
			Misspelled_cfgDictitIT:SetChecked(false)
		else
			PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end

	end)

	local cfgDictruRU = CreateFrame("CHECKBUTTON", "Misspelled_cfgDictruRU", cfgFrame, "InterfaceOptionsCheckButtonTemplate")
	Misspelled_cfgDictruRU:SetPoint("TOPLEFT", 40, -184)
	Misspelled_cfgDictruRUText:SetText("ruRU")
	Misspelled_cfgDictruRU:SetChecked(Misspelled_DB.LoadDictionary == "ruRU")
	Misspelled_cfgDictruRU:SetScript("OnClick", function(self)
		if self:GetChecked() then
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
			Misspelled_DB.LoadDictionary = "ruRU"
			Misspelled_cfgDictdeDE:SetChecked(false)
			Misspelled_cfgDictenGB:SetChecked(false)
			Misspelled_cfgDictenUS:SetChecked(false)
			Misspelled_cfgDictfrFR:SetChecked(false)
			Misspelled_cfgDictesES:SetChecked(false)
			Misspelled_cfgDictitIT:SetChecked(false)
		else
			PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end

	end)

	local cfgDictitIT = CreateFrame("CHECKBUTTON", "Misspelled_cfgDictitIT", cfgFrame, "InterfaceOptionsCheckButtonTemplate")
	Misspelled_cfgDictitIT:SetPoint("TOPLEFT", 40, -208)
	Misspelled_cfgDictitITText:SetText("itIT")
	Misspelled_cfgDictitIT:SetChecked(Misspelled_DB.LoadDictionary == "itIT")
	Misspelled_cfgDictitIT:SetScript("OnClick", function(self)
		if self:GetChecked() then
			PlaySound(856) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
			Misspelled_DB.LoadDictionary = "itIT"
			Misspelled_cfgDictdeDE:SetChecked(false)
			Misspelled_cfgDictenGB:SetChecked(false)
			Misspelled_cfgDictenUS:SetChecked(false)
			Misspelled_cfgDictfrFR:SetChecked(false)
			Misspelled_cfgDictesES:SetChecked(false)
			Misspelled_cfgDictruRU:SetChecked(false)
		else
			PlaySound(857) -- SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF
		end

	end)

	--Edit User Dictionary Button
	local cfgEditUserDict = CreateFrame("Button", "EdutUserDictButton", cfgFrame, "UIPanelButtonTemplate")
        cfgEditUserDict:SetPoint("TOPLEFT", 20, -287)
        cfgEditUserDict:SetText(L["Edit User Dictionary..."])
	cfgEditUserDict:SetWidth(200)
	cfgEditUserDict:SetHeight(24)
	cfgEditUserDict:SetScript("OnClick", function(self)
		--PlaySound("igMainMenuOptionCheckBoxOn")
		Misspelled:EditUserDict()
	end)

	--set options on startup
	Misspelled_cfgDictdeDE:SetChecked(false)
	Misspelled_cfgDictenUS:SetChecked(false)
	Misspelled_cfgDictenGB:SetChecked(false)
	Misspelled_cfgDictesES:SetChecked(false)
	Misspelled_cfgDictfrFR:SetChecked(false)
	Misspelled_cfgDictruRU:SetChecked(false)
	Misspelled_cfgDictitIT:SetChecked(false)

	if Misspelled_DB.LoadDictionary == "deDE" then
		Misspelled_cfgDictdeDE:SetChecked(true)
	elseif Misspelled_DB.LoadDictionary == "enGB" then
		Misspelled_cfgDictenGB:SetChecked(true)
	elseif Misspelled_DB.LoadDictionary == "enUS" then
		Misspelled_cfgDictenUS:SetChecked(true)
	elseif Misspelled_DB.LoadDictionary == "esES" then
		Misspelled_cfgDictesES:SetChecked(true)
	elseif Misspelled_DB.LoadDictionary == "frFR" then
		Misspelled_cfgDictfrFR:SetChecked(true)
	elseif Misspelled_DB.LoadDictionary == "ruRU" then
		Misspelled_cfgDictruRU:SetChecked(true)
	elseif Misspelled_DB.LoadDictionary == "itIT" then
		Misspelled_cfgDictitIT:SetChecked(true)
	end

	if Misspelled_DB.AutoSelectDictionary == true then
			Misspelled_cfgDictdeDE:Disable()
			Misspelled_cfgDictenGB:Disable()
			Misspelled_cfgDictenUS:Disable()
			Misspelled_cfgDictesES:Disable()
			Misspelled_cfgDictfrFR:Disable()
			Misspelled_cfgDictruRU:Disable()
			Misspelled_cfgDictitIT:Disable()
	else
			Misspelled_cfgDictdeDE:Enable()
			Misspelled_cfgDictenGB:Enable()
			Misspelled_cfgDictenUS:Enable()
			Misspelled_cfgDictesES:Enable()
			Misspelled_cfgDictfrFR:Enable()
			Misspelled_cfgDictruRU:Enable()
			Misspelled_cfgDictitIT:Enable()
	end

	InterfaceOptions_AddCategory(cfgFrame)
end


-------------------------------------------------------------------------
--
-- Utility Routines
--
-------------------------------------------------------------------------

--Split a string, at patt delimiter, into a table
function Misspelled:split(str, patt)
	vals = {}; valindex = 0; word = ""
	-- need to add a trailing separator to catch the last value.
	str = str .. patt
	for i = 1, string_len(str) do

		cha = string_sub(str, i, i)
		if cha ~= patt then
			word = word .. cha
		else
			if word ~= nil then
				vals[valindex] = word
				valindex = valindex + 1
				word = ""
			else
				-- in case we get a line with no data.
				break
			end
		end

	end
	return vals
end

function Misspelled:tprint (t, indent, done)
  -- in case we run it standalone
  local Note = Note or print
--  local Tell = Tell or io.write

  -- show strings differently to distinguish them from numbers
  local function show (val)
    if type (val) == "string" then
      return '"' .. val .. '"'
    else
      return tostring(val)
    end -- if
  end -- show
  -- entry point here
  done = done or {}
  indent = indent or 0
  for key, value in pairs (t) do
    print(string_rep(" ", indent)) -- indent it
    if type (value) == "table" and not done [value] then
      done [value] = true
      Note (show (key), ":");
      Misspelled:tprint(value, indent + 2, done)
    else
      print(show (key), "=")
      print (show (value))
    end
  end
end

function Misspelled:print(...)
	SELECTED_DOCK_FRAME:AddMessage(...)
end

--Check your friends list to see if the string: name is on the friends list.
function Misspelled:IsFriend(name)
	local numFriends

	numFriends = GetNumFriends()
	if numFriends > 0 then
		for i = 1, numFriends do
			if name == GetFriendInfo(i) then
				return true
			end
		end
	end
	return false
end

--check the guild roster to see if the string: name, is a guild member.
function Misspelled:IsGuildMember(name)
	local numGuildMembers

	if IsInGuild() then
		numGuildMembers = GetNumGuildMembers(true);	-- true to include offline members
		if ( numGuildMembers > 0 ) then
			for i=1, numGuildMembers do
				if name == GetGuildRosterInfo(i) then
					return true
				end
			end
		end
	end

	return false
end
-------------------------------------------------------------------------
-- End: Utility Routines
-------------------------------------------------------------------------


--[[
--testing
require("bit")
require("WordDict")
--~ require("Dict\\Dic_en_US")
--~ Misspelled_DB = {}
--~ WordDict:Init()
--~ ChatFrameEditBox = {}
--~ function ChatFrameEditBox:GetText()
--~ 	return "Leatherworking"
--~ end
s = "Test |cffff91c8A|cffxxxxxxBSecondWord|r|r"
s2 = string.gsub(s, SPELLED_WRONG_HIGHLIGHT .. "(.-)|r", function(x) return x end)
print(s2)
---]]
