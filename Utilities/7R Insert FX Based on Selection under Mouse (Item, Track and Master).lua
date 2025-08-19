--[[
@description 7R Insert FX Based on Selection under Mouse cursor (Track or Item, Master)
@author 7thResonance
@version 2.6
@changelog - Better Parsing using Sexan's FX Broswer PArser V7
@donation https://paypal.me/7thresonance
@about Opens GUI for track, item or master under cursor with GUI to select FX
    - Saves position and size of GUI
    - Cache for quick search. Updates when new plugins are installed
    - Settings for basic options
@screenshot https://i.postimg.cc/DyqgzknJ/Screenshot-2025-07-11-062605.png
    https://i.postimg.cc/3JM17J5Q/Screenshot-2025-07-11-062614.png

--]]

-- REAIMGUI SETUP
if not reaper.ImGui_CreateContext then
  reaper.ShowMessageBox("ReaImGui not found! Please install via ReaPack.", "Error", 0)
  return
end

--------------------------------------------------------------------------
-- START: Integrated Sexan FX Browser Parser V7
--------------------------------------------------------------------------

local r                                = reaper
local os                               = r.GetOS()
local os_separator                     = package.config:sub(1, 1)
local script_path                      = debug.getinfo(1, "S").source:match [[^@?(.*[\/])[^\/]-$]]

local FX_FILE                          = script_path .. "/FX_LIST.txt"
local FX_CAT_FILE                      = script_path .. "/FX_CAT_FILE.txt"
local FX_DEV_LIST_FILE                 = script_path .. "/FX_DEV_LIST_FILE.txt"

local CAT                              = {}
local DEVELOPER_LIST                   = { " (Waves)" }
local PLUGIN_LIST                      = {}
local INSTRUMENTS                      = {}
local VST_INFO, VST, VSTi, VST3, VST3i = {}, {}, {}, {}, {}
local JS_INFO, JS                      = {}, {}
local AU_INFO, AU, AUi                 = {}, {}, {}
local CLAP_INFO, CLAP, CLAPi           = {}, {}, {}
local LV2_INFO, LV2, LV2i              = {}, {}, {}

local function ResetTables()
    CAT = {}
    DEVELOPER_LIST = { " (Waves)" }
    PLUGIN_LIST = {}
    INSTRUMENTS = {}
    VST_INFO, VST, VSTi, VST3, VST3i = {}, {}, {}, {}, {}
    JS_INFO, JS = {}, {}
    AU_INFO, AU, AUi = {}, {}, {}
    CLAP_INFO, CLAP, CLAPi = {}, {}, {}
    LV2_INFO, LV2, LV2i = {}, {}, {}
end

function MakeFXFiles()
    GetFXTbl()
    local serialized_fx = TableToString(PLUGIN_LIST)
    WriteToFile(FX_FILE, serialized_fx)

    local serialized_cat = TableToString(CAT)
    WriteToFile(FX_CAT_FILE, serialized_cat)

    local serialized_dev_list = TableToString(DEVELOPER_LIST)
    WriteToFile(FX_DEV_LIST_FILE, serialized_dev_list)

    return PLUGIN_LIST, CAT, DEVELOPER_LIST
end

function ReadFXFile()
    local fx_file = io.open(FX_FILE, "r")
    if fx_file then
        PLUGIN_LIST = {}
        local fx_string = fx_file:read("*all")
        fx_file:close()
        PLUGIN_LIST = StringToTable(fx_string)
    end

    local cat_file = io.open(FX_CAT_FILE, "r")
    if cat_file then
        CAT = {}
        local cat_string = cat_file:read("*all")
        cat_file:close()
        CAT = StringToTable(cat_string)
    end

    local dev_list_file = io.open(FX_DEV_LIST_FILE, "r")
    if dev_list_file then
        DEVELOPER_LIST = {}
        local dev_list_string = dev_list_file:read("*all")
        dev_list_file:close()
        DEVELOPER_LIST = StringToTable(dev_list_string)
    end

    return PLUGIN_LIST, CAT, DEVELOPER_LIST
end

function WriteToFile(path, data)
    local file_cat = io.open(path, "w")
    if file_cat then
        file_cat:write(data)
        file_cat:close()
    end
end

