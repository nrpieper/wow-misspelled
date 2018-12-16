--[[
Misspelled utilizes a slightly Lua'ified version of the Hunspell Dictionary format.
Note: Not all Dictionary sets tags are supported.

Phonetic information has been appeneded, after the affix codes, to each base word
example: "hello/GMS/HL"
A phonetic lookup set "Phonetic" exists before the base words.

Here is some rather generic documentation on that format.
From: http://sourceforge.net/docman/display_doc.php?docid=29374&group_id=143754

TRY
sets the change characters for suggestions.

REP (Replace)
sets a replacement table for multiple character corrections in suggestion mode.

The following affix file example:. 'TRY' suggestions differ from the bad word with an
English letter or an apostrophe. With these REP definitions, Hunspell can suggest the
right word form, when the misspelled word contains f instead of ph and vice versa.


	TRY esianrtolcdugmphbyfvkwzESIANRTOLCDUGMPHBYFVKWZ

	REP 2
	REP f ph
	REP ph f

	PFX A Y 1
	PFX A 0 re .

	SFX B Y 2
	SFX B 0 ed [^y]
	SFX B y ied y

There are two affix classes in the dictionary.
Class A defines a 're-' prefix. Class B defines two '-ed' suffixes.
First suffix can be added to a word if the last character of the word isn't 'y'.
Second suffix can be added to the words terminated with an 'y'. (See later.)

The following dictionary file uses these affix classes.

	3
	hello
	try/B
	work/AB

All accepted words with this dictionary: "hello", "try", "tried", "work", "worked", "rework", "reworked".


Affix Compression
--------------------------------------------------------------------------
An affix is either a  prefix or a suffix attached to root words to make
other words.  For example supply -> supplied by dropping the "y" and
adding an "ied" (the suffix).

Here is an example of how to define one specific suffix borrowed
from the en_US.aff file used by the OpenOffice org spellchecker

SFX D Y 4
SFX D   0     d          e
SFX D   y     ied        [^aeiou]y
SFX D   0     ed         [^ey]
SFX D   0     ed         [aeiou]y

This file is space delimited and case sensitive.
So this information can be interpreted as follows:

The first line has 4 fields:

Field
-----
1     SFX - indicates this is a suffix
2     D   - is the name of the character which represents this suffix
3     Y   - indicates it can be combined with prefixes (cross product)
4     4   - indicates that sequence of 4 affix entries are needed to
               properly store the affix information

The remaining lines describe the unique information for the 4 affix
entries that make up this affix.  Each line can be interpreted
as follows: (note fields 1 and 2 are used as a check against line 1 info)

Field
-----
1     SFX         - indicates this is a suffix
2     D           - is the name of the character which represents this affix
3     y           - the string of chars to strip off before adding affix
                         (a 0 here indicates the NULL string)
4     ied         - the string of affix characters to add
                         (a 0 here indicates the NULL string)
5     [^aeiou]y   - the conditions which must be met before the affix
                    can be applied

Field 5 is interesting.  Since this is a suffix, field 5 tells us that
there are 2 conditions that must be met.  The first condition is that
the next to the last character in the word must *NOT* be any of the
following "a", "e", "i", "o" or "u".  The second condition is that
the last character of the word must end in "y".

So how can we encode this information concisely and be able to
test for both conditions in a fast manner?  The answer is found
but studying the wonderful ispell code of Geoff Kuenning, et.al.
(now available under a normal BSD license).

If we set up a conds array of 256 bytes indexed (0 to 255) and access it
using a character (cast to an unsigned char) of a string, we have 8 bits
of information we can store about that character.  Specifically we
could use each bit to say if that character is allowed in any of the
last (or first for prefixes) 8 characters of the word.

Basically, each character at one end of the word (up to the number
of conditions) is used to index into the conds array and the resulting
value found there says whether the that character is valid for a
specific character position in the word.

For prefixes, it does this by setting bit 0 if that char is valid
in the first position, bit 1 if valid in the second position, and so on.

If a bit is not set, then that char is not valid for that postion in the
word.

If working with suffixes bit 0 is used for the character closest
to the front, bit 1 for the next character towards the end, ...,
with bit numconds-1 representing the last char at the end of the string.

Note: since entries in the conds[] are 8 bits, only 8 conditions
(read that only 8 character positions) can be examined at one
end of a word (the beginning for prefixes and the end for suffixes.

So to make this clearer, lets encode the conds array values for the
first two affentries for the suffix D described earlier.


  For the first affentry:
     numconds = 1             (only examine the last character)

     conds['e'] =  (1 << 0)   (the word must end in an E)
     all others are all 0

  For the second affentry:
     numconds = 2             (only examine the last two characters)

     conds[X] = conds[X] | (1 << 0)     (aeiou are not allowed)
         where X is all characters *but* a, e, i, o, or u


     conds['y'] = (1 << 1)     (the last char must be a y)
     all other bits for all other entries in the conds array are zero


--]]

if bit == nil then
	require("bit")
end

if string.utf8len == nil then
	require("UTF8\\utf8data")
	require("UTF8\\utf8")
end


--Local reference to Global functions for speed
local ipairs = ipairs
local pairs = pairs
local string_byte = string.byte
local string_utf8byte = string.utf8byte
local string_find = string.find
local string_gsub = string.gsub
local string_len = string.len
local string_utf8len = string.utf8len
local string_lower = string.lower
local string_utf8lower = string.utf8lower
local string_match = string.match
local string_rep = string.rep
local string_sub = string.sub
local string_utf8sub = string.utf8sub
local string_upper = string.upper
local string_utf8upper = string.utf8upper

local table_concat = table.concat
local table_insert = table.insert
local table_sort = table.sort

local bit_bor = bit.bor
local bit_lshift = bit.lshift
local bit_rshift = bit.rshift
local bit_band = bit.band
local bit_bnot = bit.bnot
local math_min = math.min

local utf8 = false

--WordDict_Dictionary = {}

local DICTIONARY_TO_LOAD_FROM

--split a string, at delimiter into a table
-- Compatibility: Lua-5.1
local split_t
local split_fpat
local split_last_end
local split_s, split_e, split_cap
local function split(str, pat)
   split_t = {}  -- NOTE: use {n = 0} in Lua-5.0
   split_fpat = "(.-)" .. pat
   split_last_end = 1
   split_s, split_e, split_cap = string_find(str, split_fpat, 1)
   while split_s do
      if split_s ~= 1 or split_cap ~= "" then
	 table_insert(split_t, split_cap)
      end
      split_last_end = split_e+1
      split_s, split_e, split_cap = string_find(str, split_fpat, split_last_end)
   end
	 if split_last_end <= #str then
		split_cap = string_sub(str, split_last_end)
		table_insert(split_t, split_cap)
	 end
   return split_t
end


--WordDict Class
WordDict = {}
WordDict = {
			locale = "",
			baseWords = {},
			replaceChars = {},
			prefixRules = {},
			suffixRules = {},
			phoneticRules= {},
			tryChars = {},
			lastContainsWord = "",
			possibleBaseWords = {},
			suggestions= {},
			soundslike = "Generic",
			maxSuggestions = 8,
			maxEditDistance = 4
			}

WordDict.AffixUtility = {}

--Takes aff file condition string and creates the condition array
--Rather similar to hunspell affixmgr.cpp AffixMgr::encodeit()
--http://www.google.com/codesearch/p?hl=en#e_ObwTAVPyo/extensions/spellcheck/hunspell/src/affixmgr.cpp&q=affix encode condition&l=1004
function WordDict.AffixUtility:EncodeConditions(conditionText)
	local condition = {}
	local utf8Condition = {}
	utf8Condition["ascii"] = {}
	utf8Condition["all"] = {}
	utf8Condition["neg"] = {}
	utf8Condition["utf8Chars"] = {}

	local group = false  	--Group indicator
	local groupend = false	--end contition indicator
	local neg = false -- complement indicator
	local conditionCount = 0 -- number of conditions

	local memberChars = {}
	local numMember = 0		-- number of member in group

	local str_sub = string_sub
	local str_len = string_len

	if utf8 == true then
		str_len = string.utf8len
		str_sub = string.utf8sub
 	end

	--local BeginningOnly = false
	--local EndOnly = false

	local ReplaceMode = false


	--print("conditionText", conditionText)

	--Clear the condition array
	for j=0,255 do
		condition[j] = 0
	end

	--Clear the utf8Condition array
	for j=0, 127 do
		utf8Condition.ascii[j] = 0
	end

	--If no condition just return
	if conditionText == "." then
		conditionCount = 0
		return conditionCount, Condition
	end

	for i = 1, str_len(conditionText) do
		local cond = str_sub(conditionText, i, i)
		--	print("i", i, "cond", cond)

		--start group indicator
		if cond == "[" then
			group = true

		--complement flag (negative group)
		elseif cond == "^" and group == true then
			neg = true

		--end group indicator
		elseif cond == "]" then
			endgroup = true  -- end of a group

		--add character of group to list
		elseif group == true then
			memberChars[numMember] = cond
			numMember = numMember + 1
		else
			endgroup = true --no group
		end

		--set condition
		if endgroup == true then
			if utf8 == false then
				if group == true then
					if neg == false then
						--turn on chars in member group
						--set the proper bits in the condition array vals for those chars
						for j = 0, numMember -1 do
							local charCode = string_byte(memberChars[j])
							condition[charCode] = bit_bor(condition[charCode], bit_lshift(1, conditionCount))
						end
					else
						--complement so set all of chars on, then uset indicated ones.
						for j=0,255 do
							condition[j] = bit_bor(condition[j], bit_lshift(1, conditionCount))
						end
						--turn off chars in member groupend
						for j = 0, numMember -1 do
							local charCode = string_byte(memberChars[j])
							condition[charCode] = bit_band(condition[charCode], bit_bnot(bit_lshift(1, conditionCount)))
						end
					end
					neg = false
					group = false
					numMember = 0
				else
					--not in a group, so just set the proper bit for this char
					--but first handle special case of . inside condition
					if cond == "." then
						--wild char character, turn all chars on
						for j=0, 255 do
							condition[j] = bit_bor(condition[j], bit_lshift(1, CounditionCount))
						end
					else
						--turn on char
						local charCode = string_byte(cond)
						condition[charCode] = bit_bor(condition[charCode], bit_lshift(1, conditionCount))
					end
				end

			else	-- utf8 character set
				--Use two storage methods to store the conditions.
				--First, for simple one byte utf8 characters (ascii) use the storage method above
				--with the understanding tha we know an 1 byte ACSII utf char has to be less than 128,
				--and this requires fewer bits of storage
				--
				--For multi-byte utf8 condition chars, store, up to 8 of them, in and character array,
				--along with the flag information about negative condition groups and the all char
				--wildcard use
				--struct {
				--	char ascii[SETSIZE/2];
				--	char neg[8];
				--	char all[8];
				--	w_char * wchars[8];
				--	int wlen[8];
				--} utf8condition;
				--
				--use the utf8 safe version of byte


				if group == true then
					utf8Condition.neg[conditionCount] = neg
					--
					--First handel the Acsii one byte utf8 chars
					--
					if neg == false then
						--set the proper bits in the condition array vals for those chars
						for j=0, numMember -1 do
							local charCode = string_utf8byte(memberChars[j])
							if charCode > 0 and charCode < 128 then
								utf8Condition.ascii[charCode] = bit_bor(utf8Condition.ascii[charCode], bit_lshift(1, conditionCount))
							end
						end
					else --neg = true
						--complement so set all of chars on, then uset indicated ones.
						for j=0,127 do
							utf8Condition.ascii[j] = bit_bor(utf8Condition.ascii[j], bit_lshift(1, conditionCount))
						end

						--turn off chars in member groupend
						for j = 0, numMember -1 do
							local charCode = string_utf8byte(memberChars[j])
							if charCode < 128 then
								utf8Condition.ascii[charCode] = bit_band(utf8Condition.ascii[charCode], bit_bnot(bit_lshift(1, conditionCount)))
							end
						end
					end

					--Store utf8 multi-byte conditions
					for j = 0, numMember - 1 do
						if string_byte(memberChars[j]) >= 128 then
							if utf8Condition.utf8Chars[conditionCount] == nil then
								utf8Condition.utf8Chars[conditionCount] = ""
							end
							utf8Condition.utf8Chars[conditionCount] = utf8Condition.utf8Chars[conditionCount] .. memberChars[j]
						end
					end

					neg = false
					group = false
					numMember = 0

				else  --group == false
					local condCode = string_utf8byte(cond)
					--Is cond a utf8 multi-byte character
					if  condCode >= 128 then
							if utf8Condition.utf8Chars[conditionCount] == nil then
								utf8Condition.utf8Chars[conditionCount] = ""
							end
							utf8Condition.utf8Chars[conditionCount] = utf8Condition.utf8Chars[conditionCount] .. cond
					else
						--not a group so just set the proper bit for this char
						--by first handle special case of . inside condition
						if cond == "." then
							utf8Condition.all[conditionCount] = true
							for j = 0, 127 do
								utf8Condition.ascii[j] = bit_bor(utf8Condition.ascii[j], bit_lshift(1, conditionCount))
							end
						else
							utf8Condition.all[conditionCount] = false
							utf8Condition.ascii[condCode] = bit_bor(utf8Condition.ascii[condCode], bit_lshift(1, conditionCount))
						end
					end
					neg = false
				end
				conditionCount = conditionCount + 1
				endgroup = false
				neg = false
			end
		end
	end

	--Condition["conditionCount"] = conditionCount
	return conditionCount, condition, utf8Condition
end

--Removes the affix suffix rule entry for the word if valid
function WordDict.AffixUtility:RemoveSuffix(word, entry)
	local tempLength
	local tempWord
	local c
	local charCode
	local passCount

	if utf8 == false then
		tempLength = #word - #entry.AddChars
		if (tempLength > 0)
			and (tempLength + #entry.StripChars >= entry.ConditionCount)
			and (string_match(word, entry.AddChars .. "$") ~= nil) then  --word ends with suffix

			--word without affix
			tempWord = string_sub(word, 1, tempLength)
			--add back strip chars
			tempWord = tempWord .. entry.StripChars
			--check that this is valid
			passCount = 0
			for i = 0, entry.ConditionCount - 1 do
				charCode = string_byte(string_sub(tempWord, #tempWord - (entry.ConditionCount -i) + 1))

				if bit_band(entry.Conditions[charCode], bit_lshift(1, i)) == bit_lshift(1 , i) then
					passCount = passCount + 1
				end
			end
			if passCount == entry.ConditionCount then
				return tempWord
			end
		end
	else
		tempLength = string_utf8len(word) - string_utf8len(entry.AddChars)
 		if (tempLength > 0)
			and (tempLength + string_utf8len(entry.StripChars) >= entry.ConditionCount)
			and (string_match(word, entry.AddChars .. "$") ~= nil) then --word ends with suffix

			--word without suffix
			tempWord = string_utf8sub(word, 1, tempLength)
			--add back strip chars
			tempWord = tempWord .. entry.StripChars

			--check if tempWord is valid
			passCount = 0
			for i = 0, entry.ConditionCount - 1 do
				c = string_utf8sub(tempWord, string_utf8len(tempWord) - (entry.ConditionCount - i) + 1)
				charCode = string_utf8byte(c)

				--if this charCode is 1 byte, check the utf8Condition.Ascii table
				if charCode > 0 and charCode < 128 then
					if bit_band(entry.Utf8Conditions.ascii[charCode], bit_lshift(1, i)) == bit_lshift(1, i) then
						passCount = passCount + 1
					end
				else
					--this is a multi byte utf8 char
					--check if it's stored in the utf8 specific part of the rule.
					local all
					local neg
					local utf8Chars

					all = entry.Utf8Conditions.all[i]
					neg = entry.Utf8Conditions.neg[i]
					utf8Chars = entry.Utf8Conditions.utf8Chars[i]

					--check if this condition has any utf8 multibyte chars.
					if utf8Chars ~= nil then
						if all == true then	-- "." match all characters
							passCount = passCount + 1
						elseif neg == false then
							--check if this char is present
							if string_find(utf8Chars, c) ~= nil then
								passCount = passCount + 1
							end
						else  -- neg == true.  Make sure we can't find the char.
							if string_find(utf8Chars, c) == nil then
								passCount = passCount + 1
							end
						end
					end
				end
			end
			if passCount == entry.ConditionCount then
				return tempWord
			end
		end
	end
	return word
end

--Removes the affix prefix rule entry for the word if valid
function WordDict.AffixUtility:RemovePrefix(word, entry)
	local tempLength
	local tempWord
	local c
	local charCode
	local passCount
	if utf8 == false then
		tempLength = #word - #entry.AddChars
		if (tempLength > 0)
			and (tempLength + #entry.StripChars >= entry.ConditionCount)
			and (string_match(word, "^" .. entry.AddChars) ~= nil) then  --word starts with

			--word with out affix
			tempWord = string_sub(word, #entry.AddChars+1)
			--add back strip chars
			tempWord = entry.StripChars .. tempWord
			--check that this is valid
			passCount = 0
			for i = 0, entry.ConditionCount - 1 do
				charCode = string_byte(string_sub(tempWord, i+1, i+1))

				if bit_band(entry.Conditions[charCode], bit_lshift(1, i)) == bit_lshift(1 , i) then
					passCount = passCount + 1
				end
			end
			if passCount == entry.ConditionCount then
				return tempWord
			end
		end
	else
		tempLength = string_utf8len(word) - string_utf8len(entry.AddChars)
 		if (tempLength > 0)
 			and (tempLength + string_utf8len(entry.StripChars) >= entry.ConditionCount)
			and (string_match(word, "^" .. entry.AddChars) ~= nil) then --word starts with

			--word with out prefix
			tempWord = string_sub(word, string_utf8len(entry.AddChars) + 1)
			--add back strip chars
			tempWord = entry.StripChars .. tempWord

			--check if tempWord is valid
			passCount = 0
			for i = 0, entry.ConditionCount - 1 do
				c = string_utf8sub(tempWord, i+1, i+1)
				charCode = string_utf8byte(c)

				--if this charCode is 1 byte, check the utf8Condition.Ascii table
				if charCode > 0 and charCode < 128 then
					if bit_band(entry.Utf8Conditions.ascii[charCode], bit_lshift(1, i)) == bit_lshift(1, i) then
						passCount = passCount + 1
					end
				else
					--this is a multi byte utf8 char
					local all
					local neg
					local utf8Chars

					all = entry.Utf8Conditions.all[i]
					neg = entry.Utf8Conditions.neg[i]
					utf8Chars = entry.Utf8Conditions.utf8Chars[i]
					--check if this condition has any utf8 multibyte chars.
					if utf8Chars ~= nil then
						if all == true then	-- "." match all characters
							passCount = passCount + 1
						elseif neg == false then
							--check if this char is present
							if string_find(utf8Chars, c) ~= nil then
								passCount = passCount + 1
							end
						else
							if string_find(utf8Chars, c) == nil then
								passCount = passCount + 1
							end
						end
					end
				end
			end
			if passCount == entry.ConditionCount then
				return tempWord
			end
		end
	end
	return word
end

--Adds a suffix to a word
--Returns the word with the suffix added
function WordDict.AffixUtility:AddSuffix(word, rule)
	local passCount
	local charCode
	local tempLen
	local tempWord

	for i, entry in ipairs(rule.AffixEntries) do
		--check if this entry is valid
		if utf8 == false then
			if #word >= entry.ConditionCount then
				passCount = 0
				for i=0, entry.ConditionCount - 1 do
					charCode = string_byte(string_sub(word, #word - (entry.ConditionCount -i)+1,#word - (entry.ConditionCount -i)+1))

					if bit_band(entry.Conditions[charCode], bit_lshift(1, i)) == bit_lshift(1 , i) then
						passCount = passCount + 1
					else
						break
					end
				end
				if passCount == entry.ConditionCount then
					tempLen = #word - #entry.StripChars
					tempWord = string_sub(word, 1, tempLen)
					tempWord = tempWord .. entry.AddChars
					return tempWord
				end
			end
		else  --utf8
			if string_utf8len(word) >= entry.ConditionCount then
				passCount = 0
				for i = 0, entry.ConditionCount - 1 do
					--For each condition, we need to check utf8 characters at the end of the word
					local conditionPos = string_utf8len(word) - (entry.ConditionCount - i) + 1
					local c = string_utf8sub(word, conditionPos, conditionPos)
					charCode = string_utf8byte(c)

					--if this charCode is 1 byte, check the utf8Condition.Ascii table
					if charCode > 0 and charCode < 128 then
						if bit_band(entry.Utf8Conditions.ascii[charCode], bit_lshift(1, i)) == bit_lshift(1, i) then
							passCount = passCount + 1
						else
							break
						end
					else
						--this is a multi-byte utf8 character, check
						local all
						local neg
						local utf8Chars

						all = entry.Utf8Conditions.all[i]
						neg = entry.Utf8Conditions.neg[i]
						utf8Chars = entry.Utf8Conditions.utf8Chars[i]
						--check if this condition has any utf8 multibyte chars.
						if utf8Chars ~= nil then
							if all == true then	-- "." match all characters
								passCount = passCount + 1
							elseif neg == false then
								--check if this char is present
								if string_find(utf8Chars, c) ~= nil then
									passCount = passCount + 1
								else
									break
								end
							else	-- neg == true
								-- check complement
								if string_find(utf8Chars, c) == nil then
									passCount = passCount + 1
								else
									break
								end
							end
						end
					end
				end
				if passCount == entry.ConditionCount then
					tempLen = string_len(word) - #entry.StripChars
					tempWord = string_sub(word, 1 , tempLen)
					tempWord = tempWord .. entry.AddChars
					return tempWord
				end
			end
		end
	end
	return word
end

--Adds a prefix to a word
--Returns the word with the prefix added
function WordDict.AffixUtility:AddPrefix(word, rule)
	local passCount
	local charCode
	local tempLen
	local tempWord
	for i, entry in ipairs(rule.AffixEntries) do
		--check if this entry is valid
		if utf8 == false then
			if #word >= entry.ConditionCount then
				passCount = 0
				for i=0, entry.ConditionCount -1 do
					charCode = string_byte(string_sub(word, i+1, i+1))

					if bit_band(entry.Conditions[charCode], bit_lshift(1, i)) == bit_lshift(1 , i) then
						passCount = passCount + 1
					else
						break
					end
				end
				if passCount == entry.ConditionCount then
					tempWord = string_sub(word, #entry.StripChars)
					tempWord = entry.AddChars .. tempWord
					return tempWord
				end
			end
		else  --utf8
			if string_utf8len(word) >= entry.ConditionCount then
				passCount = 0
				for i = 0, entry.ConditionCount - 1 do
					--For each condition, we need to check utf8 characters at the end of the word
					local c = string_utf8sub(word, i + 1, i + 1)
					charCode = string_utf8byte(c)

					--if this charCode is 1 byte, check the utf8Condition.Ascii table
					if charCode > 0 and charCode < 128 then
						if bit_band(entry.Utf8Conditions.ascii[charCode], bit_lshift(1, i)) == bit_lshift(1, i) then
							passCount = passCount + 1
						else
							break
						end
					else
						--this is a multi-byte utf8 character, check
						local all
						local neg
						local utf8Chars

						all = entry.Utf8Conditions.all[i]
						neg = entry.Utf8Conditions.neg[i]
						utf8Chars = entry.Utf8Conditions.utf8Chars[i]

						--check if this condition has any utf8 multibyte chars.
						if utf8Chars ~= nil then
							if all == true then	-- "." match all characters
								passCount = passCount + 1
							elseif neg == false then
								--check if this char is present
								if string_find(utf8Chars, c) ~= nil then
									passCount = passCount + 1
								else
									break
								end
							else  -- neg == true
								-- check for the complement
								if string_find(utf8Chars, c) == nil then
									passCount = passCount + 1
								else
									break
								end
							end
						end
					end
				end
				if passCount == entry.ConditionCount then
					tempWord = string_sub(word, #entry.StripChars)
					tempWord = entry.AddChars .. tempWord
					return tempWord
				end

			end
		end
	end
	return word
end


function WordDict:LoadPrefixRules()
	local row = 1 --row pointer
	local rowCount = #DICTIONARY_TO_LOAD_FROM.Prefix

	local header
	local hparts
	local hpart1
	local hpart2
	local hpart3
	local rulecount
	local rule1
	local rule2
	local rule3
	local rule4
	local AllowCombine = false
	local entry
	local parsedEntry
	local condCount
	local conditions
	local utf8Conditions

	local p = DICTIONARY_TO_LOAD_FROM.Prefix

	while row < rowCount do
			header = p[row]

			-- headers are in 3 parts
			hparts = split(header, "%s+")
			hpart1 = hparts[1] -- Part 1 = affix key
			hpart2 = hparts[2] -- Part 2 = Allow combine flag
			hpart3 = hparts[3] -- Part 3 = rule count

 			--determin how many parts there are to this prefix
			rulecount = tonumber(hpart3 )
			--print("header", hpart1, hpart2, hpart3)

			--Add header parts 1 & 2 to PrefixRules collection
			self.prefixRules[hpart1] = {["Combine"]=hpart2, ["Rules"]={}}

			--Rules have 4 parts
			--Part1: affix(prefix/suffix) key
			--Part2: strip char
			--Part3: add chars
			--Part4: conditions

			AllowCombine = false
			if hpart2 == "Y" then AllowCombine = true end

			--Add header parts 1 & 2 to PrefixRules collection
			self.prefixRules[hpart1] = {["AllowCombine"]=AllowCombine, ["AffixEntries"]={}}

			for x = 1, rulecount do
				row = row + 1
				entry = p[row]
				parsedEntry = split(entry, "%s+")
				self.prefixRules[hpart1]["AffixEntries"][x] = {}
				--part 2 - strip char
				if parsedEntry[2] == "0" then
					self.prefixRules[hpart1]["AffixEntries"][x]["StripChars"] = ""
				else
				    self.prefixRules[hpart1]["AffixEntries"][x]["StripChars"] = parsedEntry[2]
				end
				--part 3 - add chars
				self.prefixRules[hpart1]["AffixEntries"][x]["AddChars"] = parsedEntry[3]
				--part 4 - conditions
				condCount = nil
				conditions = nil
				utf8Conditions = nil
				condCount, conditions, utf8Conditions = WordDict.AffixUtility:EncodeConditions(parsedEntry[4])
				self.prefixRules[hpart1]["AffixEntries"][x]["ConditionCount"] = condCount
				self.prefixRules[hpart1]["AffixEntries"][x]["Conditions"] = conditions
				self.prefixRules[hpart1]["AffixEntries"][x]["Utf8Conditions"] = utf8Conditions
			end
			row = row + 1
	end

end

function WordDict:LoadSuffixRules()
	local row = 1 --row pointer
	local rowCount = #DICTIONARY_TO_LOAD_FROM.Suffix

	local header
	local hparts
	local hpart1
	local hpart2
	local hpart3
	local rulecount
	local rule1
	local rule2
	local rule3
	local rule4
	local AllowCombine = false
	local entry
	local parsedEntry
	local condCount
	local conditions
	local utf8Conditions

	local s = DICTIONARY_TO_LOAD_FROM.Suffix

	while row < rowCount do
		header = s[row]
		-- headers are in 3 parts
		hparts = split(header, "%s+")
		hpart1 = hparts[1] -- Part 1 = affix key
		hpart2 = hparts[2] -- Part 2 = combine flag
		hpart3 = hparts[3] -- Part 3 = rule count

		--determin how many parts there are to this prefix
		rulecount = tonumber(hpart3)
		--print("Suffix Header", hpart1, hpart2, hpart3, "##", header, "##")


		AllowCombine = false
		if hpart2 == "Y" then AllowCombine = true end

		--Add header parts 1 & 2 to SuffixRules collection
		self.suffixRules[hpart1] = {["AllowCombine"]=AllowCombine, ["AffixEntries"]={}}

		--Rules have 4 parts
		--Part1: affix(prefix/suffix) key
		--Part2: strip char
		--Part3: add chars
		--Part4: conditions

		for x = 1, rulecount do
			row = row + 1
			entry = s[row]
			parsedEntry = split(entry, "%s+")

			--print("Suffix Entry:", entry, "##")
			--tprint(parsedEntry)

			self.suffixRules[hpart1]["AffixEntries"][x] = {}
			--part 2 - strip char
			if parsedEntry[2] == "0" then
				self.suffixRules[hpart1]["AffixEntries"][x]["StripChars"] = ""
			else
				self.suffixRules[hpart1]["AffixEntries"][x]["StripChars"] = parsedEntry[2]
			end
			--part 3 - add chars
			self.suffixRules[hpart1]["AffixEntries"][x]["AddChars"] = parsedEntry[3]
			--part 4 - conditions
			condCount = nil
			conditions = nil
			utf8Conditions = nil
			condCount, conditions, utf8Conditions = WordDict.AffixUtility:EncodeConditions(parsedEntry[4])
			self.suffixRules[hpart1]["AffixEntries"][x]["ConditionCount"] = condCount
			self.suffixRules[hpart1]["AffixEntries"][x]["Conditions"] = conditions
			self.suffixRules[hpart1]["AffixEntries"][x]["Utf8Conditions"] = utf8Conditions
		end
		row = row + 1
	end

end

WordDict.PhoneticUtility = {}

function WordDict.PhoneticUtility:EncodeRule(ruleText)

	local string_byte = string_byte
	local string_len = string_len
	local string_sub = string_sub

	if utf8 then
		string_byte = string_utf8byte
		string_len = string_utf8len
		string_sub = string_utf8sub
	end

	local group = false  	--Group indicator
	local groupend = false	--end contition indicator

	local memberChars = {}
	local numMember = 0		-- number of member in groupend

	local BeginningOnly = false
	local EndOnly = false
	local ConsumeCount = 0
	local ReplaceMode = false
	local Priority = 0
	local ConditionCount = 0
	local cond
	local charCode

	local Rule = {}
	Rule["Condition"] = {}
	Rule["ConsumeCount"] = 0

	--for j = 0, 255 do
	--	RuleCondition[j] = 0
	--end

	--print("ruletext", ruleText)

	for i = 1, string_len(ruleText) do
		cond = string_sub(ruleText, i, i)
		--print("i", i, "cond", cond)

		if cond == "(" then group = true
		elseif cond == ")" then endgroup = true
		elseif cond == "^" then
			BeginningOnly = true
			Rule["BeginningOnly"] = true
		elseif cond == "$" then
			EndOnly = true
			Rule["EndOnly"] = true
		elseif cond == "-" then
			ConsumeCount = ConsumeCount + 1
			Rule["ConsumeCount"] = ConsumeCount
		elseif cond == "<" then
			ReplaceMode = true
			Rule["ReplaceMode"] = true
		--local p = tonumber(cond)
		elseif tonumber(cond) ~= nil then
			Priority = tonumber(cond)
			Rule["Priority"] = Priority
		else
			if group == true then
				--add chars to group
				memberChars[numMember] = cond
				numMember = numMember + 1
			else
				endgroup = true
			end
		end
		if endgroup == true then
			if group == true then
				--turn on chars in member group
				for j = 0, numMember - 1 do
					charCode = string_byte(memberChars[j])
					Rule["Condition"][charCode] = bit_bor(Rule["Condition"][charCode] or 0, bit_lshift(1, ConditionCount))
				end
				group = false
				numMember = 0
			else
				--turn on char
				charCode = string_byte(cond)
				Rule["Condition"][charCode] = bit_bor(Rule["Condition"][charCode] or 0, bit_lshift(1, ConditionCount))
			end
			endgroup = false
			ConditionCount = ConditionCount + 1
			Rule["ConditionCount"] = ConditionCount
		end
	end
	return Rule
end

function WordDict:LoadPhoneticRules()
	local pr = DICTIONARY_TO_LOAD_FROM.Phonetic

	--Phonetic rules are in 2 parts
	--Part1: Encoded Rule
	--Part2: ReplaceString
	for i, v in ipairs(pr) do
		parsedrule = split(v, "%s+")
		--self.phoneticRules[i]= {parsedrule[1], parsedrule[2]}
		self.phoneticRules[i] = WordDict.PhoneticUtility:EncodeRule(parsedrule[1])
		self.phoneticRules[i]["ReplaceString"] = parsedrule[2]

	end
end

function WordDict:LoadWords()
	local w = DICTIONARY_TO_LOAD_FROM.Words

	local baseWord
	local affixKeys
	local phoneticCode
	local parse = {}

	for i, v in ipairs(w) do
		-- split word input line into its parts
		--Part1: base word
		--Part2: affix keys
		--Part3: phonetic code
		--       Note: Some languanges don't have phonetic info,
		--		 and just use the Generic Phonetic method.
		parse = split(v, "/")
		baseWord = parse[1]
		if parse[2] ~= nil then
			affixKeys = parse[2]
		else
			affixKeys = ""
		end
		if parse[3] ~= nil then
			phoneticCode = parse[3]
		elseif self.soundslike == "Generic" then
			phoneticCode = self:GenericSoundsLike(baseWord)
		else
			phoneticCode = ""
		end


		--(r18) Don't store the affixKeys and phoneticCode in a sub table
		--Saves 6MB of memory.
		--self.baseWords[baseWord] = {affixKeys, phoneticCode}
		self.baseWords[baseWord] = affixKeys .."/" .. phoneticCode
	end
end

--Generates a phonetic code of how the word sounds based on phonetic
--ruless loaded from the dictionary
--Input: word (string)
--Return: a code of how the word sounds
function WordDict:PhoneticCode(word)
	local string_byte = string_byte
	local string_len = string_len
	local string_upper = string_upper
	local string_sub = string_sub

	if utf8 then
		string_byte = string_utf8byte
		string_len = string_utf8len
		string_sub = string_utf8sub
		string_upper = string_utf8upper
	end

	local tempWord = string_upper(word)
	local prevWord = ""
	local code = ""

	local begining
	local ending
	local passCount
	local charCode
	local ruleCondition

	while #tempWord > 0 do
		--save previous word
		prevWord = tempWord

		for i,v in ipairs(self.phoneticRules) do
			begining = false
			ending = false
			if #tempWord == #word then
				begining = true
			end
			if v.ConditionCount == string_len(tempWord) then
				ending = true
			end

			if ((v.BeginningOnly == begining or not v.BeginningOnly)
				and (v.EndOnly == ending or not v.EndOnly)
				and (v.ConditionCount <= string_len(tempWord))) then

				passCount = 0
				-- loop through conditions
				for i = 1, v.ConditionCount do
					charCode = string_byte(string_sub(tempWord, i, i))
					ruleCondition = v.Condition[charCode] or 0

					if bit_band(ruleCondition, bit_lshift(1, i-1)) == bit_lshift(1, i-1) then
						passCount = passCount + 1 -- condition passed
					else
						break -- rule fails if on condition fails
					end
				end
				-- if all conditions passed
				if passCount == v.ConditionCount then
					if v.ReplaceMode == true then
						tempWord = v.ReplaceString .. string_sub(tempWord, v.ConditionCount - v.ConsumeCount + 1, -1)
					else
						if v.ReplaceString ~= "_" then
							code = code .. v.ReplaceString
						end
						tempWord = string_sub(tempWord, v.ConditionCount - v.ConsumeCount + 1)
					end
					break
				end
			end
		end

		-- if no match consume one char
		if #prevWord == #tempWord then
			tempWord = string_sub(tempWord, 2)
		end
	end
	return code
end

local AccentTransformations={
	["á"]="a",["à"]="a",["ã"]="a",["â"]="a",["å"]="a",["ä"]="a",
	["ç"]="c",
	["é"]="e",["è"]="e",["ë"]="e",["ê"]="e",
	["í"]="i",["ì"]="i",["ï"]="i",["î"]="i",
	["ñ"]="n",
	["ó"]="o",["ò"]="o",["õ"]="o",["ô"]="o",["ö"]="o",["ø"]="o",
	["ù"]="u",["û"]="u",["ú"]="u",["ü"]="u",
	["ÿ"]="y",["ý"]="y",
	["Á"]="A",["À"]="A",["Ã"]="A",["Â"]="A",["Å"]="A",["Ä"]="A",
	["Ç"]="C",
	["É"]="E",["È"]="E",["Ë"]="E",["Ê"]="E",
	["Í"]="I",["Ì"]="I",["Ï"]="I",["Î"]="I",
	["Ñ"]="N",
	["Ó"]="O",["Ò"]="O",["Õ"]="O",["Ô"]="O",["Ö"]="O",["Ø"]="0",
	["Ù"]="U",["Û"]="U",["Ú"]="U",["Ü"]="U",
	["Ý"]="Y",["Ÿ"]="Y",
	["Ð"]="D",
	["Œ"]="OE",
	["Þ"]="TH",
	["æ"]="AE",
	["ð"]="d",
	["œ"]="oe",
	["ß"]="ss",
	["þ"]="th"
}
local function removeAccents(text)
	return string_gsub(text, ".", AccentTransformations)
end

--Returns a generic sounds like code, for languanges that don't specify phonetic codes in their dirctionaries,
--and choose to use this "Generic" function in it's place.  Should work for Spanish and French.
--Remove all accents, vowels, and numbers.  Then uppercase the string, and return non repeating characters.
--Example: "herrmanóÞ" returns "HRMNTH"
--Hopefully this code doesn't need to worry about UTF8 because we remove all Accents
function WordDict:GenericSoundsLike(text)
	if text == nil then return "" end
	if #text == 0 then return "" end

	local s = string.upper(removeAccents(text))
	local sRet = ""
	local cPrev
	local cCurr

	s = string.gsub(s, "[AEIOUY0-9]", "")

	if #s >0 then
		cPrev = string.sub(s,1,1)
		sRet = cPrev

		for i = 1, #s do
			cCurr = string.sub(s,i,i)
			if cCurr ~= cPrev then
				sRet = sRet .. cCurr
				cPrev = cCurr
			end
		end
	end
	return sRet
end


--Searched all containted word lists for word
function WordDict:Contains(word)
	--save the word we're checking, so if someone calls Suggest(word)
	--without first calling Contains, we can, call Contains() to refresh the
	--possibleBaseWords list.
	self.lastContainsWord = word

	--clean up possible base word lists
	self.possibleBaseWords = {}

	--Step1: If word length is 1 char, return true
	if #word == 1 then
		return true
	end

	--Step2: search BaseWords
	if self.baseWords[word] ~= nil then
		return true
	end

	--Step3: Remove suffix, then search basewords
	-- save suffixed words for use when removing prefix
	local suffixWords = {}

	suffixWords[word] = 1

	--tprint(self.suffixRules)
	local tempWord
	local baseWordTemp
	local affixKeys
	for key, rule in pairs(self.suffixRules) do
		--print("suffix rule: ", key)
		for x, entry in ipairs(rule.AffixEntries) do
			--print("word/AffixEntry addchars", word, entry.AddChars)
			--tprint(entry)

			tempWord = WordDict.AffixUtility:RemoveSuffix(word, entry)
			if tempWord ~= word then
				baseWordTemp = self.baseWords[tempWord]
				if baseWordTemp ~= nil then
					affixKeys = string_sub(baseWordTemp, 1, (string_find(baseWordTemp, "/") -1))
					--make sure base word has this affix key
					if string_find(affixKeys, key) ~= nil then
						return true --word found
					end
				end

				if rule.AllowCombine == true then
					-- saving word to check if it is a word after prefix is removed
					suffixWords[tempWord] = 1
				else
					-- saving possible base words for use in generating suggestions
					self.possibleBaseWords[tempWord] = 1
				end
			end
		end
	end
	--save possible base words for use in generating suggestions
	for k, v in pairs(suffixWords) do
		self.possibleBaseWords[k] = 1
	end

	--Step4: Remove prefix, then search basewords
	for key, rule in pairs(self.prefixRules) do
		for x, entry in ipairs(rule.AffixEntries) do
			for suffixWord, y in pairs(suffixWords) do
				tempWord = WordDict.AffixUtility:RemovePrefix(suffixWord, entry)
				if tempWord ~= suffixWord then
					baseWordTemp = self.baseWords[tempWord]
					if baseWordTemp ~= nil then
						--make sure base word has this affix keys
						affixKeys = string_sub(baseWordTemp, 1, (string_find(baseWordTemp, "/") -1))

						if string_find(affixKeys, key) ~= nil then
							return true --word found
						end
					end

					--save possible base workd for use in generating suggestions
					self.possibleBaseWords[tempWord] = 1
				end
			end
		end
	end

	return false
end

--Expands an affix compressed base word
--takes in a base word entry with coresponsind affix & phonetic info
--returns a table of the expanded words
function WordDict:ExpandWord(word, affixKeys)
	local suffixWords = {}
	local words = {}

	local string_len = string_len
	local string_sub = string_sub

	if utf8 then
		string_len = string_utf8len
		string_sub = string_utf8sub
	end

	--add word to the suffixWords table
	suffixWords[word] = 1
	local prefixKeys = ""

	-- check suffix keys first
	local key
	local rule
	local tempWord
	for x=1, string_len(affixKeys) do
		key = string_sub(affixKeys, x, x)
		if WordDict.suffixRules[key] ~= nil then
			rule = WordDict.suffixRules[key]
			tempWord = WordDict.AffixUtility:AddSuffix(word, rule)
			if tempWord ~= word then
				if rule.AllowCombine == true then
					suffixWords[tempWord] = 1
				else
					words[tempWord] = 1
				end
			end
		elseif WordDict.prefixRules[key] ~= nil then
			prefixKeys = prefixKeys..key
		end
	end

	--apply prefixes
	for x = 1, string_len(prefixKeys) do
		key = string_sub(prefixKeys, x, x)
		rule = WordDict.prefixRules[key]
		for suffixWord,v in pairs(suffixWords) do
			tempWord = WordDict.AffixUtility:AddPrefix(suffixWord, rule)
			if tempWord ~= suffixWord then
				words[tempWord] = 1
			end
		end
	end

	for key,v in pairs(suffixWords) do
		words[key] = 1
	end
	return words
end

--Calculated the minimum number of changes, inserts of deletes
--required to change the firstWord into the secondWord
--PositionPriority: set to true if the first and last char should have priority
function WordDict:EditDistance(source, target)
	local string_len = string_len
	local string_lower = string_lower
	local string_sub = string_sub

	if utf8 == true then
		string_len = string_utf8len
		string_lower = string_utf8lower
		string_sub = string_utf8sub
	end

	local m = string_len(source)
	local n = string_len(target)

	if n == 0 then return m end
	if m == 0 then return n end

	if source == "teh" and target == "the" then return 0.1 end
	
	local rows = {}
	rows[0] = {[0]=0}

	for x=0, m+1 do
		rows[x] = {[0]=0}
		for y=0,n do
			rows[x][y] = 0
		end
	end

	--tprint(rows)

	for i=0,m do
		rows[i][0] = i
	end

	for j=0,n do
		rows[0][j] = j
	end

	--Ignore if the strings that only differ by case
	source = string_lower(source)
	target = string_lower(target)

	--tprint(rows)
	local subsitutionCost

	for i=1, m do
		for j=1,n do
			if string_sub(source, i, i) == string_sub(target, j, j) then
				subsitutionCost = 0
			else
				subsitutionCost = 1
			end

			rows[i][j] = math_min(	rows[i-1][j] + 1, 					--Insertion
									rows[i][j-1] + 1, 					--Deletion
									rows[i-1][j-1] + subsitutionCost)	--Substitution
		end
	end

	local dist = rows[m][n]

	-- extra edit on first and last chars if position Priority is important
	if string_sub(source, 1, 1) ~= string_sub(target, 1, 1) then
		dist = dist + 1
	end

	if string_sub(source, -1) ~= string_sub(target, -1) then
		dist = dist + 1
	end

	--potential additional
	-- If every character in sounce is in target, give it priority
	--and if every character in target is also in source, give it even more priority.
--~ 	public int EditDistance(string source, string target, bool positionPriority)
--~ 	{
--~ 	string testasciiSource = source.ToLower();
--~ 	string testasciiTarget = target.ToLower();
--~ 	int dist = -1;

--~ 	// If every character in source is also in target, give it priority

--~ 	bool subset = false;
--~		if (Math.Abs(testasciiTarget.Length - testasciiSource.Length) <= 1)
--~		{
--~			subset = true;
--~ 		for (int i = 0; i < testasciiSource.Length; i++)
--~ 		if (testasciiTarget.IndexOf(testasciiSource[i]) == -1)
--~ 		{
--~ 			subset = false;
--~ 			break;
--~ 		}
--~		}

--~ 	// If every character in target is also in source, give it even more priority

--~ 	if (subset)
--~ 	{
--~ 	dist--;
--~ 	for (int i = 0; i < testasciiTarget.Length; i++)
--~ 	if (testasciiSource.IndexOf(testasciiTarget[i]) == -1)
--~ 	{
--~ 	dist++;
--~ 	break;
--~ 	}
--~ 	}

--~ 	if (!subset)
--~ 	{
--~ 	// i.e. 2-D array
--~ 	Array matrix = Array.CreateInstance(typeof(int), source.Length+1, target.Length+1);

--~ 	// boundary conditions
--~ 	matrix.SetValue(0, 0, 0);

--~ 	for(int j=1; j <= target.Length; j++)
--~ 	{
--~ 	// boundary conditions
--~ 	int val = (int)matrix.GetValue(0,j-1);
--~ 	matrix.SetValue(val+1, 0, j);
--~ 	}

--~ 	// outer loop
--~ 	for(int i=1; i <= source.Length; i++)
--~ 	{
--~ 	// boundary conditions
--~ 	int val = (int)matrix.GetValue(i-1, 0);
--~ 	matrix.SetValue(val+1, i, 0);

--~ 	// inner loop
--~ 	for(int j=1; j <= target.Length; j++)
--~ 	{
--~ 	int diag = (int)matrix.GetValue(i-1, j-1);

--~ 	if(source.Substring(i-1, 1) != target.Substring(j-1, 1))
--~ 	{
--~ 	diag++;
--~ 	}

--~ 	int deletion = (int)matrix.GetValue(i-1, j);
--~ 	int insertion = (int)matrix.GetValue(i, j-1);
--~ 	int match = Math.Min(deletion+1, insertion+1);
--~ 	matrix.SetValue(Math.Min(diag, match), i, j);
--~ 	}//for j
--~ 	}//for i

--~ 	dist = (int)matrix.GetValue(source.Length, target.Length);
--~ 	}

--~ 	// extra edit on first and last chars
--~ 	if (positionPriority)
--~ 	{
--~ 	if (source[0] != target[0]) dist++;
--~ 	if (source[source.Length-1] != target[target.Length-1]) dist++;
--~ 	}
--~ 	return dist;
--~ 	}

	--tprint(rows)

	return dist
end



--returns true if word or lower(word) are in baseWords
function WordDict:TestWord(word)
	if WordDict:Contains(word) == true then
		return true
	end

	--check the lower case version of the word, if it contains a capitol
	local w
	if utf8 == false then
		w = string_lower(word)
		if w ~= word then
			if WordDict:Contains(w) == true  then
				return true
			end
		end
	else
		w = string_utf8lower(word)
		if w ~= word then
			if WordDict:Contains(w) == true  then
				return true
			end
		end
	end

	return false
end


function WordDict:FirstCapital(currentWord)
	local suggestions = {}
	local suggestionsCount = 0

	local string_upper = string_upper
	local string_sub = string_sub

	if utf8 == true then
		string_upper = string_utf8upper
		string_sub = string_utf8sub
	end

	local testWord = string_upper(string_sub(currentWord, 1, 1)) .. string_lower(string_sub(currentWord, 2))

	if self:TestWord(testWord) == true then
		suggestions[testWord] = self:EditDistance(currentWord, testWord)
		suggestionsCount = 1
	end

	return suggestions, suggestionsCount
end

--suggestions for a typical fault of spelling, that
--differs with more, than 1 letter from the right form.
function WordDict:ReplaceChars(CurrentWord)
	local suggestions = {}
	local suggestionsCount = 0

	local string_lower = string_lower
	--local string_sub = string_sub

	if utf8 then
		string_lower = string_utf8lower
		--string_sub = string_utf8sub
	end

	--Test each set of replacement (key, replacement) pairs.
	for i = 1, #self.replaceChars do
		local key
		local replacement
		local testWord = CurrentWord
		local keyMatches = - 1
		local pos1, pos2
		local atEnd = false

		key, replacement = unpack(split(self.replaceChars[i], "%s+"))

		pos1, pos2 = string_find(CurrentWord, key, 1, true)
		if pos2 == #CurrentWord then
			atEnd = true
		end
		while pos1 ~= nil do
			testWord = string_sub(testWord, 1, pos1 -1) .. replacement .. string_sub(testWord, pos2 + 1)

			if self:TestWord(testWord) == true then
				suggestions[string_lower(testWord)] = self:EditDistance(CurrentWord, testWord)
				suggestionsCount = suggestionsCount + 1
			end

			if atEnd == true then
				break
			end

			pos1, pos2 = string_find(CurrentWord, key, pos1 + 1, true)
			if pos2 == #testWord then
				atEnd = true
			end
		end
	end

	return suggestions, suggestionsCount
end


--swap out each char one by one and try all the tryme chars
--in its place to see if that makes a good word
function WordDict:BadChar(CurrentWord)
	local suggestions = {}
	local suggestionsCount = 0

	local tempWord = {}
	local testWord
	local saveChar
	local tryChar
	local string_len = string_len
	local string_sub = string_sub
	local string_lower = string_lower

	if utf8 then
		string_len = string_utf8len
		string_sub = string_utf8sub
		string_lower = string.utf8lower
	end

	for i=1, string_len(CurrentWord) do
		tempWord[i] = string_sub(CurrentWord, i, i)
	end

	for i=1, string_len(CurrentWord) do
		saveChar = tempWord[i]

		for x=1, string_len(self.tryChars) do
			tryChar = string_sub(self.tryChars, x, x)
			if tempWord[i] ~= tryChar then
				tempWord[i] = tryChar

				testWord = table_concat(tempWord)

				if self:TestWord(testWord) == true then
					suggestions[string_lower(testWord)] = self:EditDistance(CurrentWord, testWord)
					suggestionsCount = suggestionsCount + 1
				end
			end
		end

		tempWord[i] = saveChar
	end

	return suggestions, suggestionsCount
end

--try omitting one char of word at a time
function WordDict:ExtraChar(CurrentWord)
	local suggestions = {}
	local suggestionsCount = 0
	local tempWord

	local string_len = string_len
	local string_sub = string_sub
	local string_lower = string_lower

	if utf8 == true then
		string_len = string_utf8len
		string_sub = string_utf8sub
		string_lower = string_utf8lower
	end

	if string_len(CurrentWord) > 1 then
		for i=1, string_len(CurrentWord) do
			tempWord = string_sub(CurrentWord, 0, i-1) .. string_sub(CurrentWord, i+1)

			if self:TestWord(tempWord) == true then
				suggestions[string_lower(tempWord)] = self:EditDistance(CurrentWord, tempWord)
				suggestionsCount = suggestionsCount + 1
			end
		end
	end

	return suggestions, suggestionsCount
end


--try inserting a tryme character before every letter
function WordDict:ForgotChar(CurrentWord)
	local suggestions = {}
	local suggestionsCount = 0
	local tempWord
	local tryme = self.tryChars

	local string_len = string_len
	local string_sub = string_sub
	local string_lower = string_lower

	if utf8 == true then
		string_len = string_utf8len
		string_sub = string_utf8sub
		string_lower = string_utf8lower
	end

	for i=1, string_len(CurrentWord) do
		for x=1, string_len(tryme) do
			tempWord = string_sub(CurrentWord, 0, i) .. string_sub(tryme, x, x) .. string_sub(CurrentWord, i+1)
			if self:TestWord(tempWord) == true then
				suggestions[string_lower(tempWord)] = self:EditDistance(CurrentWord, tempWord)
				local suggestionsCount = suggestionsCount + 1
			end
		end
	end

	return suggestions, suggestionsCount
end

--try swapping adjacent chars one by one
function WordDict:SwapChar(CurrentWord)
	local suggestions = {}
	local suggestionsCount = 0
	local tempWord = {}
	local swap
	local testWord

	local string_len = string_len
	local string_sub = string_sub
	local string_lowr = string_lower

	if utf8 == true then
		string_len = string_utf8len
		string_sub = string_utf8sub
		string_lower = string_utf8lower
	end

	for i=1, string_len(CurrentWord) - 1 do
		tempWord = {}
		for x=1, string_len(CurrentWord) do
			tempWord[x] = string_sub(CurrentWord, x, x)
		end

		swap = tempWord[i]
		tempWord[i] = tempWord[i+1]
		tempWord[i+1] = swap

		testWord = table_concat(tempWord)

		if self:TestWord(testWord) == true then
			suggestions[string_lower(testWord)] = self:EditDistance(CurrentWord, testWord)
			suggestionsCount = suggestionsCount + 1
		end
	end

	return suggestions, suggestionsCount
end


--split the string into two pieces after every char
--if both pieces are good words make them a suggestion
function WordDict:TwoWords(CurrentWord)
	local suggestions = {}
	local suggestionsCount = 0

	local string_len = string_len
	local string_sub = string_sub
	local string_lower = string_lower

	if utf8 == true then
		string_len = string_utf8len
		string_sub = string_utf8sub
		string_lower = string_utf8lower
	end

	if #CurrentWord < 3 then
		return suggestions, suggestionsCount
	end

	local firstWord
	local secondWord
	local tempWord

	for i=1, string_len(CurrentWord) -2 do
		firstWord = string_sub(CurrentWord, 1, i)
		secondWord = string_sub(CurrentWord, i+1)

		if self:TestWord(firstWord) == true then
			if self:TestWord(secondWord) == true then
				tempWord = firstWord .. " " .. secondWord
				suggestions[tempWord] = self:EditDistance(CurrentWord, tempWord) + 0.5
				suggestionsCount = suggestionsCount + 1
			end
		end
	end

	return suggestions, suggestionsCount
end


function WordDict:Suggest(currentWord)
	--Reload the possibleBaseWords if Suggest() isn't being called right after Contains()
	if self.lastContainsWord ~= currentWord then
		WordDict:Contains(currentWord)
	end

	local tempSugCount = 0

	tempSuggestion = {}

	-- generate phonetic code for possible root word
	local codes = {}
	local tempCode

	for tempWord, v in pairs(WordDict.possibleBaseWords) do
		if tempWord ~= nil and #tempWord ~= 1 then
			if self.soundslike == "Phonetic" then
				tempCode = WordDict:PhoneticCode(tempWord)
			elseif self.soundslike == "Generic" then
				tempCode = WordDict:GenericSoundsLike(tempWord)
			else
				tempCode = ""
			end
			if #tempCode > 0 and codes[tempCode] == nil then
				codes[tempCode] = 1
			end
		end
	end

	local codeCount = 0
	for k,v in pairs(codes) do
		codeCount = codeCount + 1
	end

	local words = {}
	local editDistance
	local affixKeys
	local pCode

	if codeCount > 0 then
		--search root words for phonetic codes
		for word, v in pairs(WordDict.baseWords) do
			--check if this word's phonetic code matches a phonetic stored in codes
--~ 		affixKeys = string_sub(v, 1, (string_find(v, "/") -1))
--~ 		pCode = string_sub(v, (string_find(v, "/") + 1))
			--New version of above
			affixKeys, pCode = string_match(v, "(.*)/(.*)")
			if codes[pCode] ~= nil then
				words = {}
				words = WordDict:ExpandWord(word, affixKeys)
				--add expanded words
				for expandedWord,v in pairs(words) do
					editDistance = WordDict:EditDistance(currentWord, expandedWord)
					tempSuggestion[expandedWord] = editDistance
					tempSugCount = tempSugCount + 1
				end
			end
		end
	end

	--Obtain additional suggestions

	--check if the first letter should have been capitalized
	--print("Call: FirstCapital()", tempSugCount, "Mem:", collectgarbage("count"))
	for sWord, editDistance in pairs(self:FirstCapital(currentWord)) do
		tempSuggestion[sWord] = editDistance
		tempSugCount = tempSugCount + 1
	end

	--check if a char was typed in place of a replacementChar
	--print("Call: ReplaceChars()", tempSugCount, "Mem:", collectgarbage("count"))
	for sWord, editDistance in pairs(self:ReplaceChars(currentWord)) do
		tempSuggestion[sWord] = editDistance
		tempSugCount = tempSugCount + 1
	end

	--swap out each char on by one and try all the tryme
	--chars in its place to see if that makes a good word
	--print("Call: BadChar()", "", tempSugCount, "Mem:", collectgarbage("count"))
	if utf8 == false then
		for sWord, editDistance in pairs(self:BadChar(currentWord)) do
			tempSuggestion[sWord] = editDistance
			tempSugCount = tempSugCount + 1
		end
	end

	--try swapping adjcent chars on by one
	--print("Call: SwapChar()", tempSugCount, "Mem:", collectgarbage("count"))
	for sWord, editDistance in pairs(self:SwapChar(currentWord)) do
		tempSuggestion[sWord] = editDistance
		tempSugCount = tempSugCount + 1
	end

	--try inserting a tryme character before every letter
	--print("Call: ForgotChar()", tempSugCount, "Mem:", collectgarbage("count"))
	if utf8 == false then
		for sWord, editDistance in pairs(self:ForgotChar(currentWord)) do
			tempSuggestion[sWord] = editDistance
			tempSugCount = tempSugCount + 1
		end
	end

	--try ommitting one char of word at a time
	--print("Call: ExtraChar()", tempSugCount, "Mem:", collectgarbage("count"))
	for sWord, editDistance in pairs(self:ExtraChar(currentWord)) do
		tempSuggestion[sWord] = editDistance
		tempSugCount = tempSugCount + 1
	end

	--split the string into two pieces after every char
	--if both pieces are good words mak them a suggestions
	--print("Call: TwoWords()", tempSugCount, "Mem:", collectgarbage("count"))
	for sWord, editDistance in pairs(self:TwoWords(currentWord)) do
		tempSuggestion[sWord] = editDistance
		tempSugCount = tempSugCount + 1
	end


	--Sort the associative table holding suggestions, by EditDistance.
	local sorted = {}
	for w, d in pairs(tempSuggestion) do
		table_insert(sorted, {Word = w, EditDistance = d})
	end
	table_sort(sorted, function(A, B) return A.EditDistance < B.EditDistance end)

	--print("Sorted Table:")
	--tprint(sorted)

	WordDict.suggestions = {}


	for i, v in ipairs(sorted) do
		if v.EditDistance < self.maxEditDistance then
			table_insert(WordDict.suggestions, {Word = v.Word, EditDistance = v.EditDistance})

			if #self.suggestions >= self.maxSuggestions then
				break
			end
		end
	end

	return self.suggestions
end

function WordDict:Init(locale)

	if locale == nil then
		self.locale = GetLocale()
	else
		self.locale = locale
	end

	--Load the dictionary

	--If we don't have a languange specific dictionary, load the US English dictionary
	if self.locale == "ruRU" then
		DICTIONARY_TO_LOAD_FROM = WordDict_GetDictionary_ruRU()
		--utf8 = true
	elseif self.locale == "itIT" then		
		DICTIONARY_TO_LOAD_FROM = WordDict_GetDictionary_itIT()
		--utf8 = true
	elseif self.locale == "enGB" then		
		DICTIONARY_TO_LOAD_FROM = WordDict_GetDictionary_enGB()
		--utf8 = true
	elseif self.locale == "deDE" then
		DICTIONARY_TO_LOAD_FROM = WordDict_GetDictionary_deDE()
		--utf8 = false
	elseif self.locale == "esES" then
		DICTIONARY_TO_LOAD_FROM = WordDict_GetDictionary_esES()
		--utf8 = true
	elseif self.locale == "frFR" then
		DICTIONARY_TO_LOAD_FROM = WordDict_GetDictionary_frFR()
		--utf8 = true
	elseif self.locale == "enUS" then
		DICTIONARY_TO_LOAD_FROM = WordDict_GetDictionary_enUS()
		--utf8 = false
	else
		DICTIONARY_TO_LOAD_FROM = WordDict_GetDictionary_enUS()
		--utf8 = false
	end

	--set the dictionary functions to nil to free memory
	WordDict_GetDictionary_ruRU = nil
	WordDict_GetDictionary_itIT = nil
	WordDict_GetDictionary_enGB = nil
	WordDict_GetDictionary_deDE = nil
	WordDict_GetDictionary_esES = nil
	WordDict_GetDictionary_frFR = nil
	WordDict_GetDictionary_enUS = nil

	--Set the UTF8 flag
	utf8 = DICTIONARY_TO_LOAD_FROM.UTF8

	--Load the tryChars
	self.tryChars = DICTIONARY_TO_LOAD_FROM.Try[1]

	--Load the replaceChars
	for i, v in ipairs(DICTIONARY_TO_LOAD_FROM.Replace) do
		table_insert(self.replaceChars, v)
	end

	--Load Affix Rules
	self:LoadPrefixRules()
	self:LoadSuffixRules()

	--Some languanges just use the generic sounds like routine.
	self.soundslike = DICTIONARY_TO_LOAD_FROM.Soundslike
	if self.soundslike == "Phonetic" then
		--Load Phonetic Rules
		self:LoadPhoneticRules()
	end

	--Load the Base Words
	self:LoadWords()

	--Free the table we loaded the dictionary from
	DICTIONARY_TO_LOAD_FROM = nil

	--Collect Garbage to free up memory
	collectgarbage("collect")

	return self.locale
end

--[[
--testing

function tprint (t, indent, done)
  -- in case we run it standalone
  local Note = Note or print
  local Tell = Tell or io.write

  -- show strings differently to distinguish them from numbers
  local function show (val)
    if type (val) == "string" then
      return '"' .. val .. '"'
    else
      return tostring (val)
    end -- if
  end -- show
  -- entry point here
  done = done or {}
  indent = indent or 1
  for key, value in pairs (t) do
    Tell(string_rep (" ", indent)) -- indent it
    if type (value) == "table" and not done [value] then
      done [value] = true
      Note (show (key), ":");
      tprint (value, indent + 2, done)
    else
      Tell (show (key), "=")
      print (show (value))
    end
  end
end

function GetLocale() return "frFR" end
--function GetLocale() return "deDE" end
--function GetLocale() return "esES" end
--function GetLocale() return "enUS" end



--require("bit")

require("Dict\\Dic_" .. GetLocale())

WordDict:Init()

function test1()
	print("UTF8", utf8)

	--testword = "applepie"
	--testword = "hermonóo"
	--testword = "helpin"
	testword = "procrea"
	testword = "contraórdenes"
	testword = "holla"
	testword = "hóla"
	testword = "Bahammas"
	testword = "mehrstelling"
	testword = "abbürtsen"
	testword = "angstrœm"
	testword = "d'angstrœm"
	testword = "angstrœms"
	testword = "qu'a"
	print("Contains")
	print("Testing: " ..testword, WordDict:Contains(testword), "Len", string_utf8len(testword))
    tprint(WordDict:Suggest(testword))

	--s, sc = WordDict:ReplaceChars("holla")
	--tprint(s)

	tprint(WordDict:ExpandWord("a", "Q"))

	print("Phonetic Code:", WordDict:PhoneticCode("angstrœm"))
--	print(WordDict.AffixUtility:RemovePrefix("procrea", WordDict.prefixRules["o"]))
end


test1()

--~ print(string.utf8byte("Đ"))

--~ cnt,cc,ccc = WordDict.AffixUtility:EncodeConditions("[^eioĐ]ño")
--~ print("Condition Count:", cnt)
--~ tprint(ccc, 4)



--tprint(WordDict:Suggest(testword))


--~ print("len:", #"hermanó")
--~ print(WordDict:Contains("hermanos"))
--~ print(WordDict:Contains("hermonóo"))
--~ tprint(WordDict:Suggest("hermonó0"))

--print("Memory:", collectgarbage("count"))
--Timmer now = os.clock(); test(); print(os.clock() - now)
---]]
