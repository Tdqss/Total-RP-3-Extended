----------------------------------------------------------------------------------
-- Total RP 3: Extended features
--	---------------------------------------------------------------------------
--	Copyright 2015 Sylvain Cossement (telkostrasz@totalrp3.info)
--
--	Licensed under the Apache License, Version 2.0 (the "License");
--	you may not use this file except in compliance with the License.
--	You may obtain a copy of the License at
--
--		http://www.apache.org/licenses/LICENSE-2.0
--
--	Unless required by applicable law or agreed to in writing, software
--	distributed under the License is distributed on an "AS IS" BASIS,
--	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--	See the License for the specific language governing permissions and
--	limitations under the License.
----------------------------------------------------------------------------------

local Globals, Events, Utils = TRP3_API.globals, TRP3_API.events, TRP3_API.utils;
local pairs, assert, tostring, strsplit, wipe, date = pairs, assert, tostring, strsplit, wipe, date;
local EMPTY = TRP3_API.globals.empty;
local Log = Utils.log;
local loc = TRP3_API.locale.getText;
local fireEvent = TRP3_API.events.fireEvent;
local after  = C_Timer.After;
local getFullID, getClass = TRP3_API.extended.getFullID, TRP3_API.extended.getClass;
local setTooltipForSameFrame = TRP3_API.ui.tooltip.setTooltipForSameFrame;
local refreshTooltipForFrame = TRP3_RefreshTooltipForFrame;

local toolFrame;

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- API
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

TRP3_API.extended.tools = {};

local BACKGROUNDS = {
	"Interface\\ENCOUNTERJOURNAL\\UI-EJ-Classic",
	"Interface\\ENCOUNTERJOURNAL\\UI-EJ-BurningCrusade",
	"Interface\\ENCOUNTERJOURNAL\\UI-EJ-WrathoftheLichKing",
	"Interface\\ENCOUNTERJOURNAL\\UI-EJ-CATACLYSM",
	"Interface\\ENCOUNTERJOURNAL\\UI-EJ-MistsofPandaria",
	"Interface\\ENCOUNTERJOURNAL\\UI-EJ-WarlordsofDraenor",
}

function TRP3_API.extended.tools.setBackground(backgroundIndex)
	assert(BACKGROUNDS[backgroundIndex], "Unknown background index:" .. tostring(backgroundIndex));
	local texture = BACKGROUNDS[backgroundIndex];
	toolFrame.BkgMain:SetTexture(texture);
	toolFrame.BkgHeader:SetTexture(texture);
	toolFrame.BkgScroll:SetTexture(texture);
end
local setBackground = TRP3_API.extended.tools.setBackground;

local PAGE_BY_TYPE = {
	[TRP3_DB.types.CAMPAIGN] = {
		frame = nil,
		tabTextGetter = function(id)
			return loc("TYPE_CAMPAIGN") .. ": " .. id;
		end,
		background = 2,
	},
	[TRP3_DB.types.QUEST] = {
		frame = nil,
		tabTextGetter = function(id)
			return loc("TYPE_QUEST") .. ": " .. id;
		end,
		background = 2,
	},
	[TRP3_DB.types.QUEST_STEP] = {
		frame = nil,
		tabTextGetter = function(id)
			return loc("TYPE_QUEST_STEP") .. ": " .. id;
		end,
		background = 2,
	},
	[TRP3_DB.types.ITEM] = {
		frame = "item",
		tabTextGetter = function(id, class, isRoot)
			return ("%s: %s"):format(loc("TYPE_ITEM"),  TRP3_API.inventory.getItemLink(class));
		end,
		background = 3,
	},
	[TRP3_DB.types.DOCUMENT] = {
		frame = "document",
		tabTextGetter = function(id)
			return loc("TYPE_DOCUMENT") .. ": " .. id;
		end,
		background = 4,
	},
	[TRP3_DB.types.DIALOG] = {
		frame = nil,
		tabTextGetter = function(id)
			return loc("TYPE_DIALOG") .. ": " .. id;
		end,
		background = 5,
	},
	[TRP3_DB.types.LOOT] = {
		frame = nil,
		tabTextGetter = function(id)
			return loc("TYPE_LOOT") .. ": " .. id;
		end,
		background = 6,
	},
}

