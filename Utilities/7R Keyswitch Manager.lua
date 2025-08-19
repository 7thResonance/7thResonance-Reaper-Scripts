--[[
@description 7R Keyswitch Manager
@author 7thResonance
@version 1.o
@changelog
     - Initial
@donation https://paypal.me/7thresonance
@about Original Script by Ugurcan Orcun; ReaKS - Keyswitch Articulation Manager
   I have added a few extra features.
      - Search and load MIDInotename files right inside the script.
      - Option to Extend already existing (live played or inserted KS notes).
      - Autosave window positions and size on close.
@screenshot Window https://i.postimg.cc/xjBRHWP8/Screenshot-2025-08-20-044639.png
    Settings https://i.postimg.cc/wMR1g4tb/Screenshot-2025-08-20-044443.png
    Loaded KSs https://i.postimg.cc/XXMpJKdN/Screenshot-2025-08-20-044433.png
    KS Inject https://i.postimg.cc/Wpd8d2gx/Screenshot-2025-08-20-044509.png
--]]
if not reaper.ImGui_GetBuiltinPath then
    return reaper.MB('ReaImGui is not installed or too old.', 'ReaKS', 0)
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

ActiveMidiEditor = nil
PreviousMidiEditor = nil
ActiveTake = nil
ActiveItem = nil
ActiveTrack = nil
MIDIHash = nil
PreviousMIDIHash = nil
Articulations = {}
CC = {}
ActivatedKS = {}

function ThemeColorToImguiColor(themeColorName)
    local color = reaper.GetThemeColor(themeColorName, 0)
    local r, g, b = reaper.ColorFromNative(color)
    return ImGui.ColorConvertDouble4ToU32(r/255, g/255, b/255, 1)
end

EnumThemeColors = { -- fetch colors from Reaper theme
    A = ThemeColorToImguiColor("col_tracklistbg"), -- Background
    B = ThemeColorToImguiColor("col_tracklistbg") + 0x111111FF, -- Default Interactive
    C = ThemeColorToImguiColor("col_tracklistbg") + 0x444444FF, -- Clicked
    D = ThemeColorToImguiColor("col_tracklistbg") + 0x222222FF, -- Hovered
    E = ThemeColorToImguiColor("col_tcp_text"), -- HeaderText
    F = 0xFFFFFFFF, -- Text
    G = ThemeColorToImguiColor("midi_editcurs") -- Active Articulation
}

InsertionModes = {
    "Single",
    "Multi"
}

FontTitle = ImGui.CreateFont('sans-serif', 24, ImGui.FontFlags_Italic)
Font = ImGui.CreateFont('sans-serif', 14)

ActiveTakeName = nil
ActiveTrackName = nil
ActiveTrackColor = 0xFFFFFFFF

Setting_AutoupdateTextEvent = true
Setting_ItemsPerColumn = 10
Setting_PPQOffset = -1
Setting_SendNoteWhenClicked = false
Setting_ChaseMode = false
Setting_ExtendOnRefresh = true

Modal_Settings = false
Modal_NoteNameHelper = false

Injector_NotesList = ""
Injector_FirstNoteID = 36

PPQ = reaper.SNM_GetIntConfigVar("miditicksperbeat", 960)

function SaveSettings()
    reaper.SetExtState("ReaKS", "Setting_AutoupdateTextEvent", tostring(Setting_AutoupdateTextEvent), true)
    reaper.SetExtState("ReaKS", "Setting_ItemsPerColumn", tostring(Setting_ItemsPerColumn), true)
    reaper.SetExtState("ReaKS", "Setting_PPQOffset", tostring(Setting_PPQOffset), true)
    reaper.SetExtState("ReaKS", "Setting_SendNoteWhenClicked", tostring(Setting_SendNoteWhenClicked), true)
    reaper.SetExtState("ReaKS", "Setting_ChaseMode", tostring(Setting_ChaseMode), true)
    reaper.SetExtState("ReaKS", "Setting_ExtendOnRefresh", tostring(Setting_ExtendOnRefresh), true)

    -- Save window position & size
    reaper.SetExtState("ReaKS", "Window_PosX", tostring(Window_PosX), true)
    reaper.SetExtState("ReaKS", "Window_PosY", tostring(Window_PosY), true)
    reaper.SetExtState("ReaKS", "Window_SizeW", tostring(Window_SizeW), true)
    reaper.SetExtState("ReaKS", "Window_SizeH", tostring(Window_SizeH), true)
end

