-- Sticky Custom Channels
-- WoW only remembers built-in chat types (/p, /g, /raid...). Addon "channels" are
-- just slash commands, so the chat box forgets them. This addon
-- remembers the last custom command you chatted in and prefills it when you open chat.

local ADDON = ...
local GetMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
local VERSION = GetMetadata(ADDON, "Version") or "?"
local DEFAULT_COMMANDS = {}

local db
local commands = {} -- set of lowercase sticky commands
local typed = ""    -- last non-empty text seen in the chat box

local function Print(msg)
	print("|cffe6c35cSticky Custom Channels:|r " .. msg)
end

local function RebuildSet()
	wipe(commands)
	for _, cmd in ipairs(db.commands) do commands[cmd:lower()] = true end
end

local function GetActiveEditBox()
	if ChatEdit_GetActiveWindow then return ChatEdit_GetActiveWindow() end
	if ChatFrameUtil and ChatFrameUtil.GetActiveWindow then return ChatFrameUtil.GetActiveWindow() end
end

-- Put the sticky command (e.g. "/mychan ") into the box. ChatFrame_OpenChat sets the box text on the next frame
-- (editBox.setText/editBox.text), so fill that in too or ours gets wiped.
local function Prefill(eb)
	if not (db and db.sticky and eb) then return end
	local prefix = db.sticky .. " "
	if eb.setText == 1 and (eb.text == nil or eb.text == "") then
		eb.text = prefix
	end
	C_Timer.After(0, function()
		if db.sticky and eb:HasFocus() and eb:GetText() == "" then
			eb:SetText(db.sticky .. " ")
		end
	end)
end

local function OnOpenChat(text)
	if text and text ~= "" then return end -- e.g. /w Name, leave it alone
	typed = ""
	Prefill(GetActiveEditBox())
end

local function HookEditBox(eb)
	if not eb or eb.StickyCustomChannelsHooked then return end
	eb.StickyCustomChannelsHooked = true

	eb:HookScript("OnTextChanged", function(self)
		local text = self:GetText()
		-- Sticky command prefilled and you start another command: drop it so /p, /w etc. work
		local cmd, rest = text:match("^(/%S+) (/.*)$")
		if cmd and commands[cmd:lower()] then
			self:SetText(rest)
			return
		end
		if text ~= "" then typed = text end
	end)

	eb:HookScript("OnEnterPressed", function()
		local cmd = typed:match("^(/%S+)")
		if cmd and commands[cmd:lower()] then
			if typed:match("^/%S+%s+%S") then db.sticky = cmd:lower() end
		elseif typed ~= "" and typed:sub(1, 1) ~= "/" then
			db.sticky = nil -- a normal chat message went out, so the custom channel is off
		end
		typed = ""
	end)
end

local function NormalizeCommand(cmd)
	cmd = strtrim(cmd or ""):lower():match("^(%S*)") or ""
	if cmd ~= "" and cmd:sub(1, 1) ~= "/" then cmd = "/" .. cmd end
	return cmd
end

local RefreshSettings -- set once the settings window exists

local function AddCommand(cmd)
	cmd = NormalizeCommand(cmd)
	if cmd == "" or cmd == "/" then return end
	if not commands[cmd] then table.insert(db.commands, cmd) end
	RebuildSet()
	if RefreshSettings then RefreshSettings() end
end

local function RemoveCommand(cmd)
	cmd = NormalizeCommand(cmd)
	for i = #db.commands, 1, -1 do
		if db.commands[i]:lower() == cmd then table.remove(db.commands, i) end
	end
	if db.sticky == cmd then db.sticky = nil end
	RebuildSet()
	if RefreshSettings then RefreshSettings() end
end

---------------------------------------------------------------------------
-- Settings window
---------------------------------------------------------------------------

local settings
local ROW_HEIGHT = 24

