-- Copyright (c) 2023, kounch
-- All rights reserved.
--
-- SPDX-License-Identifier: BSD-2-Clause


import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

local gfx <const> = playdate.graphics
gfx.setBackgroundColor(gfx.kColorWhite)


-----------------
-- Global vars --
-----------------

local configPath = nil    -- Path to current level pack config directory
local configData = nil    -- Current level pack config
local roomsData = nil     -- All rooms data (obtained from JSON)
local hiScore = nil       -- All times High Score
local crankRadius = 0     -- Used for crank controls

-- Image tables for sprites
local singleTable = nil   -- Big Images table (no animation) - Portals and some guardians
local multiTable = nil    -- Big Images table (animated) - Willy and guardians
local roomTable = nil     -- Small Images table - Room elements
local fallTable = nil     -- Constructed animation images for melting floors
local conveyTable = nil   -- Idem for conveyor belts
local switchTable = nil   -- Idem for switches (for Kong rooms)
local exitTable = nil     -- Idem for room portals
local bgImage = nil       -- Game background (bezel, etc.)
local menuImage = nil     -- Main Menu (and part of room 20) bacground image

-- Sprites
local bgSprite = nil      -- Room decoration background (frame, room name, etc.)
local roomSprite = nil    -- Sprite built with room tiles - Room elements
local killSprites = nil   -- Sprites for each killer element
local fallSprites = nil   -- Sprites for each melting floor element
local conveySprites = nil -- Sprites for each conveyor belt element
local keySprites = nil    -- Sprites for each key item
local exitSprite = nil    -- Sprite for room portal
local switchSprites = nil -- Sprites for switches (if needed)
local beamSprites = nil   -- Sprites for light beams (if needed)
local playerSprite = nil  -- Player Sprite

-- Tilemaps
local roomMap = nil       -- Room tilemap
local roomElements = nil  -- Partial tile map for room elements (melting floors ...)

-- Enemies
local hGuardianList = nil  -- List with sprites and attributes for horizontal guardians
local vGuardianList = nil  -- List with sprites and attributes for vertical guardians

-- Global Room Attributes
local roomX = 0           -- Horizontal displacement for room drawing in screen
local roomY = -1           -- Vertical displacement
local lscale = 0          -- Scale (used to convert to/from virtual coords and tile coords)
local gameStatus = 0      -- Global status (on game menu, playing, etc.)
local roomNumber = 0      -- Current room number
local roomStatus = 0      -- Current room status (to distinguis game over and game end)
local keyCount = 0        -- Number of keys remaining to open the current room portal
local blinkCount = 0      -- Counter for updating room sprites, etc.
local conveyLeft = false  -- Indicates if current room conveyor moves to the left
local tuneCount = 1       -- Counter for current music note / text banner displacement

-- Global Player Attributes
local playerx = 0         -- Virtual X coordinate (0-127) for player
local playery = 0         -- Virtual Y coordinate (0-127) for player
local playerleft = false  -- Is player facing left?
local onConveyor = false  -- Is player touching a conveyor?
local dx=0                -- Virtual X coordinate displacement vector
local pdx=0               -- Previous frame virtual X coordinate displacement vector
local jumpState = -1      -- Current player jump loop status
local gameScore = 0       -- Current game score
local diffGameScore = 0   -- Game score (for extra lives)
local isKill = false      -- Has the player been killed?
local gameLives = 0       -- Remaining player lives
local fallCount = 0       -- If falling, current fall length

-- Global game Attributes
local endRoom = false     -- Should finish current room?
local newRoom = false     -- Initialize a room?
local roomAir = 0         -- Remaining air for current room
local soundSynth = 2      -- Sound and music synthesis method (excluding Menu and emptyAir)
local cheatLevel = 0      -- No comments ;-)
local hasCheated = false
local ki = 1
local oldGameStatus = 0

-- Other
local iStep = 0           -- Global counter for foot step animation / Level Pack Menu / Demo mode
local mSynth = nil        -- Sound Synth for music
local sSynth = nil        -- Sound Synth for sound effects
local sSample = nil       -- Sound Sample for game ending
local bannerImage = nil   -- Text banner shown after playing main menu tune
local roomLoaded = false  -- Flag variable for room objects allocation status


---------------
-- Functions --
---------------

local function checkTileBounds (x, y)
    -- Check if a tile coordinates are within the bounds

    local inBounds = true
    if x<1 or y<1 then
        inBounds = false
    end
    if x>32 or y>16 then
        inBounds = false
    end
    return inBounds
end

local function checkWall(x,y)
    -- Check if a tile next to current player coordinates is a wall
    -- x,y denote which side should we check: x<0 left, x>0 right, y>0 up, y<0 down

    local tilex = (playerx+5) // 4  -- Current player tile x
    local tiley = 16 - playery // 8  -- Current player feet tile y
    local isWall = false

    if x ~= 0 then
        local mini = -2
        if playery%8 == 0 then
            mini = -1
        end
        for i = mini, 0 do
            if checkTileBounds(tilex + x, tiley + i) then
                local tileindex = roomMap:getTileAtPosition(tilex + x, tiley + i)
                if tileindex%9 == 4 then
                    isWall = true
                end
            end
        end
    end

    if y > 0 then
        local tdx = 1
        if playerx%4==3 then
            tdx = -1
        end

        local mini = math.min(0, tdx)
        local maxi = math.max(0, tdx)
        for i = mini, maxi do
            if checkTileBounds(tilex + i, tiley - 2) then
                local tileindex = roomMap:getTileAtPosition(tilex + i, tiley - 2)
                if tileindex%9 == 4 then
                    isWall = true
                end
            end
        end
    end

    return isWall
end

local function checkFloor()
    -- Given virtual player coordinates, find if the tiles below are a floor

    local tilex = (playerx+5) // 4  -- Current player tile x
    local tiley = 16 - playery // 8  -- Current player feet tile y

    onConveyor = false
    local isfloor = false

    local tdx = 1
    if playerx%4==3 then
        tdx = -1
    end
    local spaces = true
    for i = 0, 1 do
        if checkTileBounds(tilex + tdx, tiley - i) then
            local tileindex = roomMap:getTileAtPosition(tilex + tdx, tiley - i)
            if tileindex%9 == 4 then
                spaces = false
            end
        end
    end
    if not spaces then
        tdx = 0
    end

    local mini = math.min(0, tdx)
    local maxi = math.max(0, tdx)
    for i = mini, maxi do
        if checkTileBounds(tilex + i, tiley + 1) then
            local tileindex = roomMap:getTileAtPosition(tilex + i, tiley + 1)
            if tileindex%9 == 3 then
                local spriteState = roomElements[tiley + 1][tilex + i]
                if spriteState > 0 then
                    isfloor = true
                end
            elseif tileindex%9>1 and tileindex%9<6 or tileindex%9==8 then
                isfloor = true
                if tileindex%9 == 5 then
                    onConveyor = true
                end
            end
        end
    end
    return isfloor
end

local function checkPlayerMove(x,y)
    -- Check if desired player movement is valid, and alter virtual coordinates accordingly
    -- x,y denote the desired change in coordinates, i.e. playerx + x, playery + y

    local moved = false
    local stop = false
    local fall = false

    -- Adjust movement if player is on a conveyor belt
    if onConveyor and playery%8==0 then
        local dcx = 1
        if conveyLeft then
            dcx = -1
        end
        if dcx == dx then    -- Player already moving in the conveyor direction
            x = dcx
        else                 -- Moving in the opposite direction
            if pdx == dcx then  -- Was previously moving in the conveyor direction
                x = dcx
                dx = dcx
            else
                if x == 0 then
                    x = dcx
                end
            end
        end
    else
        onConveyor = false
    end
    pdx = dx  -- Record previous movement direction

    if x>0 then  -- Moving to the right
        if dx==1 then
            if playerx+x<128 then
                if playerx%4~=3 or not checkWall(x,y) then
                    playerx += x
                    moved = true
                end
            else
                dx = 0  -- It's a wall or offlimits
            end
        else
            dx += 1
            playerleft = false
        end
    elseif x<0 then  -- Moving to the left
        if dx==-1 then
            if playerx+x>0 then
                if playerx%4~=0 or not checkWall(x,y) then
                    playerx += x
                    moved = true
                end
            else
                dx = 0  -- It's a wall or offlimits
            end
        else
            dx -= 1
            playerleft = true
        end
    else
        dx = 0  -- No horizontal movement
    end

    if y>0 then  -- Jumping Up
        if playery+y<128 then
            if playery%8==0 then  -- Will move to a different tile
                if checkWall(0,y) then  -- Next tile is a ceiling?
                    if jumpState > -1 then
                        moved = false
                        if checkFloor() then  -- Landing on a floor tile?
                            stop = true
                        end
                    end
                else
                    playery += y
                    moved = true
                end
            else
                playery += y
                moved = true
            end
        end
    elseif y<0 then  -- Falling
        if playery+y>0 then
            playery += y
            if playery%8 == 0 then  -- Moving to a different tile
                if checkWall(x,y) and moved then  -- Next tile is a wall?
                    playerx -= x
                end
                if checkFloor() then  -- Landing on a floor tile?
                    stop = true
                end
            end
            moved = true
        else
            playery = 0
            moved = true
        end
    else  -- No vertical movement
        if jumpState<0 then
            if not checkFloor() then  -- Fall if there's no floor below
                if jumpState>-2 then
                    fall = true
                end
            end
        end
    end

    return moved, stop, fall
