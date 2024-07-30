local mq = require('mq')
local ffi = require("ffi")
local ImGui = require('ImGui')
local script = "SillySounds"
local itemWatch = false
if mq.TLO.EverQuest.GameState() ~= "INGAME" then
    printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...",script)
    mq.exit()
end

-- C code definitions for volume control
ffi.cdef[[
    int sndPlaySoundA(const char *pszSound, unsigned int fdwSound);
    uint32_t waveOutSetVolume(void* hwo, uint32_t dwVolume);
    uint32_t waveOutGetVolume(void* hwo, uint32_t* pdwVolume);
]]

local winmm = ffi.load("winmm")

local SND_ASYNC = 0x0001
local SND_FILENAME = 0x00020000
local flags = SND_FILENAME + SND_ASYNC
local originalVolume = 100
local soundDuration = 1
local timerPlay =0
local playing = false

-- Main Settings
local RUNNING = true
local path = string.format("%s/%s/sounds/",mq.TLO.Lua.Dir(), script)
local configFile = string.format("%s/MyUI/%s/%s/%s.lua", mq.configDir, script, mq.TLO.EverQuest.Server(), mq.TLO.Me.Name())
local settings, defaults = {}, {}
local timerA, timerB = os.time(), os.time()
local openConfigGUI = false
local tmpTheme = 'default'
local alarmTagged = false

defaults = {
    doHit = true,
    doBonk = true,
    doLvl = true,
    doDie = true,
    doHP = true,
    doAA = true,
    doAlarm = true,
    doItem = true,
    doFizzle = true,
    volFizzle = 25,
    volAlarm = 25,
    volAA = 10,
    volHit = 2,
    volBonk = 5,
    volLvl = 100,
    volDie = 100,
    volItem = 100,
    volHP = 20,
    lowHP = 50,
    theme = 'default',
    Pulse = 1,
    ItemWatch = '',
    Sounds = {
        default = {
            soundHit = {file = "Hit.wav", duration = 2},
            soundAlarm = {file = "Alarm.wav", duration = 5},
            soundBonk = {file = "Bonk.wav", duration = 2},
            soundLvl = {file = "LevelUp.wav", duration = 3},
            soundDie = {file = "Die.wav", duration = 4},
            soundLowHp = {file = "lowHP.wav", duration = 3},
            soundAA = {file = "AA.wav", duration = 2},
            soundFizzle = {file = 'Fizzle.wav', duration = 1},
            soundItem = {file = 'Hit.wav', duration = 2}
        }
    }
}

-- Check if the file exists
local function File_Exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

-- Function to play sound allowing for simultaneous plays
local function playSound(filename)
    if File_Exists(filename) then
        timerPlay = os.time()
        playing = true
        winmm.sndPlaySoundA(filename, flags)
    else
        printf('\aySound File \aw[\ag%s\aw]\ao is MISSING!!\ax', filename)
    end
end

-- Function to get the current volume
local function getVolume()
    local pdwVolume = ffi.new("uint32_t[1]")
    winmm.waveOutGetVolume(nil, pdwVolume)
    return pdwVolume[0]
end

-- Function to set volume
local function setVolume(volume)
    if volume < 0 or volume > 100 then
        error("Volume must be between 0 and 100")
    end
    local vol = math.floor(volume / 100 * 0xFFFF)
    local leftRightVolume = bit32.bor(bit32.lshift(vol, 16), vol) -- Set both left and right volume
    winmm.waveOutSetVolume(nil, leftRightVolume)
end

local function eventSound(_, event, vol)
    if not settings["do" .. event] then return end
    local sound = settings.Sounds[settings.theme]["sound" .. event]
    if sound and settings["do" .. event] then
        soundDuration = sound.duration
        local fullPath = string.format("%s%s/%s", path, settings.theme, sound.file)
        setVolume(vol)
        timerPlay = os.time()
        playSound(fullPath)
    end
end

local function resetVolume()
    playing = false
    winmm.waveOutSetVolume(nil, originalVolume)
    timerPlay = 0
    mq.delay(100)
