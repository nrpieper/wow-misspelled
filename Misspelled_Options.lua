local Misspelled = _G.Misspelled
local L = LibStub("AceLocale-3.0"):GetLocale("Misspelled", true)

function Misspelled:CreateInterfaceOptions()
	local cfgFrame = CreateFrame("FRAME", nil, UIParent)
	cfgFrame.name = "Misspelled"

	local cfgFrameHeader = cfgFrame:CreateFontString("OVERLAY", nil, "GameFontNormalLarge")
	cfgFrameHeader:SetPoint("TOPLEFT", 15, -15)
	cfgFrameHeader:SetText(self.Version)

	local cfgFrameReloadTip = cfgFrame:CreateFontString("OVERLAY", nil, "GameFontNormal")
	cfgFrameReloadTip:SetPoint("TOPLEFT", 20, -252)
	cfgFrameReloadTip:SetText(L["Note: reload the game UI to load a different selected dictionary"])

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

	--Add options frame to the list of in-game addon options
	--Adding addon options changed in Wow 11.0
	if InterfaceOptions_AddCategory then -- Check for compatiability for older Wow clients.
		InterfaceOptions_AddCategory(cfgFrame)  -- For Wow clients < v11
	elseif Settings then -- For Wow clients > v11
		local category, layout = Settings.RegisterCanvasLayoutCategory(cfgFrame, cfgFrame.name)
		Settings.RegisterAddOnCategory(category)
	end
end