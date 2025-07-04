--[[
@description 7R Marker n Region Exporter (Project/Take/Regions)
@author 7thResonance
@version 1.3
@changelog
  - Added back Bar and Beat support
  - Fixed item-relative marker filtering when time selection is active and item is not at project start.
@about GUI for exporting project and take markers and Regions in various formats.
- HH:MM:SS
- HH:MM:SS:MS
- MM:SS Youtube timestamp style
- MM:SS:MS
- SS
- SS:MS
- MS only
- Frames
- Bar:beat
- Beats

-Optional Numbering

--]]
local reaper = reaper

-- SETTINGS
local SCRIPT_TITLE = "Export Markers/Regions (Bar:Beat/Beat/Time)"

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
local format_options = {
  "HH:MM:SS",
  "HH:MM:SS:MS",
  "MM:SS",
  "MM:SS:MS",
  "SS",
  "SS:MS",
  "MS Only",
  "Frames",
  "Bar:Beat",
  "Beat"
}
local marker_time_format = 1
local marker_numbering = true
local item_marker_timebase = 1 -- 1:Item-Relative, 2:Project-Relative
local region_len_fmt = 1
local region_start_fmt = 1
local region_end_fmt = 1
local region_numbering = true

local timebase_options = {
  "Item-Relative",
  "Project-Relative"
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

-- Bar:Beat and Beat formatting using accurate logic
local function format_bar_beat(seconds)
  local proj = 0
  local beat_in_bar, bar_idx = reaper.TimeMap2_timeToBeats(proj, seconds)
  return string.format("%d:%02.3f", (bar_idx or 0) + 1, (beat_in_bar or 0) + 1)
end

local function format_beat(seconds)
  local proj = 0
  local _, _, _, total_full_beats = reaper.TimeMap2_timeToBeats(proj, seconds)
  return string.format("%.4f", total_full_beats or 0)
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
  elseif fmt == 9 then
    -- Bar:Beat
    return format_bar_beat(seconds)
  elseif fmt == 10 then
    -- Beat
    return format_beat(seconds)
  else
    return tostring(seconds)
  end
end

local function region_length_bar_beat(start_sec, end_sec)
  -- Uses bar_idx and beat_in_bar for both ends, calculates difference
  local proj = 0
  local beat_in_bar1, bar_idx1 = reaper.TimeMap2_timeToBeats(proj, start_sec)
  local beat_in_bar2, bar_idx2 = reaper.TimeMap2_timeToBeats(proj, end_sec)
  local bar_diff = (bar_idx2 or 0) - (bar_idx1 or 0)
  local beat_diff = (beat_in_bar2 or 0) - (beat_in_bar1 or 0)
  if beat_diff < 0 then
    bar_diff = bar_diff - 1
    -- get beats per bar at start_sec
    local _, beats_per_bar = reaper.TimeMap_GetTimeSigAtTime(proj, start_sec)
    beat_diff = beat_diff + (beats_per_bar or 0)
  end
  return string.format("%d bars + %.3f beats", bar_diff, beat_diff)
end

local function region_length_beats(start_sec, end_sec)
  local proj = 0
  local _, _, _, fullbeats1 = reaper.TimeMap2_timeToBeats(proj, start_sec)
  local _, _, _, fullbeats2 = reaper.TimeMap2_timeToBeats(proj, end_sec)
  return string.format("%.4f", (fullbeats2 or 0) - (fullbeats1 or 0))
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

local function GetProjectRegionsFiltered(time_sel_start, time_sel_end)
  local regions = {}
  local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
  local total = num_markers + num_regions
  for i = 0, total-1 do
    local retval, isrgn, pos, rgnend, name, idx = reaper.EnumProjectMarkers(i)
    if isrgn then
      local include = true
      if time_sel_start and time_sel_end and time_sel_end > time_sel_start then
        -- region overlaps time selection?
        include = (rgnend > time_sel_start) and (pos < time_sel_end)
      end
      if include then
        table.insert(regions, {
          idx = idx,
          name = name or "",
          start = pos,
          ["end"] = rgnend,
          length = rgnend - pos
        })
      end
    end
  end
  return regions
end

local function GetSelectedItems()
  local t = {}
  for i = 0, reaper.CountSelectedMediaItems(0)-1 do
    t[#t+1] = reaper.GetSelectedMediaItem(0, i)
  end
  return t
end

-- timebase: 1 = item-relative, 2 = project-relative
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
    end

    -- Only include markers within played portion of item (for item- and project-relative)
    local include = true
    if timebase == 1 then
      include = (pos >= 0 and pos <= item_len)
    elseif timebase == 2 then
      include = (pos >= item_pos and pos <= item_pos + item_len)
    end

    -- Robust time selection filtering (always check marker's project position)
    local marker_project_pos = item_pos + (src_pos - take_offset) / rate
    if time_sel_start and time_sel_end and time_sel_end > time_sel_start then
      include = include and (marker_project_pos >= time_sel_start and marker_project_pos <= time_sel_end)
    end

    if include then
      table.insert(ret, {idx=i+1, pos=pos, name=name or "", item_pos=item_pos})
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

local function GenerateMarkerBlock(markers, fmt, numbering, framerate, timebase)
  local lines = {}
  for i, m in ipairs(markers) do
    local idx = numbering and (tostring(i) .. " ") or ""
    local pos = m.pos
    local time_str
    if fmt == 9 then -- Bar:Beat
      time_str = format_bar_beat(pos)
    elseif fmt == 10 then
      time_str = format_beat(pos)
    else
      time_str = format_time(pos, fmt, framerate)
    end
    local line = string.format("%s%s %s", idx, time_str, m.name)
    table.insert(lines, line)
  end
  return lines
end

local function GenerateRegionBlock(regions, fmt_len, fmt_start, fmt_end, framerate, numbering)
  local lines = {}
  for i, r in ipairs(regions) do
    local N = numbering and (tostring(i) .. ". ") or ""
    local name = r.name or ""
    local length, start, end_ = r.length, r.start, r["end"]
    local len_str, start_str, end_str

    -- Length
    if fmt_len == 9 then -- Bar:Beat
      len_str = region_length_bar_beat(start, end_)
    elseif fmt_len == 10 then -- Beat
      len_str = region_length_beats(start, end_)
    else
      len_str = format_time(length, fmt_len, framerate)
    end

    -- Start
    if fmt_start == 9 then
      start_str = format_bar_beat(start)
    elseif fmt_start == 10 then
      start_str = format_beat(start)
    else
      start_str = format_time(start, fmt_start, framerate)
    end

    -- End
    if fmt_end == 9 then
      end_str = format_bar_beat(end_)
    elseif fmt_end == 10 then
      end_str = format_beat(end_)
    else
      end_str = format_time(end_, fmt_end, framerate)
    end

    local line = string.format("%s%s - %s - %s to %s", N, name, len_str, start_str, end_str)
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
    local proj_lines = GenerateMarkerBlock(proj_markers, marker_time_format, marker_numbering, framerate, 2)
    for _, line in ipairs(proj_lines) do table.insert(out, line) end
    table.insert(out, "")
  end

  -- Item/Take Markers
  local items = GetSelectedItems()
  if #items > 0 then
    for i, item in ipairs(items) do
      local name = GetItemName(item)
      table.insert(out, "Item: " .. name)
      local timebase = item_marker_timebase
      local markers = GetTakeMarkersFiltered(item, timebase, time_sel_start, time_sel_end)
      local lines = GenerateMarkerBlock(markers, marker_time_format, marker_numbering, framerate, timebase)
      for _, line in ipairs(lines) do table.insert(out, line) end
      table.insert(out, "")
    end
  end

  -- Regions
  local regions = GetProjectRegionsFiltered(time_sel_start, time_sel_end)
  if #regions > 0 then
    table.insert(out, "Regions:")
    local region_lines = GenerateRegionBlock(
      regions,
      region_len_fmt, region_start_fmt, region_end_fmt,
      framerate, region_numbering
    )
    for _, line in ipairs(region_lines) do table.insert(out, line) end
    table.insert(out, "")
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
    reaper.ImGui_Text(ctx, "Marker & Region Export Options")
    reaper.ImGui_PopFont(ctx)

    -- Project markers
    _, marker_time_format = reaper.ImGui_Combo(ctx, "Marker/Take Marker Format", marker_time_format-1, table.concat(format_options, "\0").."\0")
    marker_time_format = marker_time_format + 1

    _, marker_numbering = reaper.ImGui_Checkbox(ctx, "Enable Marker Numbering (1, 2...)", marker_numbering)

    local num_sel = reaper.CountSelectedMediaItems(0)
    if num_sel > 0 then
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Text(ctx, "Item Marker Options")

      local tb_opts = timebase_options
      local tb_count = #timebase_options
      local tb_opts_str = table.concat(tb_opts, "\0") .. "\0"
      local curr_tb_idx = item_marker_timebase - 1
      if curr_tb_idx < 0 then curr_tb_idx = 0 end
      if curr_tb_idx >= tb_count then curr_tb_idx = tb_count - 1 end

      local changed, new_tb_idx = reaper.ImGui_Combo(ctx, "Item Marker Timebase", curr_tb_idx, tb_opts_str)
      if changed then
        item_marker_timebase = new_tb_idx + 1
      end
      reaper.ImGui_Text(ctx, "Selected Items: " .. tostring(num_sel))
    end

    reaper.ImGui_Separator(ctx)

    -- Regions
    reaper.ImGui_Text(ctx, "Region Export Options")
    _, region_numbering = reaper.ImGui_Checkbox(ctx, "Enable Region Numbering (1. 2. ...)", region_numbering)

    _, region_len_fmt = reaper.ImGui_Combo(ctx, "Region Length Format", region_len_fmt-1, table.concat(format_options, "\0").."\0")
    region_len_fmt = region_len_fmt + 1
    _, region_start_fmt = reaper.ImGui_Combo(ctx, "Region Start Format", region_start_fmt-1, table.concat(format_options, "\0").."\0")
    region_start_fmt = region_start_fmt + 1
    _, region_end_fmt = reaper.ImGui_Combo(ctx, "Region End Format", region_end_fmt-1, table.concat(format_options, "\0").."\0")
    region_end_fmt = region_end_fmt + 1

    reaper.ImGui_Separator(ctx)

    if reaper.ImGui_Button(ctx, "Export Markers & Regions to Clipboard & Console") then
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