end

local function checkAlarms()
    if alarmTagged then return end
    local textOutput = mq.TLO.Window('ConfirmationDialogBox').Child('CD_TextOutput').Text()
    local sessionEnded = textOutput:match("Your session %(.-%) has ended%.")
    if sessionEnded then
        alarmTagged = true
        eventSound('', 'Alarm', settings.volAlarm)
        mq.TLO.Window('ConfirmationDialogBox').DoClose()
    end
end

local function eventItem(line)
    eventSound('', 'Item', settings.volItem)
end

-- Settings
local function loadSettings()
    if not File_Exists(configFile) then
        settings = defaults
        mq.pickle(configFile, settings)
        loadSettings()
    else
        settings = dofile(configFile)
        if not settings then
            settings = {}
            settings = defaults
        end
    end
    tmpTheme = settings.theme or 'default'
    local newSetting = false
    for k, v in pairs(defaults) do
        if settings[k] == nil then
            settings[k] = v
            newSetting = true
        end
    end
    for k, v in pairs(defaults.Sounds.default) do
        if settings.Sounds[settings.theme][k] == nil then
            settings.Sounds[settings.theme][k] = v
            newSetting = true
        end
    end
    for k, v in pairs(settings.Sounds[settings.theme]) do
        if not File_Exists(string.format("%s%s/%s", path, settings.theme, v.file)) then
            settings[k] = false
            printf("\aySound file %s missing!!\n\tTurning %s \arOFF", string.format("%s%s/%s", path, settings.theme, v.file), k)
        end
    end
    if settings.ItemWatch ~= '' then
        local eStr = string.format("#*#%s#*#", settings.ItemWatch)
        mq.event("item_added", eStr, eventItem)
        itemWatch = true
    end
    if newSetting then mq.pickle(configFile, settings) end
end

-- Print Help
local function helpList(type)
    local timeStamp = mq.TLO.Time()
    if type == 'help' then
        printf('\aw%s \ax:: \ay%s Help\ax', timeStamp, script)
        printf('\aw%s \ax:: \at /sillysounds hit     \t \ag Toggles sound on and off for your hits\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds bonk    \t \ag Toggles sound on and off for you being hit\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds fizzle    \t \ag Toggles sound on and off for your spell fizzles\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds lvl     \t \ag Toggles sound on and off for when you Level\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds aa      \t \ag Toggles sound on and off for You gain AA\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds die     \t \ag Toggles sound on and off for your Deaths\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds hp      \t \ag Toggles sound on and off for Low Health\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds hp 1-100\t \ag Sets PctHPs to toggle low HP sound, 1-100\ax', timeStamp)
        printf('\aw%s \ax:: \ay%s Volume Control\ax', timeStamp, script)
        printf('\aw%s \ax:: \at /sillysounds hit 0-100\t \ag Sets Volume for hits 0-100 accepts decimal values\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds bonk 0-100\t\ag Sets Volume for bonk 0-100 accepts decimal values\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds fizzle 0-100\t \ag Sets Volume for fizzle 0-100 accepts decimal values\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds lvl 0-100 \t\ag Sets Volume for lvl 0-100 accepts decimal values\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds aa 0-100 \t\ag Sets Volume for AA 0-100 accepts decimal values\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds die 0-100 \t\ag Sets Volume for die 0-100 accepts decimal values\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds volhp 0-100 \t\ag Sets Volume for lowHP 0-100 accepts decimal values\ax', timeStamp)
        printf('\aw%s \ax:: \ay%s Other\ax', timeStamp,script)
        printf('\aw%s \ax:: \at /sillysounds help      \t\ag Brings up this list\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds config    \t\ag Opens Config GUI Window\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds show      \t\ag Prints out the current settings\ax', timeStamp)
        printf('\aw%s \ax:: \at /sillysounds quit      \t\ag Exits the script\ax', timeStamp)
    elseif type == 'show' then
        printf('\aw%s \ax:: \ay%s Current Settings\ax', timeStamp, script)
        for k, v in pairs(settings) do
            if k ~= 'Sounds' then
                printf("\aw%s \ax:: \at%s \ax:\ag %s\ax", timeStamp, k, tostring(v))
            end
        end
    end
