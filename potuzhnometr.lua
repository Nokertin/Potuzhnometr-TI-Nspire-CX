-- POTUZHNOMETR v1.2
-- TI-Nspire CX (1st gen), Lua 5.1, API 2.0
-- v1.1 fix: Del key did not work in the editor, because the
-- handler was wrongly named on.backspace(). The correct TI
-- event is on.backspaceKey() - it fires on the handheld Del key.
-- v1.2: two modes on start - SHKALY (the old meters) and
-- TRUE / FALSE (green/red gauge, needle lands on TRUE or FALSE).
-- Only ASCII / English alphabet, translit labels.
-- A fun simulator: it does NOT measure anything real.
platform.apiLevel = "2.0"

local W, H = 318, 212
local initialized = false

local meters = nil
local sel = 1
local mode = "menu" -- menu, measure, edit, help (inside SHKALY mode)
local screen = "select" -- select, scales, tf
local topSel = 1 -- 1 SHKALY, 2 TRUE / FALSE
local tfAngle = 90 -- needle angle, deg: 180 = TRUE (left), 0 = FALSE (right)
local tfResult = nil -- "TRUE", "FALSE" or nil
local tfSpinning = false
local tfSpin = 0
local tfTrue = 0
local tfFalse = 0
local value = 0
local target = 0
local measuring = false
local exploded = false
local boom = 0
local tick = 0

local editMeter = nil
local editField = 1 -- 1 NAME, 2 UNIT, 3 MAX, 4 CRIT %
local editIsNew = false

local maxChoices = {10, 20, 50, 100, 200, 500, 1000}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function defaultMeters()
    return {
        {name = "POTUZHNOMETR", unit = "PW", max = 100, crit = 85},
        {name = "MANGOMETR", unit = "MG", max = 100, crit = 80},
        {name = "KOTOMETR", unit = "KT", max = 100, crit = 90},
    }
end

