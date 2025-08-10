--from: https://gist.github.com/markandgo/5130894#file-asserts-lua

local assert    = assert
local tostring  = tostring
local pcall     = pcall

local FORMAT_ASSERT_EQUALS  = 'expected %s to be equal to %s'
local FORMAT_ASSERT_UNEQ    = 'all values are %s'

asserteq = function(...)
	local values = {...}
	local first  = values[1]
	local i = 2
	repeat
		if first ~= values[i] then error(FORMAT_ASSERT_EQUALS:format(tostring(first),tostring(values[i]))) end
		i=i+1
	until not values[i]
end

assertnoteq = function(...)
	local values = {...}
	local first  = values[1]
	local i = 2
	repeat
		if first ~= values[i] then 
			return
		end
		i=i+1
	until not values[i]
	error(FORMAT_ASSERT_UNEQ:format(tostring(first))) 
end

asserttruthy = function(v)
	assert(v,'value is '..tostring(v))
end

asserttrue = function(v)
	assert(v == true,'value is '..tostring(v))
end

assertfalsy = function(v)
	assert(not v,'value is '..tostring(v))
end

assertfalse = function(v)
	assert(v == false,'value is '..tostring(v))
end

asserterror = function(func)
	assert(not pcall(func),'function ran without an error')
end