function LoadSettings()
    local val
    val = reaper.GetExtState("ReaKS", "Setting_AutoupdateTextEvent")
    if val ~= "" then Setting_AutoupdateTextEvent = val == "true" end

    val = reaper.GetExtState("ReaKS", "Setting_ItemsPerColumn")
    if val ~= "" then Setting_ItemsPerColumn = tonumber(val) end

    val = reaper.GetExtState("ReaKS", "Setting_PPQOffset")
    if val ~= "" then Setting_PPQOffset = tonumber(val) end

    val = reaper.GetExtState("ReaKS", "Setting_SendNoteWhenClicked")
    if val ~= "" then Setting_SendNoteWhenClicked = val == "true" end

    val = reaper.GetExtState("ReaKS", "Setting_ChaseMode")
    if val ~= "" then Setting_ChaseMode = val == "true" end

    val = reaper.GetExtState("ReaKS", "Setting_ExtendOnRefresh")
    if val ~= "" then Setting_ExtendOnRefresh = val == "true" end

    -- Load window position & size
    val = reaper.GetExtState("ReaKS", "Window_PosX")
    if val ~= "" then Window_PosX = tonumber(val) end

    val = reaper.GetExtState("ReaKS", "Window_PosY")
    if val ~= "" then Window_PosY = tonumber(val) end

    val = reaper.GetExtState("ReaKS", "Window_SizeW")
    if val ~= "" then Window_SizeW = tonumber(val) end

    val = reaper.GetExtState("ReaKS", "Window_SizeH")
    if val ~= "" then Window_SizeH = tonumber(val) end
end

function UpdateActiveTargets()
    ActiveMidiEditor = reaper.MIDIEditor_GetActive() or nil
    ActiveTake = reaper.MIDIEditor_GetTake(ActiveMidiEditor) or nil
    if ActiveTake ~= nil then ActiveTrack = reaper.GetMediaItemTake_Track(ActiveTake) end
    if ActiveTake ~= nil then ActiveItem = reaper.GetMediaItemTake_Item(ActiveTake) end

    if ActiveTake ~= nil and ActiveTake ~= PreviousTake then
        Articulations = {}
        CC = {}
        RefreshGUI()

        ActiveTakeName = reaper.GetTakeName(ActiveTake)
        _, ActiveTrackName = reaper.GetTrackName(ActiveTrack)

        ActiveTrackColor = reaper.GetTrackColor(ActiveTrack)
        if ActiveTrackColor == 0 then ActiveTrackColor = 0xFFFFFFFF end

        local r, g, b = reaper.ColorFromNative(ActiveTrackColor)
        ActiveTrackColor = ImGui.ColorConvertDouble4ToU32(r/255, g/255, b/255, 1)
    end

    PreviousTake = ActiveTake
end

function UpdateTextEvents()
    if ActiveTake == nil then return end

    --Clear all text events first
    local _, _, _, TextSysexEventCount = reaper.MIDI_CountEvts(ActiveTake)
    for TextSysexEvent = TextSysexEventCount, 1, -1 do
        local _, _, _, _, eventType, _, _ = reaper.MIDI_GetTextSysexEvt(ActiveTake, TextSysexEvent - 1)
        if eventType == 1 then
            reaper.MIDI_DeleteTextSysexEvt(ActiveTake, TextSysexEvent - 1)
        end
    end

    --Insert a text event for each note event that's in the articulation list
    local _, noteCount = reaper.MIDI_CountEvts(ActiveTake)
    for noteID = 1, noteCount do
        local _, _, _, startppqpos, _, _, pitch, _ = reaper.MIDI_GetNote(ActiveTake, noteID - 1)
        if Articulations[pitch] ~= nil then
            reaper.MIDI_InsertTextSysexEvt(ActiveTake, false, false, startppqpos, 1, Articulations[pitch])
        end
    end
end

function LoadNoteNames()
    Articulations = {}
    CC = {}
    reaper.MIDIEditor_LastFocused_OnCommand(40409, false)
    RefreshGUI()
end

function SaveNoteNames()
    reaper.MIDIEditor_LastFocused_OnCommand(40410, false)
end

function ClearNoteNames()
    reaper.MIDIEditor_LastFocused_OnCommand(40412, false)
    Articulations = {}
    CC = {}
end

function InjectNoteNames(noteNames, firstNoteID)
    if ActiveTake == nil then return end
    local noteNameTable = {}
    for noteName in string.gmatch(noteNames, "([^\n]+)") do
        table.insert(noteNameTable, noteName)
    end

    for i, noteName in ipairs(noteNameTable) do
        reaper.SetTrackMIDINoteNameEx(0, ActiveTrack, firstNoteID + i - 1, 0, noteName)
    end

    RefreshGUI()
end

function ParseNoteNamesFromTake()
    if ActiveTake == nil then return end

    Articulations = {}
    for i = 0, 127 do
        local notename = reaper.GetTrackMIDINoteNameEx(0, ActiveTrack, i, 0)
        if notename ~= nil then
            Articulations[i] = notename
        end
    end