local function getTypeLocale(type)
	if PAGE_BY_TYPE[type] and PAGE_BY_TYPE[type].loc then
		return PAGE_BY_TYPE[type].loc;
	end
	return UNKOWN;
end
TRP3_API.extended.tools.getTypeLocale = getTypeLocale;

local function getClassDataSafeByType(class)
	if class.TY == TRP3_DB.types.CAMPAIGN or class.TY == TRP3_DB.types.QUEST or class.TY == TRP3_DB.types.ITEM or class.TY == TRP3_DB.types.DOCUMENT then
		return TRP3_API.extended.getClassDataSafe(class);
	end
	if class.TY == TRP3_DB.types.QUEST_STEP then
		return "inv_inscription_scroll", (class.TX or ""):gsub("\n", ""):sub(1, 70) .. "...";
	end
	if class.TY == TRP3_DB.types.DIALOG then
		return "ability_warrior_rallyingcry", (class.ST[1].TX or ""):gsub("\n", ""):sub(1, 70) .. "...";
	end
	if class.TY == TRP3_DB.types.LOOT then
		return "inv_misc_coinbag_special", class.NA or "";
	end
end
TRP3_API.extended.tools.getClassDataSafeByType = getClassDataSafeByType;

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Root object action
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

local draftData = {};
local draftRegister = {};

local function getModeLocale(mode)
	if mode == TRP3_DB.modes.QUICK then
		return loc("MODE_QUICK");
	end
	if mode == TRP3_DB.modes.NORMAL then
		return loc("MODE_NORMAL");
	end
	if mode == TRP3_DB.modes.EXPERT then
		return loc("MODE_EXPERT");
	end
	return tostring(mode);
end
TRP3_API.extended.tools.getModeLocale = getModeLocale;

local function openObjectAndGetDraft(rootClassID, forceDraftReload)
	for k, _ in pairs(draftRegister) do
		draftRegister[k] = nil;
	end
	if forceDraftReload or toolFrame.rootClassID ~= rootClassID then
		Log.log(("Refreshing root draft.\nPrevious: %s\nNex: %s"):format(tostring(toolFrame.rootClassID), tostring(rootClassID)));
		wipe(TRP3_Tools_Parameters.editortabs);
		wipe(draftData);
		toolFrame.rootClassID = rootClassID;
		Utils.table.copy(draftData, getClass(rootClassID));
	end
	TRP3_API.extended.registerDB({[rootClassID] = draftData}, 0, draftRegister);
	return draftData;
end

local function displayRootInfo(rootClassID, rootClass, classFullID, classID, specificDraft)
	assert(rootClass.MD, "No metadata MD in root class.");
	assert(specificDraft.MD, "No metadata MD in specific class.");
	local color = "|cffffff00";
	local fieldFormat = "|cffff9900%s: " .. color .. "%s";

	local objectText = ("%s (%s: |cff00ffff%s|r)"):format(TRP3_API.inventory.getItemLink(rootClass), loc("ROOT_GEN_ID"), rootClassID);
	objectText = objectText .. "\n\n" .. fieldFormat:format(loc("ROOT_VERSION"), rootClass.MD.V or 0);
	objectText = objectText .. "\n\n|cffff9900" .. loc("ROOT_CREATED"):format(color .. (rootClass.MD.CB or "?") .. "|cffff9900", color .. (rootClass.MD.CD or "?"));
	objectText = objectText .. "\n\n|cffff9900" .. loc("ROOT_SAVED"):format(color .. (rootClass.MD.SB or "?") .. "|cffff9900", color .. (rootClass.MD.SD or "?"));
	toolFrame.root.text:SetText(objectText);

	TRP3_API.ui.frame.setupFieldPanel(toolFrame.specific, getTypeLocale(specificDraft.TY), 150);
	local specificText = "";
	if rootClassID == classID then
		specificText = specificText .. fieldFormat:format(loc("ROOT_GEN_ID"), "|cff00ffff" .. classID);
	else
		specificText = specificText .. fieldFormat:format(loc("SPECIFIC_INNER_ID"), "|cff00ffff" .. classID);
	end
	specificText = specificText .. "\n\n" .. fieldFormat:format(loc("TYPE"), getTypeLocale(specificDraft.TY));
	specificText = specificText .. "\n\n" .. fieldFormat:format(loc("SPECIFIC_MODE"), getModeLocale(specificDraft.MD.MO));
	toolFrame.specific.text:SetText(specificText);