end

-- Binds
local function bind(...)
    local newSetting = false
    local args = {...}
    local key = args[1]
    local value = tonumber(args[2], 10) or nil
    if key == nil then
        helpList('help')
        return
    end
    if string.lower(key) == 'hit' then
        if value ~= nil then
            settings.volHit = value or 50
            printf("setting %s Volume to %s", key, tostring(settings.volHit))
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundHit.file))
        else
            settings.doHit = not settings.doHit
            printf("setting %s to %s", key, tostring(settings.doHit))
        end
        newSetting = true
    elseif string.lower(key) == 'bonk' then
        if value ~= nil then
            settings.volBonk = value or 50
            printf("setting %s Volume to %d", key, tostring(settings.volBonk))
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundBonk.file))
        else
            settings.doBonk = not settings.doBonk
            printf("setting %s to %s", key, tostring(settings.doBonk))
        end
        newSetting = true
    elseif string.lower(key) == 'aa' then
        if value ~= nil then
            settings.volAA = value or 50
            printf("setting %s Volume to %d", key, tostring(settings.volAA))
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundAA.file))
        else
            settings.doAA = not settings.doAA
            printf("setting %s to %s", key, tostring(settings.doAA))
        end
        newSetting = true
    elseif string.lower(key) == 'config' then
        openConfigGUI = true
    elseif string.lower(key) == 'lvl' then
        if value ~= nil then
            settings.volLvl = value or 50
            printf("setting %s Volume to %d", key, tostring(settings.volLvl))
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundLvl.file))
        else
            settings.doLvl = not settings.doLvl
            printf("setting %s to %s", key, tostring(settings.doLvl))
        end
        newSetting = true
    elseif string.lower(key) == 'die' then
        if value ~= nil then
            settings.volDie = value or 50
            printf("setting %s Volume to %d", key, tostring(settings.volDie))
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundDie.file))
        else
            settings.doDie = not settings.doDie
            printf("setting %s to %s", key, tostring(settings.doDie))
        end
        newSetting = true
    elseif string.lower(key) == 'hp' then
        if value ~= nil then
            settings.lowHP = value or 0
            printf("setting %s to %s", key, tostring(value))
        else
            settings.doHP = not settings.doHP
            printf("setting %s to %s", key, tostring(settings.doHP))
        end
        newSetting = true
    elseif string.lower(key) == 'volhp' then
        if value ~= nil then
            settings.volHP = value or 50
            printf("setting %s Volume to %d", key, tostring(settings.volHP))
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundLowHp.file))
            newSetting = true
        end
    elseif string.lower(key) == 'help' or key == nil then
        helpList('help')
    elseif string.lower(key) == 'show' then
        helpList(key)
    elseif string.lower(key) == 'quit' or key == nil then
        RUNNING = false
    end
    if newSetting then mq.pickle(configFile, settings) end
end