end

function ParseCCNamesFromTake()
    if ActiveTake == nil then return end

    CC = {}
    for i = 128, 255 do
        local ccname = reaper.GetTrackMIDINoteNameEx(0, ActiveTrack, i, 0)
        if ccname ~= nil then
            CC[i] = ccname
        end
    end
end

function FocusToCCLane(i)
    reaper.BR_MIDI_CCLaneReplace(ActiveMidiEditor, 0, i)
end

function RenameAliasCCLane()
    reaper.MIDIEditor_LastFocused_OnCommand(40416, false)
    RefreshGUI()
end

function InsertKS(noteNumber, isShiftHeld)
    if ActiveTake == nil then return end

    local newKSStartPPQ, newKSEndPPQ

    local insertionRangeStart = math.huge
    local insertionRangeEnd = 0
    local selectionMode = false

    local MIDIItemEndPPQ = reaper.MIDI_GetPPQPosFromProjTime(ActiveTake, reaper.GetMediaItemInfo_Value(ActiveItem, "D_POSITION") + reaper.GetMediaItemInfo_Value(ActiveItem, "D_LENGTH"))

    local singleGridLength = reaper.MIDI_GetGrid(ActiveTake) * PPQ

    reaper.MIDI_DisableSort(ActiveTake)

    -- Find the earliest start time and latest end time of selected notes, if any
    if reaper.MIDI_EnumSelNotes(ActiveTake, -1) ~= -1 then
        selectionMode = true

        local selectedNoteIDX = -1
        selectedNoteIDX = reaper.MIDI_EnumSelNotes(ActiveTake, selectedNoteIDX)

        while selectedNoteIDX ~= -1 do
            local _, _, _, selectedNoteStartPPQ, selectedNoteEndPPQ = reaper.MIDI_GetNote(ActiveTake, selectedNoteIDX)

            insertionRangeStart = math.min(insertionRangeStart, selectedNoteStartPPQ)
            insertionRangeEnd = math.max(insertionRangeEnd, selectedNoteEndPPQ)
            selectedNoteIDX = reaper.MIDI_EnumSelNotes(ActiveTake, selectedNoteIDX)
        end
    -- Find playhead and one exact grid length after it if no notes are selected
    else
        insertionRangeStart = reaper.GetCursorPosition()
        insertionRangeStart = reaper.MIDI_GetPPQPosFromProjTime(ActiveTake, insertionRangeStart)

        if Setting_ChaseMode then
            insertionRangeEnd = MIDIItemEndPPQ
        else
            insertionRangeEnd = insertionRangeStart + singleGridLength
        end
    end

    newKSStartPPQ = insertionRangeStart + Setting_PPQOffset
    newKSEndPPQ = insertionRangeEnd + Setting_PPQOffset

    -- Operations on other KS notes
    local _, noteCount = reaper.MIDI_CountEvts(ActiveTake)
    if not isShiftHeld then
        for noteID = noteCount, 0, -1 do
            local _, _, _, startPosPPQ, endPosPPQ, _, pitch, _ = reaper.MIDI_GetNote(ActiveTake, noteID)
            newKSStartPPQ = insertionRangeStart + Setting_PPQOffset
            newKSEndPPQ = insertionRangeEnd + Setting_PPQOffset

            -- Process overlapping notes
            if Articulations[pitch] then
                if startPosPPQ < newKSStartPPQ and endPosPPQ > newKSStartPPQ then reaper.MIDI_SetNote(ActiveTake, noteID, nil, nil, nil, newKSStartPPQ) end
                if startPosPPQ < newKSStartPPQ and endPosPPQ > newKSStartPPQ and endPosPPQ < newKSEndPPQ then reaper.MIDI_SetNote(ActiveTake, noteID, nil, nil, nil, newKSStartPPQ) end
                if startPosPPQ >= newKSStartPPQ and startPosPPQ < newKSEndPPQ and endPosPPQ > newKSEndPPQ then reaper.MIDI_SetNote(ActiveTake, noteID, nil, nil, newKSEndPPQ, nil) end
                if startPosPPQ >= newKSStartPPQ and endPosPPQ <= newKSEndPPQ then reaper.MIDI_DeleteNote(ActiveTake, noteID) end
            end
        end
    end

    reaper.Undo_BeginBlock()
    reaper.MarkTrackItemsDirty(ActiveTrack, ActiveItem)

    -- Insert the new KS note

    reaper.MIDI_InsertNote(ActiveTake, false, false, newKSStartPPQ, newKSEndPPQ, 0, noteNumber, 100, false)

    -- Move edit cursor to the end of the new note if no notes are selected
    if reaper.MIDI_EnumSelNotes(ActiveTake, -1) == -1 and not isShiftHeld then
        local mouseMovePos = 0
        if Setting_ChaseMode then mouseMovePos = insertionRangeStart + singleGridLength else mouseMovePos = insertionRangeEnd end

        reaper.SetEditCurPos(reaper.MIDI_GetProjTimeFromPPQPos(ActiveTake, mouseMovePos), true, false)
    end

    -- Update text events if the setting is enabled
    if Setting_AutoupdateTextEvent then UpdateTextEvents() end

    reaper.Undo_EndBlock("Insert KS Note", -1)

    reaper.MIDI_Sort(ActiveTake)