local function sanitizeMeters()
    if type(meters) ~= "table" or #meters == 0 then
        meters = defaultMeters()
    end
    for i = 1, #meters do
        local m = meters[i]
        if type(m) ~= "table" then
            meters[i] = {name = "METER " .. i, unit = "U", max = 100, crit = 85}
        else
            if type(m.name) ~= "string" or m.name == "" then m.name = "METER " .. i end
            if type(m.unit) ~= "string" or m.unit == "" then m.unit = "U" end
            if type(m.max) ~= "number" or m.max < 1 then m.max = 100 end
            if type(m.crit) ~= "number" then m.crit = 85 end
            m.crit = clamp(math.floor(m.crit + 0.5), 50, 99)
            m.name = string.upper(m.name)
            m.unit = string.upper(m.unit)
        end
    end
    sel = clamp(sel, 1, #meters)
end

local function init()
    if initialized then return end
    initialized = true
    sanitizeMeters()
    -- Stir the random generator a little. TI Lua has no os.time,
    -- so the sequence still differs from run to run in practice
    -- because math.random is called many times during play.
    math.randomseed(1234567)
    for i = 1, 20 do math.random() end
end

local function cur()
    sanitizeMeters()
    return meters[sel]
end

local function pct()
    local m = cur()
    if m.max == 0 then return 0 end
    return (value / m.max) * 100
end

local function verdictText(p)
    if exploded then return "BOOM! VZRYV!" end
    if measuring then return "IZMERYAEM..." end
    if p < 20 then return "SLABO"
    elseif p < 45 then return "NORM"
    elseif p < 70 then return "HOROSHO"
    elseif p < 85 then return "SILNO"
    elseif p < 100 then return "POTUZHNO!"
    else return "KRITICHNO!" end
end

local function zoneColor(p, m)
    if p >= m.crit then return 220, 40, 40 end
    if p >= 50 then return 230, 140, 0 end
    return 40, 160, 60
end

local function textWidth(gc, s)
    local ok, w = pcall(function() return gc:getStringWidth(s) end)
    if ok and type(w) == "number" then return w end
    return #s * 7
end

local function drawCenter(gc, s, y, size, bold, r, g, b)
    gc:setColorRGB(r, g, b)
    if bold then gc:setFont("sansserif", "b", size)
    else gc:setFont("sansserif", "r", size) end
    local w = textWidth(gc, s)
    gc:drawString(s, math.floor((W - w) / 2), y, "top")
end

local function drawLeft(gc, s, x, y, size, bold, r, g, b)
    gc:setColorRGB(r, g, b)
    if bold then gc:setFont("sansserif", "b", size)
    else gc:setFont("sansserif", "r", size) end
    gc:drawString(s, x, y, "top")
end

local function drawHeader(gc, title)
    gc:setColorRGB(25, 55, 130)
    gc:fillRect(0, 0, W, 26)
    drawCenter(gc, title, 5, 13, true, 255, 255, 255)
end

local function drawFooter(gc, line1, line2)
    gc:setColorRGB(90, 90, 90)
    gc:setFont("sansserif", "r", 9)
    if line2 then
        gc:drawString(line1, 6, H - 26, "top")
        gc:drawString(line2, 6, H - 14, "top")
    else
        gc:drawString(line1, 6, H - 16, "top")
    end
end

-- ---------- MENU ----------

local menuFirst = 1

local function drawMenu(gc)
    drawHeader(gc, "POTUZHNOMETR v1.2")
    drawLeft(gc, "VYBERI SHKALU:", 8, 32, 11, true, 0, 0, 0)
    -- show 5 items at a time, scroll when selection moves down
    if sel < menuFirst then menuFirst = sel end
    if sel > menuFirst + 4 then menuFirst = sel - 4 end
    if menuFirst > #meters - 4 and #meters > 5 then menuFirst = #meters - 4 end
    if menuFirst < 1 then menuFirst = 1 end
    local y0 = 50
    for i = menuFirst, #meters do
        local m = meters[i]
        local y = y0 + (i - menuFirst) * 26
        if y > H - 34 then break end
        if i == sel then
            gc:setColorRGB(190, 215, 255)
            gc:fillRect(4, y - 2, W - 8, 24)
            gc:setColorRGB(25, 55, 130)
            gc:drawRect(4, y - 2, W - 8, 24)
        end
        local label = i .. ". " .. m.name .. "  (" .. m.unit .. ", max " .. m.max .. ")"
        drawLeft(gc, label, 10, y, 11, i == sel, 0, 0, 0)
    end
    drawFooter(gc, "Up/Down: vybor   Enter: izmerit", "N: novaya   E: redakt.   D: udalit   H: pomosch")
end

-- ---------- START SCREEN: TWO MODES ----------

local function drawSelect(gc)
    drawHeader(gc, "POTUZHNOMETR v1.2")
    drawCenter(gc, "VYBERI REZHIM:", 38, 13, true, 0, 0, 0)
    local items = {
        {title = "1. SHKALY", desc = "Potuzhnometr, Mangometr, Kotometr"},
        {title = "2. TRUE / FALSE", desc = "Strelka: TRUE ili FALSE?"},
    }
    for i = 1, 2 do
        local y = 62 + (i - 1) * 52
        if i == topSel then
            gc:setColorRGB(190, 215, 255)
            gc:fillRect(8, y - 2, W - 16, 44)
            gc:setColorRGB(25, 55, 130)
            gc:drawRect(8, y - 2, W - 16, 44)
        end
        drawLeft(gc, items[i].title, 20, y + 2, 13, true, 0, 0, 0)
        drawLeft(gc, items[i].desc, 20, y + 22, 10, false, 60, 60, 60)
    end
    drawFooter(gc, "Up/Down: vybor   Enter: otkryt", "1: shkaly   2: true / false")
end

-- ---------- TRUE / FALSE ----------

local function drawTF(gc)
    drawHeader(gc, "TRUE / FALSE")
    local cx = math.floor(W / 2)
    local cy = 142
    local r = 72

    -- coloured arc ticks: left half green (TRUE), right half red (FALSE),
    -- a small orange strip at the top, like the picture
    for deg = 0, 180, 5 do
        local ang = math.rad(deg)
        local x1 = cx + math.floor((r - 13) * math.cos(ang) + 0.5)
        local y1 = cy - math.floor((r - 13) * math.sin(ang) + 0.5)
        local x2 = cx + math.floor(r * math.cos(ang) + 0.5)
        local y2 = cy - math.floor(r * math.sin(ang) + 0.5)
        if deg > 95 then gc:setColorRGB(40, 160, 60)
        elseif deg >= 85 then gc:setColorRGB(230, 140, 0)
        else gc:setColorRGB(220, 40, 40) end
        gc:setPen("thick", "smooth")
        gc:drawLine(x1, y1, x2, y2)
    end
    gc:setPen("thin", "smooth")
    gc:setColorRGB(0, 0, 0)
    gc:drawArc(cx - r, cy - r, r * 2, r * 2, 0, 180)
    gc:drawArc(cx - r + 13, cy - r + 13, (r - 13) * 2, (r - 13) * 2, 0, 180)

    -- needle
    local ang = math.rad(tfAngle)
    local nx = cx + math.floor((r - 16) * math.cos(ang) + 0.5)
    local ny = cy - math.floor((r - 16) * math.sin(ang) + 0.5)
    gc:setColorRGB(40, 40, 40)
    gc:setPen("thick", "smooth")
    gc:drawLine(cx, cy, nx, ny)
    gc:setPen("thin", "smooth")
    gc:fillArc(cx - 6, cy - 6, 12, 12, 0, 360)

    -- result text inside the gauge
    if tfSpinning then
        drawCenter(gc, "DUMAEM...", 96, 14, true, 90, 90, 90)
    elseif tfResult == "TRUE" then
        drawCenter(gc, "TRUE!", 96, 18, true, 40, 160, 60)
    elseif tfResult == "FALSE" then
        drawCenter(gc, "FALSE!", 96, 18, true, 220, 40, 40)
    else
        drawCenter(gc, "?", 96, 18, true, 90, 90, 90)
    end

    -- TRUE / FALSE labels, the result one is coloured
    if tfResult == "TRUE" then
        drawLeft(gc, "TRUE", 16, cy + 4, 16, true, 40, 160, 60)
    else
        drawLeft(gc, "TRUE", 16, cy + 4, 16, true, 0, 0, 0)
    end
    if tfResult == "FALSE" then
        drawLeft(gc, "FALSE", W - 76, cy + 4, 16, true, 220, 40, 40)
    else
        drawLeft(gc, "FALSE", W - 76, cy + 4, 16, true, 0, 0, 0)
    end

    drawCenter(gc, "TRUE: " .. tfTrue .. "    FALSE: " .. tfFalse, 176, 11, true, 0, 0, 0)
    drawFooter(gc, "Enter: KRUTIT   R: sbros scheta", "Esc: nazad k vyboru rezhima")
end

local function startTF()
    if tfSpinning then return end
    tfResult = nil
    tfSpinning = true
    tfSpin = 0
    timer.start(0.05)
    platform.window:invalidate()
end

-- ---------- MEASURE ----------

local function drawMeasure(gc)
    local m = cur()
    drawHeader(gc, m.name)
    local cx = math.floor(W / 2)
    local cy = 158
    local r = 74
    local p = pct()
    local pShow = clamp(p, 0, 100)

    -- coloured scale ticks on the arc, 0% left -> 100% right
    for pp = 0, 100, 5 do
        local ang = math.rad(180 - pp * 1.8)
        local x1 = cx + math.floor((r - 9) * math.cos(ang) + 0.5)
        local y1 = cy - math.floor((r - 9) * math.sin(ang) + 0.5)
        local x2 = cx + math.floor(r * math.cos(ang) + 0.5)
        local y2 = cy - math.floor(r * math.sin(ang) + 0.5)
        local cr, cg, cb = zoneColor(pp, m)
        gc:setColorRGB(cr, cg, cb)
        gc:setPen("thick", "smooth")
        gc:drawLine(x1, y1, x2, y2)
    end
    gc:setPen("thin", "smooth")

    -- arc outline, top semicircle: start 0 deg, turn 180 deg
    gc:setColorRGB(0, 0, 0)
    gc:drawArc(cx - r, cy - r, r * 2, r * 2, 0, 180)
    gc:drawArc(cx - r + 9, cy - r + 9, (r - 9) * 2, (r - 9) * 2, 0, 180)

    -- tick labels
    gc:setColorRGB(90, 90, 90)
    gc:setFont("sansserif", "r", 9)
    gc:drawString("0", cx - r - 2, cy - 4, "top")
    gc:drawString("100", cx + r - 16, cy - 4, "top")
    gc:drawString(tostring(m.max), cx - 8, cy - r - 14, "top")

    -- needle
    local ang = math.rad(180 - pShow * 1.8)
    local nx = cx + math.floor((r - 14) * math.cos(ang) + 0.5)
    local ny = cy - math.floor((r - 14) * math.sin(ang) + 0.5)
    local cr, cg, cb = zoneColor(p, m)
    gc:setColorRGB(cr, cg, cb)
    gc:setPen("thick", "smooth")
    gc:drawLine(cx, cy, nx, ny)
    gc:setPen("thin", "smooth")
    gc:setColorRGB(0, 0, 0)
    gc:fillArc(cx - 6, cy - 6, 12, 12, 0, 360)

    -- big value
    local valStr = tostring(value) .. " " .. m.unit
    drawCenter(gc, valStr, 96, 20, true, cr, cg, cb)
    drawCenter(gc, string.format("%d%%", math.floor(p + 0.5)), 120, 12, true, 0, 0, 0)

    -- verdict / status
    local vt = verdictText(p)
    local vr, vg, vb = 0, 0, 0
    if exploded then vr, vg, vb = 220, 0, 0
    elseif p >= m.crit then vr, vg, vb = 220, 40, 40 end
    drawCenter(gc, vt, 168, 13, true, vr, vg, vb)

    -- explosion animation
    if exploded then
        gc:setColorRGB(220, 0, 0)
        gc:setPen("thick", "smooth")
        for i = 1, 10 do
            local a = math.random(0, 359)
            local rr = 26 + math.random(0, 22) + boom
            local x1 = cx + math.floor(14 * math.cos(math.rad(a)) + 0.5)
            local y1 = cy - 42 + math.floor(14 * math.sin(math.rad(a)) + 0.5)
            local x2 = cx + math.floor(rr * math.cos(math.rad(a)) + 0.5)
            local y2 = cy - 42 + math.floor(rr * math.sin(math.rad(a)) + 0.5)
            gc:drawLine(x1, y1, x2, y2)
        end
        gc:setPen("thin", "smooth")
        drawCenter(gc, "BOOM!", 36, 24, true, 220, 0, 0)
    end

    if measuring then
        drawFooter(gc, "Enter: STOP")
    else
        drawFooter(gc, "Enter: IZMERIT   R: sbros", "Esc: nazad v menju")
    end
end

-- ---------- EDIT / CREATE CUSTOM METER ----------

local function startEdit(isNew)
    editIsNew = isNew
    editField = 1
    if isNew then
        editMeter = {name = "", unit = "", max = 100, crit = 85}
    else
        local m = cur()
        editMeter = {name = m.name, unit = m.unit, max = m.max, crit = m.crit}
    end
    mode = "edit"
    platform.window:invalidate()
end

local function maxIndex(v)
    for i = 1, #maxChoices do
        if maxChoices[i] == v then return i end
    end
    return 4
end

local function saveEdit()
    if editMeter == nil then return end
    if editMeter.name == nil or editMeter.name == "" then editMeter.name = "METER" end
    if editMeter.unit == nil or editMeter.unit == "" then editMeter.unit = "U" end
    editMeter.name = string.upper(editMeter.name)
    editMeter.unit = string.upper(editMeter.unit)
    if editIsNew then
        meters[#meters + 1] = editMeter
        sel = #meters
    else
        meters[sel] = editMeter
    end
    sanitizeMeters()
    editMeter = nil
    mode = "menu"
    platform.window:invalidate()
end

local function drawEdit(gc)
    if editMeter == nil then mode = "menu" return end
    if editIsNew then drawHeader(gc, "NOVAYA SHKALA")
    else drawHeader(gc, "REDAKTOR SHKALY") end

    local fields = {
        "NAME:  " .. editMeter.name,
        "UNIT:  " .. editMeter.unit,
        "MAX:  " .. tostring(editMeter.max),
        "KRIT %:  " .. tostring(editMeter.crit),
    }
    local y0 = 44
    for i = 1, 4 do
        local y = y0 + (i - 1) * 28
        if i == editField then
            gc:setColorRGB(190, 215, 255)
            gc:fillRect(4, y - 3, W - 8, 24)
        end
        drawLeft(gc, fields[i], 12, y, 12, i == editField, 0, 0, 0)
        if i == editField then
            drawLeft(gc, "<", W - 22, y, 12, true, 25, 55, 130)
        end
    end
    drawLeft(gc, "Pechatay bukvy i tsifry.", 8, 164, 10, false, 0, 0, 0)
    drawFooter(gc, "Up/Down: pole   Left/Right: chislo", "Enter: dalshe / sohranit   Esc: otmena")
end

-- ---------- HELP ----------

local function drawHelp(gc)
    drawHeader(gc, "POMOSCH")
    local lines = {
        "Eto shutochny simulator.",
        "On nichego ne izmeryaet",
        "po-nastoyaschemu.",
        "",
        "Dva rezhima na starte:",
        "SHKALY i TRUE / FALSE.",
        "Esc v menju shkal - nazad",
        "k vyboru rezhima.",
        "",
        "MENU: Up/Down, Enter.",
        "N - novaya shkala,",
        "E - redaktirovat,",
        "D - udalit shkaly.",
        "",
        "IZMERENIE: Enter - start,",
        "Up - podkachat vruchnuyu.",
        "Esli znachenie vyshe MAX -",
        "shkala vzryvaetsya :)",
        "",
        "TRUE / FALSE: Enter -",
        "krutit strelku, R - sbros",
        "scheta TRUE / FALSE.",
        "",
        "Shkaly sohranyayutsya",
        "v dokumente (.tns).",
    }
    local y = 34
    gc:setFont("sansserif", "r", 11)
    gc:setColorRGB(0, 0, 0)
    for i = 1, #lines do
        gc:drawString(lines[i], 10, y, "top")
        y = y + 13
        if y > H - 20 then break end
    end
    drawFooter(gc, "Esc: nazad v menju")
end

-- ---------- MEASURE LOGIC ----------

local function startMeasure()
    local m = cur()
    value = 0
    exploded = false
    boom = 0
    local roll = math.random(1, 100)
    local pTarget
    if roll <= 65 then
        pTarget = math.random(8, 88)
    elseif roll <= 90 then
        pTarget = math.random(89, 99)
    else
        pTarget = math.random(101, 118)
    end
    target = math.floor(m.max * pTarget / 100 + 0.5)
    measuring = true
    timer.start(0.05)
    platform.window:invalidate()
end

local function stopMeasure()
    measuring = false
    timer.stop()
    platform.window:invalidate()
end

-- ---------- EVENTS ----------

function on.resize(w, h)
    if type(w) == "number" and w > 0 then W = w end
    if type(h) == "number" and h > 0 then H = h end
end

function on.create()
    init()
end

function on.construction()
    init()
end

function on.paint(gc)
    init()
    gc:setColorRGB(255, 255, 255)
    gc:fillRect(0, 0, W, H)
    if screen == "select" then
        drawSelect(gc)
    elseif screen == "tf" then
        drawTF(gc)
    elseif mode == "menu" then
        drawMenu(gc)
    elseif mode == "measure" then
        drawMeasure(gc)
    elseif mode == "edit" then
        drawEdit(gc)
    elseif mode == "help" then
        drawHelp(gc)
    end
end

function on.timer()
    init()
    tick = tick + 1
    if tfSpinning then
        tfSpin = tfSpin + 1
        tfAngle = math.random(15, 165)
        if tfSpin >= 26 then
            tfSpinning = false
            timer.stop()
            if math.random(1, 2) == 1 then
                tfResult = "TRUE"
                tfAngle = 135
                tfTrue = tfTrue + 1
            else
                tfResult = "FALSE"
                tfAngle = 45
                tfFalse = tfFalse + 1
            end
        end
        platform.window:invalidate()
        return
    end
    if measuring then
        local m = cur()
        local step = math.max(1, math.floor(m.max * math.random(1, 3) / 100 + 0.5))
        value = value + step
        if value >= target then
            value = target
            measuring = false
            if value > m.max then
                exploded = true
                boom = 0
                timer.start(0.12)
            else
                timer.stop()
            end
        end
    elseif exploded then
        boom = boom + 1
        if boom >= 14 then
            timer.stop()
        end
    else
        timer.stop()
    end
    platform.window:invalidate()
end

function on.enterKey()
    init()
    if screen == "select" then
        if topSel == 1 then
            screen = "scales"
            mode = "menu"
        else
            screen = "tf"
            tfAngle = 90
            tfResult = nil
        end
    elseif screen == "tf" then
        startTF()
    elseif mode == "menu" then
        value = 0
        exploded = false
        measuring = false
        mode = "measure"
    elseif mode == "measure" then
        if measuring then stopMeasure()
        else startMeasure() end
    elseif mode == "edit" then
        if editField < 4 then
            editField = editField + 1
        else
            saveEdit()
        end
    elseif mode == "help" then
        mode = "menu"
    end
    platform.window:invalidate()
end

function on.escapeKey()
    init()
    if screen == "tf" then
        tfSpinning = false
        timer.stop()
        screen = "select"
    elseif screen == "scales" and mode == "menu" then
        screen = "select"
    elseif mode == "measure" then
        stopMeasure()
        exploded = false
        mode = "menu"
    elseif mode == "edit" then
        editMeter = nil
        mode = "menu"
    elseif mode == "help" then
        mode = "menu"
    end
    platform.window:invalidate()
end

local function deleteLastChar()
    if mode == "edit" and editMeter ~= nil then
        if editField == 1 and #editMeter.name > 0 then
            editMeter.name = string.sub(editMeter.name, 1, #editMeter.name - 1)
        elseif editField == 2 and #editMeter.unit > 0 then
            editMeter.unit = string.sub(editMeter.unit, 1, #editMeter.unit - 1)
        end
        platform.window:invalidate()
    end
end

-- Correct TI event name: on.backspaceKey() fires on the
-- handheld Del key (and on Backspace on a desktop keyboard).
-- The old on.backspace() never fired - that was the v1.0 bug.
function on.backspaceKey()
    init()
    deleteLastChar()
end

-- Desktop Delete key, as a backup.
function on.deleteKey()
    init()
    deleteLastChar()
end

-- Ctrl+Clear on the handheld: clear the whole NAME / UNIT field.
function on.clearKey()
    init()
    if mode == "edit" and editMeter ~= nil then
        if editField == 1 then editMeter.name = ""
        elseif editField == 2 then editMeter.unit = "" end
        platform.window:invalidate()
    end
end

function on.arrowKey(key)
    init()
    if screen == "select" then
        if key == "up" or key == "down" then
            if topSel == 1 then topSel = 2 else topSel = 1 end
        end
    elseif screen == "tf" then
        -- Left / Right: point the needle manually, without counting
        if not tfSpinning then
            if key == "left" then
                tfResult = "TRUE"
                tfAngle = 135
            elseif key == "right" then
                tfResult = "FALSE"
                tfAngle = 45
            end
        end
    elseif mode == "menu" then
        if key == "up" then
            sel = sel - 1
            if sel < 1 then sel = #meters end
        elseif key == "down" then
            sel = sel + 1
            if sel > #meters then sel = 1 end
        end
    elseif mode == "measure" then
        -- manual pump: Up adds a little, Down takes a little off
        if key == "up" and not measuring then
            local m = cur()
            value = clamp(value + math.max(1, math.floor(m.max / 20)), 0, m.max)
            if value > m.max then exploded = true end
        elseif key == "down" and not measuring then
            value = clamp(value - 1, 0, 1000000)
            exploded = false
        end
    elseif mode == "edit" and editMeter ~= nil then
        if key == "up" then
            editField = editField - 1
            if editField < 1 then editField = 4 end
        elseif key == "down" then
            editField = editField + 1
            if editField > 4 then editField = 1 end
        elseif key == "left" or key == "right" then
            local d = 1
            if key == "left" then d = -1 end
            if editField == 3 then
                local idx = maxIndex(editMeter.max) + d
                if idx < 1 then idx = #maxChoices end
                if idx > #maxChoices then idx = 1 end
                editMeter.max = maxChoices[idx]
            elseif editField == 4 then
                editMeter.crit = clamp(editMeter.crit + d * 5, 50, 99)
            end
        end
    end
    platform.window:invalidate()
end

function on.charIn(ch)
    init()
    if type(ch) ~= "string" or ch == "" then return end
    local low = string.lower(ch)
    if screen == "select" then
        if ch == "1" then
            screen = "scales"
            mode = "menu"
        elseif ch == "2" or low == "t" then
            screen = "tf"
            tfAngle = 90
            tfResult = nil
        end
        platform.window:invalidate()
        return
    end
    if screen == "tf" then
        if ch == " " then
            startTF()
        elseif low == "b" then
            tfSpinning = false
            timer.stop()
            screen = "select"
        elseif low == "r" then
            tfTrue = 0
            tfFalse = 0
            tfResult = nil
            tfAngle = 90
        end
        platform.window:invalidate()
        return
    end
    if mode == "menu" then
        if low == "n" then
            startEdit(true)
        elseif low == "e" then
            startEdit(false)
        elseif low == "d" then
            if #meters > 1 then
                table.remove(meters, sel)
                sanitizeMeters()
            end
        elseif low == "h" then
            mode = "help"
        end
    elseif mode == "measure" then
        if ch == " " then
            if measuring then stopMeasure() else startMeasure() end
        elseif low == "b" then
            stopMeasure()
            exploded = false
            mode = "menu"
        elseif low == "r" and not measuring then
            value = 0
            exploded = false
        end
    elseif mode == "edit" and editMeter ~= nil then
        -- Fallback: some keyboards send Del as a backspace char.
        if ch == "\b" or ch == "\127" then
            deleteLastChar()
            return
        end
        if editField == 1 then
            if string.find(ch, "^[A-Za-z0-9 ]$") and #editMeter.name < 14 then
                editMeter.name = editMeter.name .. string.upper(ch)
            end
        elseif editField == 2 then
            if string.find(ch, "^[A-Za-z0-9]$") and #editMeter.unit < 4 then
                editMeter.unit = editMeter.unit .. string.upper(ch)
            end
        end
    end
    platform.window:invalidate()
end

function on.mouseDown(x, y)
    init()
    if screen == "select" then
        if y >= 60 and y < 104 then
            topSel = 1
            screen = "scales"
            mode = "menu"
        elseif y >= 114 and y < 158 then
            topSel = 2
            screen = "tf"
            tfAngle = 90
            tfResult = nil
        end
    elseif screen == "tf" then
        if y > H - 34 then startTF() end
    elseif mode == "menu" then
        local idx = math.floor((y - 50) / 26) + menuFirst
        if idx >= 1 and idx <= #meters then
            if sel == idx then
                value = 0
                exploded = false
                measuring = false
                mode = "measure"
            else
                sel = idx
            end
        end
    elseif mode == "measure" then
        if y > H - 34 then
            if measuring then stopMeasure() else startMeasure() end
        end
    end
    platform.window:invalidate()
end

function on.save()
    init()
    return {meters = meters, sel = sel, tfTrue = tfTrue, tfFalse = tfFalse}
end

function on.restore(data)
    if type(data) == "table" then
        if type(data.meters) == "table" and #data.meters > 0 then
            meters = data.meters
        end
        if type(data.sel) == "number" then
            sel = data.sel
        end
        if type(data.tfTrue) == "number" then tfTrue = data.tfTrue end
        if type(data.tfFalse) == "number" then tfFalse = data.tfFalse end
    end
    initialized = false
    init()
    sanitizeMeters()
end
