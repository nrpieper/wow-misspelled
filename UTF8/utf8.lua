
-- $Id: utf8.lua 147nate 2009-06-01 $
--
--	Changes made by Nate:  Removed much of the argument checking
--	Added: string.utf8charToInt(c) and string.utf8byte(s, i, ...)
--
-- Provides UTF-8 aware string functions implemented in pure lua:
-- * string.utf8len(s)
-- * string.utf8sub(s, i, j)
-- * string.utf8reverse(s)
--
-- If utf8data.lua (containing the lower<->upper case mappings) is loaded, these
-- additional functions are available:
-- * string.utf8upper(s)
-- * string.utf8lower(s)
--
-- Added by Nathan Pieper
-- * string.utf8charToInt(c)
-- * string.utf8byte(s, i, ...)  -Poorly named.  returns (4 byte) 32bit number
--
-- All functions behave as their non UTF-8 aware counterparts with the exception
-- that UTF-8 characters are used instead of bytes for all units.

--[[
Copyright (c) 2006-2007, Kyle Smith
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the author nor the names of its contributors may be
      used to endorse or promote products derived from this software without
      specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]]

-- ABNF from RFC 3629
--
-- UTF8-octets = *( UTF8-char )
-- UTF8-char   = UTF8-1 / UTF8-2 / UTF8-3 / UTF8-4
-- UTF8-1      = %x00-7F
-- UTF8-2      = %xC2-DF UTF8-tail
-- UTF8-3      = %xE0 %xA0-BF UTF8-tail / %xE1-EC 2( UTF8-tail ) /
--               %xED %x80-9F UTF8-tail / %xEE-EF 2( UTF8-tail )
-- UTF8-4      = %xF0 %x90-BF 2( UTF8-tail ) / %xF1-F3 3( UTF8-tail ) /
--               %xF4 %x80-8F 2( UTF8-tail )
-- UTF8-tail   = %x80-BF
--

--UTF-8 Binary format of bytes in sequence:
--
--  1st Byte  2nd Byte  3rd Byte  4th Byte  Number of Free Bits  Maximum Expressible Unicode Value
--  0xxxxxxx                                          07         007F hex (127)
--  110xxxxx  10xxxxxx                          (5+6)=11         07FF hex (2047)
--  1110xxxx  10xxxxxx  10xxxxxx              (4+6+6)=16         FFFF hex (65535)
--  11110xxx  10xxxxxx  10xxxxxx  10xxxxxx  (3+6+6+6)=21         10FFFF hex (1,114,111)
--

-- The "x" characters in the table above represent the number of "Free Bits", those bits are empty and we can write to them.
-- The other bits are reserved for the UTF-8 format, they are used as headers / markers. 
-- Thanks to these headers, when the bytes are being read using the UTF-8 encoding, the computer knows, which bytes to read together and which separately.
-- The byte size of your character, after being encoded using the UTF-8 format, depends on how many bits you need to store.
-- In our case the "汉" character is exactly 2 bytes or 16bits: "01101100 01001001"
-- thus the size of our character after being encoded to UTF-8, 
-- will be 3 bytes or 24bits: "11100110 10110001 10001001"
-- because "3 UTF-8 bytes" have 16 Free Bits, which we can write to
--
--  A Chinese character:      汉
-- 	its Unicode value:        U+6C49
-- 	convert 6C49 to binary:   01101100 01001001
-- 	encode 6C49 as UTF-8:     11100110 10110001 10001001

local byte 	= string.byte
local char 	= string.char
local len	= string.len
local strcmputf8i = strcmputf8i -- WoW built in function: case-insensative string comparision accounting for UTF-8 chars, returning C style 0, 0<, 0>.

local utf8CodepointByteLenCache = {} -- cache of UTF-8 variable-width byte length of encoded Unicode code point.

-- Use the UTF8 header byte (first most byte) to determine the UFT8 variable-width encoded byte length of the codepoint: one to four
-- Conditional Logic: The function uses a series of conditional statements to determine the length based on the value of the first byte:
-- If byte is nil, it returns 0.
-- If byte is less than 0x80 (128 in decimal), it returns 1, indicating a single-byte UTF-8 character.
-- If byte is greater than or equal to 0xF0 (240 in decimal), it returns 4, indicating a four-byte UTF-8 character.
-- If byte is between 0xE0 (224 in decimal) and 0xEF (239 in decimal), it returns 3, indicating a three-byte UTF-8 character.
-- If byte is between 0xC0 (192 in decimal) and 0xDF (223 in decimal), it returns 2, indicating a two-byte UTF-8 character.
local function utf8CodepointByteLen(byte)
  if type(byte) ~= "number" then
    error("bad argument #1 to 'utf8CodepointByteLen' (number expected, got ".. type(byte).. ")")
  end

  return not byte and 0 or (byte < 0x80 and 1) or (byte >= 0xF0 and 4) or (byte >= 0xE0 and 3) or (byte >= 0xC0 and 2) or 1