end

function SendMIDINote(noteNumber)
    --send a MIDI note to the virtual MIDI keyboard
    reaper.StuffMIDIMessage(0, 0x90, noteNumber, 100)

    --send note off
    reaper.StuffMIDIMessage(0, 0x80, noteNumber, 0)
end

function RemoveKS(noteNumber)
    if ActiveTake == nil then return end

    if ActivatedKS[noteNumber] ~= nil then
        reaper.MIDI_DeleteNote(ActiveTake, ActivatedKS[noteNumber])
    end
end

function LengthenSelectedNotes(toLeft)
    if ActiveTake == nil then return end

    local selectedNoteIDX = -1
    local selectedNotes = {}

    selectedNoteIDX = reaper.MIDI_EnumSelNotes(ActiveTake, selectedNoteIDX)
    while selectedNoteIDX ~= -1 do
        table.insert(selectedNotes, selectedNoteIDX)
        selectedNoteIDX = reaper.MIDI_EnumSelNotes(ActiveTake, selectedNoteIDX)
    end

    reaper.Undo_BeginBlock()
    reaper.MarkTrackItemsDirty(ActiveTrack, ActiveItem)

    for _, noteID in pairs(selectedNotes) do
        local _, _, _, startPosPPQ, endPosPPQ, _, _, _ = reaper.MIDI_GetNote(ActiveTake, noteID)
        local moveAmount = PPQ / 32

        if toLeft then
            startPosPPQ = startPosPPQ - moveAmount
        else
            endPosPPQ = endPosPPQ + moveAmount
        end

        reaper.MIDI_SetNote(ActiveTake, noteID, nil, nil, startPosPPQ, endPosPPQ)
    end

    reaper.Undo_EndBlock("Lengthen Selected Notes", -1)
end

function GetActiveKSAtPlayheadPosition()
    if ActiveTake == nil then return end

    ActivatedKS = {}
    local playheadPosition

    playheadPosition = reaper.GetPlayState() == 1 and reaper.GetPlayPosition() or reaper.GetCursorPosition()
    playheadPosition = reaper.MIDI_GetPPQPosFromProjTime(ActiveTake, playheadPosition)

    local _, noteCount = reaper.MIDI_CountEvts(ActiveTake)

    for noteID = 1, noteCount do
        local _, _, _, startppqpos, endppqpos, _, pitch, _ = reaper.MIDI_GetNote(ActiveTake, noteID - 1)
        if startppqpos <= playheadPosition and endppqpos >= playheadPosition then
            if Articulations[pitch] ~= nil then
                    ActivatedKS[pitch] = noteID - 1
            end
        end
    end
end

function RefreshGUI()
    UpdateTextEvents()
    ParseNoteNamesFromTake()
    ParseCCNamesFromTake()
end

function StylingStart(ctx)
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, EnumThemeColors.A)

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ButtonTextAlign, 0, 0.5)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, EnumThemeColors.B)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, EnumThemeColors.C)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, EnumThemeColors.D)

    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, EnumThemeColors.B)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, EnumThemeColors.C)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, EnumThemeColors.D)

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, EnumThemeColors.F)

    ImGui.PushStyleColor(ctx, ImGui.Col_Header, EnumThemeColors.B)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, EnumThemeColors.C)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, EnumThemeColors.D)

    ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark, EnumThemeColors.F)

    ImGui.PushFont(ctx, Font)
end

function StylingEnd(ctx)
    ImGui.PopStyleColor(ctx, 12)
    ImGui.PopStyleVar(ctx, 1)
    ImGui.PopFont(ctx)
end

-- UI Part
local ctx = ImGui.CreateContext('7R Keyswitch Manager')
ImGui.Attach(ctx, Font)
ImGui.Attach(ctx, FontTitle)