-- UI
local function Config_GUI(open)
    if not openConfigGUI then return end
    local lbl = string.format("%s##%s", script, script)
    open, openConfigGUI = ImGui.Begin(lbl, open, bit32.bor(ImGuiWindowFlags.None, ImGuiWindowFlags.NoCollapse))
    if not openConfigGUI then
        openConfigGUI = false
        open = false
        ImGui.End()
        return open
    end

    tmpTheme = ImGui.InputText("Sound Folder Name##FolderName", tmpTheme)
    ImGui.SameLine()
    if ImGui.Button('Update##'..script) then
        if settings.Sounds[tmpTheme] == nil then
            settings.Sounds[tmpTheme] = {
                soundHit = {file = "Hit.wav", duration = 2},
                soundBonk = {file = "Bonk.wav", duration = 2},
                soundLvl = {file = "LevelUp.wav", duration = 3},
                soundDie = {file = "Die.wav", duration = 4},
                soundLowHp = {file = "lowHP.wav", duration = 3},
                soundAlarm = {file = "Alarm.wav", duration = 5},
                soundAA = {file = "AA.wav", duration = 2},
                soundFizzle = {file = 'Fizzle.wav', duration = 1}
            }
        end
        settings.theme = tmpTheme
        mq.pickle(configFile, settings)
        loadSettings()
    end
    --- tmp vars to change ---
    local tmpSndHit = settings.Sounds[settings.theme].soundHit.file or 'Hit.wav'
    local tmpVolHit = settings.volHit or 100
    local tmpDurHit = settings.Sounds[settings.theme].soundHit.duration or 2
    local tmpDoHit = settings.doHit
    local tmpSndBonk = settings.Sounds[settings.theme].soundBonk.file or 'Bonk.wav'
    local tmpVolBonk = settings.volBonk or 100
    local tmpDurBonk = settings.Sounds[settings.theme].soundBonk.duration or 2
    local tmpDoBonk = settings.doBonk
    local tmpSndFizzle = settings.Sounds[settings.theme].soundFizzle.file or 'Fizzle.wav'
    local tmpVolFizzle = settings.volFizzle or 100
    local tmpDurFizzle = settings.Sounds[settings.theme].soundFizzle.duration or 1
    local tmpDoFizzle = settings.doFizzle
    local tmpSndLvl = settings.Sounds[settings.theme].soundLvl.file or 'LevelUp.wav'
    local tmpVolLvl = settings.volLvl or 100
    local tmpDurLvl = settings.Sounds[settings.theme].soundLvl.duration or 3
    local tmpDoLvl = settings.doLvl
    local tmpSndAA = settings.Sounds[settings.theme].soundAA.file or 'AA.wav'
    local tmpVolAA = settings.volAA or 100
    local tmpDurAA = settings.Sounds[settings.theme].soundAA.duration or 2
    local tmpDoAA = settings.doAA
    local tmpSndDie = settings.Sounds[settings.theme].soundDie.file or 'Die.wav'
    local tmpVolDie = settings.volDie or 100
    local tmpDurDie = settings.Sounds[settings.theme].soundDie.duration or 4
    local tmpDoDie = settings.doDie
    local tmpSndAlarm = settings.Sounds[settings.theme].soundAlarm.file or 'Alarm.wav'
    local tmpVolAlarm = settings.volAlarm or 100
    local tmpDurAlarm = settings.Sounds[settings.theme].soundAlarm.duration or 5
    local tmpDoAlarm = settings.doAlarm
    local tmpSndHP = settings.Sounds[settings.theme].soundLowHp.file or 'lowHP.wav'
    local tmpVolHP = settings.volHP or 100
    local tmpDurHP = settings.Sounds[settings.theme].soundLowHp.duration or 3
    local tmpDoHP = settings.doHP or false
    local tmpLowHp = settings.lowHP or 50
    local tmpPulse = settings.Pulse or 1
    local tmpDoItem = settings.doItem or false
    local tmpSndItem = settings.Sounds[settings.theme].soundItem.file or 'Hit.wav'
    local tmpVolItem = settings.volItem or 100
    local tmpDurItem = settings.Sounds[settings.theme].soundItem.duration or 2

    if ImGui.BeginTable('Settings_Table##'..script, 5, ImGuiTableFlags.None) then
        ImGui.TableSetupColumn('##Toggle_'..script, ImGuiTableColumnFlags.WidthAlwaysAutoResize)
        ImGui.TableSetupColumn('##File_'..script, ImGuiTableColumnFlags.WidthAlwaysAutoResize)
        ImGui.TableSetupColumn('##Vol_'..script, ImGuiTableColumnFlags.WidthAlwaysAutoResize)
        ImGui.TableSetupColumn('##Dur_'..script, ImGuiTableColumnFlags.WidthAlwaysAutoResize)
        ImGui.TableSetupColumn('##SaveBtn_'..script, ImGuiTableColumnFlags.WidthAlwaysAutoResize)
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        tmpDoHit = ImGui.Checkbox('Hit Alert##'..script, tmpDoHit)
        if tmpDoHit ~= settings.doHit then
            settings.doHit = tmpDoHit
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(70)
        tmpSndHit = ImGui.InputText('Filename##HITSND', tmpSndHit)
        if tmpSndHit ~= settings.Sounds[settings.theme].soundHit.file then
            settings.Sounds[settings.theme].soundHit.file = tmpSndHit
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpVolHit = ImGui.InputFloat('Volume##HITVOL', tmpVolHit, 0.1)
        if tmpVolHit ~= settings.volHit then
            settings.volHit = tmpVolHit
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpDurHit = ImGui.InputInt('Duration##HITDUR', tmpDurHit)
        if tmpDurHit ~= settings.Sounds[settings.theme].soundHit.duration then
            settings.Sounds[settings.theme].soundHit.duration = tmpDurHit
        end
        ImGui.TableNextColumn()
        if ImGui.Button("Test and Save##HITALERT") then
            soundDuration = tmpDurHit
            setVolume(settings.volHit)
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundHit.file))
            mq.pickle(configFile, settings)
        end
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        --- Bonk Alerts ---
        tmpDoBonk = ImGui.Checkbox('Bonk Alert##'..script, tmpDoBonk)
        if tmpDoBonk ~= settings.doBonk then
            settings.doBonk = tmpDoBonk
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(70)
        tmpSndBonk = ImGui.InputText('Filename##BonkSND', tmpSndBonk)
        if tmpSndBonk ~= settings.Sounds[settings.theme].soundBonk.file then
            settings.Sounds[settings.theme].soundBonk.file = tmpSndBonk
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpVolBonk = ImGui.InputFloat('Volume##BonkVOL', tmpVolBonk, 0.1)
        if tmpVolBonk ~= settings.volBonk then
            settings.volBonk = tmpVolBonk
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpDurBonk = ImGui.InputInt('Duration##BonkDUR', tmpDurBonk)
        if tmpDurBonk ~= settings.Sounds[settings.theme].soundBonk.duration then
            settings.Sounds[settings.theme].soundBonk.duration = tmpDurBonk
        end
        ImGui.TableNextColumn()
        if ImGui.Button("Test and Save##BonkALERT") then
            soundDuration = tmpDurBonk
            setVolume(settings.volBonk)
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundBonk.file))
            mq.pickle(configFile, settings)
        end
        --- Spell Fizzle Alerts ---
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        tmpDoFizzle = ImGui.Checkbox('Fizzle Alert##'..script, tmpDoFizzle)
        if tmpDoFizzle ~= settings.doFizzle then
            settings.doFizzle = tmpDoFizzle
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(70)
        tmpSndFizzle = ImGui.InputText('Filename##FizzleSND', tmpSndFizzle)
        if tmpSndFizzle ~= settings.Sounds[settings.theme].soundFizzle.file then
            settings.Sounds[settings.theme].soundFizzle.file = tmpSndFizzle
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpVolFizzle = ImGui.InputFloat('Volume##FizzleVOL', tmpVolFizzle, 0.1)
        if tmpVolFizzle ~= settings.volFizzle then
            settings.volFizzle = tmpVolFizzle
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpDurFizzle = ImGui.InputInt('Duration##FizzleDUR', tmpDurFizzle)
        if tmpDurFizzle ~= settings.Sounds[settings.theme].soundFizzle.duration then
            settings.Sounds[settings.theme].soundFizzle.duration = tmpDurFizzle
        end
        ImGui.TableNextColumn()
        if ImGui.Button("Test and Save##FizzleALERT") then
            soundDuration = tmpDurFizzle
            setVolume(settings.volFizzle)
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundFizzle.file))
            mq.pickle(configFile, settings)
        end

        --- Lvl Alerts ---
        ImGui.TableNextRow()
        ImGui.TableNextColumn()

        tmpDoLvl = ImGui.Checkbox('LvlUp Alert##'..script, tmpDoLvl)
        if settings.doLvl ~= tmpDoLvl then
            settings.doLvl = tmpDoLvl
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(70)
        tmpSndLvl = ImGui.InputText('Filename##LvlUpSND', tmpSndLvl)
        if tmpSndLvl ~= settings.Sounds[settings.theme].soundLvl.file then
            settings.Sounds[settings.theme].soundLvl.file = tmpSndLvl
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpVolLvl = ImGui.InputFloat('Volume##LvlUpVOL', tmpVolLvl, 0.1)
        if tmpVolLvl ~= settings.volLvl then
            settings.volLvl = tmpVolLvl
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpDurLvl = ImGui.InputInt('Duration##LvlUpDUR', tmpDurLvl)
        if tmpDurLvl ~= settings.Sounds[settings.theme].soundLvl.duration then
            settings.Sounds[settings.theme].soundLvl.duration = tmpDurLvl
        end
        ImGui.TableNextColumn()
        if ImGui.Button("Test and Save##LvlUpALERT") then
            soundDuration = tmpDurLvl
            setVolume(settings.volLvl)
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundLvl.file))
            mq.pickle(configFile, settings)
        end
        --- AA Alerts ---
        ImGui.TableNextRow()
        ImGui.TableNextColumn()

        tmpDoAA = ImGui.Checkbox('AA Alert##'..script, tmpDoAA)
        if tmpDoAA ~= settings.doAA then
            settings.doAA = tmpDoAA
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(70)
        tmpSndAA = ImGui.InputText('Filename##AASND', tmpSndAA)
        if tmpSndAA ~= settings.Sounds[settings.theme].soundAA.file then
            settings.Sounds[settings.theme].soundAA.file = tmpSndAA
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpVolAA = ImGui.InputFloat('Volume##AAVOL', tmpVolAA, 0.1)
        if tmpVolAA ~= settings.volAA then
            settings.volAA = tmpVolAA
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpDurAA = ImGui.InputInt('Duration##AADUR', tmpDurAA)
        if tmpDurAA ~= settings.Sounds[settings.theme].soundAA.duration then
            settings.Sounds[settings.theme].soundAA.duration = tmpDurAA
        end
        ImGui.TableNextColumn()
        if ImGui.Button("Test and Save##AAALERT") then
            soundDuration = tmpDurAA
            setVolume(settings.volAA)
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundAA.file))
            mq.pickle(configFile, settings)
        end

        --- Death Alerts ---
        ImGui.TableNextRow()
        ImGui.TableNextColumn()

        tmpDoDie = ImGui.Checkbox('Death Alert##'..script, tmpDoDie)
        if settings.doDie ~= tmpDoDie then
            settings.doDie = tmpDoDie
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(70)
        tmpSndDie = ImGui.InputText('Filename##DeathSND', tmpSndDie)
        if tmpSndDie ~= settings.Sounds[settings.theme].soundDie.file then
            settings.Sounds[settings.theme].soundDie.file = tmpSndDie
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpVolDie = ImGui.InputFloat('Volume##DeathVOL', tmpVolDie, 0.1)
        if tmpVolDie ~= settings.volDie then
            settings.volDie = tmpVolDie
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpDurDie = ImGui.InputInt('Duration##DeathDUR', tmpDurDie)
        if tmpDurDie ~= settings.Sounds[settings.theme].soundDie.duration then
            settings.Sounds[settings.theme].soundDie.duration = tmpDurDie
        end
        ImGui.TableNextColumn()
        if ImGui.Button("Test and Save##DeathALERT") then
            soundDuration = tmpDurDie
            setVolume(settings.volDie)
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundDie.file))
            mq.pickle(configFile, settings)
        end
        -- Alarm Alerts
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        tmpDoAlarm = ImGui.Checkbox('Alarm Alert##'..script, tmpDoAlarm)
        if settings.doAlarm ~= tmpDoAlarm then
            settings.doAlarm = tmpDoAlarm
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(70)
        tmpSndAlarm = ImGui.InputText('Filename##AlarmSND', tmpSndAlarm)
        if tmpSndAlarm ~= settings.Sounds[settings.theme].soundAlarm.file then
            settings.Sounds[settings.theme].soundAlarm.file = tmpSndAlarm
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpVolAlarm = ImGui.InputFloat('Volume##AlarmVOL', tmpVolAlarm, 0.1)
        if tmpVolAlarm ~= settings.volAlarm then
            settings.volAlarm = tmpVolAlarm
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpDurAlarm = ImGui.InputInt('Duration##AlarmDUR', tmpDurAlarm)
        if tmpDurAlarm ~= settings.Sounds[settings.theme].soundAlarm.duration then
            settings.Sounds[settings.theme].soundAlarm.duration = tmpDurAlarm
        end
        ImGui.TableNextColumn()
        if ImGui.Button("Test and Save##AlarmALERT") then
            soundDuration = tmpDurAlarm
            setVolume(settings.volAlarm)
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundAlarm.file))
            mq.pickle(configFile, settings)
        end

        --- LOW HP ---
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        tmpDoHP = ImGui.Checkbox('Low Health Alert##'..script, tmpDoHP)
        if settings.doHP ~= tmpDoHP then
            settings.doHP = tmpDoHP
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(70)
        tmpSndHP = ImGui.InputText('Filename##LowHealthSND', tmpSndHP)
        if tmpSndHP ~= settings.Sounds[settings.theme].soundLowHp.file then
            settings.Sounds[settings.theme].soundLowHp.file = tmpSndHP
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpVolHP = ImGui.InputFloat('Volume##LowHealthVOL', tmpVolHP, 0.1)
        if tmpVolHP ~= settings.volHP then
            settings.volHP = tmpVolHP
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpDurHP = ImGui.InputInt('Duration##LowHealthDUR', tmpDurHP)
        if tmpDurHP ~= settings.Sounds[settings.theme].soundLowHp.duration then
            settings.Sounds[settings.theme].soundLowHp.duration = tmpDurHP
        end
        ImGui.TableNextColumn()
        if ImGui.Button("Test and Save##LowHealthALERT") then
            soundDuration = tmpDurHP
            setVolume(settings.volHP)
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundLowHp.file))
            mq.pickle(configFile, settings)
        end

        --- Item Alerts ---
        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        tmpDoItem = ImGui.Checkbox('Item Alert##'..script, tmpDoItem)
        if settings.doItem ~= tmpDoItem then
            settings.doItem = tmpDoItem
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(70)
        tmpSndItem = ImGui.InputText('Filename##ItemSND', tmpSndItem)
        if tmpSndItem ~= settings.Sounds[settings.theme].soundItem.file then
            settings.Sounds[settings.theme].soundItem.file = tmpSndItem
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpVolItem = ImGui.InputFloat('Volume##ItemVOL', tmpVolItem, 0.1)
        if tmpVolItem ~= settings.volItem then
            settings.volItem = tmpVolItem
        end
        ImGui.TableNextColumn()
        ImGui.SetNextItemWidth(100)
        tmpDurItem = ImGui.InputInt('Duration##ItemDUR', tmpDurItem)
        if tmpDurItem ~= settings.Sounds[settings.theme].soundItem.duration then
            settings.Sounds[settings.theme].soundItem.duration = tmpDurItem
        end
        ImGui.TableNextColumn()
        if ImGui.Button("Test and Save##ItemALERT") then
            soundDuration = tmpDurItem
            setVolume(settings.volItem)
            playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundItem.file))
            mq.pickle(configFile, settings)
        end

        ImGui.EndTable()
    end
    tmpLowHp = ImGui.InputInt('Low HP Threshold##LowHealthThresh', tmpLowHp, 1)
    if tmpLowHp ~= settings.lowHP then
        settings.lowHP = tmpLowHp
    end
    tmpPulse = ImGui.InputInt('Pulse Delay##LowHealthPulse', tmpPulse, 1)
    if tmpPulse ~= settings.Pulse then
        settings.Pulse = tmpPulse
    end
    if tmpDoItem then
        settings.ItemWatch = ImGui.InputText('Item Watch##ItemWatch', settings.ItemWatch)
    end

    if ImGui.Button('Close') then
        openConfigGUI = false
        mq.pickle(configFile, settings)
        if tmpDoItem then
            if itemWatch then
                mq.unevent("item_added")
                itemWatch = false
            end
            if settings.ItemWatch ~= '' then
                local eStr = string.format("#*#%s#*#", settings.ItemWatch)
                mq.event("item_added", eStr,  function(line)
                    eventSound(line, 'Item', settings.volItem)
                    soundDuration = settings.Sounds[settings.theme].soundItem.duration
                end)
                itemWatch = true
            end
        end
    end

    ImGui.End()
