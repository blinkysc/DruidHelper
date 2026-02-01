-- UI.lua
-- Visual display for DruidHelper (3.3.5a compatible, no dependencies)

local DH = DruidHelper
if not DH then return end

local ns = DH.ns
local class = DH.Class

-- Create main display frame
local function CreateMainFrame()
    local frame = CreateFrame("Frame", "DruidHelperFrame", UIParent)
    frame:SetSize(220, 60)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    frame:SetScript("OnDragStart", function(self)
        if DH.db and not DH.db.locked then
            self:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if DH.db then
            local _, _, _, x, y = self:GetPoint()
            DH.db.display.x = x
            DH.db.display.y = y
        end
    end)

    -- Simple black background
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetTexture(0, 0, 0, 0.7)

    ns.UI.MainFrame = frame
    return frame
end

-- Create ability button
local function CreateAbilityButton(parent, index)
    local size = DH.db and DH.db.display.iconSize or 50
    local button = CreateFrame("Button", "DruidHelperButton" .. index, parent)
    button:SetSize(size, size)

    -- Position buttons horizontally
    if index == 1 then
        button:SetPoint("LEFT", parent, "LEFT", 10, 0)
    else
        button:SetPoint("LEFT", ns.UI.Buttons[index - 1], "RIGHT", 5, 0)
    end

    -- Icon texture
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetAllPoints()
    button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Cooldown sweep animation (like normal action bars)
    button.cooldown = CreateFrame("Cooldown", "DruidHelperCooldown" .. index, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints()

    -- Cooldown text overlay (for longer CDs, optional)
    button.cooldownText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    button.cooldownText:SetPoint("CENTER")
    button.cooldownText:SetTextColor(1, 1, 0)
    button.cooldownText:SetText("")

    -- Range indicator (simple red overlay)
    button.rangeOverlay = button:CreateTexture(nil, "OVERLAY")
    button.rangeOverlay:SetAllPoints()
    button.rangeOverlay:SetTexture(1, 0, 0, 0.3)
    button.rangeOverlay:Hide()

    -- Mark first button as primary (slightly larger)
    if index == 1 then
        button.isPrimary = true
        button:SetSize(size + 10, size + 10)
    end

    button:Hide()
    return button
end

-- Initialize UI
function ns.InitializeUI(addon)
    if ns.UI.MainFrame then return end

    local mainFrame = CreateMainFrame()

    -- Create buttons
    local numIcons = addon.db.display.numIcons or 4
    for i = 1, numIcons do
        ns.UI.Buttons[i] = CreateAbilityButton(mainFrame, i)
    end

    -- Update frame size based on number of icons
    local iconSize = addon.db.display.iconSize or 50
    local spacing = 5
    local padding = 10
    local width = (iconSize * numIcons) + (spacing * (numIcons - 1)) + (padding * 2)
    mainFrame:SetSize(width, iconSize + 20)

    -- Apply saved position
    if addon.db.display.x and addon.db.display.y then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", addon.db.display.x, addon.db.display.y)
    end

    -- Apply scale and alpha
    mainFrame:SetScale(addon.db.display.scale or 1.0)
    mainFrame:SetAlpha(addon.db.display.alpha or 1.0)

    -- Lock state
    mainFrame:EnableMouse(not addon.db.locked)

    -- Initially hidden
    mainFrame:Hide()
end

-- Update UI with recommendations
function ns.UpdateUI(addon)
    if not ns.UI.MainFrame then
        ns.InitializeUI(addon)
    end

    local buttons = ns.UI.Buttons
    local recs = ns.recommendations
    local state = DH.State

    for i = 1, addon.db.display.numIcons do
        local button = buttons[i]
        if not button then break end

        if recs[i] and recs[i].texture then
            button.icon:SetTexture(recs[i].texture)

            -- Update cooldown sweep animation
            local abilityKey = recs[i].ability
            local showSweep = false
            local cdStart, cdDuration = 0, 0

            -- Check ability cooldown first
            if abilityKey and state.cooldown[abilityKey] then
                local cd = state.cooldown[abilityKey]
                if cd.remains > 0 and cd.start and cd.duration then
                    cdStart = cd.start
                    cdDuration = cd.duration
                    showSweep = true
                end
            end

            -- For primary icon, show GCD sweep if no ability CD
            if i == 1 and not showSweep and state.gcd_remains > 0.1 then
                -- Calculate GCD start from remains
                local gcdDuration = state.gcd or 1.0
                cdStart = GetTime() - (gcdDuration - state.gcd_remains)
                cdDuration = gcdDuration
                showSweep = true
            end

            -- Apply cooldown sweep
            if showSweep and cdStart > 0 and cdDuration > 0 then
                button.cooldown:SetCooldown(cdStart, cdDuration)
                -- Show text only for long cooldowns (> 3 sec)
                if cdDuration > 3 then
                    button.cooldownText:SetText(string.format("%.0f", cdStart + cdDuration - GetTime()))
                else
                    button.cooldownText:SetText("")
                end
            else
                button.cooldown:SetCooldown(0, 0)
                button.cooldownText:SetText("")
            end

            -- Range check for melee abilities
            if i == 1 and addon.db.display.showRange then
                local isMeleeAbility = abilityKey and (
                    abilityKey:find("shred") or
                    abilityKey:find("mangle") or
                    abilityKey:find("rake") or
                    abilityKey:find("rip") or
                    abilityKey:find("swipe") or
                    abilityKey:find("lacerate") or
                    abilityKey:find("maul") or
                    abilityKey:find("bite")
                )

                if isMeleeAbility and state.target.exists and not state.target.inRange then
                    button.rangeOverlay:Show()
                else
                    button.rangeOverlay:Hide()
                end
            else
                button.rangeOverlay:Hide()
            end

            button:Show()
        else
            button:Hide()
        end
    end

    -- Update live debug frame if enabled
    ns.UpdateDebugFrame()
end

-- Show UI
function ns.ShowUI()
    if ns.UI.MainFrame then
        ns.UI.MainFrame:Show()
    end
end

-- Hide UI
function ns.HideUI()
    if ns.UI.MainFrame then
        ns.UI.MainFrame:Hide()
    end
end

-- Create debug frame for live state display
local function CreateDebugFrame()
    if ns.DebugFrame then return ns.DebugFrame end

    local frame = CreateFrame("Frame", "DruidHelperDebugFrame", UIParent)
    frame:SetSize(260, 130)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -200)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetTexture(0, 0, 0, 0.8)

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.text:SetPoint("TOPLEFT", 5, -5)
    frame.text:SetPoint("BOTTOMRIGHT", -5, 5)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetJustifyV("TOP")

    frame:Hide()
    ns.DebugFrame = frame
    return frame
