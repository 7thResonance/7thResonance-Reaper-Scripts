--[[
@description 7R Marker n Region Exporter (Project/Take/Regions)
@author 7thResonance
@version 1.4
@changelog
  - Added Custom export option
  - Added Preset save and load options
  - Fixed some value bugs
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
local SCRIPT_TITLE = "Export Markers/Regions (Custom Formats & Presets)"
local PRESET_FILENAME = "MarkerExportPresets.json"

-- REAIMGUI SETUP
if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("ReaImGui not found! Please install via ReaPack.", "Error", 0)
  return
end

local ctx = reaper.ImGui_CreateContext(SCRIPT_TITLE)
local FONT_SIZE = 16.0
local font = reaper.ImGui_CreateFont('sans-serif', FONT_SIZE)
reaper.ImGui_Attach(ctx, font)

------------------------------------------------------
-- PRESET STORAGE
------------------------------------------------------

-- Get REAPER resource path and preset file path
local function get_preset_file_path()
  local resource_path = reaper.GetResourcePath()
  return resource_path .. "/" .. PRESET_FILENAME
end

local function save_presets(presets)
  local path = get_preset_file_path()
  local f = io.open(path, "w")
  if not f then
    reaper.ShowMessageBox("Could not write preset file:\n" .. path, "Error", 0)
    return false
  end
  f:write(reaper.utils and reaper.utils.TableToJSON and reaper.utils.TableToJSON(presets) or 
          (require("dkjson").encode(presets, { indent = true })))
  f:close()
  return true
end

local function load_presets()
  local path = get_preset_file_path()
  local f = io.open(path, "r")
  if not f then return {} end
  local str = f:read("*a")
  f:close()
  if reaper.utils and reaper.utils.JSONToTable then
    return reaper.utils.JSONToTable(str) or {}
  elseif package.searchpath and package.searchpath("dkjson", package.path) then
    local json = require("dkjson")
    local obj, _, err = json.decode(str)
    return obj or {}
  else
    -- fallback: simple unsafe eval (not secure, but REAPER sandboxed)
    local func = load("return " .. str)
    local ok, val = pcall(func)
    if ok then return val else return {} end
  end
end

------------------------------------------------------
-- CUSTOM FORMAT TOKEN SYSTEM
------------------------------------------------------

local function pad(num, digits)
  return string.format("%0" .. digits .. "d", num)
end

local function parse_custom_format(fmt_str, context)
  -- Replace tokens with values from context table
  local s = fmt_str

  -- Time breakdown
  local total_sec = context.seconds or 0
  local h = math.floor(total_sec / 3600)
  local m = math.floor((total_sec % 3600) / 60)
  local s_int = math.floor(total_sec % 60)
  local ms = math.floor((total_sec % 1) * 1000)

  -- Truncate beat and fullbeats to 2 decimal places without rounding
  local beat_truncated = math.floor((context.beat or 0) * 100) / 100
  local fullbeats_truncated = math.floor((context.fullbeats or 0) * 100) / 100
  local seconds_truncated = math.floor(total_sec * 100) / 100

  local replacements = {
    ["{bar}"]        = context.bar or "",
    ["{beat}"]       = string.format("%.2f", beat_truncated),
    ["{fullbeats}"]  = string.format("%.2f", fullbeats_truncated),
    ["{seconds}"]    = string.format("%.2f", seconds_truncated),
    ["{ms}"]         = tostring(math.floor(total_sec * 1000)),
    ["{frames}"]     = context.frames or "",
    ["{hh}"]         = pad(h, 2),
    ["{mm}"]         = pad(m, 2),
    ["{ss}"]         = pad(s_int, 2),
    ["{sss}"]        = pad(ms, 3),
    ["{markername}"] = context.markername or "",
    ["{itemname}"]   = context.itemname or "",
    ["{regionlen}"]  = context.regionlen or "",
    ["{regionstart}"]= context.regionstart or "",
    ["{regionend}"]  = context.regionend or "",
    ["{tempo}"]      = context.tempo or "",
    ["{tsig_num}"]   = context.tsig_num or "",
    ["{tsig_denom}"] = context.tsig_denom or "",
  }

  for token, val in pairs(replacements) do
    s = s:gsub(token, tostring(val))
  end
  return s
end

local CUSTOM_TOKENS_TOOLTIP = [[
Custom format tokens:
{bar}        - Bar number (1-based)
{beat}       - Beat in bar (1-based, float)
{fullbeats}  - Total full beats from project start
{seconds}    - Time in seconds
{ms}         - Time in milliseconds
{frames}     - Time in frames
{hh}         - Hours (zero-padded)
{mm}         - Minutes (zero-padded)
{ss}         - Seconds (zero-padded)
{sss}        - Milliseconds (zero-padded)
{markername} - Marker/region name
{itemname}   - Item/take name
{regionlen}  - Region length (format depends, see below)
{regionstart} - Region start (format depends, see below)
{regionend}  - Region end (format depends, see below)
{tempo}      - Tempo (BPM)
{tsig_num}   - Time signature numerator
{tsig_denom} - Time signature denominator
]]

------------------------------------------------------
-- FORMAT SYSTEM
------------------------------------------------------

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
  "Beat",
  "Custom..."
}
local NUM_FORMATS = #format_options

local timebase_options = {
  "Item-Relative",
  "Project-Relative"
}

------------------------------------------------------
-- STATE
------------------------------------------------------

local marker_time_format = 1
local marker_custom_format = ""
local marker_numbering = true
local item_marker_timebase = 1 -- 1:Item-Relative, 2:Project-Relative

local region_len_fmt = 1
local region_start_fmt = 1
local region_end_fmt = 1
local region_custom_len_format = ""
local region_custom_start_format = ""
local region_custom_end_format = ""
local region_numbering = true

-- Preset system
local presets = load_presets()
local preset_names = {}
for k in pairs(presets) do table.insert(preset_names, k) end
table.sort(preset_names)
local current_preset = ""
local new_preset_name = ""
local preset_to_delete = ""
local show_save_preset = false
local show_delete_preset = false

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
local function get_bar_beat_fullbeats(time)
  local proj = 0
  local beat_in_bar, bar_idx, _, total_full_beats = reaper.TimeMap2_timeToBeats(proj, time)
  return (bar_idx or 0) + 1, (beat_in_bar or 0) + 1, total_full_beats or 0
end

local function get_time_sig_and_tempo(time)
  local proj = 0
  local _, tsig_denom, tempo = reaper.TimeMap_GetTimeSigAtTime(proj, time)
  local _, tsig_num = reaper.TimeMap_GetTimeSigAtTime(proj, time)
  return tsig_num or "", tsig_denom or "", tempo or ""
end

local function format_bar_beat(seconds)
  local bar, beat = get_bar_beat_fullbeats(seconds)
  local beat_truncated = math.floor(beat * 100) / 100
  return string.format("%d:%.2f", bar, beat_truncated)
end

local function format_beat(seconds)
  local _, _, fullbeats = get_bar_beat_fullbeats(seconds)
  local fullbeats_truncated = math.floor(fullbeats * 100) / 100
  return string.format("%.2f", fullbeats_truncated)
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
  end
  return tostring(seconds)
end

local function region_length_bar_beat(start_sec, end_sec)
  -- Calculate the duration in seconds
  local duration_sec = end_sec - start_sec
  
  -- Get bar:beat for duration, but subtract 1 from both bar and beat since duration should be 0-based
  local bar, beat = get_bar_beat_fullbeats(duration_sec)
  return string.format("%d:%.2f", bar - 1, beat - 1)
end

local function region_length_beats(start_sec, end_sec)
  local _, _, fullbeats1 = get_bar_beat_fullbeats(start_sec)
  local _, _, fullbeats2 = get_bar_beat_fullbeats(end_sec)
  local beats_diff = (fullbeats2 or 0) - (fullbeats1 or 0)
  local beats_truncated = math.floor(beats_diff * 100) / 100
  return string.format("%.2f", beats_truncated)
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
    local src_pos, name = reaper.GetTakeMarker(take, i)
    local pos
    if timebase == 1 then
      pos = (src_pos - take_offset) / rate
    elseif timebase == 2 then
      pos = item_pos + (src_pos - take_offset) / rate
    end

    local include = true
    if timebase == 1 then
      include = (pos >= 0 and pos <= item_len)
    elseif timebase == 2 then
      include = (pos >= item_pos and pos <= item_pos + item_len)
    end

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

local function GenerateMarkerBlock(markers, fmt, custom_fmt, numbering, framerate, timebase)
  local lines = {}
  for i, m in ipairs(markers) do
    local idx = numbering and (tostring(i) .. " ") or ""
    local pos = m.pos
    local bar, beat, fullbeats = get_bar_beat_fullbeats(pos)
    local frames = math.floor((pos or 0) * (framerate or get_project_framerate()) + 0.5)
    local tsig_num, tsig_denom, tempo = get_time_sig_and_tempo(pos)
    local context = {
      bar = bar, beat = beat, fullbeats = fullbeats,
      seconds = pos,
      frames = frames,
      markername = m.name or "",
      itemname = m.itemname or "",
      tempo = tempo, tsig_num = tsig_num, tsig_denom = tsig_denom,
    }
    local time_str
    if fmt == 11 then -- Custom
      time_str = parse_custom_format(custom_fmt, context)
    else
      time_str = format_time(pos, fmt, framerate)
    end
    local line = string.format("%s%s %s", idx, time_str, m.name)
    table.insert(lines, line)
  end
  return lines
end

local function GenerateRegionBlock(regions, fmt_len, fmt_start, fmt_end,
                                  custom_len_fmt, custom_start_fmt, custom_end_fmt,
                                  framerate, numbering)
  local lines = {}
  for i, r in ipairs(regions) do
    local N = numbering and (tostring(i) .. ". ") or ""
    local name = r.name or ""
    local length, start, end_ = r.length, r.start, r["end"]

    local bar_len, beat_len, fullbeats_len = get_bar_beat_fullbeats(end_ - start)
    local bar_start, beat_start, fullbeats_start = get_bar_beat_fullbeats(start)
    local bar_end, beat_end, fullbeats_end = get_bar_beat_fullbeats(end_)
    local tsig_num, tsig_denom, tempo = get_time_sig_and_tempo(start)

    -- Calculate frames for each position
    local frames_len = math.floor(length * (framerate or get_project_framerate()) + 0.5)
    local frames_start = math.floor(start * (framerate or get_project_framerate()) + 0.5)
    local frames_end = math.floor(end_ * (framerate or get_project_framerate()) + 0.5)

    -- Precompute context for each field
    local context_len = {
      regionlen = length,
      seconds = length,
      bar = bar_len - 1,  -- Make 0-based for duration
      beat = beat_len - 1,  -- Make 0-based for duration
      fullbeats = fullbeats_len,
      frames = frames_len,
      tempo = tempo,
      tsig_num = tsig_num,
      tsig_denom = tsig_denom,
    }
    local context_start = {
      regionstart = start,
      seconds = start,
      bar = bar_start,
      beat = beat_start,
      fullbeats = fullbeats_start,
      frames = frames_start,
      tempo = tempo,
      tsig_num = tsig_num,
      tsig_denom = tsig_denom,
    }
    local context_end = {
      regionend = end_,
      seconds = end_,
      bar = bar_end,
      beat = beat_end,
      fullbeats = fullbeats_end,
      frames = frames_end,
      tempo = tempo,
      tsig_num = tsig_num,
      tsig_denom = tsig_denom,
    }

    local len_str, start_str, end_str

    -- Length
    if fmt_len == 11 then
      context_len.regionlen = length
      len_str = parse_custom_format(custom_len_fmt, context_len)
    elseif fmt_len == 9 then -- Bar:Beat
      len_str = region_length_bar_beat(start, end_)
    elseif fmt_len == 10 then
      len_str = region_length_beats(start, end_)
    else
      len_str = format_time(length, fmt_len, framerate)
    end

    -- Start
    if fmt_start == 11 then
      context_start.regionstart = start
      start_str = parse_custom_format(custom_start_fmt, context_start)
    elseif fmt_start == 9 then
      start_str = format_bar_beat(start)
    elseif fmt_start == 10 then
      start_str = format_beat(start)
    else
      start_str = format_time(start, fmt_start, framerate)
    end

    -- End
    if fmt_end == 11 then
      context_end.regionend = end_
      end_str = parse_custom_format(custom_end_fmt, context_end)
    elseif fmt_end == 9 then
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
    local proj_lines = GenerateMarkerBlock(proj_markers, marker_time_format, marker_custom_format, marker_numbering, framerate, 2)
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
      -- add itemname to context
      for _, m in ipairs(markers) do m.itemname = name end
      local lines = GenerateMarkerBlock(markers, marker_time_format, marker_custom_format, marker_numbering, framerate, timebase)
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
      region_custom_len_format, region_custom_start_format, region_custom_end_format,
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

local function PresetGUI()
  -- Preset selection
  reaper.ImGui_Text(ctx, "Preset System")
  if #preset_names > 0 then
    local curr_idx = 0
    for i, n in ipairs(preset_names) do if n == current_preset then curr_idx = i - 1 end end
    local changed, new_idx = reaper.ImGui_Combo(ctx, "Choose Preset", curr_idx, table.concat(preset_names, "\0") .. "\0")
    if changed then
      local name = preset_names[new_idx + 1]
      current_preset = name
      -- Apply preset to state
      local p = presets[name]
      if p then
        marker_time_format = p.marker_time_format or 1
        marker_custom_format = p.marker_custom_format or ""
        marker_numbering = p.marker_numbering or true
        item_marker_timebase = p.item_marker_timebase or 1
        region_len_fmt = p.region_len_fmt or 1
        region_start_fmt = p.region_start_fmt or 1
        region_end_fmt = p.region_end_fmt or 1
        region_custom_len_format = p.region_custom_len_format or ""
        region_custom_start_format = p.region_custom_start_fmt or ""
        region_custom_end_format = p.region_custom_end_fmt or ""
        region_numbering = p.region_numbering or true
      end
    end
    reaper.ImGui_SameLine(ctx)
  end
  if reaper.ImGui_Button(ctx, "Save New Preset") then show_save_preset = true end
  reaper.ImGui_SameLine(ctx)
  if reaper.ImGui_Button(ctx, "Delete Preset") then show_delete_preset = true end

  if show_save_preset then
    reaper.ImGui_OpenPopup(ctx, "SavePresetPopup")
  end
  if show_delete_preset then
    reaper.ImGui_OpenPopup(ctx, "DeletePresetPopup")
  end

  if reaper.ImGui_BeginPopup(ctx, "SavePresetPopup") then
    local _, name = reaper.ImGui_InputText(ctx, "Preset Name", new_preset_name or "", 256)
    new_preset_name = name
    if reaper.ImGui_Button(ctx, "Save") and name and #name > 0 then
      -- Save state to preset
      presets[name] = {
        marker_time_format = marker_time_format,
        marker_custom_format = marker_custom_format,
        marker_numbering = marker_numbering,
        item_marker_timebase = item_marker_timebase,
        region_len_fmt = region_len_fmt,
        region_start_fmt = region_start_fmt,
        region_end_fmt = region_end_fmt,
        region_custom_len_format = region_custom_len_format,
        region_custom_start_fmt = region_custom_start_fmt,
        region_custom_end_format = region_custom_end_fmt,
        region_numbering = region_numbering
      }
      save_presets(presets)
      current_preset = name
      preset_names = {}
      for k in pairs(presets) do table.insert(preset_names, k) end
      table.sort(preset_names)
      show_save_preset = false
      new_preset_name = ""
      reaper.ImGui_CloseCurrentPopup(ctx)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Cancel") then show_save_preset = false; reaper.ImGui_CloseCurrentPopup(ctx) end
    reaper.ImGui_EndPopup(ctx)
  end

  if reaper.ImGui_BeginPopup(ctx, "DeletePresetPopup") then
    if current_preset and #current_preset > 0 and presets[current_preset] then
      reaper.ImGui_Text(ctx, "Delete preset '"..current_preset.."'?")
      if reaper.ImGui_Button(ctx, "Delete") then
        presets[current_preset] = nil
        save_presets(presets)
        preset_names = {}
        for k in pairs(presets) do table.insert(preset_names, k) end
        table.sort(preset_names)
        current_preset = ""
        show_delete_preset = false
        reaper.ImGui_CloseCurrentPopup(ctx)
      end
      reaper.ImGui_SameLine(ctx)
      if reaper.ImGui_Button(ctx, "Cancel") then show_delete_preset = false; reaper.ImGui_CloseCurrentPopup(ctx) end
    else
      reaper.ImGui_Text(ctx, "No preset selected.")
      if reaper.ImGui_Button(ctx, "Close") then show_delete_preset = false; reaper.ImGui_CloseCurrentPopup(ctx) end
    end
    reaper.ImGui_EndPopup(ctx)
  end
end

local function loop()
  local visible, open = reaper.ImGui_Begin(ctx, SCRIPT_TITLE, true, reaper.ImGui_WindowFlags_AlwaysAutoResize())
  if visible then
    reaper.ImGui_PushFont(ctx, font)
    reaper.ImGui_Text(ctx, "Marker & Region Export Options")
    reaper.ImGui_PopFont(ctx)

    PresetGUI()

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Project/Take Marker Format")
    _, marker_time_format = reaper.ImGui_Combo(ctx, "Marker/Take Marker Format", marker_time_format-1, table.concat(format_options, "\0").."\0")
    marker_time_format = marker_time_format + 1
    if marker_time_format == 11 then
      _, marker_custom_format = reaper.ImGui_InputText(ctx, "Custom Marker Format", marker_custom_format or "", 256)
      if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, CUSTOM_TOKENS_TOOLTIP) end
    end
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
    reaper.ImGui_Text(ctx, "Region Export Options")
    _, region_numbering = reaper.ImGui_Checkbox(ctx, "Enable Region Numbering (1. 2. ...)", region_numbering)
    _, region_len_fmt = reaper.ImGui_Combo(ctx, "Region Length Format", region_len_fmt-1, table.concat(format_options, "\0").."\0")
    region_len_fmt = region_len_fmt + 1
    if region_len_fmt == 11 then
      _, region_custom_len_format = reaper.ImGui_InputText(ctx, "Custom Region Length Format", region_custom_len_format or "", 256)
      if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, CUSTOM_TOKENS_TOOLTIP) end
    end
    _, region_start_fmt = reaper.ImGui_Combo(ctx, "Region Start Format", region_start_fmt-1, table.concat(format_options, "\0").."\0")
    region_start_fmt = region_start_fmt + 1
    if region_start_fmt == 11 then
      _, region_custom_start_format = reaper.ImGui_InputText(ctx, "Custom Region Start Format", region_custom_start_format or "", 256)
      if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, CUSTOM_TOKENS_TOOLTIP) end
    end
    _, region_end_fmt = reaper.ImGui_Combo(ctx, "Region End Format", region_end_fmt-1, table.concat(format_options, "\0").."\0")
    region_end_fmt = region_end_fmt + 1
    if region_end_fmt == 11 then
      _, region_custom_end_format = reaper.ImGui_InputText(ctx, "Custom Region End Format", region_custom_end_format or "", 256)
      if reaper.ImGui_IsItemHovered(ctx) then reaper.ImGui_SetTooltip(ctx, CUSTOM_TOKENS_TOOLTIP) end
    end

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