local function CreateSettings()
	settings = CreateFrame("Frame", "StickyCustomChannelsSettings", UIParent, "BackdropTemplate")
	settings:SetSize(300, 184)
	settings:SetPoint("CENTER")
	settings:SetFrameStrata("DIALOG")
	settings:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	settings:SetMovable(true)
	settings:EnableMouse(true)
	settings:RegisterForDrag("LeftButton")
	settings:SetScript("OnDragStart", settings.StartMoving)
	settings:SetScript("OnDragStop", settings.StopMovingOrSizing)
	settings:SetClampedToScreen(true)
	tinsert(UISpecialFrames, settings:GetName()) -- Escape closes it

	local title = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -18)
	title:SetText("Sticky Custom Channels")

	local version = settings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	version:SetPoint("TOP", title, "BOTTOM", 0, -3)
	version:SetText("v" .. VERSION)

	local close = CreateFrame("Button", nil, settings, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local help = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	help:SetPoint("TOPLEFT", 20, -58)
	help:SetPoint("TOPRIGHT", -20, -58)
	help:SetJustifyH("LEFT")
	help:SetText("Chat commands that stay selected after you send, like /p does.")

	local current = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	current:SetPoint("TOPLEFT", help, "BOTTOMLEFT", 0, -8)
	settings.current = current

	local clear = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
	clear:SetSize(60, 20)
	clear:SetPoint("RIGHT", settings, "RIGHT", -20, 0)
	clear:SetPoint("TOP", current, "TOP", 0, 4)
	clear:SetText("Clear")
	clear:SetScript("OnClick", function()
		db.sticky = nil
		RefreshSettings()
	end)

	local empty = settings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	empty:SetPoint("TOPLEFT", current, "BOTTOMLEFT", 0, -14)
	empty:SetText("No commands yet. Add one below, e.g. /mychan")
	settings.empty = empty

	local input = CreateFrame("EditBox", nil, settings, "InputBoxTemplate")
	input:SetSize(170, 20)
	input:SetPoint("BOTTOMLEFT", 26, 20)
	input:SetAutoFocus(false)
	input:SetMaxLetters(32)
	settings.input = input

	local add = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
	add:SetSize(70, 22)
	add:SetPoint("LEFT", input, "RIGHT", 8, 0)
	add:SetText("Add")

	local function DoAdd()
		AddCommand(input:GetText())
		input:SetText("")
		input:ClearFocus()
	end
	add:SetScript("OnClick", DoAdd)
	input:SetScript("OnEnterPressed", DoAdd)
	input:SetScript("OnEscapePressed", input.ClearFocus)

	settings.rows = {}
	settings:Hide()
end

local function GetRow(i)
	local row = settings.rows[i]
	if row then return row end
	row = CreateFrame("Frame", nil, settings)
	row:SetHeight(ROW_HEIGHT)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	row.text:SetPoint("LEFT", 4, 0)
	row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.remove:SetSize(70, 20)
	row.remove:SetPoint("RIGHT", 0, 0)
	row.remove:SetText("Remove")
	row.remove:SetScript("OnClick", function() RemoveCommand(row.cmd) end)
	settings.rows[i] = row
	return row
end

RefreshSettings = function()
	if not settings then return end
	settings.current:SetText("Current: " .. (db.sticky and ("|cffffffff" .. db.sticky .. "|r") or "none"))
	for _, row in ipairs(settings.rows) do row:Hide() end
	for i, cmd in ipairs(db.commands) do
		local row = GetRow(i)
		row.cmd = cmd
		row.text:SetText(cmd)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", settings.current, "BOTTOMLEFT", 0, -8 - (i - 1) * ROW_HEIGHT)
		row:SetPoint("RIGHT", settings, "RIGHT", -20, 0)
		row:Show()
	end
	settings.empty:SetShown(#db.commands == 0)
	settings:SetHeight(184 + math.max(#db.commands - 1, 0) * ROW_HEIGHT)
end

local function ToggleSettings()
	if not settings then CreateSettings() end
	if settings:IsShown() then
		settings:Hide()
	else
		RefreshSettings()
		settings:Show()
	end
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------

local minimapButton

local function PositionMinimapButton()
	local angle = math.rad(db.minimapAngle or 200)
	local radius = Minimap:GetWidth() / 2 + 10
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function CreateMinimapButton()
	local b = CreateFrame("Button", "StickyCustomChannelsMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture("Interface\\AddOns\\StickyCustomChannels\\media\\minimap")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 6, -5)

	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:SetScript("OnClick", ToggleSettings)

	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
			PositionMinimapButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddDoubleLine("Sticky Custom Channels", "v" .. VERSION)
		GameTooltip:AddLine("Current: " .. (db.sticky or "none"), 1, 1, 1)
		GameTooltip:AddLine("Click to open settings, drag to move.", 0.7, 0.7, 0.7)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)

	minimapButton = b
	PositionMinimapButton()
	b:SetShown(not db.hideMinimap)
end

---------------------------------------------------------------------------
-- Startup and /scc
---------------------------------------------------------------------------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		StickyCustomChannelsDB = StickyCustomChannelsDB or {}
		db = StickyCustomChannelsDB
		db.commands = db.commands or CopyTable(DEFAULT_COMMANDS)
		RebuildSet()
	elseif event == "PLAYER_LOGIN" then
		for i = 1, NUM_CHAT_WINDOWS do HookEditBox(_G["ChatFrame" .. i .. "EditBox"]) end
		if ChatFrame_OpenChat then hooksecurefunc("ChatFrame_OpenChat", OnOpenChat) end
		if ChatFrameUtil and ChatFrameUtil.OpenChat then hooksecurefunc(ChatFrameUtil, "OpenChat", OnOpenChat) end
		CreateMinimapButton()
	end
end)

SLASH_STICKYCUSTOMCHANNELS1 = "/scc"
SlashCmdList.STICKYCUSTOMCHANNELS = function(input)
	local action = strtrim(input or ""):lower()
	if action == "minimap" then
		db.hideMinimap = not db.hideMinimap
		minimapButton:SetShown(not db.hideMinimap)
		Print("minimap button " .. (db.hideMinimap and "hidden" or "shown"))
	else
		ToggleSettings()
	end
end