-- Extend current KS to item end or until next KS
function ExtendAllKS()
    if not ActiveTake then return end

    local _, noteCount = reaper.MIDI_CountEvts(ActiveTake)

    -- Collect all KS notes
    local ksNotes = {}
    for i = 0, noteCount-1 do
        local _, _, _, startPPQ, _, _, pitch, _ = reaper.MIDI_GetNote(ActiveTake, i)
        if Articulations[pitch] ~= nil then
            table.insert(ksNotes, { index = i, pitch = pitch, startPPQ = startPPQ })
        end
    end

    -- Sort KS notes by start time
    table.sort(ksNotes, function(a, b) return a.startPPQ < b.startPPQ end)

    -- Calculate end of item
    local itemEndPPQ = reaper.MIDI_GetPPQPosFromProjTime(ActiveTake,
        reaper.GetMediaItemInfo_Value(ActiveItem, "D_POSITION") +
        reaper.GetMediaItemInfo_Value(ActiveItem, "D_LENGTH"))

    -- Extend each KS until next KS or item end
    for i, ks in ipairs(ksNotes) do
        local nextStart = itemEndPPQ
        if ksNotes[i+1] then
            nextStart = ksNotes[i+1].startPPQ
        end
        reaper.MIDI_SetNote(ActiveTake, ks.index, nil, nil, nil, nextStart, nil, nil, nil)
    end

    reaper.MIDI_Sort(ActiveTake)
end

-- Note Name Browser helpers (attached child window content)
function GetNoteNamesRoot()
    local sep = package.config:sub(1,1)
    return reaper.GetResourcePath() .. sep .. 'MIDINoteNames'
end

function PathJoin(a, b)
    local sep = package.config:sub(1,1)
    if a:sub(-1) == sep then return a .. b else return a .. sep .. b end
end

function RenderNoteNameTree(path)
    local hadEntries = false

    -- Subdirectories
    local i = 0
    while true do
        local sub = reaper.EnumerateSubdirectories(path, i)
        if not sub then break end
        hadEntries = true
        local full = PathJoin(path, sub)
        local label = sub .. '##' .. full  -- show folder name, keep unique ID
        if ImGui.TreeNode(ctx, label) then
            RenderNoteNameTree(full)
            ImGui.TreePop(ctx)
        end
        i = i + 1
    end

    -- Files
    i = 0
    while true do
        local file = reaper.EnumerateFiles(path, i)
        if not file then break end
        hadEntries = true
        if file:lower():match('%.txt$') then
            if ImGui.Selectable(ctx, file, false) then
                local full = PathJoin(path, file)
                LoadNoteNamesFromFile(full)
            end
        else
            ImGui.BulletText(ctx, file)
        end
        i = i + 1
    end

    if not hadEntries then
        ImGui.Text(ctx, "(empty)")
    end
end

-- Search/browser state
NoteBrowser_Search = NoteBrowser_Search or ""
NoteBrowser_SelectedIndex = NoteBrowser_SelectedIndex or 1
NoteBrowser_Files = NoteBrowser_Files or nil
NoteBrowser_InputFocusNext = NoteBrowser_InputFocusNext or false
NoteBrowser_WasOpen = NoteBrowser_WasOpen or false
NoteBrowser_LastRoot = NoteBrowser_LastRoot or nil
NoteBrowser_CurrentDir = NoteBrowser_CurrentDir or nil

-- Build a flat list of all .txt files under the root
function BuildNoteNameFileList(root)
    NoteBrowser_Files = {}
    local function scan(path)
        -- Recurse subfolders
        local i = 0
        while true do
            local sub = reaper.EnumerateSubdirectories(path, i)
            if not sub then break end
            scan(PathJoin(path, sub))
            i = i + 1
        end
        -- Collect files
        i = 0
        while true do
            local file = reaper.EnumerateFiles(path, i)
            if not file then break end
            if file:lower():match('%.txt$') then
                table.insert(NoteBrowser_Files, { name = file, path = PathJoin(path, file) })
            end
            i = i + 1
        end
    end
    scan(root)
    table.sort(NoteBrowser_Files, function(a, b) return a.name:lower() < b.name:lower() end)
end

-- Build file list only for the selected folder (non-recursive)
function BuildFilesInDir(dir)
    NoteBrowser_Files = {}
    local i = 0
    while true do
        local file = reaper.EnumerateFiles(dir, i)
        if not file then break end
        if file:lower():match('%.txt$') then
            table.insert(NoteBrowser_Files, { name = file, path = PathJoin(dir, file) })
        end
        i = i + 1
    end
    table.sort(NoteBrowser_Files, function(a, b) return a.name:lower() < b.name:lower() end)
end

