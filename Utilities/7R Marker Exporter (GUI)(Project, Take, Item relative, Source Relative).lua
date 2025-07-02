--[[
@description 7R Marker Exporter (Project/Take)
@author 7thResonance
@version 1.0
@changelog Initial
@about GUI for exporting project and take markers in vairious formats.
- HH:MM:SS
- HH:MM:SS:MS
- MM:SS Youtube timestamp style
- MM:SS:MS
- SS
- SS:MS
- MS only
- Frames
- Beats
- Bar:Beats

-Optional Numbering

--]]
local reaper = reaper

-- SETTINGS
local SCRIPT_TITLE = "Export Project & Item Markers"

-- REAIMGUI SETUP
if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("ReaImGui not found! Please install via ReaPack.", "Error", 0)
  return
end

local ctx = reaper.ImGui_CreateContext(SCRIPT_TITLE)
local FONT_SIZE = 16.0
local font = reaper.ImGui_CreateFont('sans-serif', FONT_SIZE)
reaper.ImGui_Attach(ctx, font)

-- GUI STATE
local marker_time_format = 1 -- see format_options below
local marker_numbering = true
local item_marker_timebase = 1 -- 1:Item-Relative, 2:Project-Relative, 3:Source-Relative

local format_options = {
  "HH:MM:SS",
  "HH:MM:SS:MS",
  "MM:SS",
  "MM:SS:MS",
  "SS",
  "SS:MS",
  "MS Only",
  "Frames",
  "Beats",
  "Bar:Beat"
}
local timebase_options = {
  "Item-Relative",
  "Project-Relative",
  "Source-Relative"
}

------------------------------------------------------
-- UTILS
------------------------------------------------------

local function get_project_framerate()
  local rate = reaper.SNM_GetIntConfigVar and reaper.SNM_GetIntConfigVar("projfrrate", -1) or -1
  if rate == -1 then
    local _, str = reaper.GetSetProjectInfo_String(0, "VIDEO_FRAME_RATE", "", false)
    rate = tonumber(str) or 30
  end
  return rate
end

local function format_time(seconds, fmt, framerate)
  seconds = tonumber(seconds) or 0
  local ms = math.floor((seconds % 1) * 1000)
  if fmt == 1 then
    -- HH:MM:SS
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d", h, m, s)
  elseif fmt == 2 then
    -- HH:MM:SS:MS
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
  elseif fmt == 3 then
    -- MM:SS
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d", m, s)
  elseif fmt == 4 then
    -- MM:SS:MS
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return string.format("%02d:%02d.%03d", m, s, ms)
  elseif fmt == 5 then
    -- SS
    local s = math.floor(seconds)
    return string.format("%d", s)
  elseif fmt == 6 then
    -- SS:MS
    local s = math.floor(seconds)
    return string.format("%d.%03d", s, ms)
  elseif fmt == 7 then
    -- MS only
    local ms_total = math.floor(seconds * 1000)
    return string.format("%d", ms_total)
  elseif fmt == 8 then
    -- Frames
    local rate = framerate or get_project_framerate()
    local frames = math.floor(seconds * rate + 0.5)
    return tostring(frames)
  else
    return tostring(seconds)
  end
end

local function format_beats(time)
  local proj = 0
  local qn = reaper.TimeMap2_timeToQN(proj, time)
  return string.format("%.3f", qn)
end

local function format_bar_beat(time)
  local proj = 0
  local _, bar, beat, _ = reaper.TimeMap2_timeToBeats(proj, time)
  return string.format("%d:%d", bar, beat)
end

local function GetProjectMarkers()
  local markers = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions
  for i = 0, total-1 do
    local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers(i)
    if not isrgn then
      table.insert(markers, {idx=idx, pos=pos, name=name or ""})
    end
  end
  return markers
end

local function GetProjectMarkerSelection(time_sel_start, time_sel_end)
  local all = GetProjectMarkers()
  if not (time_sel_start and time_sel_end and time_sel_end > time_sel_start) then
    return all
  end
  local filtered = {}
  for _, m in ipairs(all) do
    if m.pos >= time_sel_start and m.pos <= time_sel_end then
      table.insert(filtered, m)
    end
  end
  return filtered
end