end

-- Populate the cache utf8codepointlenCache with 256 values to indicate the UTF-8 sequence byte length 
-- for a given UTF-8 encoding beginning with the given URF-8 header byte value at the array index
for i = 0, 255 do
	utf8CodepointByteLenCache[i] = utf8CodepointByteLen(i)
end

-- Return the number of bytes used to encode a UTF-8 character at byte pos in string str.
local function utf8CharByteLen(str, bytePos)
	-- lookup UTF-8 encoded character byte length from cache
  return utf8CodepointByteLen[byte(str, bytePos) or 256]
end

-- Given string: str as an array of bytes, return the byte postition of the next UTF-8 character in the string,
-- after the UTF-8 encoeed character at byte postiion: pos.
local function utf8NextCharPosition(str, bytePos)
  return bytePos + utf8CharByteLen(str, bytePos)
end


-- returns the number of bytes used by the UTF-8 character at byte i in string s
-- also doubles as a UTF-8 character validator
local function utf8charbytes (s, i)
	-- argument defaults
	i = i or 1

	-- argument checking
 	if type(s) ~= "string" then
 		error("bad argument #1 to 'utf8charbytes' (string expected, got ".. type(s).. ")")
 	end
 	if type(i) ~= "number" then
 		error("bad argument #2 to 'utf8charbytes' (number expected, got ".. type(i).. ")")
 	end

	local c = s:byte(i)

	-- determine bytes needed for character, based on RFC 3629
	-- validate byte 1
	if c > 0 and c <= 127 then
		-- UTF8-1
		return 1

	elseif c >= 194 and c <= 223 then
		-- UTF8-2
--~ 		local c2 = s:byte(i + 1)

--~ 		if not c2 then
--~ 			error("UTF-8 string terminated early")
--~ 		end

--~ 		-- validate byte 2
--~ 		if c2 < 128 or c2 > 191 then
--~ 			error("Invalid UTF-8 character")
--~ 		end

		return 2

	elseif c >= 224 and c <= 239 then
		-- UTF8-3
--~ 		local c2 = s:byte(i + 1)
--~ 		local c3 = s:byte(i + 2)

--~			if not c2 or not c3 then
--~ 			error("UTF-8 string terminated early")
--~ 		end

--~ 		-- validate byte 2
--~ 		if c == 224 and (c2 < 160 or c2 > 191) then
--~ 			error("Invalid UTF-8 character")
--~ 		elseif c == 237 and (c2 < 128 or c2 > 159) then
--~ 			error("Invalid UTF-8 character")
--~ 		elseif c2 < 128 or c2 > 191 then
--~ 			error("Invalid UTF-8 character")
--~ 		end

--~ 		-- validate byte 3
--~ 		if c3 < 128 or c3 > 191 then
--~ 			error("Invalid UTF-8 character")
--~ 		end

		return 3

	elseif c >= 240 and c <= 244 then
		-- UTF8-4
--~ 		local c2 = s:byte(i + 1)
--~ 		local c3 = s:byte(i + 2)
--~ 		local c4 = s:byte(i + 3)

--~ 		if not c2 or not c3 or not c4 then
--~ 			error("UTF-8 string terminated early")
--~ 		end

--~ 		-- validate byte 2
--~ 		if c == 240 and (c2 < 144 or c2 > 191) then
--~ 			error("Invalid UTF-8 character")
--~ 		elseif c == 244 and (c2 < 128 or c2 > 143) then
--~ 			error("Invalid UTF-8 character")
--~ 		elseif c2 < 128 or c2 > 191 then
--~ 			error("Invalid UTF-8 character")
--~ 		end

--~ 		-- validate byte 3
--~ 		if c3 < 128 or c3 > 191 then
--~ 			error("Invalid UTF-8 character")
--~ 		end

--~ 		-- validate byte 4
--~ 		if c4 < 128 or c4 > 191 then
--~ 			error("Invalid UTF-8 character")
--~ 		end

		return 4

	else
		error("Invalid UTF-8 character: " .. tostring(c))
	end
end


-- returns the number of characters in a UTF-8 string
local function utf8len (s)
 	-- argument checking
 	if type(s) ~= "string" then
 		error("bad argument #1 to 'utf8len' (string expected, got ".. type(s).. ")")
 	end

	local pos = 1
	local bytes = len(s)
	local len = 0

	while pos <= bytes do
		len = len + 1
		pos = pos + utf8CharByteLen(s, pos)
	end

	return len
end

-- install in the string library
if not string.utf8len then
	if strlenutf8 then  -- WoW supplied UTF8 string length function (20x faster)
		string.utf8len = strlenutf8
	else
		string.utf8len = utf8len
	end
end

-- Expose the urf8len function here for performance comparison testing with strlenutf8 in WoW
if not string.utf8lenold then
	string.utf8lenold = utf8len
end

