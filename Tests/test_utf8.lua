if Misspelled.Tests == nil then
    Misspelled.Tests = {}
end

Misspelled.Tests.UTF8 = {}

local string_utf8byte = string.utf8byte

-- Tests UTF8 functions
function Misspelled.Tests.UTF8:utf8byte()
	print("Missspelled.Tests Starting: UFT8:utf8byte()")
	local testUTF8str = "ACĐ"
	assert(string_utf8byte(testUTF8str) == 65)
	assert(string_utf8byte(testUTF8str,3) == 50320)
	print("Missspelled.Tests Done: UTF8:utf8byte()")
end



function Misspelled.Tests.UTF8:RunTests()
    Misspelled.Tests.UTF8:utf8byte()
end