-- Render a directory-only tree; clicking a folder selects it
function RenderFolderTree(path)
    local i = 0
    while true do
        local sub = reaper.EnumerateSubdirectories(path, i)
        if not sub then break end
        local full = PathJoin(path, sub)
        local opened = ImGui.TreeNode(ctx, sub .. '##' .. full)
        if ImGui.IsItemClicked(ctx) then
            NoteBrowser_CurrentDir = full
            BuildFilesInDir(NoteBrowser_CurrentDir)
            NoteBrowser_SelectedIndex = 1
        end
        if opened then
            RenderFolderTree(full)
            ImGui.TreePop(ctx)
        end
        i = i + 1
    end
end

-- Single-pane browser: visible files accumulator
NoteBrowser_VisibleFiles = NoteBrowser_VisibleFiles or {}

-- Returns true if this folder contains any matching .txt files (directly or in subfolders)
function HasMatch(path, q)
    if q == "" then return true end
    -- Files in this folder
    local i = 0
    while true do
        local file = reaper.EnumerateFiles(path, i)
        if not file then break end
        if file:lower():match('%.txt$') and file:lower():find(q, 1, true) then
            return true
        end
        i = i + 1
    end
    -- Subfolders
    i = 0
    while true do
        local sub = reaper.EnumerateSubdirectories(path, i)
        if not sub then break end
        if HasMatch(PathJoin(path, sub), q) then
            return true
        end
        i = i + 1
    end
    return false
end

-- Render the folder tree (without showing the root label), listing .txt files under each folder.
-- When searching, only branches with matches are shown and are default-open.
function RenderNoteNameTreeFiltered(root, showRoot, q)
    NoteBrowser_VisibleFiles = {}

    local function renderDir(dir, displayName)
        if q ~= "" and not HasMatch(dir, q) then
            return
        end

        if displayName then
            local label = displayName .. '##' .. dir
            if q ~= "" then
                ImGui.SetNextItemOpen(ctx, true)
            end
            local opened = ImGui.TreeNode(ctx, label)
            if opened then
                -- Files in this folder
                local i = 0
                while true do
                    local file = reaper.EnumerateFiles(dir, i)
                    if not file then break end
                    local fl = file:lower()
                    if fl:match('%.txt$') and (q == "" or fl:find(q, 1, true)) then
                        local idx = #NoteBrowser_VisibleFiles + 1
                        local selected = (NoteBrowser_SelectedIndex == idx)
                        if ImGui.Selectable(ctx, file, selected) then
                            NoteBrowser_SelectedIndex = idx
                        end
                        if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then
                            LoadNoteNamesFromFile(PathJoin(dir, file))
                        end
                        table.insert(NoteBrowser_VisibleFiles, { name = file, path = PathJoin(dir, file) })
                    end
                    i = i + 1
                end

                -- Subfolders
                i = 0
                while true do
                    local sub = reaper.EnumerateSubdirectories(dir, i)
                    if not sub then break end
                    renderDir(PathJoin(dir, sub), sub)
                    i = i + 1
                end

                ImGui.TreePop(ctx)
            end
        else
            -- Root: render immediate subfolders only (no label for root)
            local i = 0
            while true do
                local sub = reaper.EnumerateSubdirectories(dir, i)
                if not sub then break end
                renderDir(PathJoin(dir, sub), sub)
                i = i + 1
            end
        end
    end

    renderDir(root, showRoot and (root:match("([^/\\]+)$") or root) or nil)
end

-- Load note/cc names from a file and apply to the active track
function LoadNoteNamesFromFile(filePath)
    if not ActiveTrack then return end

    -- Clear existing names
    ClearNoteNames()

    local f = io.open(filePath, "r")
    if not f then return end

    for line in f:lines() do
        line = line:gsub("\r", "")
        line = line:match("^%s*(.-)%s*$") or ""
        if line ~= "" and not line:match("^//") and not line:match("^#") then
            -- CC entries: "CC <num> <name>"
            local ccnum, ccname = line:match("^[Cc][Cc]%s+(%d+)%s+(.+)$")
            if ccnum and ccname then
                local n = tonumber(ccnum)
                if n and n >= 0 and n <= 127 then
                    reaper.SetTrackMIDINoteNameEx(0, ActiveTrack, 128 + n, 0, ccname)
                end
            else
                -- NOTE entries: "NOTE <num> <name>"
                local notenum, notename = line:match("^[Nn][Oo][Tt][Ee]%s+(%d+)%s+(.+)$")
                if notenum and notename then
                    local n = tonumber(notenum)
                    if n and n >= 0 and n <= 127 then
                        reaper.SetTrackMIDINoteNameEx(0, ActiveTrack, n, 0, notename)
                    end
                else
                    -- Plain mapping: "<num> <name>" (supports 0-127 for notes and 128-255 for CC indices)
                    local num, name = line:match("^(%d+)%s+(.+)$")
                    if num and name then
                        local n = tonumber(num)
                        if n then
                            if n >= 0 and n <= 127 then
                                reaper.SetTrackMIDINoteNameEx(0, ActiveTrack, n, 0, name)
                            elseif n >= 128 and n <= 255 then
                                reaper.SetTrackMIDINoteNameEx(0, ActiveTrack, n, 0, name)
                            end
                        end
                    end
                end
            end
        end
    end
    f:close()

    RefreshGUI()