end

-- Main loop
local function mainLoop()
    while RUNNING do
        if mq.TLO.EverQuest.GameState() ~= "INGAME" then
            printf("\aw[\at%s\ax] \arNot in game, \ayTry again later...",script)
            mq.exit()
        end
        mq.doevents()
        mq.delay(1)
        if mq.TLO.Window('ConfirmationDialogBox').Open() then
            alarmTagged = false
            checkAlarms()
        end
        if mq.TLO.Me.PctHPs() <= settings.lowHP and mq.TLO.Me.PctHPs() > 1 and settings.doHP then
            timerA = os.time()
            if timerA - timerB > settings.Pulse then
                originalVolume = getVolume()
                setVolume(settings.volHP)
                timerPlay = os.time()
                soundDuration = settings.Sounds[settings.theme].soundLowHp.duration
                playSound(string.format("%s%s/%s", path, settings.theme, settings.Sounds[settings.theme].soundLowHp.file))
                timerB = os.time()
            end
        end
        local tnpVol = getVolume()
        if playing == true  and timerPlay > 0 then
            local curTime = os.time()
            if curTime - timerPlay > soundDuration then
                resetVolume()
            end
        end
        if not playing and timerPlay == 0 then
            mq.delay(100)
            local tmpVol = getVolume()
            if originalVolume ~= tmpVol then
                originalVolume = tmpVol
            end
        end
    end
