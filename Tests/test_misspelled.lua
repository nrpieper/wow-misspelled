if Misspelled.Tests == nil then
    Misspelled.Tests = {}
end

Misspelled.Tests.Misspelled = {}

-- Tests for Chat EditBox cursor positioning to confirm assumptions for UTF8 
function Misspelled.Tests.Misspelled:ChatEditCursorPosition()
	local editbox = ChatFrame1EditBox
	ChatFrame1EditBox:SetText("")
	assert(editbox:GetCursorPosition() == 0)
	assert(editbox:GetUTF8CursorPosition() == 0)
	
	--Non-UTF8 text
	editbox:SetText("Applez.")
	assert(editbox:GetCursorPosition() == 7)
	assert(editbox:GetUTF8CursorPosition() == 7)

	--UFT8 text
	editbox:SetText("éí.á")
	assert(editbox:GetCursorPosition() == 7)
	assert(editbox:GetUTF8CursorPosition() == 4)

    editbox:SetText("test: |cnIQ2:|Hitem:225566::::::::80:258:::::::::|h[Warped Wing]|h|r |cff7dc6fbbadd|r.")
	assert(editbox:GetCursorPosition() == 86)
	assert(editbox:GetUTF8CursorPosition() == 86)

	--Testing UTF8 á subsitition in the string
	editbox:SetText("test: |cnIQ2:|Hitem:225566::::::::80:258:::::::::|h[Warped Wing]|h|r |cff7dc6fbbádd|r.")
	assert(editbox:GetCursorPosition() == 87)
	assert(editbox:GetUTF8CursorPosition() == 86)
end

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
    Misspelled.Tests.Misspelled:ChatEditCursorPosition()
	Misspelled.Tests.Misspelled:TestRemoveHighlighting()
end