end

-- Update debug frame
function ns.UpdateDebugFrame()
    if not DH.db or not DH.db.showDebugFrame then return end
    if not ns.DebugFrame then CreateDebugFrame() end

    local s = DH.State
    local rec1 = ns.recommendations[1] and ns.recommendations[1].ability or "none"
    local rec2 = ns.recommendations[2] and ns.recommendations[2].ability or "none"
    local rec3 = ns.recommendations[3] and ns.recommendations[3].ability or "none"

    -- Check why FF might be blocked
    local ff_status = "?"
    local ff_remains = s.cooldown.faerie_fire_feral.remains
    if ff_remains > 0.1 then
        ff_status = string.format("|cFFFF0000CD %.1f|r", ff_remains)
    elseif s.buff.berserk.up then
        ff_status = "|cFFFFFF00RDY(Bzk)|r"
    elseif s.buff.clearcasting.up then
        ff_status = "|cFFFFFF00RDY(CC)|r"
    else
        ff_status = "|cFF00FF00RDY!|r"
    end

    -- Bearweave status
    local bw_status = ""
    local bw_enabled = DH.db.feral_cat and DH.db.feral_cat.bearweave
    if bw_enabled then
        if s.bear_form then
            bw_status = string.format("|cFFFF8800BEAR|r R:%d Lac:%d/%d",
                s.rage.current,
                s.debuff.lacerate.stacks or 0,
                s.debuff.lacerate.up and math.floor(s.debuff.lacerate.remains) or 0)
        else
            -- Show when bearweave would trigger
            local can_bw = s.energy.current < 40 and not s.buff.clearcasting.up
                and (not s.debuff.rip.up or s.debuff.rip.remains > 4.5)
                and not s.buff.berserk.up
            if can_bw then
                bw_status = "|cFF00FF00BW_RDY|r"
            else
                bw_status = "|cFF888888BW:wait|r"
            end
        end
    end

    local lines = {
        "|cFFFFFF00=== Live Debug ===|r",
        string.format("E: %d | CP: %d | GCD: %.2f", s.energy.current, s.combo_points.current, s.gcd_remains),
        string.format("Berserk: %s | CC: %s", s.buff.berserk.up and "|cFFFF0000UP|r" or "no", s.buff.clearcasting.up and "|cFF00FF00UP|r" or "no"),
        string.format("FF: %s %s", ff_status, bw_status),
        string.format("SR:%.1f Rip:%.1f Rake:%.1f", s.buff.savage_roar.remains, s.debuff.rip.remains, s.debuff.rake.remains),
        string.format("|cFFFFFF00Rec: %s > %s > %s|r", rec1, rec2, rec3),
    }

    ns.DebugFrame.text:SetText(table.concat(lines, "\n"))
    ns.DebugFrame:Show()
end