local function GetSelectedItems()
  local t = {}
  for i = 0, reaper.CountSelectedMediaItems(0)-1 do
    t[#t+1] = reaper.GetSelectedMediaItem(0, i)
  end
  return t
end

-- Unified take marker extraction and conversion, with filtering by time selection
-- timebase: 1 = item-relative, 2 = project-relative, 3 = source-relative
local function GetTakeMarkersFiltered(item, timebase, time_sel_start, time_sel_end)
  local take = reaper.GetActiveTake(item)
  if not take then return {} end
  local ret = {}
  local num = reaper.GetNumTakeMarkers(take)
  local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  local take_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

  for i = 0, num-1 do
    local src_pos, name = reaper.GetTakeMarker(take, i) -- src_pos is source-relative!
    local pos
    if timebase == 1 then
      pos = (src_pos - take_offset) / rate
    elseif timebase == 2 then
      pos = item_pos + (src_pos - take_offset) / rate
    elseif timebase == 3 then
      pos = src_pos
    end

    -- Filter: only markers within played portion of item (for item- and project-relative)
    local include = true
    if timebase == 1 then
      include = (pos >= 0 and pos <= item_len)
    elseif timebase == 2 then
      include = (pos >= item_pos and pos <= item_pos + item_len)
    end

    -- --- FIX for source-relative + time selection filtering ---
    if timebase == 3 and time_sel_start and time_sel_end and time_sel_end > time_sel_start then
      local project_time = item_pos + (src_pos - take_offset) / rate
      include = (project_time >= time_sel_start and project_time <= time_sel_end)
    elseif (timebase == 1 or timebase == 2) and time_sel_start and time_sel_end and time_sel_end > time_sel_start then
      include = include and (pos >= time_sel_start and pos <= time_sel_end)
    end

    if include then
      table.insert(ret, {idx=i+1, pos=pos, name=name or ""})
    end
  end
  return ret
end

local function GetItemName(item)
  local take = reaper.GetActiveTake(item)
  if not take then return "No Take" end
  local _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  if name ~= "" then return name end
  local src = reaper.GetMediaItemTake_Source(take)
  local fn = reaper.GetMediaSourceFileName(src, "")
  return fn:match("[^\\/]+$") or "Unnamed"
end

local function GenerateMarkerBlock(markers, fmt, numbering, framerate, time_format_func)
  local lines = {}
  for i, m in ipairs(markers) do
    local idx = numbering and (tostring(i) .. " ") or ""
    local time_str = ""
    if time_format_func then
      time_str = time_format_func(m.pos)
    else
      time_str = format_time(m.pos, fmt, framerate)
    end
    local line = string.format("%s%s %s", idx, time_str, m.name)
    table.insert(lines, line)
  end
  return lines
end

------------------------------------------------------
-- MAIN EXPORT LOGIC
------------------------------------------------------

local function Main_Export()
  local out = {}
  local framerate = get_project_framerate()

  -- Time selection
  local time_sel_start, time_sel_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if time_sel_end <= time_sel_start then
    time_sel_start, time_sel_end = nil, nil
  end

  -- Project Markers
  local proj_markers = GetProjectMarkerSelection(time_sel_start, time_sel_end)
  if #proj_markers > 0 then
    table.insert(out, "Project Markers:")
    local time_func = nil
    if marker_time_format == 9 then
      time_func = format_beats
    elseif marker_time_format == 10 then
      time_func = format_bar_beat
    end
    local proj_lines = GenerateMarkerBlock(proj_markers, marker_time_format, marker_numbering, framerate, time_func)
    for _, line in ipairs(proj_lines) do table.insert(out, line) end
    table.insert(out, "")
  end

  -- Item/Take Markers
  local items = GetSelectedItems()
  if #items > 0 then
    for i, item in ipairs(items) do
      local name = GetItemName(item)
      table.insert(out, "Item: " .. name)
      local markers = GetTakeMarkersFiltered(item, item_marker_timebase, time_sel_start, time_sel_end)
      local time_func = nil
      if marker_time_format == 9 then
        time_func = function(t)
          if item_marker_timebase == 1 then
            local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            return format_beats(item_pos + t)
          elseif item_marker_timebase == 2 then
            return format_beats(t)
          elseif item_marker_timebase == 3 then
            return string.format("%.3f", t)
          end
        end
      elseif marker_time_format == 10 then
        time_func = function(t)
          if item_marker_timebase == 1 then
            local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            return format_bar_beat(item_pos + t)
          elseif item_marker_timebase == 2 then
            return format_bar_beat(t)
          elseif item_marker_timebase == 3 then
            return "0:0"
          end
        end
      end
      local lines = GenerateMarkerBlock(markers, marker_time_format, marker_numbering, framerate, time_func)
      for _, line in ipairs(lines) do table.insert(out, line) end
      table.insert(out, "")
    end
  end

  local result = table.concat(out, "\n")
  if reaper.CF_SetClipboard then
    reaper.CF_SetClipboard(result)
  else
    if reaper.GetOS():find("Win") then
      local tmp = os.tmpname() .. ".txt"
      local f = io.open(tmp, "w")
      if f then f:write(result) f:close() end
      os.execute('type "' .. tmp .. '" | clip')
      os.remove(tmp)
    end
  end
  reaper.ShowConsoleMsg(result .. "\n")
end

------------------------------------------------------
-- GUI LOOP
------------------------------------------------------

local function loop()
  local visible, open = reaper.ImGui_Begin(ctx, SCRIPT_TITLE, true, reaper.ImGui_WindowFlags_AlwaysAutoResize())
  if visible then
    reaper.ImGui_PushFont(ctx, font)
    reaper.ImGui_Text(ctx, "Marker Export Options")
    reaper.ImGui_PopFont(ctx)

    _, marker_time_format = reaper.ImGui_Combo(ctx, "Format", marker_time_format-1, table.concat(format_options, "\0").."\0")
    marker_time_format = marker_time_format + 1

    _, marker_numbering = reaper.ImGui_Checkbox(ctx, "Enable Marker Numbering (1, 2...)", marker_numbering)

    local num_sel = reaper.CountSelectedMediaItems(0)
    if num_sel > 0 then
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Text(ctx, "Item Marker Options")
      _, item_marker_timebase = reaper.ImGui_Combo(ctx, "Item Marker Timebase", item_marker_timebase-1, table.concat(timebase_options, "\0").."\0")
      item_marker_timebase = item_marker_timebase + 1
      reaper.ImGui_Text(ctx, "Selected Items: " .. tostring(num_sel))
    end

    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_Button(ctx, "Export Markers to Clipboard & Console") then
      Main_Export()
      reaper.ImGui_Text(ctx, "Exported!")
    end

    reaper.ImGui_End(ctx)
  end

  if open then
    reaper.defer(loop)
  else
    if ctx and reaper.ImGui_DestroyContext then
      reaper.ImGui_DestroyContext(ctx)
    end
  end
end

reaper.defer(loop)