-- returns a 32bit integer representation of the UTF-8 character
local function utf8charToInt(c)
 	--argument checking
 	if type(c) ~= "string" then
 		error("bad argument #1 to 'utf8chartoInt' (string expected, got ".. type(c).. ")")
 	end

	local pos = 1
	local bytes = c:len()
	local ret = c:byte(pos)

	for pos = 2, bytes do
		ret = bit.lshift(ret, 8)
		ret = bit.bor(ret, c:byte(pos))
	end

	return ret
end

--install in the string library
if not string.utf8charToInt then
	string.utf8charToInt = utf8charToInt
end

--print(string.utf8charToInt("Đ"))
--print(string.byte("Đ", 1, 2, 3, 4))

-- functions identically to string.sub except that i and j are UTF-8 characters
-- instead of bytes
local function utf8sub (s, i, j)
	-- argument defaults
	j = j or -1

 	-- argument checking
 	if type(s) ~= "string" then
 		error("bad argument #1 to 'utf8sub' (string expected, got ".. type(s).. ")")
 	end
 	if type(i) ~= "number" then
 		error("bad argument #2 to 'utf8sub' (number expected, got ".. type(i).. ")")
 	end
 	if type(j) ~= "number" then
 		error("bad argument #3 to 'utf8sub' (number expected, got ".. type(j).. ")")
 	end

	local pos = 1
	local bytes = s:len()
	local len = 0

	-- only set l if i or j is negative
	local l = (i >= 0 and j >= 0) or utf8len(s)
	local startChar = (i >= 0) and i or l + i + 1
	local endChar   = (j >= 0) and j or l + j + 1

	-- can't have start before end!
	if startChar > endChar then
		return ""
	end

	-- byte offsets to pass to string.sub
	local startByte, endByte = 1, bytes

	while pos <= bytes do
		len = len + 1

		if len == startChar then
			startByte = pos
		end

		pos = pos + utf8charbytes(s, pos)

		if len == endChar then
			endByte = pos - 1
			break
		end
	end

	return s:sub(startByte, endByte)
end

-- install in the string library
if not string.utf8sub then
	string.utf8sub = utf8sub
end


--functions acts like string.byte (s [, i [, j]])
--function returns the 4byte integer/s for a utf8 char as pos 'i' through 'j' in string 's'
function utf8byte(s, ...)
 	-- argument checking
 	if type(s) ~= "string" then
 		error("bad argument #1 to 'utf8sub' (string expected, got ".. type(s).. ")")
 	end

	local arg = {...}
	if #arg > 0 then
		for x = 1, #arg do
			arg[x] = utf8charToInt(utf8sub(s, arg[x], arg[x]))
		end
	else
		return utf8charToInt(utf8sub(s, 1, 1))
	end

	return i, unpack(arg)
end

--install in the string library
if not string.utf8byte then
	string.utf8byte = utf8byte
end

--print(utf8byte("ACĐ", 1, 2, 3))  --Đ


-- replace UTF-8 characters based on a mapping table
local function utf8replace (s, mapping)
 	-- argument checking
 	if type(s) ~= "string" then
 		error("bad argument #1 to 'utf8replace' (string expected, got ".. type(s).. ")")
 	end
 	if type(mapping) ~= "table" then
 		error("bad argument #2 to 'utf8replace' (table expected, got ".. type(mapping).. ")")
 	end

	local pos = 1
	local bytes = s:len()
	local charbytes
	local newstr = ""

	while pos <= bytes do
		charbytes = utf8charbytes(s, pos)
		local c = s:sub(pos, pos + charbytes - 1)

		newstr = newstr .. (mapping[c] or c)

		pos = pos + charbytes
	end

	return newstr
end


-- identical to string.upper except it knows about unicode simple case conversions
local function utf8upper (s)
	return utf8replace(s, utf8_lc_uc)
end

-- install in the string library
if not string.utf8upper and utf8_lc_uc then
	string.utf8upper = utf8upper
end


-- identical to string.lower except it knows about unicode simple case conversions
local function utf8lower (s)
	return utf8replace(s, utf8_uc_lc)
end

-- install in the string library
if not string.utf8lower and utf8_uc_lc then
	string.utf8lower = utf8lower
end


-- identical to string.reverse except that it supports UTF-8
local function utf8reverse (s)
 	-- argument checking
 	if type(s) ~= "string" then
 		error("bad argument #1 to 'utf8reverse' (string expected, got ".. type(s).. ")")
 	end

	local bytes = s:len()
	local pos = bytes
	local charbytes
	local newstr = ""
	local c

	while pos > 0 do
		c = s:byte(pos)
		while c >= 128 and c <= 191 do
			pos = pos - 1
			c = s:byte(pos)
		end

		charbytes = utf8charbytes(s, pos)

		newstr = newstr .. s:sub(pos, pos + charbytes - 1)

		pos = pos - 1
	end

	return newstr
end

-- install in the string library
if not string.utf8reverse then
	string.utf8reverse = utf8reverse
end
