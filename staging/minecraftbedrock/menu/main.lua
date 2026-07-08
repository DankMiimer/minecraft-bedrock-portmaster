-- MCPE Launcher version-selector menu.
-- Original by ImpressiveStay (R36S mcpe_launcher port); extended with
-- per-version architecture tags for the dual 32/64-bit port.
local versions = {}
local selected = 1
local W, H
local BG      = {0.08, 0.08, 0.10}
local ACCENT  = {0.20, 0.80, 0.40}
local FG      = {0.90, 0.90, 0.90}
local DIM     = {0.40, 0.40, 0.40}
local BLOCK_H = 52
local PADDING = 20

local fontTitolo
local fontTesto

local BASEDIR = os.getenv("MCPE_GAMEDIR")
local VERDIR = BASEDIR.."/versions"

local function fileExists(path)
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

local function abiTag(name)
    local has64 = fileExists(VERDIR.."/"..name.."/lib/arm64-v8a/libminecraftpe.so")
    local has32 = fileExists(VERDIR.."/"..name.."/lib/armeabi-v7a/libminecraftpe.so")
    if has64 and has32 then return " (32/64-bit)" end
    if has64 then return " (64-bit)" end
    if has32 then return " (32-bit)" end
    return ""
end

local function scanVersions()
    local p = io.popen("ls -d '"..VERDIR.."'/*/ 2>/dev/null")
    for line in p:lines() do
        local name = line:match(".+/(.-)/$")
        if name then
            table.insert(versions, {name = name, label = name..abiTag(name)})
        end
    end
    p:close()
    table.sort(versions, function(a, b) return a.name < b.name end)
end

local function writeSelected(ver)
    local f = io.open(BASEDIR.."/menu/selected_version.txt", "w")
    if f then f:write(ver); f:close() end
    love.event.quit(0)
end

function love.load()
    bgImage = love.graphics.newImage("bg.jpg")
    W, H = love.graphics.getDimensions()
    W = love.graphics.getWidth()
    H = love.graphics.getHeight()

    fontTitolo = love.graphics.newFont("font_titolo.ttf", 24)
    fontTesto = love.graphics.newFont("font_testo.ttf", 16)

    scanVersions()
    table.insert(versions, {name = "__EXIT__", label = "Exit"})
end

function love.draw()
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(bgImage, 0, 0, 0, W/bgImage:getWidth(), H/bgImage:getHeight())
    love.graphics.setColor(0,0,0,0.7)
    love.graphics.rectangle("fill", 0, 0, 360, H)

    love.graphics.setColor(ACCENT)
    love.graphics.setFont(fontTitolo)
    love.graphics.printf("MCPE Launcher", 36, 30, 320, "left")

    love.graphics.setColor(DIM)
    love.graphics.rectangle("fill", PADDING*3, 62, 280, 1)

    love.graphics.setFont(fontTesto)
    local startY = (H - #versions * BLOCK_H) / 2
    for i, v in ipairs(versions) do
        local y = startY + (i-1)*BLOCK_H
        local isExit = (v.name == "__EXIT__")
        if i == selected then
            love.graphics.setColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.15)
            love.graphics.rectangle("fill", PADDING, y+4, 320, BLOCK_H-8, 6, 6)
            love.graphics.setColor(ACCENT)
            love.graphics.rectangle("fill", PADDING, y+4, 4, BLOCK_H-8, 2, 2)
            love.graphics.setColor(isExit and {0.9,0.3,0.3} or FG)
        else
            love.graphics.setColor(isExit and {0.6,0.2,0.2} or DIM)
        end
        love.graphics.printf(v.label, PADDING+16, y+(BLOCK_H-16)/2, 320, "left")
    end
    love.graphics.setFont(love.graphics.newFont(11))
    love.graphics.setColor(DIM)
end

function love.keypressed(key)
    if key == "up" or key == "dpup" then
        selected = selected - 1
        if selected < 1 then selected = #versions end
    elseif key == "down" or key == "dpdown" then
        selected = selected + 1
        if selected > #versions then selected = 1 end
    elseif key == "return" or key == "a" or key == "space" then
        local v = versions[selected]
        if v.name == "__EXIT__" then writeSelected("") else writeSelected(v.name) end
    elseif key == "escape" then
        writeSelected("")
    end
end

function love.gamepadpressed(joystick, button)
    if button == "dpup" then love.keypressed("up")
    elseif button == "dpdown" then love.keypressed("down")
    elseif button == "a" then love.keypressed("return")
    elseif button == "b" then love.keypressed("escape")
    end
end