function SerializeToFile(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0
    local tmp = string.rep(" ", depth)
    if name then
        if type(name) == "number" and math.floor(name) == name then
            name = "[" .. name .. "]"
        elseif not string.match(name, '^[a-zA-z_][a-zA-Z0-9_]*$') then
            name = string.gsub(name, "'", "''")
            name = "['" .. name .. "']"
        end
        tmp = tmp .. name .. " = "
    end
    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")
        for k, v in pairs(val) do
            tmp = tmp .. SerializeToFile(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end
        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "nil"
    end
    return tmp
end

function StringToTable(str)
    local f, err = load("return " .. str)
    if err then
        -- suppress console output
    end
    return f ~= nil and f() or nil
end

function TableToString(table) return SerializeToFile(table) end

function Literalize(str)
    return str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", function(c) return "%" .. c end)
end

function GetFileContext(fp)
    local str = "\n"
    if not fp then return str end
    local f = io.open(fp, 'r')
    if f then
        str = f:read('a')
        f:close()
    end
    return str
end

local function GetDirFilesRecursive(dir, tbl, filter)
    for index = 0, math.huge do
        local path = r.EnumerateSubdirectories(dir, index)
        if not path then break end
        tbl[#tbl + 1] = { dir = path, {} }
        GetDirFilesRecursive(dir .. os_separator .. path, tbl[#tbl], filter)
    end

    for index = 0, math.huge do
        local file = r.EnumerateFiles(dir, index)
        if not file then break end
        if file:find(filter, nil, true) then
            tbl[#tbl + 1] = file:gsub(filter, "")
        end
    end
end

local function FindCategory(cat)
    for i = 1, #CAT do
        if CAT[i].name == cat then return CAT[i].list end
    end
end

local function FindFXIDName(tbl, id, js)
    for i = 1, #tbl do
        if js then
            if tbl[i].id:find(id) then return tbl[i].name end
        else
            if tbl[i].id == id then return tbl[i].name end
        end
    end
end

function InTbl(tbl, val)
    for i = 1, #tbl do
        if tbl[i].name == val then return tbl[i].fx end
    end
end

function AddDevList(val)
    for i = 1, #DEVELOPER_LIST do
        if DEVELOPER_LIST[i] == " (" .. val .. ")" then return end
    end
    DEVELOPER_LIST[#DEVELOPER_LIST + 1] = " (" .. val .. ")"
end

local function ParseVST(name, ident)
    if not name:match("^VST") then return end

    if name:match("VST: ") then
        VST[#VST + 1] = name
    elseif name:match("VSTi: ") then
        VSTi[#VSTi + 1] = name
        INSTRUMENTS[#INSTRUMENTS + 1] = name
    elseif name:match("VST3: ") then
        VST3[#VST3 + 1] = name
    elseif name:match("VST3i: ") then
        VST3i[#VST3i + 1] = name
        INSTRUMENTS[#INSTRUMENTS + 1] = name
    end
    ident = os:match("Win") and ident:reverse():match("(.-)\\") or ident:reverse():match("(.-)/")
    ident = ident:reverse():gsub(" ", "_"):gsub("-", "_")
    VST_INFO[#VST_INFO + 1] = { id = ident, name = name }
    PLUGIN_LIST[#PLUGIN_LIST + 1] = name
end

local function ParseJSFX(name, ident)
    if not name:match("^JS:") then return end
    JS[#JS + 1]                   = name
    JS_INFO[#JS_INFO + 1]         = { id = ident, name = name }
    PLUGIN_LIST[#PLUGIN_LIST + 1] = name
end

local function ParseAU(name, ident)
    if not name:match("^AU") then return end

    if name:match("AU: ") then
        AU[#AU + 1] = name
    elseif name:match("AUi: ") then
        AUi[#AUi + 1] = name
        INSTRUMENTS[#INSTRUMENTS + 1] = name
    end
    AU_INFO[#AU_INFO + 1]         = { id = ident, name = name }
    PLUGIN_LIST[#PLUGIN_LIST + 1] = name
end

local function ParseCLAP(name, ident)
    if not name:match("^CLAP") then return end

    if name:match("CLAP: ") then
        CLAP[#CLAP + 1] = name
    elseif name:match("CLAPi: ") then
        CLAPi[#CLAPi + 1] = name
        INSTRUMENTS[#INSTRUMENTS + 1] = name
    end
    CLAP_INFO[#CLAP_INFO + 1] = { id = ident, name = name }
    PLUGIN_LIST[#PLUGIN_LIST + 1] = name
end

local function ParseLV2(name, ident)
    if not name:match("^LV2") then return end

    if name:match("LV2: ") then
        LV2[#LV2 + 1] = name
    elseif name:match("LV2i: ") then
        LV2i[#LV2i + 1] = name
        INSTRUMENTS[#INSTRUMENTS + 1] = name
    end
    LV2_INFO[#LV2_INFO + 1] = { id = ident, name = name }
    PLUGIN_LIST[#PLUGIN_LIST + 1] = name
end

local function has_fx(tbl, val)
    for i = 1, #tbl do
        if tbl[i] == val then return true end
    end
    return false
end

local function ParseFXTags()
    local tags_path = r.GetResourcePath() .. "/reaper-fxtags.ini"
    local tags_str  = GetFileContext(tags_path)
    local DEV       = true
    for line in tags_str:gmatch('[^\r\n]+') do
        local category = line:match("^%[(.+)%]")
        if line:match("^%[(category)%]") then
            DEV = false
        end
        if category then
            CAT[#CAT + 1] = { name = category:upper(), list = {} }
        end
        local FX, dev_category = line:match("(.+)=(.+)")
        if dev_category then
            dev_category = dev_category:gsub("[%[%]]", "")
            if DEV then AddDevList(dev_category) end
            local fx_name = FindFXIDName(VST_INFO, FX)
            fx_name = fx_name and fx_name or FindFXIDName(AU_INFO, FX)
            fx_name = fx_name and fx_name or FindFXIDName(CLAP_INFO, FX)
            fx_name = fx_name and fx_name or FindFXIDName(JS_INFO, FX, "JS")
            fx_name = fx_name and fx_name or FindFXIDName(LV2_INFO, FX)
            if dev_category:match("|") then
                for category_type in dev_category:gmatch('[^%|]+') do
                    local dev_tbl = InTbl(CAT[#CAT].list, category_type)
                    if fx_name then
                        if not dev_tbl then
                            table.insert(CAT[#CAT].list, { name = category_type, fx = { fx_name } })
                        else
                            if not has_fx(dev_tbl, fx_name) then
                                table.insert(dev_tbl, fx_name)
                            end
                        end
                    end
                end
            else
                local dev_tbl = InTbl(CAT[#CAT].list, dev_category)
                if fx_name then
                    if not dev_tbl then
                        table.insert(CAT[#CAT].list, { name = dev_category, fx = { fx_name } })
                    else
                        if not has_fx(dev_tbl, fx_name) then
                            table.insert(dev_tbl, fx_name)
                        end
                    end
                end
            end
        end
    end
end

local function ParseCustomCategories()
    local fav_path = r.GetResourcePath() .. "/reaper-fxfolders.ini"
    local fav_str  = GetFileContext(fav_path)
    local cur_cat_tbl
    for line in fav_str:gmatch('[^\r\n]+') do
        local category = line:match("%[(.-)%]")

        if category then
            if category == "category" then
                cur_cat_tbl = FindCategory(category:upper())
            elseif category == "developer" then
                cur_cat_tbl = FindCategory(category:upper())
            else
                cur_cat_tbl = nil
            end
        end

        if cur_cat_tbl then
            local FX, categories = line:match("(.+)=(.+)")
            if categories then
                local fx_name = FindFXIDName(VST_INFO, FX)
                fx_name = fx_name and fx_name or FindFXIDName(AU_INFO, FX)
                fx_name = fx_name and fx_name or FindFXIDName(CLAP_INFO, FX)
                fx_name = fx_name and fx_name or FindFXIDName(JS_INFO, FX, "JS")
                fx_name = fx_name and fx_name or FindFXIDName(LV2_INFO, FX)
                for category_type in categories:gmatch('([^+%-%|]+)') do
                    local dev_tbl = InTbl(cur_cat_tbl, category_type)
                    if fx_name then
                        if not dev_tbl then
                            table.insert(cur_cat_tbl, { name = category_type, fx = { fx_name } })
                        else
                            if not has_fx(dev_tbl, fx_name) then
                                table.insert(dev_tbl, fx_name)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function SortFoldersINI(fav_str)
    local folders = {}
    local add
    for line in fav_str:gmatch('[^\r\n]+') do
        local category = line:match("^%[(.-)%]")
        if category then
            if category:find("Folder", nil, true) then
                add = true
                folders[#folders + 1] = { name = category }
            else
                add = false
            end
            if settings then
                settings.last_left_section = "all"
                settings.last_left_value = ""
                if save_settings then save_settings() end
            end
        end
        if folders[#folders] and not category and add then
            folders[#folders][#folders[#folders] + 1] = line .. "\n"
        end
    end

    local main_folder
    for i = #folders, 1, -1 do
        table.sort(folders[i])
        table.insert(folders[i], 1, "[" .. folders[i].name .. "]\n")
        if folders[i].name == "Folders" then
            main_folder = table.remove(folders, i)
        end
    end
    folders[#folders + 1] = main_folder

    local sorted = ""
    for i = 1, #folders do
        folders[i].name = nil
        sorted = sorted .. table.concat(folders[i])
    end

    return sorted
end

local magic = {
    ["not"] = { ' and ', ' not %s:find("%s") ' },
    ["or"] = { ' or ', ' %s:find("%s") ' },
    ["and"] = { ' and ', '%s:find("%s") ' },
}

local function ParseSmartFolder(smart_string)
    local smart_terms = {}
    local SMART_FX = {}

    for exact in smart_string:gmatch('"(.-)"') do
        smart_string = smart_string:gsub('"' .. exact .. '"', '_schwa_magic_' .. exact:gsub(' ', '|||'))
    end

    smart_string = smart_string:gsub('"', '')

    for term in smart_string:gmatch("([^%s]+)") do
        term = term:lower():gsub('[%(%)%.%+%-%*%?%[%]%^%$%%]', '%%%1')
        if term:find('_schwa_magic_') then
            term = term:gsub('_schwa_magic_', '')
            if term:find('|||') then
                term = '(' .. term:gsub('|||', ' ') .. ')'
            else
                term = '%A' .. term .. '%A'
            end
        end
        smart_terms[#smart_terms + 1] = term
    end

    local code_gen = { "for i = 1, #PLUGIN_LIST do\nlocal target = PLUGIN_LIST[i]:lower()", "" }

    local add_magic
    for i = 1, #smart_terms do
        if magic[smart_terms[i]] then
            add_magic = i > 1 and (magic[smart_terms[i]][1] .. magic[smart_terms[i]][2]) or magic[smart_terms[i]][2]
        else
            if add_magic then
                code_gen[2] = code_gen[2] .. add_magic:format("target", smart_terms[i])
                add_magic = nil
            else
                code_gen[2] = i > 1 and code_gen[2] .. " and " .. (' %s:find("%s")'):format("target", smart_terms[i]) or
                    code_gen[2] .. (' %s:find("%s")'):format("target", smart_terms[i])
            end
        end
    end

    code_gen[2] = 'if ' .. code_gen[2] .. ' then'
    code_gen[#code_gen + 1] = 'SMART_FX[#SMART_FX+1] = PLUGIN_LIST[i]\nend\nend\n'

    local code_str = table.concat(code_gen, "\n")

    local func_env = {
        SMART_FX = SMART_FX,
        PLUGIN_LIST = PLUGIN_LIST,
        string = string,
    }

    local func, err = load(code_str, "ScriptRun", "t", func_env)

    if func then
        local status, err2 = pcall(func)
        if err2 then
            -- suppress console output
        end
    end
    return SMART_FX
end

local function ParseFavorites()
    local fav_path    = r.GetResourcePath() .. "/reaper-fxfolders.ini"
    local fav_str     = GetFileContext(fav_path)
    fav_str           = SortFoldersINI(fav_str)
    CAT[#CAT + 1]     = { name = "FOLDERS", list = {} }
    local item_lookup = {}
    local current_folder
    for line in fav_str:gmatch('[^\r\n]+') do
        local folder = line:match("^%[(Folder%d+)%]")

        if folder then current_folder = folder end

        if line:match("Item%d+") then
            local item_id, item_path = line:match("Item(%d+)=(.+)")
            local item = "R_ITEM_" .. item_path
            item_lookup[item_id] = item_path
            local dev_tbl = InTbl(CAT[#CAT].list, current_folder)
            if not dev_tbl then
                table.insert(CAT[#CAT].list,
                    { name = current_folder, fx = { item }, order = current_folder:match("Folder(%d+)") })
            else
                table.insert(dev_tbl, item)
            end
        end

        if line:match("Type%d+") then
            local line_id, fx_type = line:match("(%d+)=(%d+)")
            local folder_item = item_lookup[line_id]
            if folder_item then
                local item = folder_item:gsub("R_ITEM_", "", 1)
                local fx_found
                if fx_type == "3" then -- VST
                    local id = os:match("Win") and item:reverse():match("(.-)\\") or item:reverse():match("(.-)/")
                    if id then
                        id = id:reverse():gsub(" ", "_"):gsub("-", "_")
                        fx_found = FindFXIDName(VST_INFO, id)
                    end
                elseif fx_type == "2" then -- JSFX
                    fx_found = FindFXIDName(JS_INFO, item)
                elseif fx_type == "7" then -- CLAP
                    fx_found = FindFXIDName(CLAP_INFO, item)
                elseif fx_type == "1" then -- LV2
                    fx_found = FindFXIDName(LV2_INFO, item)
                elseif fx_type == "5" then -- AU
                    fx_found = FindFXIDName(AU_INFO, item)
                elseif fx_type == "1048576" then -- SMART FOLDER
                    CAT[#CAT].list[#CAT[#CAT].list].smart = true
                    CAT[#CAT].list[#CAT[#CAT].list].fx = ParseSmartFolder(item)
                elseif fx_type == "1000" then -- FX CHAIN
                    table.insert(CAT[#CAT].list[#CAT[#CAT].list].fx, item .. ".RfxChain")
                end
                if fx_found then
                    table.insert(CAT[#CAT].list[#CAT[#CAT].list].fx, fx_found)
                end
            end
        end

        if line:match("Name%d+=(.+)") then
            local folder_name = line:match("Name%d+=(.+)")
            local folder_ID = line:match("(%d+)=")

            for i = 1, #CAT[#CAT].list do
                if CAT[#CAT].list[i].name == "Folder" .. folder_ID then
                    CAT[#CAT].list[i].name = folder_name
                end
            end
        end
    end

    table.sort(CAT[#CAT].list, function(a, b) return tonumber(a.order) < tonumber(b.order) end)

    for i = 1, #CAT do
        for j = #CAT[i].list, 1, -1 do
            if CAT[i].list[j] then
                for f = #CAT[i].list[j].fx, 1, -1 do
                    if CAT[i].list[j].fx[f]:find("R_ITEM_") then
                        table.remove(CAT[i].list[j].fx, f)
                    end
                end
            end
        end
    end
end

local function ParseFXChains()
    local fxChainsFolder = r.GetResourcePath() .. "/FXChains"
    local FX_CHAINS = {}
    GetDirFilesRecursive(fxChainsFolder, FX_CHAINS, ".RfxChain")
    return FX_CHAINS
end

local function ParseTrackTemplates()
    local trackTemplatesFolder = r.GetResourcePath() .. "/TrackTemplates"
    local TRACK_TEMPLATES = {}
    GetDirFilesRecursive(trackTemplatesFolder, TRACK_TEMPLATES, ".RTrackTemplate")
    return TRACK_TEMPLATES
end

local function AllPluginsCategory()
    CAT[#CAT + 1] = { name = "ALL PLUGINS", list = {} }
    if #JS ~= 0 then table.insert(CAT[#CAT].list, { name = "JS", fx = JS }) end
    if #AU ~= 0 then table.insert(CAT[#CAT].list, { name = "AU", fx = AU }) end
    if #AUi ~= 0 then table.insert(CAT[#CAT].list, { name = "AUi", fx = AUi }) end
    if #CLAP ~= 0 then table.insert(CAT[#CAT].list, { name = "CLAP", fx = CLAP }) end
    if #CLAPi ~= 0 then table.insert(CAT[#CAT].list, { name = "CLAPi", fx = CLAPi }) end
    if #VST ~= 0 then table.insert(CAT[#CAT].list, { name = "VST", fx = VST }) end
    if #VSTi ~= 0 then table.insert(CAT[#CAT].list, { name = "VSTi", fx = VSTi }) end
    if #VST3 ~= 0 then table.insert(CAT[#CAT].list, { name = "VST3", fx = VST3 }) end
    if #VST3i ~= 0 then table.insert(CAT[#CAT].list, { name = "VST3i", fx = VST3i }) end
    if #LV2 ~= 0 then table.insert(CAT[#CAT].list, { name = "LV2", fx = LV2 }) end
    if #LV2i ~= 0 then table.insert(CAT[#CAT].list, { name = "LV2i", fx = LV2i }) end
    if #INSTRUMENTS ~= 0 then table.insert(CAT[#CAT].list, { name = "INSTRUMENTS", fx = INSTRUMENTS }) end

    for i = 1, #CAT do
        if CAT[i].name ~= "FOLDERS" and CAT[i].name ~= "FX CHAINS" and CAT[i].name ~= "TRACK TEMPLATES" then
            table.sort(CAT[i].list,
                function(a, b) if a.name and b.name then return a.name:lower() < b.name:lower() end end)
        end
        for j = 1, #CAT[i].list do
            if CAT[i].list[j].fx then
                table.sort(CAT[i].list[j].fx, function(a, b) if a and b then return a:lower() < b:lower() end end)
            end
        end
    end

    table.sort(CAT, function(a, b) if a.name and b.name then return a.name:lower() < b.name:lower() end end)
end

function GenerateFxList()
    PLUGIN_LIST[#PLUGIN_LIST + 1] = "Container"
    PLUGIN_LIST[#PLUGIN_LIST + 1] = "Video processor"

    for i = 0, math.huge do
        local retval, name, ident = r.EnumInstalledFX(i)
        if not retval then break end
        ParseVST(name, ident)
        ParseJSFX(name, ident)
        ParseAU(name, ident)
        ParseCLAP(name, ident)
        ParseLV2(name, ident)
    end

    ParseFXTags() -- CATEGORIES
    ParseCustomCategories()
    ParseFavorites()
    local FX_CHAINS = ParseFXChains()
    if #FX_CHAINS ~= 0 then
        CAT[#CAT + 1] = { name = "FX CHAINS", list = FX_CHAINS }
    end
    local TRACK_TEMPLATES = ParseTrackTemplates()
    if #TRACK_TEMPLATES ~= 0 then
        CAT[#CAT + 1] = { name = "TRACK TEMPLATES", list = TRACK_TEMPLATES }
    end
    AllPluginsCategory()

    return PLUGIN_LIST
end

local sub = string.sub
function Stripname(name, prefix, suffix)
    if not DEVELOPER_LIST then return name end
    if suffix then
        for i = 1, #DEVELOPER_LIST do
            local ss, se = name:find(DEVELOPER_LIST[i], nil, true)
            if ss then
                name = sub(name, 0, ss)
                break
            end
        end
    end
    if prefix then
        local ps, pe = name:find("(%S+: )")
        if ps then
            name = sub(name, pe)
        end
    end
    return name
end

function GetFXTbl()
    ResetTables()
    return GenerateFxList(), CAT, DEVELOPER_LIST
end

function UpdateChainsTrackTemplates(cat_tbl)
    if not cat_tbl then return end
    local FX_CHAINS = ParseFXChains()
    local TRACK_TEMPLATES = ParseTrackTemplates()
    local chain_found, template_found
    for i = 1, #cat_tbl do
        if cat_tbl[i].name == "FX CHAINS" then
            cat_tbl[i].list = FX_CHAINS
            chain_found = true
        end
        if cat_tbl[i].name == "TRACK TEMPLATES" then
            cat_tbl[i].list = TRACK_TEMPLATES
            template_found = true
        end
    end
    if not chain_found then
        cat_tbl[#cat_tbl + 1] = { name = "FX CHAINS", list = FX_CHAINS }
    end
    if not template_found then
        cat_tbl[#cat_tbl + 1] = { name = "TRACK TEMPLATES", list = TRACK_TEMPLATES }
    end
end

--------------------------------------------------------------------------
-- END: Integrated Sexan FX Browser Parser V7
--------------------------------------------------------------------------


local ctx = reaper.ImGui_CreateContext("7R FX Inserter")
local font = reaper.ImGui_CreateFont('sans-serif', 14)
local bold_font = nil -- Bold font not available in this ReaImGui build
reaper.ImGui_Attach(ctx, font)

-- GLOBAL VARIABLES
local window_open = true
local selected_fx_idx = 1
local left_selection = { section = "all", index = 0 }
local settings_window_open = false

-- Search and keyboard navigation
local search_text = ""
local highlighted_fx_index = 1
local arrow_key_pressed = false

-- The parser code above declares and populates these tables.
-- local CAT, DEVELOPER_LIST, PLUGIN_LIST

local target_track = nil
local target_item = nil
local insert_mode = "track" -- "track", "item", or "master"
local target_info = ""

settings = settings or {}
settings.auto_close_on_insert = settings.auto_close_on_insert ~= nil and settings.auto_close_on_insert or true
settings.hide_vst2_duplicates = settings.hide_vst2_duplicates ~= nil and settings.hide_vst2_duplicates or true   -- Hide VST2 if VST3 version exists
settings.search_all_folders   = settings.search_all_folders   ~= nil and settings.search_all_folders   or false  -- Placeholder for future search behavior
settings.fx_window_mode       = settings.fx_window_mode       ~= nil and settings.fx_window_mode       or 1      -- 0 = No window, 1 = FX window (float), 2 = Chain window
settings.window_x             = settings.window_x             ~= nil and settings.window_x             or -1
settings.window_y             = settings.window_y             ~= nil and settings.window_y             or -1
settings.window_width         = settings.window_width         ~= nil and settings.window_width         or 800
settings.window_height        = settings.window_height        ~= nil and settings.window_height        or 600
settings.last_left_section    = settings.last_left_section    ~= nil and settings.last_left_section    or "all"  -- "all" | "folder" | "dev"
settings.last_left_value      = settings.last_left_value      ~= nil and settings.last_left_value      or ""     -- Folder name or developer name

-- Settings persistence helpers
local function get_settings_file_path()
  local resource_path = reaper.GetResourcePath()
  return resource_path .. "/FX_Inserter_settings_v7.lua"
end

local function save_settings()
  local path = get_settings_file_path()
  local f = io.open(path, "w")
  if f then
    f:write("-- FX Inserter Settings (Self-Contained Parser Edition)\n")
    f:write("return {\n")
    f:write("  hide_vst2_duplicates = " .. tostring(settings.hide_vst2_duplicates) .. ",\n")
    f:write("  auto_close_on_insert = " .. tostring(settings.auto_close_on_insert) .. ",\n")
    f:write("  search_all_folders = " .. tostring(settings.search_all_folders) .. ",\n")
    f:write("  fx_window_mode = " .. tostring(settings.fx_window_mode) .. ",\n")
    f:write("  window_x = " .. tostring(settings.window_x) .. ",\n")
    f:write("  window_y = " .. tostring(settings.window_y) .. ",\n")
    f:write("  window_width = " .. tostring(settings.window_width) .. ",\n")
    f:write("  window_height = " .. tostring(settings.window_height) .. ",\n")
    f:write("  last_left_section = " .. string.format("%q", settings.last_left_section or "all") .. ",\n")
    f:write("  last_left_value = " .. string.format("%q", settings.last_left_value or "") .. "\n")
    f:write("}\n")
    f:close()
  end
end

local function load_settings()
  local path = get_settings_file_path()
  local file = io.open(path, "r")
  if not file then return end
  local content = file:read("*all")
  file:close()
  local loader = load or loadstring
  local ok, tbl = pcall(loader(content))
  if ok and type(tbl) == "table" then
    if tbl.hide_vst2_duplicates ~= nil then settings.hide_vst2_duplicates = tbl.hide_vst2_duplicates end
    if tbl.auto_close_on_insert ~= nil then settings.auto_close_on_insert = tbl.auto_close_on_insert end
    if tbl.search_all_folders ~= nil then settings.search_all_folders = tbl.search_all_folders end
    if tbl.fx_window_mode ~= nil then settings.fx_window_mode = tbl.fx_window_mode end
    if tbl.window_x ~= nil then settings.window_x = tbl.window_x end
    if tbl.window_y ~= nil then settings.window_y = tbl.window_y end
    if tbl.window_width ~= nil then settings.window_width = tbl.window_width end
    if tbl.window_height ~= nil then settings.window_height = tbl.window_height end
    if tbl.last_left_section ~= nil then settings.last_left_section = tbl.last_left_section end
    if tbl.last_left_value ~= nil then settings.last_left_value = tbl.last_left_value end
  end
end

local function save_window_state()
  local x, y = reaper.ImGui_GetWindowPos(ctx)
  local w, h = reaper.ImGui_GetWindowSize(ctx)
  if x and y and w and h then
    local changed = false
    if settings.window_x ~= x then settings.window_x = x; changed = true end
    if settings.window_y ~= y then settings.window_y = y; changed = true end
    if settings.window_width ~= w then settings.window_width = w; changed = true end
    if settings.window_height ~= h then settings.window_height = h; changed = true end
    if changed then save_settings() end
  end
end

------------------------------------------------------
-- TARGET DETECTION & FX INSERTION
------------------------------------------------------

local function detect_and_set_target()
  local mouse_x, mouse_y = reaper.GetMousePosition()
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

local function insert_fx(fx_name)
    if not fx_name then return false end

    local fx_to_add = fx_name
    -- Handle FX Chains and Track Templates paths
    if fx_name:match("%.RfxChain$") then
        fx_to_add = reaper.GetResourcePath() .. '/FXChains/' .. fx_name
    elseif fx_name:match("%.RTrackTemplate$") then
        reaper.Main_openProject(reaper.GetResourcePath() .. '/TrackTemplates/' .. fx_name)
        return true -- Track templates open as new tracks
    end

    local fx_index = -1
    if insert_mode == "track" and target_track then
        fx_index = reaper.TrackFX_AddByName(target_track, fx_to_add, false, -1)
    elseif insert_mode == "master" and target_track then
        fx_index = reaper.TrackFX_AddByName(target_track, fx_to_add, false, -1)
    elseif insert_mode == "item" and target_item then
        local take = reaper.GetActiveTake(target_item)
        if take then
            fx_index = reaper.TakeFX_AddByName(take, fx_to_add, -1)
        end
    end

    if fx_index > -1 then
        if settings.fx_window_mode == 1 then
            if insert_mode == "item" then
                reaper.TakeFX_Show(reaper.GetActiveTake(target_item), fx_index, 3)
            else
                reaper.TrackFX_Show(target_track, fx_index, 3)
            end
        elseif settings.fx_window_mode == 2 then
            if insert_mode == "item" then
                reaper.TakeFX_Show(reaper.GetActiveTake(target_item), fx_index, 1)
            else
                reaper.TrackFX_Show(target_track, fx_index, 1)
            end
        end
        return true
    end
    return false
end

------------------------------------------------------
-- GUI FUNCTIONS (Two-pane layout)
------------------------------------------------------

local function draw_main_gui()
    -- Restore window position and size on first open
    if settings.window_x >= 0 and settings.window_y >= 0 then
        reaper.ImGui_SetNextWindowPos(ctx, settings.window_x, settings.window_y, reaper.ImGui_Cond_FirstUseEver())
    end
    if settings.window_width > 0 and settings.window_height > 0 then
        reaper.ImGui_SetNextWindowSize(ctx, settings.window_width, settings.window_height, reaper.ImGui_Cond_FirstUseEver())
    end

    -- Disable default keyboard navigation; rely on custom keys for the FX list
    local window_flags = reaper.ImGui_WindowFlags_NoNavInputs() | reaper.ImGui_WindowFlags_NoNavFocus()
    local visible, open = reaper.ImGui_Begin(ctx, "7R FX Inserter", true, window_flags)
    if not visible then
        reaper.ImGui_End(ctx)
        return open
    end

    -- Top bar: Search + Settings
    reaper.ImGui_SetNextItemWidth(ctx, reaper.ImGui_GetContentRegionAvail(ctx) - 100)
    if reaper.ImGui_IsWindowAppearing(ctx) then
        reaper.ImGui_SetKeyboardFocusHere(ctx)
    end
    local changed_search, new_search = reaper.ImGui_InputTextWithHint(ctx, "##search", "Search FX...", search_text)
    if changed_search then
        search_text = new_search
        highlighted_fx_index = 1
        arrow_key_pressed = false
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Settings", 90, 0) then
        settings_window_open = true
    end
    reaper.ImGui_Separator(ctx)

    local left_width = math.floor(reaper.ImGui_GetWindowWidth(ctx) * 0.33)

    -- LEFT PANE
    if reaper.ImGui_BeginChild(ctx, "LeftPane", left_width, -30, 0) then
        -- User Folders
        if bold_font then reaper.ImGui_PushFont(ctx, bold_font, 14) end
        reaper.ImGui_Text(ctx, "User Folders")
        if bold_font then reaper.ImGui_PopFont(ctx) end
        local folders_cat
        for i = 1, #CAT do
            if CAT[i].name == "FOLDERS" then
                folders_cat = CAT[i]
                break
            end
        end
        if folders_cat and folders_cat.list then
            for i, folder in ipairs(folders_cat.list) do
                local fname = folder.name or ("Folder " .. i)
                local selected = (left_selection.section == "folder" and left_selection.index == i)
                    if reaper.ImGui_Selectable(ctx, fname .. "##FOLDER" .. i, selected) then
                    left_selection.section = "folder"
                    left_selection.index = i
                    settings.last_left_section = "folder"
                    settings.last_left_value = fname
                    save_settings()
                end
            end
        else
            reaper.ImGui_TextDisabled(ctx, "(No custom folders)")
        end

        reaper.ImGui_Separator(ctx)

        -- ALL FX (single entry)
        local all_selected = (left_selection.section == "all")
        if reaper.ImGui_Selectable(ctx, "ALL FX##ALL", all_selected) then
            left_selection.section = "all"
            left_selection.index = 0
        end

        reaper.ImGui_Separator(ctx)

        -- Developers
        if bold_font then reaper.ImGui_PushFont(ctx, bold_font, 14) end
        reaper.ImGui_Text(ctx, "Developers")
        if bold_font then reaper.ImGui_PopFont(ctx) end
        if #DEVELOPER_LIST > 0 then
            for i, dev in ipairs(DEVELOPER_LIST) do
                local dev_name = dev:match("%((.-)%)") or dev
                local selected = (left_selection.section == "dev" and left_selection.index == i)
                        if reaper.ImGui_Selectable(ctx, dev_name .. "##DEV" .. i, selected) then
                    left_selection.section = "dev"
                    left_selection.index = i
                    settings.last_left_section = "dev"
                    settings.last_left_value = dev_name
                    save_settings()
                end
            end
        else
            reaper.ImGui_TextDisabled(ctx, "(No developers)")
        end

        reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_SameLine(ctx)

    -- RIGHT PANE (FX list)
    if reaper.ImGui_BeginChild(ctx, "RightPane", 0, -30, 0) then
        local fx_list = nil

        if left_selection.section == "all" then
            fx_list = PLUGIN_LIST

        elseif left_selection.section == "folder" then
            local folders_cat
            for i = 1, #CAT do
                if CAT[i].name == "FOLDERS" then
                    folders_cat = CAT[i]
                    break
                end
            end
            if folders_cat and folders_cat.list and folders_cat.list[left_selection.index] then
                fx_list = folders_cat.list[left_selection.index].fx
            end

        elseif left_selection.section == "dev" then
            fx_list = {}
            local tag = DEVELOPER_LIST[left_selection.index]
            if tag then
                for i = 1, #PLUGIN_LIST do
                    if PLUGIN_LIST[i]:find(tag, 1, true) then
                        fx_list[#fx_list + 1] = PLUGIN_LIST[i]
                    end
                end
            end
        end

        -- Build display rows: label (no extension), original name, tooltip (path+extension where applicable)
        local rows = {}
        -- Choose base list depending on search scope
        local base_list = fx_list
        if search_text ~= "" and settings.search_all_folders then
            base_list = PLUGIN_LIST
        end

        if base_list and #base_list > 0 then
            -- Build a map of VST3 base names to filter out VST2 duplicates when enabled
            local vst3_basenames = {}
            if settings.hide_vst2_duplicates then
                for _, name in ipairs(base_list) do
                    if type(name) == "string" and name:match("^VST3i?%s*:") then
                        local base = name:gsub("^%s*[%w_]+%s*:%s*", ""):lower()
                        vst3_basenames[base] = true
                    end
                end
            end

            local search_lower = search_text:lower()
            for _, fx_name in ipairs(base_list) do
                if type(fx_name) == "table" then
                    -- Do not include directories when searching; show only as context when no search
                    if search_text == "" then
                        rows[#rows + 1] = { label = fx_name.dir and (fx_name.dir .. "/") or "(Folder)", original = nil, tooltip = nil, is_folder = true }
                    end
                else
                    -- Skip VST2 if a VST3 version exists (when enabled)
                    local skip = false
                    if settings.hide_vst2_duplicates and fx_name:match("^VSTi?%s*:") then
                        local base = fx_name:gsub("^%s*[%w_]+%s*:%s*", ""):lower()
                        if vst3_basenames[base] then
                            skip = true
                        end
                    end

                    if not skip then
                        local label = fx_name
                        local tooltip = nil

                        -- File-based entries: strip extension for label and compute tooltip with full path
                        if fx_name:match("%.RfxChain$") or fx_name:match("%.RTrackTemplate$") or fx_name:find("[/\\]") then
                            local basename = fx_name:match("([^/\\]+)$") or fx_name
                            label = basename:gsub("%.[^%.]+$", "")
                            if fx_name:match("%.RfxChain$") then
                                tooltip = "FX Chain: " .. (reaper.GetResourcePath() .. "/FXChains/" .. fx_name)
                            elseif fx_name:match("%.RTrackTemplate$") then
                                tooltip = "Track Template: " .. (reaper.GetResourcePath() .. "/TrackTemplates/" .. fx_name)
                            else
                                tooltip = fx_name
                            end
                        else
                            -- Not a file-based entry: strip plugin type prefixes like "VST3:", "VST:", "JS:", "AU:", etc.
                            label = label:gsub("^%s*[%w_]+%s*:%s*", "")
                            tooltip = fx_name
                        end

                        -- Apply filtering if searching
                        local include = true
                        if search_text ~= "" then
                            include = (label:lower():find(search_lower, 1, true) ~= nil)
                                or (fx_name:lower():find(search_lower, 1, true) ~= nil)
                        end

                        if include then
                            rows[#rows + 1] = { label = label, original = fx_name, tooltip = tooltip }
                        end
                    end
                end
            end

            -- Sort rows alphabetically by label (case-insensitive), keep folder markers in order
            table.sort(rows, function(a, b)
                if a.is_folder ~= b.is_folder then
                    return (a.is_folder and true) or false
                end
                return (a.label or ""):lower() < (b.label or ""):lower()
            end)

            -- Clamp highlighted index
            if #rows == 0 then
                highlighted_fx_index = 1
            else
                if highlighted_fx_index < 1 then highlighted_fx_index = 1 end
                if highlighted_fx_index > #rows then highlighted_fx_index = #rows end
            end

            -- Render rows
            for idx, row in ipairs(rows) do
                if row.is_folder then
                    reaper.ImGui_TextDisabled(ctx, row.label)
                else
                    -- Unique ID suffix based on original full name to avoid ID collisions
                    local unique_label = row.label
                    if row.original and row.original ~= "" then
                        unique_label = row.label .. "##" .. row.original
                    end
                    local is_selected = (idx == highlighted_fx_index)
                    if reaper.ImGui_Selectable(ctx, unique_label, is_selected) then
                        highlighted_fx_index = idx
                        arrow_key_pressed = true
                        if insert_fx(row.original) and settings.auto_close_on_insert then
                            open = false
                        end
                    end
                    if reaper.ImGui_IsItemHovered(ctx) and row.tooltip and row.tooltip ~= "" then
                        reaper.ImGui_SetTooltip(ctx, row.tooltip)
                    end
                end
            end

            -- Keyboard navigation
            if #rows > 0 then
                if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()) then
                    highlighted_fx_index = highlighted_fx_index - 1
                    if highlighted_fx_index < 1 then highlighted_fx_index = #rows end
                    arrow_key_pressed = true
                elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()) then
                    highlighted_fx_index = highlighted_fx_index + 1
                    if highlighted_fx_index > #rows then highlighted_fx_index = 1 end
                    arrow_key_pressed = true
                end
                if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Enter()) then
                    local insert_idx = arrow_key_pressed and highlighted_fx_index or 1
                    local target = rows[insert_idx]
                    if target and target.original then
                        if insert_fx(target.original) and settings.auto_close_on_insert then
                            open = false
                        end
                    end
                    arrow_key_pressed = false
                end
            end
        else
            reaper.ImGui_TextDisabled(ctx, "(No FX to display)")
        end

        reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Text(ctx, "Target: " .. target_info)

    -- Persist window position and size changes
    save_window_state()

    reaper.ImGui_End(ctx)
    return open
end

local function draw_settings_window()
    if not settings_window_open then return end
    local window_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize()
    local visible, open = reaper.ImGui_Begin(ctx, "FX Inserter Settings", true, window_flags)
    if visible then
        -- Hide VST2 duplicates
        local changed, new_val = reaper.ImGui_Checkbox(ctx, "Hide VST2 if VST3 is present", settings.hide_vst2_duplicates)
        if changed then
            settings.hide_vst2_duplicates = new_val
            save_settings()
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "When enabled, VST2 plugins are hidden if a VST3 version of the same plugin exists")
        end

        reaper.ImGui_Spacing(ctx)

        -- Auto close on insert
        local changed2, new_val2 = reaper.ImGui_Checkbox(ctx, "Autoclose window after FX insertion", settings.auto_close_on_insert)
        if changed2 then
            settings.auto_close_on_insert = new_val2
            save_settings()
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Close the browser automatically after inserting an FX")
        end

        reaper.ImGui_Spacing(ctx)

        -- Search all folders toggle (behavior to be implemented later)
        local changed3, new_val3 = reaper.ImGui_Checkbox(ctx, "Search all folders when using search", settings.search_all_folders)
        if changed3 then
            settings.search_all_folders = new_val3
            save_settings()
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "When enabled, search will consider all folders (to be implemented)")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- FX window mode
        reaper.ImGui_Text(ctx, "FX window mode:")
        local fx_window_options = "No window\0FX window\0FX chain\0"
        reaper.ImGui_SetNextItemWidth(ctx, 200)
        local changed4, new_selection = reaper.ImGui_Combo(ctx, "##fx_window_mode", settings.fx_window_mode, fx_window_options)
        if changed4 then
            settings.fx_window_mode = new_selection
            save_settings()
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            local tip = "Choose how FX windows are shown after insertion:\n" ..
                        "• No window: insert only, do not open any window\n" ..
                        "• FX window: open the FX in a floating window\n" ..
                        "• FX chain: show the FX chain window"
            reaper.ImGui_SetTooltip(ctx, tip)
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        if reaper.ImGui_Button(ctx, "Close", 100, 26) then
            settings_window_open = false
        end

        reaper.ImGui_End(ctx)
    end
    if not open then settings_window_open = false end
end

------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------

local function init()
    -- Load persisted settings first
    load_settings()

    detect_and_set_target()

    -- Use parser's caching mechanism
    local fx_list_test, cat_test, dev_list_test = ReadFXFile()
    if not fx_list_test or #fx_list_test == 0 or not cat_test or #cat_test == 0 then
      PLUGIN_LIST, CAT, DEVELOPER_LIST = MakeFXFiles()
  else
      PLUGIN_LIST, CAT, DEVELOPER_LIST = fx_list_test, cat_test, dev_list_test
    end

    -- Sort developer list alphabetically by display name
    if DEVELOPER_LIST and #DEVELOPER_LIST > 1 then
        table.sort(DEVELOPER_LIST, function(a, b)
            local aa = (a and a:match("%((.-)%)") or a or ""):lower()
            local bb = (b and b:match("%((.-)%)") or b or ""):lower()
            return aa < bb
        end)
    end

  -- Restore last selection
  if settings.last_left_section == "folder" and settings.last_left_value and settings.last_left_value ~= "" then
      local folders_cat
      for i = 1, #CAT do
          if CAT[i].name == "FOLDERS" then
              folders_cat = CAT[i]
              break
          end
      end
      if folders_cat and folders_cat.list then
          for i, folder in ipairs(folders_cat.list) do
              local fname = folder.name or ("Folder " .. i)
              if fname == settings.last_left_value then
                  left_selection.section = "folder"
                  left_selection.index = i
                  break
              end
          end
      end
  elseif settings.last_left_section == "dev" and settings.last_left_value and settings.last_left_value ~= "" then
      for i, dev in ipairs(DEVELOPER_LIST) do
          local dev_name = dev:match("%((.-)%)") or dev
          if dev_name == settings.last_left_value or dev == settings.last_left_value then
              left_selection.section = "dev"
              left_selection.index = i
              break
          end
      end
  else
      left_selection.section = "all"
      left_selection.index = 0
  end
end

local function main_loop()
    if not window_open then return end

    reaper.ImGui_PushFont(ctx, font, 14)
    local gui_open = draw_main_gui()
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