end

local function getElementCoords(tilex, tiley)
    -- Converts tile coordinates to real screen coordinates for room element sprites

    local i_sm = 64 * lscale
    local i_bg = 128 * lscale

    local basex = roomX + 200 - i_bg
    local basey = roomY + 96 - i_sm

    local rectX = basex - 1
    local rectY = basey - 1

    local realx = 1 + rectX + (tilex - 0.5) * 8 * lscale
    local realy = rectY + 1 + (tiley - 0.5) * 8 * lscale

    return realx, realy
end

local function getSpriteAttribs(virtualx, virtualy, mirrored)
    -- Converts pixel coordinates with origin in room local (0-127,0-119) to
    -- sprite (16x16) screen coordinates, applying displacement (and scaling if needed)
    -- Calculate animation sprite index depending on X coordinate and mirrored state

    mirrored = mirrored or false

    --Room Origin (left,down)
    local i_sm = 64 * lscale
    local i_bg = 128 * lscale
    local origx = roomX + 200 - i_bg
    local origy = roomY + 96 + i_sm

    --Sprite is 16x16 so the center is displaced by 8 right, 8 up, pixels
    origx += 8 * lscale
    origy -= 8 * lscale

    local realx = origx + (2 * virtualx) // 8 * 8 * lscale  --4 frames share the same x
    local realy = origy - virtualy * lscale

    local spriteid = 1 + virtualx % 4
    if mirrored then
        spriteid += 4
    end

    return realx, realy, spriteid
end

local function doBeep(tSynth, counter, volume, length)
    -- Converts from Frequency Divider counter to frequency in Hz and plays a note

    local freq = 440 * 109 / counter
    tSynth:playNote(freq, volume,  length)
end

local function doFall()
    -- Fall movement animation and control, including death detection

    if jumpState==-2 then
        local _, stop, _ = checkPlayerMove(0, -4)
        local getx, gety, getid = getSpriteAttribs(playerx, playery, playerleft)
        playerSprite:moveTo(getx,gety)
        playerSprite:setImage(multiTable:getImage(getid))
        fallCount += 1
        local mVol = 0.1
        local mLength = 0.05
        doBeep(sSynth, 16 * fallCount, mVol,  mLength)
        if stop then
            jumpState = -1
            if cheatLevel < 4 and fallCount > 11 then
                isKill = true
            end
            fallCount = 0
            pdx = 1
            if playerleft then
                pdx = -1
            end
        end
    end
end

local function doJump()
    -- Jump movement animation and control

    if jumpState>-1 and jumpState<18 then
        local mVol = 0.1
        local mLength = 0.05
        doBeep(sSynth, 8*(1+math.abs(jumpState-8)),  mVol,  mLength)
        local jy = 4 - jumpState // 2
        local moved, stop, fall = checkPlayerMove(dx, jy)
        if jy==0 or moved then
            local getx, gety, getid = getSpriteAttribs(playerx, playery, playerleft)
            playerSprite:moveTo(getx,gety)
            playerSprite:setImage(multiTable:getImage(getid))
            jumpState += 1
            if stop then
                jumpState = -1
            end
        else
            if jumpState<9 then
                jumpState = 17 - jumpState
            end
            jumpState += 1
            if stop then
                jumpState = -1
            end
        end
    else
        jumpState = -1
        if not checkFloor() then
            fallCount = 6
            jumpState = -2
            doFall()
        end
    end
end

local function updateSoundSynth()
    -- Changes the sound synth according to global configuration

    -- Stop synths before any change
    if mSynth ~= nil then
        mSynth:stop()
    end
    if sSynth ~= nil then
        sSynth:stop()
    end

    if soundSynth == 1 then
        mSynth = playdate.sound.synth.new(playdate.sound.kWaveSine)
        sSynth = playdate.sound.synth.new(playdate.sound.kWaveSine)
    else
        mSynth = playdate.sound.synth.new(playdate.sound.kWaveSquare)
        sSynth = playdate.sound.synth.new(playdate.sound.kWaveSquare)
    end

    -- Special case for main menu and EmptyAir()
    if gameStatus == 0 or gameStatus == 2 then
        mSynth = playdate.sound.synth.new(playdate.sound.kWaveSawtooth)
        sSynth = playdate.sound.synth.new(playdate.sound.kWaveSawtooth)
    end
end

local function loadData()
    -- Load all static assets

    print("Loading assets...")
    local roomsFile = playdate.file.open(configPath .. configData.Levels .. ".json")
    assert(roomsFile)
    roomsData = json.decodeFile(roomsFile)
    assert(roomsData)

    singleTable = nil
    multiTable = nil
    roomTable = nil
    menuImage = nil

    menuImage = gfx.image.new(configPath .. configData.Menu)
    assert(menuImage)
    singleTable = gfx.imagetable.new(configPath .. configData.SingleSprites)
    assert(singleTable)
    multiTable = gfx.imagetable.new(configPath .. configData.MultipleSprites)
    assert(multiTable)
    roomTable = gfx.imagetable.new(configPath .. configData.Blocks)
    assert(roomTable)

    print("Load OK")
end

local function buildData()
    -- Initialize all dynamic assets

    print("Building assets...")
    fallTable = gfx.imagetable.new(9, 1)
    conveyTable = gfx.imagetable.new(4, 8)
    switchTable = gfx.imagetable.new(2, 1)
    exitTable = gfx.imagetable.new(2, 1)

    print("Build OK")
end

local function buildBgSprite(room)
    -- Builds the background sprite (bezel for room with white background)
    -- The position and index were already defined in function gameSetUp()

    local i_sm = 64 * lscale
    local i_bg = 128 * lscale
    local i_hg = 256 * lscale

    local basex = roomX + 200 - i_bg
    local basey = roomY + 96 - i_sm

    local rectX = basex
    local rectY = basey
    local rectW = i_hg
    local rectH = i_bg

    gfx.lockFocus(bgImage)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(0, 0, 400, 240)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(1)
    gfx.drawRect(rectX-1, rectY, rectW+2, rectH) -- game room space
    gfx.drawTextAligned(room.name, 205, 220, kTextAlignment.center)
    if roomNumber==#roomsData then  -- Last level uses part of the main screen
        local tmpImage = gfx.image.new(configPath .. configData.Menu)
        tmpImage:draw(rectX, rectY, gfx.kImageUnflipped, 0, 0, i_hg, 56 * lscale)
    end
    gfx.unlockFocus()
    bgSprite:setImage(bgImage)  -- Background sprite
    bgSprite:setVisible(true)
end

local function buildAnimationTables(room, portal)
    -- Builds image tables for current room animations based on static image tables

    -- Build animation image table for falling floor
    for i = 0, 8, 1 do
        local tmpg = gfx.image.new(8 * lscale, 8 * lscale, gfx.kColorWhite)
        if i<8 then gfx.lockFocus(tmpg)
            roomTable:getImage(room.id * 9 + 3):draw(0, i * lscale)  -- Original image
            gfx.unlockFocus()
        end
        fallTable:setImage(i+1, tmpg)
    end

    -- Build animation image table for conveyor
    for i = 0,3 do
        local tmpg = gfx.image.new(8 * lscale, 8 * lscale, gfx.kColorWhite)  -- Get original image
        local width, _ = tmpg:getSize()
        gfx.pushContext(tmpg)
        local gtmp = roomTable:getImage(room.id * 9 + 5)
        gtmp:draw(0, lscale, gfx.kImageUnflipped, 0, lscale, width, 2 * lscale)  -- Copy upper part
        gtmp:draw(0, 4 * lscale, gfx.kImageUnflipped, 0, 4 * lscale, width, 4 * lscale) -- Copy below part
        local x1 = 2 * i * lscale
        local x2 = x1 - width
        if conveyLeft then
            x1 = -x1
            x2 = -x2
        end
        gtmp:draw(x1, 0, gfx.kImageUnflipped, 0, 0, width, lscale)  -- Scroll top left
        gtmp:draw(x2, 0, gfx.kImageUnflipped, 0, 0, width, lscale)  -- Scroll top right
        gtmp:draw(-x1, 3 * lscale, gfx.kImageUnflipped, 0, 3 * lscale, width, lscale) -- Scroll bottom left
        gtmp:draw(-x2, 3 * lscale, gfx.kImageUnflipped, 0, 3 * lscale, width, lscale) -- Scroll bottom right
        gfx.popContext()
        conveyTable:setImage(1+i, tmpg)
    end

    -- Build animation image table for switches
    local tmpg = gfx.image.new(8 * lscale, 8 * lscale, gfx.kColorWhite)
    gfx.lockFocus(tmpg)
    roomTable:getImage(room.id * 9 + 8):draw(0, 0)  -- Get base image
    switchTable:setImage(1, tmpg)  -- Original image
    tmpg = gfx.image.new(8 * lscale, 8 * lscale, gfx.kColorWhite)
    gfx.lockFocus(tmpg)
    roomTable:getImage(room.id * 9 + 8):draw(0, 0, gfx.kImageFlippedX)  -- Flip!
    gfx.unlockFocus()
    switchTable:setImage(2, tmpg)  -- Flipped image

    -- Build animation image table for portals
    local tmpg = gfx.image.new(16 * lscale, 16 * lscale, gfx.kColorWhite)
    gfx.lockFocus(tmpg)
    singleTable:getImage(room.portal.id):draw(0, 0) -- Portal sprite
    gfx.unlockFocus()
    exitTable:setImage(1, tmpg)  -- Original image
    tmpg = tmpg:invertedImage()  -- Invert!
    exitTable:setImage(2, tmpg)  -- Inverted image
