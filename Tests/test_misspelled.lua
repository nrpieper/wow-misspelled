if Misspelled.Tests == nil then
    Misspelled.Tests = {}
end

Misspelled.Tests.Misspelled = {}

-- Tests for Misspelled:TestRemoveHighlighting
function Misspelled.Tests.Misspelled:TestRemoveHighlighting()
	local string_gsub = string.gsub
    local string_len = string.len
    
	local testMessage
	local wantedMessage
	local gotMessage
	local newCPos
	local testResult

    print("Missspelled.Tests Starting: Misspelled:TestRemoveHighlighting")
    
	testMessage = "Apple"
	wantedMessage= "Apple"
	gotMessage, newCPos = Misspelled:RemoveHighlighting(testMessage, string_len(testMessage))
    assert(gotMessage == wantedMessage)

    testMessage = "|cff7dc6fbApplez|r"
	wantedMessage= "Applez"
    gotMessage, newCPos = Misspelled:RemoveHighlighting(testMessage, string_len(testMessage))
    assert(gotMessage == wantedMessage)

    testMessage = "|cff7dc6fbApplez|r good."
	wantedMessage= "Applez good."
    gotMessage, newCPos = Misspelled:RemoveHighlighting(testMessage, string_len(testMessage))
    assert(gotMessage == wantedMessage)
    
    testMessage = "Test |cff71d5ff|Hspell:2061:0|h[Flash Heal]|h|r good."
	wantedMessage= "Test |cff71d5ff|Hspell:2061:0|h[Flash Heal]|h|r good."
    gotMessage, newCPos = Misspelled:RemoveHighlighting(testMessage, string_len(testMessage))
	assert(gotMessage == wantedMessage)

	testMessage = "Test |cff71d5ff|Hspell:2061:0|h[Flash Heal]|h|r |cff7dc6fbbadd|r."
	wantedMessage= "Test |cff71d5ff|Hspell:2061:0|h[Flash Heal]|h|r badd."
    gotMessage, newCPos = Misspelled:RemoveHighlighting(testMessage, string_len(testMessage))
	assert(gotMessage == wantedMessage)

	testMessage = "Off-hand: |cffa335ee|Hitem:222566::::::::80:258::13:1:3524:6:40:2249:38:8:45:211296:46:226024:47:222584:48:224072:::::|h[Vagabond's Torch |A:Professions-ChatIcon-Quality-Tier5:17:17::1|a]|h|r"
	wantedMessage= "Off-hand: |cffa335ee|Hitem:222566::::::::80:258::13:1:3524:6:40:2249:38:8:45:211296:46:226024:47:222584:48:224072:::::|h[Vagabond's Torch |A:Professions-ChatIcon-Quality-Tier5:17:17::1|a]|h|r"
	gotMessage, newCPos = Misspelled:RemoveHighlighting(testMessage, string_len(testMessage))
    assert(gotMessage == wantedMessage)

	testMessage = "Off-hand: |cffa335ee|Hitem:222566::::::::80:258::13:1:3524:6:40:2249:38:8:45:211296:46:226024:47:222584:48:224072:::::|h[Vagabond's Torch |A:Professions-ChatIcon-Quality-Tier5:17:17::1|a]|h|r |cff7dc6fbbadd|r."
	wantedMessage= "Off-hand: |cffa335ee|Hitem:222566::::::::80:258::13:1:3524:6:40:2249:38:8:45:211296:46:226024:47:222584:48:224072:::::|h[Vagabond's Torch |A:Professions-ChatIcon-Quality-Tier5:17:17::1|a]|h|r badd."
	gotMessage, newCPos = Misspelled:RemoveHighlighting(testMessage, string_len(testMessage))
    assert(gotMessage == wantedMessage)

	testMessage  = "test: |cnIQ2:|Hitem:225566::::::::80:258:::::::::|h[Warped Wing]|h|r"
	wantedMessage = "test: |cnIQ2:|Hitem:225566::::::::80:258:::::::::|h[Warped Wing]|h|r"
	gotMessage, newCPos = Misspelled:RemoveHighlighting(testMessage, string_len(testMessage))
    assert(gotMessage == wantedMessage)
    
	testMessage  = "test: |cnIQ2:|Hitem:225566::::::::80:258:::::::::|h[Warped Wing]|h|r |cff7dc6fbbadd|r."
	wantedMessage = "test: |cnIQ2:|Hitem:225566::::::::80:258:::::::::|h[Warped Wing]|h|r badd."
    gotMessage, newCPos = Misspelled:RemoveHighlighting(testMessage, string_len(testMessage))
    assert(gotMessage == wantedMessage)

    print("Missspelled.Tests Done: Misspelled:TestRemoveHighlighting")
end

function Misspelled.Tests.Misspelled:RunTests()
    Misspelled.Tests.Misspelled:TestRemoveHighlighting()
end