end

-- Defaults for window pos/size
Window_PosX, Window_PosY = Window_PosX or 100, Window_PosY or 100
Window_SizeW, Window_SizeH = Window_SizeW or 800, Window_SizeH or 600

local function loop()
    StylingStart(ctx)

    -- Restore window pos/size
    ImGui.SetNextWindowPos(ctx, Window_PosX, Window_PosY, ImGui.Cond_FirstUseEver)
    ImGui.SetNextWindowSize(ctx, Window_SizeW, Window_SizeH, ImGui.Cond_FirstUseEver)

    local visible, open = ImGui.Begin(ctx, '7R Keyswitch Manager', true)
    if visible then
        if (ActiveTakeName ~= nil and ActiveTrackName ~= nil) then
            ImGui.PushFont(ctx, FontTitle)
            ImGui.TextColored(ctx, ActiveTrackColor, ActiveTrackName .. ": " .. ActiveTakeName)
            ImGui.PopFont(ctx)
        end

        ImGui.BeginGroup(ctx)
        ImGui.SeparatorText(ctx, "Note Name Maps")
        if ImGui.Button(ctx, "Load") then LoadNoteNames() end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Save") then SaveNoteNames() end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Clear") then ClearNoteNames() end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Refresh") then
            RefreshGUI()
            if Setting_ExtendOnRefresh then
                ExtendAllKS()
            end
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Inject") then ImGui.OpenPopup(ctx, "Note Name Injector") end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Settings") then ImGui.OpenPopup(ctx, "Settings") end
        ImGui.EndGroup(ctx)

        --TODO Make the settings modal
        if ImGui.BeginPopupModal(ctx, "Settings", true) then
            local val

            if ImGui.Checkbox(ctx, "Insert Text Events", Setting_AutoupdateTextEvent) then
                Setting_AutoupdateTextEvent = not Setting_AutoupdateTextEvent
                SaveSettings()
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Automatically inserts text events for articulations that's visible on Arrange view. Use [Refresh] button after manual edits to update visuals.") end

            if ImGui.Checkbox(ctx, "Send MIDI Note", Setting_SendNoteWhenClicked) then
                Setting_SendNoteWhenClicked = not Setting_SendNoteWhenClicked
                SaveSettings()
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Send a MIDI message when the KS button clicked. Good for previewing keyswitches.") end

            if ImGui.Checkbox(ctx, "Chase Mode", Setting_ChaseMode) then
                Setting_ChaseMode = not Setting_ChaseMode
                SaveSettings()
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "When enabled, the KS note will be inserted until the end of the MIDI item.") end

            if ImGui.Checkbox(ctx, "Extend existing KS notes when refreshing", Setting_ExtendOnRefresh) then
                Setting_ExtendOnRefresh = not Setting_ExtendOnRefresh
                SaveSettings()
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "When enabled, clicking Refresh will extend existing KS notes to the next KS or item end.") end

            _, val = ImGui.SliderInt(ctx, "KS per Column", Setting_ItemsPerColumn, 1, 100)
            if val ~= Setting_ItemsPerColumn then
                Setting_ItemsPerColumn = val
                SaveSettings()
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "How many KS buttons in a single column.") end

            _, val = ImGui.SliderInt(ctx, "New Note Offset", Setting_PPQOffset, -math.abs(PPQ/4), 0)
            if val ~= Setting_PPQOffset then
                Setting_PPQOffset = val
                SaveSettings()
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Negative offset for inserted KS note. Helps with triggering KS just before the note. Default is -1.") end

            ImGui.EndPopup(ctx)
        end


        if ImGui.BeginPopupModal(ctx, "Note Name Injector", true) then
            _, Injector_NotesList = ImGui.InputTextMultiline(ctx, "Note Names", Injector_NotesList, 128, 256)
            ImGui.SetNextItemWidth(ctx, 128)
            _, Injector_FirstNoteID = ImGui.InputInt(ctx, "Starting Note ID", Injector_FirstNoteID)
            if ImGui.Button(ctx, "Inject!") then InjectNoteNames(Injector_NotesList, Injector_FirstNoteID) end
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "Clear") then ClearNoteNames() end
            ImGui.EndPopup(ctx)
        end

        -- Show attached browser when no note name list is loaded
        local hasNoteNames = false
        for _, _ in pairs(Articulations) do
            hasNoteNames = true
            break
        end
        if not hasNoteNames then
            ImGui.SeparatorText(ctx, "Note Name Files")
            ImGui.BeginChild(ctx, "NoteNameBrowser", -1, 300, 0)

            local root = GetNoteNamesRoot()

            -- Focus search on first open
            if not NoteBrowser_WasOpen then
                NoteBrowser_InputFocusNext = true
                NoteBrowser_WasOpen = true
            end
            if NoteBrowser_InputFocusNext then
                ImGui.SetKeyboardFocusHere(ctx)
                NoteBrowser_InputFocusNext = false
            end

            -- Search bar
            ImGui.SetNextItemWidth(ctx, -1)
            _, NoteBrowser_Search = ImGui.InputText(ctx, "Search", NoteBrowser_Search)

            -- Trap other nav keys and keep focus on search
            if ImGui.IsKeyPressed(ctx, ImGui.Key_Tab, true)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_LeftArrow, true)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_RightArrow, true)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_PageUp, true)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_PageDown, true)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_Home, true)
                or ImGui.IsKeyPressed(ctx, ImGui.Key_End, true) then
                NoteBrowser_InputFocusNext = true
            end

            -- Render single-pane tree. Root label hidden; show subfolders as top-level nodes.
            local q = (NoteBrowser_Search or ""):lower()
            RenderNoteNameTreeFiltered(root, false, q)

            -- Selection bounds based on visible files in the tree
            local total = #NoteBrowser_VisibleFiles
            if total == 0 then
                NoteBrowser_SelectedIndex = 1
            else
                if NoteBrowser_SelectedIndex < 1 then NoteBrowser_SelectedIndex = 1 end
                if NoteBrowser_SelectedIndex > total then NoteBrowser_SelectedIndex = total end
            end

            -- Keyboard: arrows + enter act on visible files
            if total > 0 then
                if ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow, true) then
                    NoteBrowser_SelectedIndex = math.min(total, NoteBrowser_SelectedIndex + 1)
                end
                if ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow, true) then
                    NoteBrowser_SelectedIndex = math.max(1, NoteBrowser_SelectedIndex - 1)
                end
                if ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter) then
                    local sel = NoteBrowser_VisibleFiles[NoteBrowser_SelectedIndex]
                    if sel and sel.path then
                        LoadNoteNamesFromFile(sel.path)
                    end
                end
            end

            ImGui.EndChild(ctx)
        else
            -- Reset focus trigger when browser is closed
            NoteBrowser_WasOpen = false
        end

 if ActiveTake == nil then
            ImGui.Separator(ctx)
            ImGui.Text(ctx, "No active MIDI take is open in the MIDI editor.")
        else
            ImGui.SeparatorText(ctx, "Keyswitches")
            local itemCount = 0
            ImGui.BeginGroup(ctx)

            for i = 0, 127 do
                if Articulations[i] ~= nil then
                    local articulation = Articulations[i]

                    if ActivatedKS[i] ~= nil then ImGui.PushStyleColor(ctx, ImGui.Col_Button, EnumThemeColors.G) end

                    if ImGui.Button(ctx, articulation, 100) then
                        local isShiftHeld = ImGui.GetKeyMods(ctx) == ImGui.Mod_Shift
                        local isCtrlHeld = ImGui.GetKeyMods(ctx) == ImGui.Mod_Ctrl
                        local isAltHeld = ImGui.GetKeyMods(ctx) == ImGui.Mod_Alt

                        if isCtrlHeld then
                            SendMIDINote(i)
                        elseif isAltHeld then
                            RemoveKS(i)
                        else
                            InsertKS(i, isShiftHeld)
                            if Setting_SendNoteWhenClicked then SendMIDINote(i) end
                        end
                    end

                    if ActivatedKS[i] ~= nil then ImGui.PopStyleColor(ctx) end

                    itemCount = itemCount + 1
                    if itemCount % Setting_ItemsPerColumn == 0 then
                        ImGui.EndGroup(ctx)
                        ImGui.SameLine(ctx)
                        ImGui.BeginGroup(ctx)
                    end
                end
            end
            ImGui.EndGroup(ctx)
        end

        -- Save window pos/size before ending
        Window_PosX, Window_PosY = ImGui.GetWindowPos(ctx)
        Window_SizeW, Window_SizeH = ImGui.GetWindowSize(ctx)

        ImGui.End(ctx)
    end

    StylingEnd(ctx)
    UpdateActiveTargets()
    GetActiveKSAtPlayheadPosition()

    if open then
            reaper.defer(loop)
        else
            SaveSettings() -- Save window pos/size & other settings when closing
        end
end

LoadSettings()
reaper.set_action_options(1)
reaper.defer(loop)