end

local function buildSwitchSprites()
    -- Build sprites for switches (Kong rooms)

    switchSprites = {}
    for i = 1, 2 do
        local tx = 7 + 12 * (i - 1)
        local getx, gety = getElementCoords(tx, 1)
        local switchSprite = gfx.sprite.new(switchTable:getImage(1))
        switchSprite:setCollideRect(0, 0, switchSprite:getSize())
        switchSprite.collisionResponse = gfx.sprite.kCollisionTypeOverlap
        switchSprite:setZIndex(-32)
        switchSprite:moveTo(getx, gety)
        switchSprite:add()
        table.insert(switchSprites, switchSprite)
    end

    --Remove, if needed, wrong fall Sprites (Kong platform)
    if roomElements[3] then
        if roomElements[3][16] then
            --roomElements[3][16] = 0
            fallSprites[3][16]:remove()
            --roomElements[3][17] = 0
            fallSprites[3][17]:remove()
        end
    end
end

local function buildBeamSprites()
    -- Build sprites for light beams ()

    beamSprites = {}
    for i = 1, 3 do
        local beamSprite = gfx.sprite.addEmptyCollisionSprite(i, 0, 1, 1)
        table.insert(beamSprites, beamSprite)
    end
end

local function buildFallConveyKillSprites(room, tx, ty, baseid, tile)
    -- Build sprites for falling blocks, conveyor belts, and killer elements of room

    if not roomElements[ty] then
        roomElements[ty] = {}
    end
    if not fallSprites[ty] then
        fallSprites[ty] = {}
    end

    local getx, gety = getElementCoords(tx, ty)
    local tmpSprite = nil
    local tmpCollide = false
    if baseid==3 or baseid==5 then  -- Falling block (3) or conveyor (5)
        if baseid==3 then
            tmpSprite = gfx.sprite.new(fallTable:getImage(1))
        else
            tmpSprite = gfx.sprite.new(conveyTable:getImage(1))
        end
        if baseid==3 then
            roomElements[ty][tx] = 8
            fallSprites[ty][math.floor(tx)] = tmpSprite
        else
            table.insert(conveySprites, tmpSprite)
        end
    elseif baseid==6 or baseid==7 then  -- Killer element
        tmpSprite = gfx.sprite.new(roomTable:getImage(tile))
        tmpSprite:setCollideRect(0, 0, tmpSprite:getSize())
        tmpSprite.collisionResponse = gfx.sprite.kCollisionTypeOverlap
        table.insert(killSprites, tmpSprite)
    end

    if tmpSprite then
        tmpSprite:setZIndex(-64)
        tmpSprite:moveTo(getx, gety)
        tmpSprite:add()
    end
end