end

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Editor save delegate
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

local getClass = TRP3_API.extended.getClass;
local goToPage;

local function onSave(editor)
	assert(editor, "No editor.");
	assert(editor.onSave, "No save method in editor.");
	assert(toolFrame.rootClassID, "No rootClassID in editor.");
	assert(toolFrame.fullClassID, "No fullClassID in editor.");
	local rootClassID, fullClassID = toolFrame.rootClassID, toolFrame.fullClassID;

	-- Force save the current view in draft
	editor.onSave();

	local rootDraft = toolFrame.rootDraft;

	local object = getClass(rootClassID);
	wipe(object);
	Utils.table.copy(object, rootDraft);
	object.MD.V = object.MD.V + 1;
	object.MD.SD = date("%d/%m/%y %H:%M:%S");
	object.MD.SB = Globals.player_id;

	TRP3_API.security.computeSecurity(rootClassID, object);
	TRP3_API.extended.registerObject(rootClassID, object, 0);
	TRP3_API.script.clearRootCompilation(rootClassID);
	TRP3_API.events.fireEvent(TRP3_API.inventory.EVENT_REFRESH_BAG);

	goToPage(fullClassID, true);
end

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- Pages
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

local function goToListPage(skipButton)
	if not skipButton then
		NavBar_Reset(toolFrame.navBar);
	end
	setBackground(1);
	toolFrame.actions:Hide();
	toolFrame.specific:Hide();
	toolFrame.root:Hide();
	for _, pageData in pairs(PAGE_BY_TYPE) do
		local frame = toolFrame[pageData.frame or ""];
		if frame then
			frame:Hide();
		end
	end
	TRP3_API.extended.tools.toList();
end

