--[[
@description 7R Adds/Removes [Frozen] to Frozen Track's Name based on Undo History
@author 7thResonance
@version 1.1
@donation https://paypal.me/7thresonance
@changelog Reacts to Undo History: adds [Frozen] when tracks are frozen, removes it when unfrozen. SWS required.
@about Automatically appends or removes " [Frozen]" in track names when freeze/unfreeze actions are detected in the undo history.
--]]

-- Check if string ends with given suffix
function string.ends(String, End)
   return End == '' or string.sub(String, -string.len(End)) == End
end

-- Get current undo description
---@diagnostic disable-next-line: lowercase-global
function get_undo_desc()
    local desc = reaper.Undo_CanUndo2(0)
    if not desc then desc = "" end
    return desc:lower()
end

-- Returns true if any track is currently frozen
function track_is_frozen(track)
    return reaper.BR_GetMediaTrackFreezeCount and reaper.BR_GetMediaTrackFreezeCount(track) > 0
end

-- Appends [Frozen] to frozen tracks' names if not already present
function tag_frozen_tracks()
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count-1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetTrackName(track)
        if track_is_frozen(track) and not string.ends(track_name, " [Frozen]") then
            local new_name = track_name .. " [Frozen]"
            reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
        end
    end
end

-- Removes [Frozen] from unfrozen tracks' names if present
function untag_unfrozen_tracks()
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count-1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetTrackName(track)
        if not track_is_frozen(track) and string.ends(track_name, " [Frozen]") then
            local new_name = string.sub(track_name, 1, -10)
            reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
        end
    end
end

-- Main state
local last_undo_desc = get_undo_desc()

---@diagnostic disable-next-line: lowercase-global
function main()
    local now_undo_desc = get_undo_desc()
    if now_undo_desc ~= last_undo_desc then
        -- Check for "freeze" or "unfreeze" (case-insensitive)
        if now_undo_desc:find("freeze") and not now_undo_desc:find("unfreeze") then
            tag_frozen_tracks()
        elseif now_undo_desc:find("unfreeze") then
            untag_unfrozen_tracks()
        end
        last_undo_desc = now_undo_desc
    end
    reaper.defer(main)
end

-- SWS required for freeze state
if reaper.BR_GetMediaTrackFreezeCount then
    main()
else
    reaper.ShowMessageBox("SWS extension is required for this script to work.", "Missing SWS", 0)
end