end

-- Init
local function init()
    helpList('help')
    loadSettings()
    originalVolume = getVolume()
    -- Event bindings
    mq.event("gained_level", "You have gained a level! Welcome to level #*#", function(line)
        eventSound(line, 'Lvl', settings.volLvl)
        soundDuration = settings.Sounds[settings.theme].soundLvl.duration
    end)
    mq.event("hit", "You #*# for #*# of damage.", function(line)
        eventSound(line, 'Hit', settings.volHit)
        soundDuration = settings.Sounds[settings.theme].soundHit.duration
    end)
    mq.event("been_hit", "#*# YOU for #*# of damage.", function(line)
        eventSound(line, 'Bonk', settings.volBonk)
        soundDuration = settings.Sounds[settings.theme].soundBonk.duration
    end)
    mq.event("you_died", "You died.", function(line)
        eventSound(line, 'Die', settings.volDie)
        soundDuration = settings.Sounds[settings.theme].soundDie.duration
    end)
    mq.event("you_died2", "You have been slain by#*#", function(line)
        eventSound(line, 'Die', settings.volDie)
        soundDuration = settings.Sounds[settings.theme].soundDie.duration
    end)
    mq.event("gained_aa", "#*#gained an ability point#*#", function(line)
        eventSound(line, 'AA', settings.volAA)
        soundDuration = settings.Sounds[settings.theme].soundAA.duration
    end)
    mq.event("spell_fizzle", "Your#*#spell fizzles#*#", function(line)
        eventSound(line, 'Fizzle', settings.volFizzle)
        soundDuration = settings.Sounds[settings.theme].soundFizzle.duration
    end)

    -- Slash Command Binding
    mq.bind('/sillysounds', bind)

    -- Setup Config GUI
    mq.imgui.init(script..' Config', Config_GUI)

    mainLoop()
end

init()
