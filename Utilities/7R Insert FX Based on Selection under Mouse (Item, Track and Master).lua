--[[
@description 7R Insert FX Based on Selection under Mouse cursor (Track or Item, Master)
@author 7thResonance
@version 2.1
@changelog - Shift modifier to add to input FX`
     - hovering on FX chain window adds to track (use global shortcut for non focused hover)
@donation https://paypal.me/7thresonance
@about Opens GUI for track, item or master under cursor with GUI to select FX
    - Only supports VST2, VST3 and CLAP. (no AU, LV2 or JS) (I dont have mac or any LV2 plugins)
    - Saves position and size of GUI
    - Cache for quick search. Updates when new plugins are installed
    - Settings for basic options

--]]

-- REAIMGUI SETUP
if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("ReaImGui not found! Please install via ReaPack.", "Error", 0)
  return
end

local ctx = reaper.ImGui_CreateContext("FX Inserter")
local font = reaper.ImGui_CreateFont('sans-serif', 14)
reaper.ImGui_Attach(ctx, font)

-- GLOBAL VARIABLES
local window_open = true
local search_text = ""
local selected_folder = "" -- Start with no folder selected
local fx_data = {}
local folder_list = {}
local filtered_fx = {}
local target_track = nil
local target_item = nil
local insert_mode = "track" -- "track", "item", or "master"
local target_info = ""
local fx_tags = {} -- Store FX developer tags

-- SETTINGS VARIABLES
local settings_window_open = false
local settings = {
  hide_vst2_duplicates = true,  -- Hide VST2 if VST3 version exists
  auto_close_on_insert = true,   -- Auto close window after FX insertion
  search_all_folders = true,    -- Search across all folders instead of just selected folder
  fx_window_mode = 0,           -- 0 = No window, 1 = Auto float, 2 = Chain window
  window_x = -1,                -- Window X position (-1 = use default)
  window_y = -1,                -- Window Y position (-1 = use default)
  window_width = 700,           -- Window width
  window_height = 500,          -- Window height
  last_selected_folder = ""     -- Remember last selected folder
}

-- CACHING AND BACKGROUND SCANNING VARIABLES
local background_scan_running = false
local cache_file_path = ""
local last_update_check = 0
local update_check_interval = 1000 -- Check every 1000ms (1 second)

------------------------------------------------------
-- CACHING FUNCTIONS
------------------------------------------------------

local function get_cache_file_path()
  local resource_path = reaper.GetResourcePath()
  return resource_path .. "/FX_Inserter_cache.json"
end

local function get_file_modification_time(file_path)
  local file = io.open(file_path, "r")
  if not file then return 0 end
  file:close()
  
  -- Simple fallback: use file size as a basic change indicator
  -- This isn't perfect but works for detecting when files change
  local file_size = 0
  local f = io.open(file_path, "r")
  if f then
    f:seek("end")
    file_size = f:seek()
    f:close()
  end
  
  -- Combine with current time as a basic timestamp
  return file_size + (os.time() % 10000) -- Use file size + recent time as indicator
end

local function save_fx_cache(fx_list)
  local cache_data = {
    timestamp = os.time(),
    vst64_time = 0,
    vst32_time = 0,
    clap_time = 0,
    fx_list = fx_list
  }
  
  -- Get VST and CLAP file modification times
  local resource_path = reaper.GetResourcePath()
  cache_data.vst64_time = get_file_modification_time(resource_path .. "/reaper-vstplugins64.ini")
  cache_data.vst32_time = get_file_modification_time(resource_path .. "/reaper-vstplugins.ini")
  cache_data.clap_time = get_file_modification_time(resource_path .. "/reaper-clap-win64.ini")
  
  -- Simple JSON-like serialization (basic approach)
  local file = io.open(cache_file_path, "w")
  if file then
    file:write("-- FX Inserter Cache File\n")
    file:write("return {\n")
    file:write("  timestamp = " .. cache_data.timestamp .. ",\n")
    file:write("  vst64_time = " .. cache_data.vst64_time .. ",\n")
    file:write("  vst32_time = " .. cache_data.vst32_time .. ",\n")
    file:write("  clap_time = " .. cache_data.clap_time .. ",\n")
    file:write("  fx_list = {\n")
    
    for _, fx in ipairs(fx_list) do
      file:write("    {\n")
      file:write("      filename = " .. string.format("%q", fx.filename or "") .. ",\n")
      file:write("      name = " .. string.format("%q", fx.name or "") .. ",\n")
      file:write("      full_name = " .. string.format("%q", fx.full_name or "") .. ",\n")
      file:write("      folder = " .. string.format("%q", fx.folder or "") .. ",\n")
      file:write("      path = " .. string.format("%q", fx.path or "") .. ",\n")
      file:write("      is_vst_cache = " .. tostring(fx.is_vst_cache) .. "\n")
      file:write("    },\n")
    end
    
    file:write("  }\n")
    file:write("}\n")
    file:close()
  end
end

local function load_fx_cache()
  local file = io.open(cache_file_path, "r")
  if not file then 
    return nil 
  end
  
  local content = file:read("*all")
  file:close()
  
  local load_func = load or loadstring -- Fallback for older Lua versions
  local success, cache_data = pcall(load_func(content))
  if success and cache_data and cache_data.fx_list then
    return cache_data
  else
    return nil
  end
end

local function is_cache_outdated()
  local cache_data = load_fx_cache()
  if not cache_data then return true end
  
  local resource_path = reaper.GetResourcePath()
  local current_vst64_time = get_file_modification_time(resource_path .. "/reaper-vstplugins64.ini")
  local current_vst32_time = get_file_modification_time(resource_path .. "/reaper-vstplugins.ini")
  local current_clap_time = get_file_modification_time(resource_path .. "/reaper-clap-win64.ini")
  
  -- Check if any plugin files are newer than cache
  if current_vst64_time > (cache_data.vst64_time or 0) or 
     current_vst32_time > (cache_data.vst32_time or 0) or
     current_clap_time > (cache_data.clap_time or 0) then
    return true
  end
  
  return false
end

------------------------------------------------------
-- FX BROWSER FOLDER READING
------------------------------------------------------

local function read_fx_tags()
  local resource_path = reaper.GetResourcePath()
  local fx_tags_path = resource_path .. "/reaper-fxtags.ini"
  
  local file = io.open(fx_tags_path, "r")
  if not file then 
    return {} -- No tags file
  end
  
  local content = file:read("*all")
  file:close()
  
  local fx_tags = {}
  local count = 0
  local in_developer_section = false
  
  for line in content:gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
    
    -- Check for section headers
    if line:match("^%[developer%]") then
      in_developer_section = true
    elseif line:match("^%[category%]") then
      in_developer_section = false
    elseif line:match("^%[.+%]") then
      -- Any other section header stops developer parsing
      if in_developer_section then
        in_developer_section = false
      end
    
    -- Parse lines when we're in the developer section
    elseif in_developer_section and line ~= "" and not line:match("^;") then
      -- Parse format: filename.dll=Developer name (like reacast.dll=Cockos)
      local fx_filename, developer = line:match("^([^=]+)=(.+)")
      if fx_filename and developer then
        -- Clean up the filename and developer
        fx_filename = fx_filename:gsub("^%s+", ""):gsub("%s+$", "")
        developer = developer:gsub("^%s+", ""):gsub("%s+$", "")
        
        if fx_filename ~= "" and developer ~= "" then
          -- Store both the filename and the extracted plugin name
          fx_tags[fx_filename] = developer
          
          -- Also try to extract plugin name from filename for better matching
          local plugin_name = fx_filename:gsub("%.dll$", ""):gsub("%.vst$", ""):gsub("%.vst3$", "")
          if plugin_name ~= fx_filename then
            fx_tags[plugin_name] = developer
          end
          
          count = count + 1
        end
      end
    end
  end
  
  return fx_tags
end

local function read_fx_folders()
  local resource_path = reaper.GetResourcePath()
  local fx_folders_path = resource_path .. "/reaper-fxfolders.ini"
  
  local file = io.open(fx_folders_path, "r")
  if not file then 
    return {}, {} -- No custom folders file
  end
  
  local content = file:read("*all")
  file:close()
  
  local custom_folders = {}
  local folder_names = {}
  local current_folder = nil
  
  for line in content:gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
    
    -- Parse folder sections [Folder0], [Folder1], etc.
    if line:match("^%[Folder%d+%]") then
      current_folder = line:match("^%[(.+)%]")
      custom_folders[current_folder] = {}
    -- Parse the [Folders] section with folder names  
    elseif line:match("^%[Folders%]") then
      current_folder = "FolderNames"
      custom_folders[current_folder] = {}
    -- Parse FX entries and folder names
    elseif current_folder and line:match("^(.+)=(.+)") then
      local key, value = line:match("^(.+)=(.+)")
      if current_folder == "FolderNames" then
        -- Extract folder number and name from Name0=Mix n Master format
        local folder_num = key:match("Name(%d+)")
        if folder_num then
          folder_names[folder_num] = value
        end
      else
        -- Only store Item entries, ignore Type and Nb entries
        if key:match("^Item%d+$") then
          custom_folders[current_folder][key] = value
        end
      end
    end
  end
  
  return custom_folders, folder_names
end

local function read_vst_cache()
  local resource_path = reaper.GetResourcePath()
  local vst64_path = resource_path .. "/reaper-vstplugins64.ini"
  local vst32_path = resource_path .. "/reaper-vstplugins.ini"
  
  local all_vst_fx = {}
  
  -- Read 64-bit VST cache
  local file = io.open(vst64_path, "r")
  if file then
    local content = file:read("*all")
    file:close()
    
    for line in content:gmatch("[^\r\n]+") do
      -- Skip section headers and empty lines
      if line:match("=") and not line:match("^%[") and line:trim() ~= "" then
        local filename, data = line:match("^([^=]+)=(.+)")
        if filename and data then
          -- Parse format: {String1},{String2},{Plugin Name},{Developer Name}
          local parts = {}
          for part in data:gmatch("[^,]+") do
            table.insert(parts, part)
          end
          
          -- We need at least 3 parts to get the plugin name (3rd part)
          if #parts >= 3 then
            local plugin_name = parts[3]
            -- Clean up the plugin name
            plugin_name = plugin_name:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
            
            -- Skip empty plugin names
            if plugin_name ~= "" then
              local fx_entry = {
                filename = filename,
                name = plugin_name,
                full_name = plugin_name,
                folder = "All FX",
                path = filename,
                is_vst_cache = true
              }
              
              table.insert(all_vst_fx, fx_entry)
            end
          end
        end
      end
    end
  end
  
  -- Read 32-bit VST cache
  file = io.open(vst32_path, "r")
  if file then
    local content = file:read("*all")
    file:close()
    
    for line in content:gmatch("[^\r\n]+") do
      -- Skip section headers and empty lines
      if line:match("=") and not line:match("^%[") and line:trim() ~= "" then
        local filename, data = line:match("^([^=]+)=(.+)")
        if filename and data then
          -- Parse format: {String1},{String2},{Plugin Name},{Developer Name}
          local parts = {}
          for part in data:gmatch("[^,]+") do
            table.insert(parts, part)
          end
          
          -- We need at least 3 parts to get the plugin name (3rd part)
          if #parts >= 3 then
            local plugin_name = parts[3]
            -- Clean up the plugin name
            plugin_name = plugin_name:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
            
            -- Check if this plugin is already in the list (avoid 32/64 duplicates)
            local already_exists = false
            for _, existing_fx in ipairs(all_vst_fx) do
              if existing_fx.name == plugin_name then
                already_exists = true
                break
              end
            end
            
            -- Skip empty plugin names and duplicates
            if plugin_name ~= "" and not already_exists then
              table.insert(all_vst_fx, {
                filename = filename,
                name = plugin_name,
                full_name = plugin_name,
                folder = "All FX",
                path = filename,
                is_vst_cache = true
              })
            end
          end
        end
      end
    end
  end
  
  return all_vst_fx
end

local function read_clap_cache()
  local resource_path = reaper.GetResourcePath()
  local clap_path = resource_path .. "/reaper-clap-win64.ini"
  
  local all_clap_fx = {}
  
  local file = io.open(clap_path, "r")
  if file then
    local content = file:read("*all")
    file:close()
    
    local current_plugin_file = nil
    
    for line in content:gmatch("[^\r\n]+") do
      line = line:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
      
      -- Parse section headers like [plugin-filename.clap]
      if line:match("^%[.+%.clap%]") then
        current_plugin_file = line:match("^%[(.+)%]")
        
      -- Parse plugin entries (skip metadata lines starting with _=)
      elseif current_plugin_file and line:match("=") and not line:match("^_=") then
        local clap_id, data = line:match("^([^=]+)=(.+)")
        if clap_id and data then
          -- Parse format: index|Display Name (Developer)
          local index, name_and_dev = data:match("^(%d+)|(.+)")
          if index and name_and_dev then
            -- Extract plugin name and developer
            local plugin_name, developer = name_and_dev:match("^(.+)%s%((.+)%)$")
            if plugin_name and developer then
              -- Clean up names
              plugin_name = plugin_name:gsub("^%s+", ""):gsub("%s+$", "")
              developer = developer:gsub("^%s+", ""):gsub("%s+$", "")
              
              local fx_entry = {
                filename = current_plugin_file,
                name = plugin_name,
                full_name = plugin_name,
                folder = "All FX",
                path = current_plugin_file,
                is_vst_cache = true, -- Use same flag for cache-based plugins
                plugin_type = "CLAP",
                clap_id = clap_id,
                developer = developer
              }
              
              table.insert(all_clap_fx, fx_entry)
            end
          end
        end
      end
    end
  end
  
  return all_clap_fx
end

local function extract_plugin_name_from_path(path)
  -- Extract plugin name from various path formats
  local name = path
  
  -- Remove file extension
  name = name:gsub("%.vst3.*$", ""):gsub("%.dll$", ""):gsub("%.vst$", ""):gsub("%.clap$", "")
  
  -- Extract from full path
  name = name:match("([^/\\]+)$") or name
  
  -- Clean up common patterns
  name = name:gsub("_x64", ""):gsub("_64", ""):gsub("_VST3", "")
  name = name:gsub("^Auburn_Sounds_", ""):gsub("^FabFilter_", "")
  
  return name
end

local function get_all_fx()
  local fx_list = {}
  
  -- Read the REAPER FX folders configuration (always fast)
  local custom_folders, folder_names = read_fx_folders()
  
  -- Build FX list directly from folder data
  for folder_key, fx_entries in pairs(custom_folders) do
    if folder_key ~= "FolderNames" then
      -- Get the actual folder name from folder_names mapping
      local folder_number = folder_key:match("Folder(%d+)")
      local folder_name = "Unknown"
      if folder_number and folder_names[folder_number] then
        folder_name = folder_names[folder_number]
      end
      
      -- Add each FX from this folder
      for fx_key, fx_path in pairs(fx_entries) do
        local plugin_name = extract_plugin_name_from_path(fx_path)
        
        table.insert(fx_list, {
          filename = fx_path,
          full_name = fx_path, -- Use the path as the full name for insertion
          folder = folder_name,
          name = plugin_name,
          path = fx_path,
          is_vst_cache = false
        })
      end
    end
  end
  
  return fx_list
end

local function get_all_fx_with_cache()
  -- Always load user folders first (fast)
  local fx_list = get_all_fx()
  
  -- Try to load VST and CLAP FX from cache
  local cache_data = load_fx_cache()
  if cache_data and cache_data.fx_list then
    for _, fx in ipairs(cache_data.fx_list) do
      if fx.is_vst_cache then
        table.insert(fx_list, fx)
      end
    end
  else
    -- No cache, scan VST and CLAP immediately (first run)
    local vst_fx = read_vst_cache()
    local clap_fx = read_clap_cache()
    
    for _, fx in ipairs(vst_fx) do
      table.insert(fx_list, fx)
    end
    for _, fx in ipairs(clap_fx) do
      table.insert(fx_list, fx)
    end
    
    -- Save cache for next time
    save_fx_cache(fx_list)
  end
  
  return fx_list
end

local function table_count(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end

local function filter_vst_duplicates(fx_list)
  if not settings.hide_vst2_duplicates then
    return fx_list
  end
  
  local filtered = {}
  local vst3_plugins = {} -- Track VST3 plugins by name
  local clap_plugins = {} -- Track CLAP plugins by name
  
  -- First pass: collect all VST3 and CLAP plugin names
  for _, fx in ipairs(fx_list) do
    if fx.filename and fx.filename:match("%.vst3") then
      vst3_plugins[fx.name] = true
    elseif fx.filename and fx.filename:match("%.clap") then
      clap_plugins[fx.name] = true
    end
  end
  
  -- Second pass: filter out VST2 if VST3 or CLAP exists
  local hidden_count = 0
  for _, fx in ipairs(fx_list) do
    local is_vst2 = fx.filename and (fx.filename:match("%.dll$") or fx.filename:match("%.vst$"))
    local has_newer_version = vst3_plugins[fx.name] or clap_plugins[fx.name]
    
    if is_vst2 and has_newer_version then
      -- Skip VST2 if VST3 or CLAP version exists
      hidden_count = hidden_count + 1
    else
      table.insert(filtered, fx)
    end
  end
  
  return filtered
end

local function organize_fx_by_folders(fx_list)
  -- Apply VST filtering based on settings
  local filtered_fx_list = filter_vst_duplicates(fx_list)
  
  local folders = {}
  local developer_folders = {}
  
  local match_attempts = 0
  local successful_matches = 0
  
  for _, fx in ipairs(filtered_fx_list) do
    -- Add to specific folder
    if not folders[fx.folder] then
      folders[fx.folder] = {}
    end
    table.insert(folders[fx.folder], fx)
    
    -- Add to developer folder if we have tag info
    match_attempts = match_attempts + 1
    
    -- Try multiple variations to match the plugin with developer tags
    local developer = nil
    local matched_key = ""
    
    -- 0. For CLAP plugins, use embedded developer info first
    if fx.plugin_type == "CLAP" and fx.developer then
      developer = fx.developer
      matched_key = "CLAP embedded"
    end
    
    -- 1. Try exact name match
    if not developer and fx_tags[fx.name] then
      developer = fx_tags[fx.name]
      matched_key = fx.name
    end
    
    -- 2. Try filename match
    if not developer and fx.filename and fx_tags[fx.filename] then
      developer = fx_tags[fx.filename]
      matched_key = fx.filename
    end
    
    -- 3. Try path match
    if not developer and fx.path and fx_tags[fx.path] then
      developer = fx_tags[fx.path]
      matched_key = fx.path
    end
    
    -- 4. Try extracting filename from path
    if not developer and fx.path then
      local filename_from_path = fx.path:match("([^/\\]+)$")
      if filename_from_path and fx_tags[filename_from_path] then
        developer = fx_tags[filename_from_path]
        matched_key = filename_from_path
      end
    end
    
    -- 5. Try variations without extensions
    if not developer then
      local name_variations = {
        fx.name,
        fx.filename,
        fx.path
      }
      
      for _, name in ipairs(name_variations) do
        if name then
          -- Try removing common extensions
          local name_no_ext = name:gsub("%.dll$", ""):gsub("%.vst$", ""):gsub("%.vst3$", "")
          if name_no_ext ~= name and fx_tags[name_no_ext] then
            developer = fx_tags[name_no_ext]
            matched_key = name_no_ext
            break
          end
        end
      end
    end
    
    if developer then
      successful_matches = successful_matches + 1
      local dev_folder_name = "Dev: " .. developer
      if not developer_folders[dev_folder_name] then
        developer_folders[dev_folder_name] = {}
      end
      table.insert(developer_folders[dev_folder_name], fx)
    end
  end
  
  -- Merge developer folders into main folders
  for dev_folder, fx_array in pairs(developer_folders) do
    folders[dev_folder] = fx_array
  end
  
  -- Sort FX within each folder alphabetically
  for folder_name, fx_array in pairs(folders) do
    table.sort(fx_array, function(a, b)
      return a.name:lower() < b.name:lower()
    end)
  end
  
  -- Create sorted folder list (user folders first, then All FX, then developers)
  local sorted_folders = {}
  
  -- Add user folders first (alphabetically)
  local user_folders = {}
  local dev_folders = {}
  
  for folder_name, _ in pairs(folders) do
    if folder_name ~= "All FX" then
      if folder_name:match("^Dev: ") then
        table.insert(dev_folders, folder_name)
      else
        table.insert(user_folders, folder_name)
      end
    end
  end
  
  -- Sort user folders and developer folders separately
  table.sort(user_folders, function(a, b)
    return a:lower() < b:lower()
  end)
  table.sort(dev_folders, function(a, b)
    return a:lower() < b:lower()
  end)
  
  -- Add user folders to the main list
  for _, folder_name in ipairs(user_folders) do
    table.insert(sorted_folders, folder_name)
  end
  
  -- Add "All FX" after user folders if it exists
  if folders["All FX"] then
    table.insert(sorted_folders, "All FX")
  end
  
  -- Add developer folders at the end
  for _, folder_name in ipairs(dev_folders) do
    table.insert(sorted_folders, folder_name)
  end
  
  return folders, sorted_folders
end

local function background_scan_vst()
  if background_scan_running then return end
  
  background_scan_running = true
  
  -- This will run in the background via defer
  local function do_background_scan()
    -- Get current user folders
    local user_fx = get_all_fx()
    
    -- Scan VST cache files
    local vst_fx = read_vst_cache()
    local clap_fx = read_clap_cache()
    
    -- Combine all FX
    local all_fx = {}
    for _, fx in ipairs(user_fx) do
      table.insert(all_fx, fx)
    end
    for _, fx in ipairs(vst_fx) do
      table.insert(all_fx, fx)
    end
    for _, fx in ipairs(clap_fx) do
      table.insert(all_fx, fx)
    end
    
    -- Save new cache
    save_fx_cache(all_fx)
    
    -- Update the live data
    fx_data, folder_list = organize_fx_by_folders(all_fx)
    
    -- Update selection if needed - restore last selected folder or use first folder
    if selected_folder == "" and #folder_list > 0 then
      local last_folder_found = false
      if settings.last_selected_folder ~= "" then
        -- Check if the last selected folder still exists
        for _, folder_name in ipairs(folder_list) do
          if folder_name == settings.last_selected_folder then
            selected_folder = settings.last_selected_folder
            last_folder_found = true
            break
          end
        end
        -- Also check if "All FX" was the last selected (it's not in folder_list)
        if not last_folder_found and settings.last_selected_folder == "All FX" and fx_data["All FX"] then
          selected_folder = "All FX"
          last_folder_found = true
        end
      end
      
      -- If last selected folder wasn't found, fall back to first folder
      if not last_folder_found then
        selected_folder = folder_list[1]
      end
      
      filtered_fx = fx_data[selected_folder] or {}
    end
    
    background_scan_running = false
  end
  
  -- Start the background scan
  do_background_scan()
end

-- Add string trim function
string.trim = string.trim or function(s)
  return s:match("^%s*(.-)%s*$")
end

-- Helper function to count table entries








local function filter_fx(fx_list, search_term)
  if search_term == "" then return fx_list end
  
  local filtered = {}
  local search_lower = search_term:lower()
  
  for _, fx in ipairs(fx_list) do
    if fx.name:lower():find(search_lower, 1, true) or 
       fx.full_name:lower():find(search_lower, 1, true) then
      table.insert(filtered, fx)
    end
  end
  
  return filtered
end



------------------------------------------------------
-- TARGET DETECTION (Called on script activation)
------------------------------------------------------

local function detect_fx_chain_window()
  -- Check if JS_ReaScriptAPI is available for window detection
  if not reaper.JS_Window_FromPoint then
    return false, nil, nil
  end
  
  local mouse_x, mouse_y = reaper.GetMousePosition()
  local hwnd = reaper.JS_Window_FromPoint(mouse_x, mouse_y)
  
  if hwnd then
    local title = reaper.JS_Window_GetTitle(hwnd)
    if title and title:match("^FX:") then
      -- Extract track name from FX window title
      local track_name = title:match("^FX: (.+)")
      if track_name then
        -- Find the track by name
        if track_name == "MASTER" then
          return true, reaper.GetMasterTrack(0), "master"
        else
          -- Search for track by name
          local track_count = reaper.CountTracks(0)
          for i = 0, track_count - 1 do
            local track = reaper.GetTrack(0, i)
            local _, current_track_name = reaper.GetTrackName(track)
            if current_track_name == track_name then
              return true, track, "track"
            end
          end
        end
      end
    end
  end
  
  return false, nil, nil
end

local function detect_and_set_target()
  local mouse_x, mouse_y = reaper.GetMousePosition()
  
  -- First, check if hovering over an FX chain window
  local is_fx_chain, fx_chain_track, fx_chain_mode = detect_fx_chain_window()
  if is_fx_chain then
    target_track = fx_chain_track
    target_item = nil
    insert_mode = fx_chain_mode
    
    if fx_chain_mode == "master" then
      target_info = "FX Chain: Master Track"
    else
      local _, track_name = reaper.GetTrackName(fx_chain_track)
      target_info = "FX Chain: " .. (track_name or "Unnamed")
    end
    return
  end
  
  -- Standard detection logic
  local item = reaper.GetItemFromPoint(mouse_x, mouse_y, true)
  local track = reaper.GetTrackFromPoint(mouse_x, mouse_y)
  
  if item then
    target_item = item
    target_track = reaper.GetMediaItem_Track(item)
    insert_mode = "item"
    target_info = "Item: " .. (reaper.GetTakeName(reaper.GetActiveTake(item)) or "Unnamed")
  elseif track then
    target_track = track
    target_item = nil
    if track == reaper.GetMasterTrack(0) then
      insert_mode = "master"
      target_info = "Master Track"
    else
      insert_mode = "track"
      local _, track_name = reaper.GetTrackName(track)
      target_info = "Track: " .. (track_name or "Unnamed")
    end
  else
    target_track = nil
    target_item = nil
    insert_mode = "none"
    target_info = "No valid target"
  end
end

------------------------------------------------------
-- FX INSERTION
------------------------------------------------------

local function insert_fx(fx, insert_to_input_fx)
  if not fx then 
    return false 
  end
  
  -- For direct path insertion, we need to use the path as the FX name
  local fx_name = fx.path or fx.full_name
  local fx_index = -1
  
  if insert_mode == "track" and target_track then
    if insert_to_input_fx then
      -- Insert to Input FX (using recIntoIndex = true)
      fx_index = reaper.TrackFX_AddByName(target_track, fx_name, true, -1)
      
      if fx_index >= 0 then
        -- Show FX window based on settings (Input FX uses negative indices for display)
        local input_fx_index = -1000 - fx_index
        if settings.fx_window_mode == 1 then
          -- Auto float window
          reaper.TrackFX_Show(target_track, input_fx_index, 3)
        elseif settings.fx_window_mode == 2 then
          -- Show in chain window
          reaper.TrackFX_Show(target_track, input_fx_index, 1)
        end
        return true
      end
    else
      -- Insert to main FX chain
      fx_index = reaper.TrackFX_AddByName(target_track, fx_name, false, -1)
      
      if fx_index >= 0 then
        -- Show FX window based on settings
        if settings.fx_window_mode == 1 then
          -- Auto float window
          reaper.TrackFX_Show(target_track, fx_index, 3) -- 3 = float and bring to front
        elseif settings.fx_window_mode == 2 then
          -- Show in chain window
          reaper.TrackFX_Show(target_track, fx_index, 1) -- 1 = show in chain
        end
        -- fx_window_mode == 0 means no window (do nothing)
        
        return true
      end
    end
    
    -- Try alternative insertion methods if the first attempt failed
    local alternative_names = {fx.filename, fx.name}
    
    -- Add name without extension
    if fx_name then
      local name_no_ext = fx_name:gsub("%.%w+$", "") -- Remove file extension
      if name_no_ext ~= fx_name then
        table.insert(alternative_names, name_no_ext)
      end
    end
    
    for _, alt_name in ipairs(alternative_names) do
      if alt_name and alt_name ~= fx_name then
        if insert_to_input_fx then
          fx_index = reaper.TrackFX_AddByName(target_track, alt_name, true, -1)
          if fx_index >= 0 then
            local input_fx_index = -1000 - fx_index
            if settings.fx_window_mode == 1 then
              reaper.TrackFX_Show(target_track, input_fx_index, 3)
            elseif settings.fx_window_mode == 2 then
              reaper.TrackFX_Show(target_track, input_fx_index, 1)
            end
            return true
          end
        else
          fx_index = reaper.TrackFX_AddByName(target_track, alt_name, false, -1)
          if fx_index >= 0 then
            if settings.fx_window_mode == 1 then
              reaper.TrackFX_Show(target_track, fx_index, 3)
            elseif settings.fx_window_mode == 2 then
              reaper.TrackFX_Show(target_track, fx_index, 1)
            end
            return true
          end
        end
      end
    end
    
    return false
    
  elseif insert_mode == "master" and target_track then
    if insert_to_input_fx then
      -- Master track Input FX
      fx_index = reaper.TrackFX_AddByName(target_track, fx_name, true, -1)
      if fx_index >= 0 then
        local input_fx_index = -1000 - fx_index
        if settings.fx_window_mode == 1 then
          reaper.TrackFX_Show(target_track, input_fx_index, 3)
        elseif settings.fx_window_mode == 2 then
          reaper.TrackFX_Show(target_track, input_fx_index, 1)
        end
        return true
      end
    else
      -- Master track main FX
      fx_index = reaper.TrackFX_AddByName(target_track, fx_name, false, -1)
      if fx_index >= 0 then
        if settings.fx_window_mode == 1 then
          reaper.TrackFX_Show(target_track, fx_index, 3)
        elseif settings.fx_window_mode == 2 then
          reaper.TrackFX_Show(target_track, fx_index, 1)
        end
        return true
      end
    end
    return false
    
  elseif insert_mode == "item" and target_item then
    -- Items don't have Input FX, so ignore the input FX flag
    local take = reaper.GetActiveTake(target_item)
    if take then
      fx_index = reaper.TakeFX_AddByName(take, fx_name, -1)
      if fx_index >= 0 then
        -- Show FX window based on settings
        if settings.fx_window_mode == 1 then
          reaper.TakeFX_Show(take, fx_index, 3)
        elseif settings.fx_window_mode == 2 then
          reaper.TakeFX_Show(take, fx_index, 1)
        end
        return true
      end
      return false
    else
      return false
    end
  else
    return false
  end
end

------------------------------------------------------
-- SETTINGS FUNCTIONS
------------------------------------------------------

local function get_settings_file_path()
  local resource_path = reaper.GetResourcePath()
  return resource_path .. "/FX_Inserter_settings.lua"
end

local function save_settings()
  local settings_path = get_settings_file_path()
  
  local file = io.open(settings_path, "w")
  if file then
    file:write("-- FX Inserter Settings File\n")
    file:write("return {\n")
    file:write("  hide_vst2_duplicates = " .. tostring(settings.hide_vst2_duplicates) .. ",\n")
    file:write("  auto_close_on_insert = " .. tostring(settings.auto_close_on_insert) .. ",\n")
    file:write("  search_all_folders = " .. tostring(settings.search_all_folders) .. ",\n")
    file:write("  fx_window_mode = " .. tostring(settings.fx_window_mode) .. ",\n")
    file:write("  window_x = " .. tostring(settings.window_x) .. ",\n")
    file:write("  window_y = " .. tostring(settings.window_y) .. ",\n")
    file:write("  window_width = " .. tostring(settings.window_width) .. ",\n")
    file:write("  window_height = " .. tostring(settings.window_height) .. ",\n")
    file:write("  last_selected_folder = " .. string.format("%q", settings.last_selected_folder) .. "\n")
    file:write("}\n")
    file:close()
  end
end

local function load_settings()
  local settings_path = get_settings_file_path()
  
  local file = io.open(settings_path, "r")
  if not file then 
    return 
  end
  
  local content = file:read("*all")
  file:close()
  
  -- Load the Lua table
  local load_func = load or loadstring -- Fallback for older Lua versions
  local success, loaded_settings = pcall(load_func(content))
  if success and loaded_settings then
    -- Use proper conditional logic to ensure values are properly loaded
    if loaded_settings.hide_vst2_duplicates ~= nil then
      settings.hide_vst2_duplicates = loaded_settings.hide_vst2_duplicates
    end
    if loaded_settings.auto_close_on_insert ~= nil then
      settings.auto_close_on_insert = loaded_settings.auto_close_on_insert
    end
    if loaded_settings.search_all_folders ~= nil then
      settings.search_all_folders = loaded_settings.search_all_folders
    end
    if loaded_settings.fx_window_mode ~= nil then
      settings.fx_window_mode = loaded_settings.fx_window_mode
    end
    if loaded_settings.window_x ~= nil then
      settings.window_x = loaded_settings.window_x
    end
    if loaded_settings.window_y ~= nil then
      settings.window_y = loaded_settings.window_y
    end
    if loaded_settings.window_width ~= nil then
      settings.window_width = loaded_settings.window_width
    end
    if loaded_settings.window_height ~= nil then
      settings.window_height = loaded_settings.window_height
    end
    if loaded_settings.last_selected_folder ~= nil then
      settings.last_selected_folder = loaded_settings.last_selected_folder
    end
  end
end

local function save_window_state()
  -- Don't save during window setup or if context is invalid
  if not ctx then return end
  
  local x, y = reaper.ImGui_GetWindowPos(ctx)
  local w, h = reaper.ImGui_GetWindowSize(ctx)
  
  -- Only save if we have valid values (reasonable window size and position)
  if x and y and w and h and w > 100 and h > 100 and x > -10000 and y > -10000 then
    local changed = false
    
    -- Only update if there's a significant change (avoid constant saving)
    if math.abs(settings.window_x - x) > 1 then
      settings.window_x = math.floor(x)
      changed = true
    end
    if math.abs(settings.window_y - y) > 1 then
      settings.window_y = math.floor(y)
      changed = true
    end
    if math.abs(settings.window_width - w) > 1 then
      settings.window_width = math.floor(w)
      changed = true
    end
    if math.abs(settings.window_height - h) > 1 then
      settings.window_height = math.floor(h)
      changed = true
    end
    
    -- Only save to disk if something actually changed
    if changed then
      save_settings()
    end
  end
end

------------------------------------------------------
-- GUI FUNCTIONS
------------------------------------------------------

local function draw_search_box()
  reaper.ImGui_Text(ctx, "Search:")
  reaper.ImGui_SameLine(ctx)
  local changed, new_text = reaper.ImGui_InputText(ctx, "##search", search_text)
  if changed then
    search_text = new_text
  end
  
  -- Settings button on the same line
  reaper.ImGui_SameLine(ctx)
  local available_width = reaper.ImGui_GetContentRegionAvail(ctx)
  reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + available_width - 80)
  
  if reaper.ImGui_Button(ctx, "Settings", 70, 0) then
    settings_window_open = true
  end
end

local function draw_folder_list()
  local available_width = reaper.ImGui_GetContentRegionAvail(ctx)
  local folder_width = available_width * 0.4 -- 40% for folders
  
  if reaper.ImGui_BeginChild(ctx, "FolderList", folder_width, -50) then
    -- Draw User Folders section
    reaper.ImGui_Text(ctx, "User Folders:")
    reaper.ImGui_Separator(ctx)
    
    local user_folder_count = 0
    for _, folder_name in ipairs(folder_list) do
      if folder_name ~= "All FX" and not folder_name:match("^Dev: ") then
        user_folder_count = user_folder_count + 1
        local is_selected = (selected_folder == folder_name)
        
        if reaper.ImGui_Selectable(ctx, folder_name, is_selected) then
          selected_folder = folder_name
          settings.last_selected_folder = folder_name
          save_settings()
        end
        
        -- Show FX count for each folder
        local fx_count = fx_data[folder_name] and #fx_data[folder_name] or 0
        if reaper.ImGui_IsItemHovered(ctx) then
          reaper.ImGui_SetTooltip(ctx, string.format("%s (%d FX)", folder_name, fx_count))
        end
      end
    end
    
    -- Add some spacing if there are user folders and All FX exists
    if user_folder_count > 0 and fx_data["All FX"] then
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)
    end
    
    -- Draw All FX section
    if fx_data["All FX"] then
      reaper.ImGui_Text(ctx, "All Installed FX:")
      reaper.ImGui_Separator(ctx)
      
      local is_selected = (selected_folder == "All FX")
      if reaper.ImGui_Selectable(ctx, "All FX", is_selected) then
        selected_folder = "All FX"
        settings.last_selected_folder = "All FX"
        save_settings()
      end
      
      local fx_count = #fx_data["All FX"]
      if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, string.format("All FX (%d plugins)", fx_count))
      end
    end
    
    -- Count developer folders
    local dev_folder_count = 0
    for _, folder_name in ipairs(folder_list) do
      if folder_name:match("^Dev: ") then
        dev_folder_count = dev_folder_count + 1
      end
    end
    
    -- Draw Developers section if we have any
    if dev_folder_count > 0 then
      reaper.ImGui_Spacing(ctx)
      reaper.ImGui_Separator(ctx)
      reaper.ImGui_Spacing(ctx)
      
      reaper.ImGui_Text(ctx, "Developers:")
      reaper.ImGui_Separator(ctx)
      
      for _, folder_name in ipairs(folder_list) do
        if folder_name:match("^Dev: ") then
          local developer_name = folder_name:gsub("^Dev: ", "") -- Remove "Dev: " prefix for display
          local is_selected = (selected_folder == folder_name)
          
          if reaper.ImGui_Selectable(ctx, developer_name, is_selected) then
            selected_folder = folder_name
            settings.last_selected_folder = folder_name
            save_settings()
          end
          
          -- Show FX count for each developer
          local fx_count = fx_data[folder_name] and #fx_data[folder_name] or 0
          if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, string.format("%s (%d FX)", developer_name, fx_count))
          end
        end
      end
    end
    
    reaper.ImGui_EndChild(ctx)
  end
end

local function draw_fx_list()
  reaper.ImGui_SameLine(ctx)
  
  local available_width = reaper.ImGui_GetContentRegionAvail(ctx)
  
  if reaper.ImGui_BeginChild(ctx, "FXList", 0, -50) then
    if selected_folder == "" then
      reaper.ImGui_Text(ctx, "Select a folder to view plugins")
    else
      -- Show cleaner folder name for display
      local display_folder = selected_folder
      if selected_folder:match("^Dev: ") then
        display_folder = selected_folder:gsub("^Dev: ", "") .. " (Developer)"
      end
      
      reaper.ImGui_Text(ctx, "Plugins in " .. display_folder .. ":")
      reaper.ImGui_Separator(ctx)
      
      local current_fx_list = fx_data[selected_folder] or {}
      
      -- If search_all_folders is enabled and there's a search term, search from "All FX" folder only
      if settings.search_all_folders and search_text ~= "" then
        if fx_data["All FX"] then
          current_fx_list = fx_data["All FX"]
        end
      end
      
      filtered_fx = filter_fx(current_fx_list, search_text)
      
      for i, fx in ipairs(filtered_fx) do
        local display_name = fx.name
        
        -- Check if Shift key is held for Input FX insertion
        local shift_held = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or 
                          reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
        
        if reaper.ImGui_Selectable(ctx, display_name) then
          local insertion_result = insert_fx(fx, shift_held)
          
          if insertion_result then
            -- Handle auto-close setting
            if settings.auto_close_on_insert then
              window_open = false
            end
          else
            reaper.ShowMessageBox("Failed to insert FX: " .. fx.name, "Error", 0)
          end
        end
        
        -- Enhanced tooltip with modifier key info
        if reaper.ImGui_IsItemHovered(ctx) then
          local tooltip_text = fx.path or fx.full_name
          if insert_mode == "track" or insert_mode == "master" then
            if shift_held then
              tooltip_text = tooltip_text .. "\n\n[Shift] Insert to Input FX"
            else
              tooltip_text = tooltip_text .. "\n\nHold [Shift] to insert to Input FX"
            end
          end
          reaper.ImGui_SetTooltip(ctx, tooltip_text)
        end
      end
    end
    reaper.ImGui_EndChild(ctx)
  end
end

local function draw_status_bar()
  reaper.ImGui_Separator(ctx)
  reaper.ImGui_Text(ctx, "Target: " .. target_info)
  reaper.ImGui_SameLine(ctx)
  
  local current_fx_list = selected_folder ~= "" and fx_data[selected_folder] or {}
  local total_fx = #current_fx_list
  local filtered_count = #filtered_fx
  
  -- Check if Shift key is held for Input FX mode indicator
  local shift_held = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or 
                    reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
  
  if selected_folder == "" then
    reaper.ImGui_Text(ctx, "| No folder selected")
  elseif search_text ~= "" then
    -- Check if we're searching across all folders
    if settings.search_all_folders then
      -- Calculate total FX across all folders for accurate count
      local total_all_fx = 0
      for _, folder_fx in pairs(fx_data) do
        total_all_fx = total_all_fx + #folder_fx
      end
      reaper.ImGui_Text(ctx, string.format("| Searching all folders: %d/%d FX", filtered_count, total_all_fx))
    else
      reaper.ImGui_Text(ctx, string.format("| Showing: %d/%d FX", filtered_count, total_fx))
    end
  else
    reaper.ImGui_Text(ctx, string.format("| Total: %d FX", total_fx))
  end
  
  -- Show Input FX mode indicator
  if (insert_mode == "track" or insert_mode == "master") and shift_held then
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, "| [SHIFT] INPUT FX MODE")
  end
end

local function draw_main_window()
  local window_flags = reaper.ImGui_WindowFlags_NoSavedSettings()
  
  -- Restore window position and size from settings
  if settings.window_x >= 0 and settings.window_y >= 0 then
    reaper.ImGui_SetNextWindowPos(ctx, settings.window_x, settings.window_y, reaper.ImGui_Cond_FirstUseEver())
  end
  
  reaper.ImGui_SetNextWindowSize(ctx, settings.window_width, settings.window_height, reaper.ImGui_Cond_FirstUseEver())
  
  local visible, open = reaper.ImGui_Begin(ctx, "FX Inserter", true, window_flags)
  
  if visible then
    draw_search_box()
    reaper.ImGui_Separator(ctx)
    
    -- Two-column layout
    draw_folder_list()
    draw_fx_list()
    
    draw_status_bar()
    
    -- Save window state when it changes
    save_window_state()
    
    reaper.ImGui_End(ctx)
  end
  
  return open
end

local function draw_settings_window()
  if not settings_window_open then return end
  
  local window_flags = reaper.ImGui_WindowFlags_NoSavedSettings() | reaper.ImGui_WindowFlags_AlwaysAutoResize()
  
  reaper.ImGui_SetNextWindowSize(ctx, 400, 200, reaper.ImGui_Cond_FirstUseEver())
  local visible, open = reaper.ImGui_Begin(ctx, "FX Inserter Settings", true, window_flags)
  
  if visible then
    reaper.ImGui_Text(ctx, "VST Plugin Filtering:")
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Hide VST2 duplicates checkbox
    local changed, new_val = reaper.ImGui_Checkbox(ctx, "Hide VST2 if VST3 version exists", settings.hide_vst2_duplicates)
    if changed then
      settings.hide_vst2_duplicates = new_val
      save_settings()
      
      -- Refresh the FX list to apply new filtering
      local all_fx = get_all_fx_with_cache()
      fx_data, folder_list = organize_fx_by_folders(all_fx)
      
      -- Update current selection
      if selected_folder ~= "" then
        local current_fx_list = fx_data[selected_folder] or {}
        filtered_fx = filter_fx(current_fx_list, search_text)
      end
    end
    
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "When enabled, VST2 plugins will be hidden from the list if a VST3 version of the same plugin exists")
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- Auto close on FX insert checkbox
    local changed2, new_val2 = reaper.ImGui_Checkbox(ctx, "Auto close window after FX insertion", settings.auto_close_on_insert)
    if changed2 then
      settings.auto_close_on_insert = new_val2
      save_settings()
    end
    
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "When enabled, the FX browser window will automatically close after inserting an FX")
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- Search all folders checkbox
    local changed3, new_val3 = reaper.ImGui_Checkbox(ctx, "Search all folders", settings.search_all_folders)
    if changed3 then
      settings.search_all_folders = new_val3
      save_settings()
    end
    
    if reaper.ImGui_IsItemHovered(ctx) then
      reaper.ImGui_SetTooltip(ctx, "When enabled, search will work across all folders instead of just the selected folder")
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- FX Window Mode dropdown
    reaper.ImGui_Text(ctx, "FX Window Mode:")
    local fx_window_options = {"No window", "Auto float", "Chain window"}
    local current_item = settings.fx_window_mode
    
    reaper.ImGui_SetNextItemWidth(ctx, 200)
    local changed4, new_selection = reaper.ImGui_Combo(ctx, "##fx_window_mode", current_item, table.concat(fx_window_options, "\0") .. "\0")
    if changed4 then
      settings.fx_window_mode = new_selection
      save_settings()
    end
    
    if reaper.ImGui_IsItemHovered(ctx) then
      local tooltip_text = "Choose how FX windows are displayed after insertion:\n" ..
                          "• No window: Only insert FX, don't show any window\n" ..
                          "• Auto float: Open FX in floating window\n" ..
                          "• Chain window: Show FX in the FX chain"
      reaper.ImGui_SetTooltip(ctx, tooltip_text)
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- Close button
    if reaper.ImGui_Button(ctx, "Close", 100, 30) then
      settings_window_open = false
    end
    
    reaper.ImGui_End(ctx)
  end
  
  if not open then
    settings_window_open = false
  end
end

------------------------------------------------------
-- ORGANIZE FX BY FOLDERS
------------------------------------------------------



------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------

local function init()
  -- Initialize cache file path
  cache_file_path = get_cache_file_path()
  
  -- Load settings
  load_settings()
  
  -- Load FX tags for developer information
  fx_tags = read_fx_tags()
  
  -- Detect target immediately on script activation
  detect_and_set_target()
  
  -- FAST STARTUP: Load from cache first
  local all_fx = get_all_fx_with_cache()
  fx_data, folder_list = organize_fx_by_folders(all_fx)
  
  -- Set initial selection - restore last selected folder if it exists, otherwise use first folder
  if #folder_list > 0 then
    local last_folder_found = false
    if settings.last_selected_folder ~= "" then
      -- Check if the last selected folder still exists
      for _, folder_name in ipairs(folder_list) do
        if folder_name == settings.last_selected_folder then
          selected_folder = settings.last_selected_folder
          last_folder_found = true
          break
        end
      end
      -- Also check if "All FX" was the last selected (it's not in folder_list)
      if not last_folder_found and settings.last_selected_folder == "All FX" and fx_data["All FX"] then
        selected_folder = "All FX"
        last_folder_found = true
      end
    end
    
    -- If last selected folder wasn't found, fall back to first folder
    if not last_folder_found then
      selected_folder = folder_list[1]
    end
    
    filtered_fx = fx_data[selected_folder] or {}
  else
    filtered_fx = {}
  end
  
  -- SMART BACKGROUND SCAN: Check if cache is outdated
  if is_cache_outdated() then
    -- Use defer to start background scan after GUI is ready
    reaper.defer(function()
      background_scan_vst()
    end)
  end
end

local function main_loop()
  if not window_open then return end
  
  -- Periodic check for updates (every second)
  local current_time = reaper.time_precise() * 1000
  if current_time - last_update_check > update_check_interval then
    last_update_check = current_time
    
    -- Only check if we're not already scanning
    if not background_scan_running and is_cache_outdated() then
      reaper.defer(function()
        background_scan_vst()
      end)
    end
  end
  
  reaper.ImGui_PushFont(ctx, font)
  local gui_open = draw_main_window()
  
  -- Only update window_open if it's still true (don't override auto-close)
  if window_open then
    window_open = gui_open
  end
  
  -- Draw settings window if open
  draw_settings_window()
  
  reaper.ImGui_PopFont(ctx)
  
  if window_open then
    reaper.defer(main_loop)
  end
end

-- Initialize and start
init()
main_loop()

-- Cleanup
reaper.atexit(function()
  if ctx and reaper.ImGui_DestroyContext then
    reaper.ImGui_DestroyContext(ctx)
  end
end)

local function save_window_state()
  if reaper.ImGui_IsWindowAppearing then
    -- Don't save state during initial window setup
    return
  end
  
  local x, y = reaper.ImGui_GetWindowPos(ctx)
  local w, h = reaper.ImGui_GetWindowSize(ctx)
  
  -- Only save if we have valid values
  if x and y and w and h and w > 100 and h > 100 then
    local changed = false
    
    if math.abs(settings.window_x - x) > 1 then
      settings.window_x = x
      changed = true
    end
    if math.abs(settings.window_y - y) > 1 then
      settings.window_y = y
      changed = true
    end
    if math.abs(settings.window_width - w) > 1 then
      settings.window_width = w
      changed = true
    end
    if math.abs(settings.window_height - h) > 1 then
      settings.window_height = h
      changed = true
    end
    
    -- Only save to disk if something actually changed
    if changed then
      save_settings()
    end
  end
end