local function buildRoomSprite(room)
    -- Build sprite for the room elements using tiles

    local half = false

    local spriteRoomX = roomX + 200
    local spriteRoomY = roomY + 96

    -- Table with indexes to room table elements
    local attr = room.attr
    local data = {}
    local attrs = {}
    for i = 1, #attr, 2 do
        local attrib = attr:sub(i,i+1)
        if not attrs[attrib] then
            attrs[attrib] = 1 + i//2
        end
    end

    -- Build data for tilemap and room items partial table
    roomElements = {}
    fallSprites = {}
    conveySprites = {}
    killSprites = {}
    local spareCount = 0
    for ty, value in ipairs(room.data) do
        for i = 1, #value, 2 do
            local attrib = value:sub(i,i+1)
            local baseid = 1  -- Blank Space
            if attrs[attrib] then
                baseid = attrs[attrib]  -- Not last room attributes
            end
            local tile = room.id * 9 + baseid
            table.insert(data, tile)
            local tx = 1 + i // 2
            buildFallConveyKillSprites(room, tx, ty, baseid, tile)
            if baseid==8 then
                spareCount += 1  -- Detection of room with switches (only two extra tiles)
            end
        end
    end

    switchSprites = nil
    if spareCount==2 then  -- Detect Kong room (with two switches using extra tiles)
        if data[3]%9==7 and data[7]%9==8 and data[11]%9==7 and data[19]%9==8 then
            buildSwitchSprites()
            half = true
        end
    end

    beamSprites = nil
    if room.special.Solar then
        buildBeamSprites()
    end

    roomMap = gfx.tilemap.new()
    roomMap:setImageTable(roomTable)
    roomMap:setTiles(data, #room.data[1] // 2)
    roomSprite = gfx.sprite.new()  -- Room sprite
    roomSprite:setTilemap(roomMap)
    roomSprite:setZIndex(-128)
    roomSprite:moveTo(spriteRoomX, spriteRoomY)
    roomSprite:add()

    return half
end

local function buildKeySprites(room)
    -- Builds sprites for all items (keys) in a room

    keySprites = {}
    keyCount = 0
    for i, value in ipairs(room.items) do
        local itemXY = tonumber(value, 16) - 23583
        local itemX = itemXY % 32
        local itemY = 2 + itemXY // 32
        local getx, gety = getElementCoords(itemX, itemY)
        local tmpSprite = gfx.sprite.new(roomTable:getImage(room.id * 9 + 9))
        tmpSprite:setCollideRect(0,0, tmpSprite:getSize())
        tmpSprite.collisionResponse = gfx.sprite.kCollisionTypeOverlap
        tmpSprite:setZIndex(-32)
        tmpSprite:moveTo(getx, gety)
        tmpSprite:add()
        table.insert(keySprites, tmpSprite)
        keyCount += 1
    end
end

local function buildExitSprite(room)
    -- Build sprite for exit portal

    local portalTileXY = tonumber(room.portal.addr, 16) - 23552
    local portalTileX = portalTileXY % 32
    local portalTileY = 2 + portalTileXY // 32
    local getx, gety, _ = getSpriteAttribs(portalTileX * 4, (16 - portalTileY) * 8)
    exitSprite = gfx.sprite.new(exitTable:getImage(1))
    exitSprite:setCollideRect(exitSprite.width/4, exitSprite.height/4, exitSprite.width/4, exitSprite.height/2)
    exitSprite.collisionResponse = gfx.sprite.kCollisionTypeOverlap
    exitSprite:setZIndex(128)
    exitSprite:moveTo(getx, gety)
    exitSprite:add()
end

local function buildGuardians(room, half)
    -- Build guardians

    local halfFrames = half or false
    vGuardianList = {}
    -- Vertical Guardians
    for i, guardian in pairs(room.VGuardians) do
        halfFrames = true
        local tmpGuardian = {}
        tmpGuardian['Frame'] = (tonumber(guardian.frame, 16) - 1) %4 + 1
        tmpGuardian['Min'] = 112 - tonumber(guardian.max, 16)
        tmpGuardian['Max'] = 112 - tonumber(guardian.min, 16)
        tmpGuardian['x'] = tonumber(guardian.location, 16) * 4
        tmpGuardian['y'] = tmpGuardian['Max'] - tonumber(guardian.start, 16)
        tmpGuardian['dy'] = tonumber(guardian.dy, 16)
        tmpGuardian['Down'] = true
        if tmpGuardian['dy'] > 4 then
            tmpGuardian['dy'] = 255 - tmpGuardian['dy']
            tmpGuardian['Down'] = false
        end
        local getx, gety, getid = getSpriteAttribs(tmpGuardian.x, tmpGuardian.y, false)

        local tmpSprite = gfx.sprite.new(multiTable:getImage(8*roomNumber + tmpGuardian.Frame))
        tmpSprite:setCollideRect(0, 0, tmpSprite:getSize())
        tmpSprite.collisionResponse = gfx.sprite.kCollisionTypeOverlap
        tmpSprite:setZIndex(0)
        tmpSprite:moveTo(getx, gety)
        tmpSprite:add()
        tmpGuardian['Sprite'] = tmpSprite

        table.insert(vGuardianList, tmpGuardian)
    end
    if room.special.Eugene ~= nil then  -- Eugene is a special case
        -- Build Eugene
        local tmpGuardian = {}
        tmpGuardian['Frame'] = 1
        tmpGuardian['Min'] = 24
        tmpGuardian['Max'] = 112
        tmpGuardian['x'] = 60
        tmpGuardian['y'] = 112
        tmpGuardian['dy'] = 1
        tmpGuardian['Down'] = true
        local getx, gety, getid = getSpriteAttribs(tmpGuardian.x, tmpGuardian.y, false)

        local tmpSprite = gfx.sprite.new(singleTable:getImage(configData.Special.Eugene))
        tmpSprite:setCollideRect(0, 0, tmpSprite:getSize())
        tmpSprite.collisionResponse = gfx.sprite.kCollisionTypeOverlap
        tmpSprite:setZIndex(0)
        tmpSprite:moveTo(getx, gety)
        tmpSprite:add()
        tmpGuardian['Sprite'] = tmpSprite
        table.insert(vGuardianList, tmpGuardian)
    end
    if room.special.Kong ~= nil then  -- Kong is a special case
        -- Build Kong
        local tmpGuardian = {}
        tmpGuardian['Frame'] = 1
        tmpGuardian['Min'] = 112
        tmpGuardian['Max'] = 112
        tmpGuardian['x'] = 60
        tmpGuardian['y'] = 112
        tmpGuardian['dy'] = 0
        tmpGuardian['Down'] = false

        local getx, gety, getid = getSpriteAttribs(tmpGuardian.x, tmpGuardian.y, false)

        local tmpSprite = gfx.sprite.new(multiTable:getImage(8*roomNumber + tmpGuardian.Frame))
        tmpSprite:setCollideRect(0, 0, tmpSprite:getSize())
        tmpSprite.collisionResponse = gfx.sprite.kCollisionTypeOverlap
        tmpSprite:setZIndex(0)
        tmpSprite:moveTo(getx, gety)
        tmpSprite:add()
        tmpGuardian['Sprite'] = tmpSprite
        table.insert(vGuardianList, tmpGuardian)
    end

    hGuardianList = {}
    -- Horizontal Guardians
    if room.special.Skylab == nil then  -- Skylab guardians are only vertical
        for i, guardian in pairs(room.HGuardians) do
            local tmpGuardian = {}
            tmpGuardian['Half'] = halfFrames
            tmpGuardian['Left'] = tonumber(guardian.frame)>3
            tmpGuardian['Slow'] = tonumber(guardian.attr, 16) & 128 > 0

            local tmpTileXY = guardian.location * 256 + tonumber(guardian.min, 16)
            tmpGuardian['Min'] = tmpTileXY % 32 * 4
            tmpTileXY = guardian.location * 256 + tonumber(guardian.max, 16)
            tmpGuardian['Max'] = tmpTileXY % 32 * 4 + 3

            local guardianTileXY = tonumber(guardian.addr, 16) - 23552
            tmpGuardian['x'] = guardianTileXY % 32 * 4 + tonumber(guardian.frame % 4)
            tmpGuardian['y'] = (16 - 2 - guardianTileXY // 32) * 8
            local getx, gety, getid = getSpriteAttribs(tmpGuardian.x, tmpGuardian.y, tmpGuardian.Left)

            local tmpSprite = gfx.sprite.new(multiTable:getImage(8*roomNumber + getid))
            tmpSprite:setCollideRect(0, 0, tmpSprite:getSize())
            tmpSprite.collisionResponse = gfx.sprite.kCollisionTypeOverlap
            tmpSprite:setZIndex(0)
            tmpSprite:moveTo(getx, gety)
            tmpSprite:add()
            tmpGuardian['Sprite'] = tmpSprite

            table.insert(hGuardianList, tmpGuardian)
        end
    end
end

local function drawRoom()
    -- Build all sprites and draw them

    blinkCount = 0
    local room = roomsData[roomNumber]
    print("Room: " .. room.name)

    conveyLeft = room.conveyor.left

    gfx.clear()

    -- Background Sprite
    buildBgSprite(room)

    -- Animation Image Tables
    buildAnimationTables(room)

    -- Room Sprite
    local half = buildRoomSprite(room)

    -- Key Sprites
    buildKeySprites(room)

    -- Exit Sprite
    buildExitSprite(room)

    -- Guardians
    buildGuardians(room, half)
end

local function DrawMenu()
    -- Draw the main game menu

    gfx.clear()
    gfx.setLineWidth(3)
    local width, _ = menuImage:getSize()
    menuImage:draw((400 - width)/2, 8)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(13, 145, 364, 20)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(5, 5, 390, 230, 5)
    gfx.drawTextAligned("Press *A* to Start - *B* to Change Levels Pack", 200, 148, kTextAlignment.center)
    gfx.setLineWidth(1)
    gfx.drawRect(7, 175, 385, 26)

    if gameStatus ~=5 and gameStatus ~=8 then  -- Not in config menu or demo mode
        if tuneCount > #configData.TitleMusic then  -- Draw scroll banner text
            local iPixel = tuneCount - #configData.TitleMusic
            bannerImage:draw(8, 210, gfx.kImageUnflipped, iPixel * 5, 0, 384, 20)
            local iSize, _ = bannerImage:getSize()
            if iPixel * 5 < iSize then
                tuneCount += 1
            else  -- Enter demo mode
                tuneCount = 1000
                iStep = 1
                roomNumber = 1
                gameStatus = 8
                updateSoundSynth()
            end
        end
    end
end

local function drawConfigMenu(listNames, iName)
    -- Draws the level pack selection menu

    DrawMenu()
    gfx.setLineWidth(3)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRoundRect(30, 30, 340, 180, 5)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRoundRect(30, 30, 340, 180, 5)
    gfx.setLineWidth(1)
    gfx.drawRoundRect(42, 65, 315, 130, 3)

    gfx.drawTextAligned("Select a Levels Pack and Press *A*", 200, 40, kTextAlignment.center)

    local minLine = (iName-1)//6*6 + 1
    local maxLine = math.min(minLine + 5, #listNames)
    for i = minLine, maxLine do
        local labelName = listNames[i]
        if i == iName then
            labelName= "*>* " .. labelName
        end
        gfx.drawTextAligned(labelName, 50, 70 + (i-1)%6*20, kTextAlignment.left)
    end

    local iPart = (#listNames-1)//6 + 1
    local iStart = (iName-1)//6
    gfx.fillRoundRect(350, 70 + 120//iPart*iStart, 4, 120//iPart, 1)
end

local function DrawStomp()
    -- Draw the stomp animation

    local room = roomsData[roomNumber]

    local iTable = gfx.imagetable.new(configPath .. configData.SingleSprites)
    assert(iTable)
    local mTable =  gfx.imagetable.new(configPath .. configData.MultipleSprites)
    assert(mTable)

    local i_sm = 64 * lscale
    local i_bg = 128 * lscale
    local i_hg = 256 * lscale

    local basex = roomX + 200 - i_bg
    local basey = roomY + 96 - i_sm

    local rectX = basex - 1
    local rectY = basey - 1
    local rectW = i_hg + 2
    local rectH = i_bg + 2

    gfx.clear()
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(rectX, rectY, rectW, rectH)
    gfx.drawTextAligned(string.format("High Score *%06d*", hiScore), roomX + 10, roomY + 199, kTextAlignment.left)
    gfx.drawTextAligned(string.format("Score %06d", gameScore), roomX + 392, roomY + 199, kTextAlignment.right)

    gfx.drawTextAligned(room.name, 205, 220, kTextAlignment.center)
    gfx.drawTextAligned("Game        Over", 195, basey + i_sm, kTextAlignment.center)

    local getx, gety, _ = getSpriteAttribs(15 * 4, 16, false)
    iTable:getImage(configData.Special.Plinth):draw(getx - 8 * lscale, gety + 8 * lscale)
    mTable:getImage(1):draw(getx - 4 * lscale, gety - 8 * lscale)

    for i = 0, iStep do
        iTable:getImage(configData.Special.Boot):draw(getx - 8 * lscale, basey + i * 2 * lscale, gfx.kImageUnflipped, 0, 0, 16 * lscale, 2 * lscale)
    end

    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(getx - 8 * lscale, basey + 2 * iStep * lscale, 16 * lscale, 16 * lscale)
    gfx.setColor(gfx.kColorBlack)
    iTable:getImage(configData.Special.Boot):draw(getx - 8 * lscale, basey + 2 * iStep * lscale)

    if iStep < 48 then
        iStep += 2
        local mVol = 0.2
        local mLength = 0.05
        if soundSynth == 1 then
            mVol *= 4
            mLength *= 2
        end
        doBeep(sSynth, 63 + 192 * iStep / 50, mVol,  mLength)
    end
end


--------------------
-- Initialization --
--------------------

local function saveOptions()
    -- Saves configuration data to playdate datastore

    print("Saving options...")
    local gameOptions = {
        configPath = configPath,
        hiScore = hiScore,
        soundSynth = soundSynth,
        endRoom = endRoom,
        roomNumber = roomNumber,
        roomStatus = roomStatus,
        gameLives = gameLives,
        gameScore = gameScore,
        diffGameScore = diffGameScore,
        cheatLevel = cheatLevel
    }
    playdate.datastore.write(gameOptions)
end

local function updateCheat(value)
    -- Updates from cheat menu item

    local newcheatLevel = math.tointeger(value) or 0
    if cheatLevel ~= newcheatLevel then
        cheatLevel = newcheatLevel
        hasCheated = true
    end
end

local function updateMusic(value)
    -- Updates from music menu item

    soundSynth = 0
    if value ~= "Off" then
        soundSynth = math.tointeger(value) or 0
    end
    updateSoundSynth()
    saveOptions()
end

local function SetPlaydateMenu()
    -- Adds menu items for Playdate

    local sysMenu = playdate.getSystemMenu()
    local listMenuItems = sysMenu:getMenuItems()
    sysMenu:removeAllMenuItems()

    sysMenu:addMenuItem("Credits",
        function()
            oldGameStatus = gameStatus
            gameStatus = 6
            ki = 1
        end
    )

    local defaultMenuItem = soundSynth + 1
    local menuOptions = {"Off", "1", "2"}
    sysMenu:addOptionsMenuItem("Music", menuOptions, defaultMenuItem, updateMusic)

    if cheatLevel>0 then
        local defaultMenuItem = cheatLevel + 1
        local menuOptions = {}
        for i = 0, 4
        do
            menuOptions[i+1] = tostring(i)
        end
        sysMenu:addOptionsMenuItem("Cheat", menuOptions, defaultMenuItem, updateCheat)
    end
end

local function gameSetUp()
    -- Main basic initialization. This is done once per roomPack

    print("Loading config...")
    local gameOptions = playdate.datastore.read()

    configPath = "roomPacks/Manic Miner/"
    if gameOptions and gameOptions.configPath then
        if playdate.file.isdir(gameOptions.configPath) then
            if playdate.file.exists(gameOptions.configPath .. "config.json") then
                configPath = gameOptions.configPath
            end
        end
    end

    hiScore = 0
    if gameOptions and gameOptions.hiScore then
        hiScore = gameOptions.hiScore
    end

    soundSynth = 2
    if gameOptions and gameOptions.soundSynth ~= nil then
        soundSynth = gameOptions.soundSynth
    end
    updateSoundSynth()
    tuneCount = 1

    if gameOptions and gameOptions.endRoom ~= nil then
        endRoom = gameOptions.endRoom
    end
    if gameOptions and gameOptions.roomNumber ~= nil then
        roomNumber = gameOptions.roomNumber
    end
    if gameOptions and gameOptions.roomStatus ~= nil then
        roomStatus = gameOptions.roomStatus
    end
    if gameOptions and gameOptions.gameLives ~= nil then
        gameLives = gameOptions.gameLives
    end
    if gameOptions and gameOptions.gameScore ~= nil then
        gameScore = gameOptions.gameScore
    end
    if gameOptions and gameOptions.diffGameScore ~= nil then
        diffGameScore = gameOptions.diffGameScore
    end
    if gameOptions and gameOptions.cheatLevel ~= nil then
        cheatLevel = gameOptions.cheatLevel
        SetPlaydateMenu()
    end
    saveOptions()

    hasCheated = false
    local configFile = playdate.file.open(configPath .. "config.json")
    assert(configFile)
    configData = json.decodeFile(configFile)

    local bannerText = ''
    for _, value in ipairs(configData.Banner) do
        bannerText = bannerText .. value
    end

    local bWidth, bHeight = gfx.getTextSize(bannerText)
    bannerImage = gfx.image.new(bWidth + 384, bHeight)
    gfx.pushContext(bannerImage)
    gfx.drawText(bannerText, 384, 0)
    gfx.popContext()

    lscale = configData.Scale

    bgImage = gfx.image.new(400, 240)
    bgSprite = gfx.sprite.new(bgImage)  -- Background sprite
    bgSprite:setZIndex(-128)
    bgSprite:moveTo(200, 120)
    bgSprite:setVisible(false)
    bgSprite:add()

    SetPlaydateMenu()
    playdate.display.setRefreshRate(12.5)
    gfx.sprite.setAlwaysRedraw(true)

    loadData()

    if roomNumber > 0 and roomStatus ~= 0 then
        gameStatus = 7
    end
end

local function roomStart()
    -- Inits a room. Sets gameStatus to -1 at the end

    print("Room loaded before roomStart: " .. tostring(roomLoaded))
    roomLoaded = true

    gfx.clear()
    buildData()
    drawRoom()
    local room = roomsData[roomNumber]
    roomAir = 382

    local playerXY = tonumber(room.start.addr, 16) - 23552
    playerx = 4 * (playerXY % 32)
    playery = 8 * (14 - playerXY // 32)
    dx = 1
    playerleft = room.start.left
    if playerleft then
        dx = -1
    end
    pdx = 0
    jumpState = -1
    fallCount = 0
    isKill = false
    onConveyor = false

    local getx, gety, getid = getSpriteAttribs(playerx, playery, playerleft)
    playerSprite = gfx.sprite.new(multiTable:getImage(getid))  -- Player sprite
    playerSprite:setCollideRect(0, 0, playerSprite:getSize())
    playerSprite:add()
    playerSprite:moveTo(getx,gety)
    playerSprite:setVisible(true)

    if gameStatus ~=8 then  -- Not demo mode
        saveOptions()
    end
    tuneCount = 1
    gameStatus = 1
end

local function gameStart()
    -- Starts a new game, applying the desired scale. Sets gameStatus to -1

    endRoom = false
    roomNumber = 1
    roomStatus = 1
    gameLives = 3 + (cheatLevel%4)
    gameScore = 0
    diffGameScore = 0
    gameStatus = -1

    updateSoundSynth()
end


------------------------
-- Global Maintenance --
------------------------

local function roomEnd()
    -- Destroys a room

    print("Room loaded before roomEnd: " .. tostring(roomLoaded))
    roomLoaded = false

    if exitSprite then
        exitSprite:remove()
    end
    if playerSprite then
        playerSprite:remove()
    end
    if bgSprite then
        bgSprite:setVisible(false)
    end
    if killSprites then
        for i, killSprite in pairs(killSprites) do
            killSprite:remove()
            killSprite = nil
        end
    end
    if fallSprites then
        for j, c in pairs(fallSprites) do
            for i, fallSprite in pairs(c) do
                fallSprite:remove()
                fallSprite = nil
            end
            c = nil
        end
    end
    if conveySprites then
        for i, conveySprite in pairs(conveySprites) do
            conveySprite:remove()
            conveySprite = nil
        end
    end
    if keySprites then
        for i, keySprite in pairs(keySprites) do
            keySprite:remove()
            keySprite = nil
        end
    end
    if switchSprites then
        for i, switchSprite in pairs(switchSprites) do
            switchSprite:remove()
            switchSprite = nil
        end
    end
    if beamSprites then
        for i, beamSprite in pairs(beamSprites) do
            beamSprite:remove()
            beamSprite = nil
        end
    end
    if hGuardianList then
        for i, guardian in pairs(hGuardianList) do
            if guardian.Sprite then
                guardian.Sprite:remove()
                guardian.Sprite = nil
            end
        end
    end
    if vGuardianList then
        for i, guardian in pairs(vGuardianList) do
            if guardian.Sprite then
                guardian.Sprite:remove()
                guardian.Sprite = nil
            end
        end
    end

    if roomSprite then
        roomSprite:remove()
    end

    if roomElements then
        for j, c in pairs(roomElements) do
            for i, roomElement in pairs(c) do
                roomElement = nil
            end
            c = nil
        end
    end

    exitSprite = nil
    playerSprite = nil
    conveySprites = nil
    killSprites = nil
    fallSprites = nil
    keySprites = nil
    switchSprites = nil
    beamSprites = nil
    roomSprite = nil
    roomMap = nil
    roomElements = nil
    hGuardianList = nil
    vGuardianList = nil

    fallTable = nil
    conveyTable = nil
    switchTable = nil
    exitTable = nil

    gfx.clear()
end

local function updateMenu()
    -- Checks inputs and starts a new game if needed

    local crankSensitivity = 180
    if gameStatus == 0 then
        DrawMenu()
        if not playdate.isCrankDocked() then
            crankRadius += playdate.getCrankChange() or 0
            if crankRadius>crankSensitivity then
                playdate.display.setInverted(false)
                crankRadius = 0
            elseif crankRadius<-crankSensitivity then
                playdate.display.setInverted(true)
                crankRadius = 0
            end
        end
        if playdate.buttonJustPressed(playdate.kButtonA) then
            gameStatus = -2
            gameStart()
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            gameStatus = 5
        end
    end

    if tuneCount <= #configData.TitleMusic then
        if configData.ShowPiano then
            for i = 2, 3 do
                local k = 31 - (configData.TitleMusic[tuneCount][i] - 8) // 8
                if k>-1 and k<32 then
                    gfx.fillRect(8 + k * 12, 189, 11, 11)
                end
            end
        end
        if not mSynth:isPlaying() and not sSynth:isPlaying() then
            local mVol = 0.8
            local mLength = 0.003625 * configData.TitleMusic[tuneCount][1]
            doBeep(mSynth, configData.TitleMusic[tuneCount][2], mVol, mLength)
            doBeep(sSynth, configData.TitleMusic[tuneCount][3], mVol, mLength)
            tuneCount += 1
        end
    end
end

local function updateConfigMenu()
    -- Checks inputs and changes level Pack if needed

    local crankSensitivity = 60
    if gameStatus == 5 then
        if not playdate.isCrankDocked() then
            crankRadius += playdate.getCrankChange() or 0
        end

        local listPacks = {}
        local listDir = playdate.file.listFiles("roomPacks/")
        local iPack = 1
        for _, value in pairs(listDir) do
            if playdate.file.exists("roomPacks/" .. value .. "config.json") then
                table.insert(listPacks, value:sub(1,#value-1))
                if iStep == 0 and "roomPacks/" .. value == configPath then
                    iStep = iPack
                end
                iPack +=1
            end
        end
        if iStep == 0 then
            iStep = 1
        end

        if playdate.buttonJustPressed(playdate.kButtonA) then
            if playdate.file.exists("roomPacks/" .. listPacks[iStep] .. "/" .. "config.json") then
                configPath = "roomPacks/" .. listPacks[iStep] .. "/"
                roomNumber = 0
                saveOptions()
                gameSetUp()
            end
            gameStatus = 0
            updateSoundSynth()
            iStep = 0
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            gameStatus = 0
            iStep = 0
        else
            if playdate.buttonJustPressed(playdate.kButtonDown) or crankRadius>crankSensitivity then
                if iStep < #listPacks then
                    iStep +=1
                else
                    iStep = 1
                end
                crankRadius = 0
            elseif playdate.buttonJustPressed(playdate.kButtonUp) or crankRadius<-crankSensitivity then
                if iStep > 1 then
                    iStep -= 1
                else
                    iStep = #listPacks
                end
                crankRadius = 0
            end
            drawConfigMenu(listPacks, iStep)
        end
    end
end

local function updateCredits()
    -- Shows and updates the credits screen

    local kr = {playdate.kButtonUp, playdate.kButtonDown, playdate.kButtonLeft, playdate.kButtonRight, playdate.kButtonB, playdate.kButtonA}

    gfx.setLineWidth(3)
    playdate.graphics.setColor(playdate.graphics.kColorWhite)
    gfx.fillRoundRect(20, 20, 360, 200, 5)
    playdate.graphics.setColor(playdate.graphics.kColorBlack)
    gfx.drawRoundRect(20, 20, 360, 200, 5)
    gfx.setLineWidth(1)

    local qrImage = gfx.image.new("qr")
    qrImage:draw(225,70)

    gfx.drawTextAligned("Manic Miner for Playdate", 200, 38, kTextAlignment.center)
    gfx.drawTextInRect("Scan this QR code to access the official web page at", 40, 75, 170, 100, nil, nil, kTextAlignment.left)
    gfx.drawTextAligned("_kounch.itch.io_", 150, 140, kTextAlignment.center)
    gfx.drawTextAligned("© Kounch 2023", 120, 182, kTextAlignment.center)

    local kc = {1, 1, 2, 2, 3, 4, 3, 4, 5, 6}
    if playdate.buttonJustPressed(kr[kc[ki]]) then
        ki += 1
        if ki==11 then
            cheatLevel = 2
            SetPlaydateMenu()
        end
    else
        if playdate.buttonJustPressed(playdate.kButtonA) or playdate.buttonJustPressed(playdate.kButtonB) then
            gameStatus = oldGameStatus
        end
    end
end

local function updateRestore()
    -- Shows and updates the restore game screen

    gfx.setLineWidth(3)
    playdate.graphics.setColor(playdate.graphics.kColorWhite)
    gfx.fillRoundRect(40, 40, 320, 160, 5)
    playdate.graphics.setColor(playdate.graphics.kColorBlack)
    gfx.drawRoundRect(40, 40, 320, 160, 5)
    gfx.setLineWidth(1)

    gfx.drawTextAligned("Manic Miner for Playdate", 200, 58, kTextAlignment.center)
    gfx.drawTextInRect("Found a previous game. What would you like to do?", 60, 95, 280, 100, nil, nil, kTextAlignment.left)
    gfx.drawTextAligned("Press *A* to restart the last level", 200, 145, kTextAlignment.center)
    gfx.drawTextAligned("Press *B* to cancel", 200, 170, kTextAlignment.center)

    if playdate.buttonJustPressed(playdate.kButtonA) then
        tuneCount = 1
        gameStatus = -1
        updateSoundSynth()
    elseif playdate.buttonJustPressed(playdate.kButtonB) then
        tuneCount = 1
        gameStatus = 0
        updateSoundSynth()
    end
end

local function updateRoom()
    -- Update all room elements (animations, counters, etc.)

    blinkCount += 1  -- Global counter for delayed animations and changes
    if blinkCount == 24 then  -- Rotate counter each 24 frames
        blinkCount = 0
    end

    if soundSynth>0 then
        local mVol = 0.25
        local mLength = 0.04
        if soundSynth == 1 then
            mVol *= 4
            mLength = 0.2
        end
        if blinkCount%2 == 0 then
            doBeep(mSynth, configData.InGameMusic[tuneCount], mVol, mLength)
            tuneCount += 1
            if tuneCount > #configData.InGameMusic then
                tuneCount = 1
            end
        else
            if soundSynth == 2 then
                doBeep(mSynth, configData.InGameMusic[tuneCount], mVol, mLength)
            end
        end
    end

    if playery % 8 == 0 and jumpState<0 then  -- Check if a falling block has to fall
        local tilex = 1 + playerx // 4
        local tiley = 17 - playery // 8
        local isfloor = false
        for i = 0,1  do
            if checkTileBounds(tilex + i, tiley) then
                local tileindex = roomMap:getTileAtPosition(tilex + i, tiley)
                if tileindex%9 == 3 then
                    local spriteState = roomElements[tiley][tilex + i]
                    if spriteState > 0 then  -- Still can fall
                        spriteState -= 1
                        roomElements[tiley][tilex + i] = spriteState
                        fallSprites[tiley][tilex + i]:setImage(fallTable:getImage(9 - spriteState))
                    end
                end
            end
        end
    end

    for i, conveySprite in pairs(conveySprites) do  -- Update conveyor sprite animation
        conveySprite:setImage(conveyTable:getImage(1 + blinkCount%4))
    end

    if blinkCount == 0 or blinkCount == 16 then  -- Update keys animation
        local keyVisible = true
        if blinkCount == 16 then
            keyVisible = false
        end
        for i, keySprite in pairs(keySprites) do
            if keySprite then
                keySprite:setVisible(keyVisible)
            end
        end
    end

    if cheatLevel<3 then  -- Check death by room element (killSprites collisions)
        for i, killSprite in pairs(killSprites) do
            if killSprite then
                local _, _, collisions, length = killSprite:checkCollisions(killSprite:getPosition())
                if length>0 then
                    for j = 1, length do
                        if collisions[j].other == playerSprite then
                            if killSprite:alphaCollision(collisions[j].other) then
                                isKill = true
                            end
                        end
                    end
                end
            end
        end
    end

    if beamSprites then
        for i, beamSprite in pairs(beamSprites) do  -- Check air loss by light beam
            local colRect = beamSprite:getCollideRect()
            if colRect.width > 1 then
                local _, _, collisions, length = beamSprite:checkCollisions(beamSprite:getPosition())
                if length and length>0 then
                    for j = 1, length do
                        if collisions[j].other == playerSprite then
                            roomAir -= 1
                        end
                    end
                end
            end
        end
    end

    for i, keySprite in pairs(keySprites) do  -- Check item (key) collection (keySprites collisions)
        if keySprite then
            local _, _, collisions, length = keySprite:checkCollisions(keySprite:getPosition())
            if length>0 then
                for j = 1, length do
                    if collisions[j].other == playerSprite then
                        if keySprite:alphaCollision(collisions[j].other) then
                            keyCount -= 1
                            keySprite:remove()
                            keySprites[i] = nil
                            gameScore += 100
                            diffGameScore += 100
                        end
                    end
                end
            end
        end
    end

    if switchSprites then  -- Check Switch change (switchSprites collisions)
        for i, switchSprite in pairs(switchSprites) do
            local _, _, collisions, length = switchSprite:checkCollisions(switchSprite:getPosition())
            if length>0 then
                for j = 1, length do
                    if collisions[j].other == playerSprite then
                        if switchSprite:alphaCollision(collisions[j].other) then
                            switchSprite:setImage(switchTable:getImage(2))
                            if i==1 then
                                --Left Switch
                                local tileindex = roomMap:getTileAtPosition(18, 12)
                                local tiletest = roomMap:getTileAtPosition(17, 12)
                                if tileindex ~= tiletest then
                                    roomMap:setTileAtPosition(18, 12, tiletest)
                                    roomMap:setTileAtPosition(18, 13, tiletest)
                                end
                                for _, tmpGuardian in pairs(hGuardianList) do  -- Extend guardian walk when wall opening
                                    if tmpGuardian.y == 24 then
                                        tmpGuardian.Max = 75
                                    end
                                end
                            else
                                local tileindex = roomMap:getTileAtPosition(18, 12)
                                local tiletest = roomMap:getTileAtPosition(17, 12)
                                if tileindex == tiletest then
                                    --Right Switch
                                    local tileindex = roomMap:getTileAtPosition(16, 3)
                                    local tiletest = roomMap:getTileAtPosition(16, 4)
                                    if tileindex ~= tiletest then  -- Kill Kong
                                        roomMap:setTileAtPosition(16, 3, tiletest)
                                        roomMap:setTileAtPosition(17, 3, tiletest)
                                        local tmpGuardian = vGuardianList[1]
                                        tmpGuardian.Frame = 3
                                        tmpGuardian.Min = 8
                                        tmpGuardian.y = 104
                                        tmpGuardian.dy = 4
                                        tmpGuardian.Down = true
                                        tmpGuardian.Sprite:clearCollideRect()
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if keyCount == 0 then  -- Check items (keys) collection status (including exit room animation and room change)
        if blinkCount%12 == 0 then
            exitSprite:setImage(exitTable:getImage(1))
        elseif blinkCount%12 == 6 then
            exitSprite:setImage(exitTable:getImage(2))
        end
        local _, _, collisions, length = exitSprite:checkCollisions(exitSprite:getPosition())
        if length>0 then
            for j = 1, length do
                if collisions[j].other == playerSprite then
                    if (exitSprite.x - collisions[j].other.x) < 4 and (exitSprite.y - collisions[j].other.y) < 4 then
                        newRoom = true
                        endRoom = true
                    end
                end
            end
        end
    end

    if gameStatus ~= 8 then  -- Not in demo mode
        if roomAir > 0 and not isKill then  -- Update room air (including checking death)
            if blinkCount%8 == 0 then
                roomAir -= 2
            end
        elseif not newRoom then
            gameLives -= 1
            if gameLives < 1 then
                roomStatus = 0
            end
            local mVol = 0.2
            local mLength = 0.05
            if soundSynth == 1 then
                mVol *= 4
                mLength *= 4
            end
            doBeep(sSynth, 7, mVol,  mLength)
            endRoom = true
        end
    end
end

local function updateStomp()
    -- Updates the game over screen

    if gameStatus == 3 then
        DrawStomp()
        if iStep > 47 then
            if playdate.buttonJustPressed(playdate.kButtonA) or playdate.buttonJustPressed(playdate.kButtonB) then
                if bgSprite then
                    bgSprite:setVisible(false)
                end
                roomNumber = 0
                saveOptions()
                iStep = 0
                tuneCount = 1
                gameStatus = 0
                updateSoundSynth()
            end
        end
    end
end

local function updateEnding()
    -- Updates the ending game screen

    if gameStatus == 4 then
        local doUpdate = true
        if sSample ~=nil then
            if not sSample:isPlaying() then
                doUpdate = false
                sSample = nil
            end
        else
            if playdate.buttonJustPressed(playdate.kButtonA) or playdate.buttonJustPressed(playdate.kButtonB) then
                doUpdate = false
            end
        end

        if doUpdate then
            gfx.sprite.update()
            gfx.setColor(gfx.kColorBlack)
            gfx.drawTextAligned(string.format("High Score *%06d*", hiScore), roomX + 10, roomY + 199, kTextAlignment.left)
            gfx.drawTextAligned(string.format("Score %06d", gameScore), roomX + 392, roomY + 199, kTextAlignment.right)
        else
            roomNumber = 1
            newRoom = true
            gameStatus = 1
        end
    end
end

local function drawScore()
    -- Draw the air bar, remaining lives and game score

    local room = roomsData[roomNumber]
    local i_sm = 64 * lscale
    local i_bg = 128 * lscale
    local basex = roomX + 200 - i_bg
    local basey = roomY + 96 - i_sm

    -- Upate sprites
    gfx.sprite.update()
    gfx.setColor(gfx.kColorBlack)

    -- Update light beams in Solar Power Generator
    if room.special.Solar ~= nil  then
        local x1 = basex + 23 * 8 * lscale
        local x2 = x1 + 7 * lscale
        local y1 = basey + 15 * 8 * lscale
        local y2 = y1
        local maxy = y1
        local x0 = basex

        for _, guardian in ipairs(hGuardianList) do
            local realx = basex + (2 * guardian.x) * lscale
            local realy = basey + i_bg - guardian.y * lscale
            if realx>x1-15 and realx<x2 then
                y1 = math.min(realy-9*lscale, y1)
                y2 = math.min(realy-16*lscale, y2)
            end
        end

        gfx.drawLine(x1, basey, x1, y1)
        gfx.drawLine(x2, basey, x2, y2)
        beamSprites[1]:moveTo(x1, basey)
        beamSprites[1]:setCollideRect(2, 1, x2 - x1, y2 - basey)
        if y1<maxy then
            for _, guardian in ipairs(vGuardianList) do
                local realx = basex + (2 * guardian.x) * lscale
                local realy = basey + i_bg - guardian.y * lscale
                if realy>y2+8 and realy<y1+16 then
                    x0 = math.max(realx+16*lscale, x0)
                end
            end
            gfx.drawLine(x0, y1, x1, y1)
            gfx.drawLine(x0, y2, x1, y2)
            beamSprites[2]:moveTo(x0, y2)
            beamSprites[2]:setCollideRect(1, 2, x1 - x0, y1 - y2)
            if x0>basex then
                gfx.drawLine(x0, y1, x0, maxy)
                gfx.drawLine(x0-8*lscale, y2, x0-8*lscale, maxy)
                beamSprites[3]:moveTo(x0-8*lscale, y1)
                beamSprites[3]:setCollideRect(2, 1, 8*lscale, maxy - y1)
            else
                beamSprites[3]:clearCollideRect()
            end
        else
            beamSprites[2]:clearCollideRect()
            beamSprites[3]:clearCollideRect()
        end
    end

    -- Air bar
    gfx.fillRoundRect(roomX + 8, roomY + 194, 384, 4, 2)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(roomX + 9 + roomAir, roomY + 195, 382 - roomAir, 2)

    if diffGameScore > 10000 then
        gameLives += 1
        diffGameScore -= 10000
    end
    -- Remaining lives
    for i = 1, gameLives-1 do
        multiTable:getImage(1):draw(roomX + i*14 - 6, roomY + 217)
    end

    -- Current score
    gfx.drawTextAligned(string.format("High Score *%06d*", hiScore), roomX + 10, roomY + 199, kTextAlignment.left)
    gfx.drawTextAligned(string.format("Score %06d", gameScore), roomX + 392, roomY + 199, kTextAlignment.right)
end

local function emptyAir()
    -- Deplete the remaining air when leaving a room through a portal. Sets gameStatus to -1

    if roomAir>9 then
        roomAir -= 9
        local mVol = 0.75
        local mLength = 0.1
        doBeep(sSynth, 2*(120-roomAir//6), mVol,  mLength)
        gameScore += 37
        diffGameScore += 37
        drawScore()
    else
        if roomStatus > -1 then
            roomNumber += 1
        else
            roomStatus = 1
        end
        newRoom = false
        endRoom = true
        gameStatus = -1
        updateSoundSynth()
    end
end

local function drawEnding()
    -- Draws the ending game screen

    local room = roomsData[roomNumber-1]

    local i_sm = 64 * lscale
    local i_bg = 128 * lscale
    local i_hg = 256 * lscale

    local basex = roomX + 200 - i_bg
    local basey = roomY + 96 - i_sm

    local rectX = basex - 1
    local rectY = basey - 1
    local rectW = i_hg + 2
    local rectH = i_bg + 2

    playery = 95
    local getx, gety, getid = getSpriteAttribs(playerx, playery, false)

    gfx.lockFocus(bgImage)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(0, 0, 400, 240)
    gfx.setColor(gfx.kColorBlack)

    gfx.drawRect(rectX, rectY, rectW, rectH) -- game room space
    gfx.drawTextAligned(room.name, 205, 220, kTextAlignment.center)
    local tmpImage = gfx.image.new(configPath .. configData.Menu)
    tmpImage:draw(rectX+1, rectY+1, gfx.kImageUnflipped, 0, 0, i_hg, 56 * lscale)
    gfx.setColor(gfx.kColorWhite)

    gfx.fillRect(getx - 8 * lscale, gety - 8 * lscale, 16 * lscale, 16 * lscale)
    gfx.setColor(gfx.kColorBlack)
    gfx.unlockFocus()
    bgSprite:setImage(bgImage)  -- Background sprite
    bgSprite:setVisible(true)

    if cheatLevel==0 and not hasCheated then
        exitSprite:setImage(singleTable:getImage(configData.Special.Swordfish))
    end

    playerSprite:moveTo(getx,gety)
    playerSprite:setImage(multiTable:getImage(getid))
    playerSprite:setVisible(true)
end

local function updateGuardians()
    -- Update screen state and check collisions for Guardians

    local room = roomsData[roomNumber]
    for i, guardian in pairs(vGuardianList) do
        if guardian.Down then
            if guardian.y > guardian.Min then
                guardian.y -= guardian.dy
                if room.special.Skylab ~= nil  then -- Skylabs animation is different
                    guardian.Frame = 1
                elseif room.special.Kong ~= nil then  -- Kong animation changes when falling
                    guardian.Frame = blinkCount % 6 // 3 + 3
                    local mVol = 0.2
                    local mLength = 0.05
                    if soundSynth == 1 then
                        mVol *= 4
                        mLength *= 2
                    end
                    doBeep(sSynth, 128 - guardian.y, mVol,  mLength)
                else
                    guardian.Frame = guardian.Frame %4 + 1
                end
            else
                if room.special.Skylab == nil then
                    if not (room.special.Eugene ~= nil and keyCount == 0) then  -- Eugene stops going up
                        guardian.Down = false
                    end
                else  -- Skylabs animation and movement is different
                    if guardian.Frame < 8 then
                        guardian.Frame += 1
                    else
                        guardian.y = guardian.Max
                        guardian.x = (guardian.x + 32)%128
                    end
                end
            end
        else
            if (room.special.Eugene ~= nil and keyCount == 0) then
                guardian.Down = true
            else
                if guardian.y < guardian.Max then
                    if room.special.Kong ~= nil then
                        guardian.Sprite:remove()
                        guardian.Sprite = nil
                        vGuardianList[i] = nil
                    else
                        guardian.y += guardian.dy
                        guardian.Frame = (2 + guardian.Frame) %4 + 1
                    end
                else
                    guardian.Down = true
                end
            end
        end
        if vGuardianList[i] ~= nil then
            if guardian.dy == 0 then  -- Kong animation is slower
                guardian.Frame = blinkCount // 12 + 1
            end
            local getx, gety, getid = getSpriteAttribs(guardian.x, guardian.y, false)
            if guardian.Half and getid<5 then
                getid += 4
            end
            if room.special.Eugene == nil then -- Eugene animation is different
                guardian.Sprite:setImage(multiTable:getImage(8*roomNumber + guardian.Frame))
            end
            guardian.Sprite:moveTo(getx, gety)

            if cheatLevel<2 then  -- Check death
                local _, _, collisions, length = guardian.Sprite:checkCollisions(guardian.Sprite:getPosition())
                if length>0 then
                    for j = 1, length do
                        if collisions[j].other == playerSprite then
                            if guardian.Sprite:alphaCollision(collisions[j].other) then
                                isKill = true
                            end
                        end
                    end
                end
            end
        end
    end

    for i, guardian in pairs(hGuardianList) do
        if guardian.Left then
            if guardian.x > guardian.Min then
                if guardian.Slow then
                    guardian.x -= 0.5
                else
                    guardian.x -= 1
                end
            else
                guardian.Left = false
            end
        else
            if guardian.x < guardian.Max then
                if guardian.Slow then
                    guardian.x += 0.5
                else
                    guardian.x += 1
                end
            else
                guardian.Left = true
            end
        end
        local getx, gety, getid = getSpriteAttribs(math.floor(guardian.x), guardian.y, guardian.Left)
        if guardian.Half and getid<5 then
            getid += 4
        end
        guardian.Sprite:setImage(multiTable:getImage(8*roomNumber + getid))
        guardian.Sprite:moveTo(getx, gety)

        if cheatLevel<2 then  -- Check death
            local _, _, collisions, length = guardian.Sprite:checkCollisions(guardian.Sprite:getPosition())
            if length>0 then
                for j = 1, length do
                    if collisions[j].other == playerSprite then
                        if guardian.Sprite:alphaCollision(collisions[j].other) then
                            isKill = true
                        end
                    end
                end
            end
        end
    end
end

local function updatePlayer()
    -- Update the player status (falling, jumping, moving, etc.)

    if jumpState == -2 then  -- Falling
        doFall()
    elseif jumpState>-1 then  -- Jumping
        doJump()
    else  -- May be moving
        local moved = false
        local fall = false
        if playdate.buttonIsPressed(playdate.kButtonA) then
            if jumpState==-1 then
                jumpState = 0
            end
            if playdate.buttonIsPressed(playdate.kButtonRight) then
                if dx<1 then
                    dx += 1
                end
                if not onConveyor then
                    playerleft = false
                end
            elseif playdate.buttonIsPressed(playdate.kButtonLeft) then
                if dx>-1 then
                    dx -= 1
                end
                if not onConveyor then
                    playerleft = true
                end
            elseif cheatLevel>0 and playdate.buttonIsPressed(playdate.kButtonB) then
                jumpState = -1
                roomStatus = 0
                endRoom = true
            else
                dx = 0
            end
            if jumpState==0 then
                doJump()
            end
        elseif cheatLevel>0 and playdate.buttonIsPressed(playdate.kButtonB) and playdate.buttonJustPressed(playdate.kButtonUp) then
            roomNumber = roomNumber + 1
            endRoom = true
        elseif playdate.buttonIsPressed(playdate.kButtonRight) then
            moved, _, fall = checkPlayerMove(1,0)
        elseif playdate.buttonIsPressed(playdate.kButtonLeft) then
            moved, _, fall  = checkPlayerMove(-1,0)
        else
            moved, _, fall = checkPlayerMove(0,0)
        end

        if not endRoom then  --Update player position, image and fall status
            local getx, gety, getid = getSpriteAttribs(playerx, playery, playerleft)
            if moved then
                playerSprite:moveTo(getx,gety)
            end
            playerSprite:setImage(multiTable:getImage(getid))
            if fall then
                jumpState = -2
                doFall()
            end
        end
    end
end

local function updateGame()
    --Main game loop. May change gameStatus

    if gameStatus == 1 then
        updateRoom()
        if not endRoom then
            updateGuardians()
        end
        if not endRoom then
            updatePlayer()
        end
    end

    if endRoom then
        gameStatus = -1
    end

    if newRoom then
        gameStatus = 2
        playerSprite:setVisible(false)
        updateSoundSynth()
    end

    if gameStatus == 1 then
        drawScore()
    end
end

local function updateDemo()
    -- Demo mode loop that cycles through all level screens

    if gameStatus == 8 then
        if iStep % 40 == 0 then
            roomEnd()
            roomNumber += 1
            if roomNumber>#roomsData  then
                iStep = 0
                tuneCount = #configData.TitleMusic + 1
                gameStatus = 0
            end
        elseif iStep % 40 == 1 then
            roomStart() -- roomStart sets gameStatus to 1 when finished
            gameStatus = 8
            playerSprite:setVisible(false)
        else
            if playdate.buttonJustPressed(playdate.kButtonA) or playdate.buttonJustPressed(playdate.kButtonB) then
                roomEnd()
                iStep = 0
                tuneCount = #configData.TitleMusic + 1
                gameStatus = 0
            else
                updateRoom()
                updateGuardians()
                gfx.sprite.update()
            end
        end
        iStep += 1
    end
end

------------------
-- Main routine --
------------------

print("Game Init...")
gameSetUp()

print("Main loop...")
function playdate.update()
-- gameStatus is used as flag to select the current environment
--  0 - Main Menu
--  1 - Playing a room
--  2 - Finished a rooom (depleting air)
--  3 - Game Over (killed)
--  4 - Game Over (finished last room)
--  5 - Level Pack selection menu
--  6 - Credits
--  7 - Restore previous game menu
--  8 - Demo mode (after menu tune and banner text)
-- -1 - Intermediate state (e.g. loading or unloading a room)
-- -2 - Safe intermediate state (No playdate.update activity)

    if gameStatus == -1 then
        gameStatus = -2
        if endRoom then
            if roomNumber>#roomsData  then
                roomStatus = -1
                gameStatus = 4
                sSample = playdate.sound.sampleplayer.new(configPath .. "ending")
                if sSample ~= nil then
                    sSample:play()
                end
                drawEnding()
            else
                roomEnd()
                if roomStatus == 0 then
                    iStep = 0
                    gameStatus = 3
                    if hiScore < gameScore then
                        hiScore = gameScore
                    end
                    saveOptions()
                end
                endRoom = false
            end
        end
        if roomStatus>0 then
            roomStart() -- roomStart sets gameStatus to 1 when finished
        end
    elseif gameStatus == 0 then
        updateMenu()  -- May change gameStatus to -2 and then to -1 (gameStart)
    elseif gameStatus == 1 then
        updateGame()  -- May change gameStatus to -1 or 2
    elseif gameStatus == 2 then
        emptyAir()  -- Will change gameStatus to -1 at the end
    elseif gameStatus == 3 then
        updateStomp()
    elseif gameStatus == 4 then
        updateEnding()
    elseif gameStatus == 5 then
        updateConfigMenu()
    elseif gameStatus == 6 then
        updateCredits()
    elseif gameStatus == 7 then
        updateRestore()
    elseif gameStatus == 8 then
        updateDemo()
    end
end