function goToPage(fullClassID, forceDraftReload)
	local parts = {strsplit(TRP3_API.extended.ID_SEPARATOR, fullClassID)};
	local rootClassID = parts[1];
	local specificClassID = parts[#parts];

	-- First of all, save to draft if same rootID !
	if toolFrame.rootClassID == rootClassID and toolFrame.currentEditor then
		toolFrame.currentEditor.onSave();
	end

	-- Go to page
	toolFrame.list:Hide();
	toolFrame.actions:Show();
	toolFrame.specific:Show();
	toolFrame.root:Show();

	-- Load data
	local rootDraft = openObjectAndGetDraft(rootClassID, forceDraftReload);
	local specificDraft = draftRegister[fullClassID];
	assert(specificDraft, "Can't find specific object in draftRegister: " .. fullClassID);

	local selectedPageData, selectedPageFrame;
	-- Hide all
	for classType, pageData in pairs(PAGE_BY_TYPE) do
		local frame = toolFrame[pageData.frame or ""];
		if specificDraft.TY ~= classType then
			if frame then
				frame:Hide();
			end
		else
			selectedPageFrame = frame;
			selectedPageData = pageData;
		end
	end

	assert(selectedPageFrame, "No editor for type " .. specificDraft.TY);
	assert(selectedPageFrame.onLoad, "No load entry for type " .. specificDraft.TY);

	-- Show selected
	setBackground(selectedPageData.background or 1);
	displayRootInfo(rootClassID, rootDraft, fullClassID, specificClassID, specificDraft);
	toolFrame.rootClassID = rootClassID;
	toolFrame.currentEditor = selectedPageFrame;
	toolFrame.fullClassID = fullClassID;
	toolFrame.specificClassID = specificClassID;
	toolFrame.rootDraft = rootDraft;
	toolFrame.specificDraft = specificDraft;
	toolFrame.currentEditor.onLoad();
	toolFrame.currentEditor:Show();

	toolFrame.actions.save:Disable();
	if TRP3_Tools_DB[rootClassID] then
		toolFrame.actions.save:Enable();
	end
	setTooltipForSameFrame(toolFrame.actions.save, "TOP", 0, 5, SAVE, loc("EDITOR_SAVE_TT"):format(TRP3_API.inventory.getItemLink(rootDraft)));
	setTooltipForSameFrame(toolFrame.actions.cancel, "TOP", 0, 5, CANCEL, loc("EDITOR_CANCEL_TT"):format(TRP3_API.inventory.getItemLink(rootDraft)));

	-- Create buttons up to the target
	NavBar_Reset(toolFrame.navBar);
	local fullId = "";
	for _, part in pairs(parts) do
		fullId = getFullID(fullId, part);
		local reconstruct = fullId;
		local class = draftRegister[reconstruct];
		local text = PAGE_BY_TYPE[class.TY].tabTextGetter(part, class, part == parts[1]);
		NavBar_AddButton(toolFrame.navBar, {id = reconstruct, name = text, OnClick = function()
			goToPage(reconstruct);
		end});
		local navButton = toolFrame.navBar.navList[#toolFrame.navBar.navList];
		navButton:SetScript("OnEnter", function(self)
			NavBar_ButtonOnEnter(self);
			refreshTooltipForFrame(self);
		end);
		navButton:SetScript("OnLeave", function(self)
			NavBar_ButtonOnLeave(self);
			TRP3_MainTooltip:Hide();
		end);
		if fullId == part then
			setTooltipForSameFrame(navButton, "TOP", 0, 5, loc("ROOT_GEN_ID"), "|cff00ffff" .. part);
		else
			setTooltipForSameFrame(navButton, "TOP", 0, 5, loc("SPECIFIC_INNER_ID"), "|cff00ffff" .. part);
		end
	end

end
TRP3_API.extended.tools.goToPage = goToPage;

--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*
-- INIT
--*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*

function TRP3_API.extended.tools.showFrame(reset)
	toolFrame:Show();
	if reset then
		goToListPage();
	end
end

local function onStart()

	-- Events
	Events.ON_OBJECT_UPDATED = "ON_OBJECT_UPDATED";
	Events.registerEvent(Events.ON_OBJECT_UPDATED);

	-- Register locales
	for localeID, localeStructure in pairs(TRP3_EXTENDED_TOOL_LOCALE) do
		local locale = TRP3_API.locale.getLocale(localeID);
		for localeKey, text in pairs(localeStructure) do
			locale.localeContent[localeKey] = text;
		end
	end

	TRP3_API.ui.frame.setupFieldPanel(toolFrame.root, loc("ROOT_TITLE"), 150);
	TRP3_API.ui.frame.setupFieldPanel(toolFrame.actions, loc("DB_ACTIONS"), 100);
	toolFrame.actions.cancel:SetText(CANCEL)
	toolFrame.actions.save:SetScript("OnClick", function()
		onSave(toolFrame.currentEditor);
	end);
	toolFrame.actions.cancel:SetScript("OnClick", function()
		goToListPage();
	end);
	toolFrame.root.id:SetText(loc("EDITOR_ID_COPY"));
	toolFrame.root.id:SetScript("OnClick", function()
		TRP3_API.popup.showTextInputPopup(loc("EDITOR_ID_COPY_POPUP"), nil, nil, toolFrame.rootClassID);
	end);
	toolFrame.specific.id:SetText(loc("EDITOR_ID_COPY"));
	toolFrame.specific.id:SetScript("OnClick", function()
		TRP3_API.popup.showTextInputPopup(loc("EDITOR_ID_COPY_POPUP"), nil, nil, toolFrame.fullClassID);
	end);

	PAGE_BY_TYPE[TRP3_DB.types.CAMPAIGN].loc = loc("TYPE_CAMPAIGN");
	PAGE_BY_TYPE[TRP3_DB.types.QUEST].loc = loc("TYPE_QUEST");
	PAGE_BY_TYPE[TRP3_DB.types.QUEST_STEP].loc = loc("TYPE_QUEST_STEP");
	PAGE_BY_TYPE[TRP3_DB.types.ITEM].loc = loc("TYPE_ITEM");
	PAGE_BY_TYPE[TRP3_DB.types.DOCUMENT].loc = loc("TYPE_DOCUMENT");
	PAGE_BY_TYPE[TRP3_DB.types.DIALOG].loc = loc("TYPE_DIALOG");
	PAGE_BY_TYPE[TRP3_DB.types.LOOT].loc = loc("TYPE_LOOT");

	toolFrame.Close:SetScript("OnClick", function(self) self:GetParent():Hide(); end);

	TRP3_API.events.NAVIGATION_EXTENDED_RESIZED = "NAVIGATION_EXTENDED_RESIZED";
	TRP3_API.events.registerEvent(TRP3_API.events.NAVIGATION_EXTENDED_RESIZED);

	toolFrame.Resize.minWidth = 1150;
	toolFrame.Resize.minHeight = 730;
	toolFrame:SetSize(toolFrame.Resize.minWidth, toolFrame.Resize.minHeight);
	toolFrame.Resize.resizableFrame = toolFrame;
	toolFrame.Resize.onResizeStop = function()
		toolFrame.Minimize:Hide();
		toolFrame.Maximize:Show();
		fireEvent(TRP3_API.events.NAVIGATION_EXTENDED_RESIZED, toolFrame:GetWidth(), toolFrame:GetHeight());
	end;

	toolFrame.Maximize:SetScript("OnClick", function()
		toolFrame.Maximize:Hide();
		toolFrame.Minimize:Show();
		toolFrame:SetSize(UIParent:GetWidth(), UIParent:GetHeight());
		after(0.1, function()
			fireEvent(TRP3_API.events.NAVIGATION_EXTENDED_RESIZED, toolFrame:GetWidth(), toolFrame:GetHeight());
		end);
	end);

	toolFrame.Minimize:SetScript("OnClick", function()
		toolFrame:SetSize(toolFrame.Resize.minWidth, toolFrame.Resize.minHeight);
		after(0.1, function()
			toolFrame.Resize.onResizeStop();
		end);
	end);

	-- Tab bar init
	local homeData = {
		name = loc("DB"),
		OnClick = function()
			goToListPage();
		end
	}
	toolFrame.navBar.home:SetWidth(110);
	toolFrame.navBar.home:SetScript("OnEnter", function(self)
		NavBar_ButtonOnEnter(self);
		refreshTooltipForFrame(self);
	end);
	toolFrame.navBar.home:SetScript("OnLeave", function(self)
		NavBar_ButtonOnLeave(self);
		TRP3_MainTooltip:Hide();
	end);

	setTooltipForSameFrame(toolFrame.navBar.home, "TOP", 0, 5, loc("DB"), loc("DB_WARNING"));
	NavBar_Initialize(toolFrame.navBar, "NavButtonTemplate", homeData, toolFrame.navBar.home, toolFrame.navBar.overflow);

	-- Init tabs
	TRP3_API.extended.tools.initBaseEffects();
	TRP3_API.extended.tools.initScript(toolFrame);
	TRP3_InnerObjectEditor.init(toolFrame);
	TRP3_API.extended.tools.initDocument(toolFrame);
	TRP3_API.extended.tools.initItems(toolFrame);
	TRP3_API.extended.tools.initList(toolFrame);

	goToListPage();

	TRP3_API.events.fireEvent(TRP3_API.events.NAVIGATION_EXTENDED_RESIZED, toolFrame:GetWidth(), toolFrame:GetHeight());
end

local function onInit()
	toolFrame = TRP3_ToolFrame;

	if not TRP3_Tools_DB then
		TRP3_Tools_DB = {};
	end
	TRP3_DB.my = TRP3_Tools_DB;

	if not TRP3_Tools_Parameters then
		TRP3_Tools_Parameters = {};
	end
	if not TRP3_Tools_Parameters.editortabs then
		TRP3_Tools_Parameters.editortabs = {};
	end
end

local MODULE_STRUCTURE = {
	["name"] = "Extended Tools",
	["description"] = "Total RP 3 extended tools: item, document and campaign creation.",
	["version"] = 0.2,
	["id"] = "trp3_extended_tools",
	["onStart"] = onStart,
	["onInit"] = onInit,
	["minVersion"] = 14,
	["requiredDeps"] = {
		{"trp3_extended", 0.2},
	}
};

TRP3_API.module.registerModule(MODULE_STRUCTURE);