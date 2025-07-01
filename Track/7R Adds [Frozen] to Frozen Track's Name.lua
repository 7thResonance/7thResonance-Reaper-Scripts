--[[
@description 7R Adds [Frozen] to Frozen Track's Name
@author 7thResonance
@version 1.0
@changelog initial
@about Adds " [Frozen]" to Frozen Track's Name. Removes it when unfrozen. SWS is needed.
--]]

-- Function to check if a string ends with a specific suffix
function string.ends(String, End)
   return End == '' or string.sub(String, -string.len(End)) == End
end

-- Function to process tracks and update names
function process_tracks()
    local track_count = reaper.CountTracks(0)
    
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        if track then
            local _, track_name = reaper.GetTrackName(track)
            local freeze_count = reaper.BR_GetMediaTrackFreezeCount and reaper.BR_GetMediaTrackFreezeCount(track) or 0
            local is_frozen = freeze_count > 0
            
            -- If track is frozen and doesn't have the tag
            if is_frozen and not string.ends(track_name, " [Frozen]") then
                local new_name = track_name .. " [Frozen]"
                reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
            -- If track is not frozen but has the tag
            elseif not is_frozen and string.ends(track_name, " [Frozen]") then
                local new_name = string.sub(track_name, 1, -10) -- Remove " [Frozen]"
                reaper.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
            end
        end
    end
end

-- Function to get project state change count
function get_project_change_count()
    return reaper.GetProjectStateChangeCount(0)
end

-- Main function to monitor track states
function main()
    local last_change_count = get_project_change_count()
    local function check()
        local current_change_count = get_project_change_count()
        if current_change_count ~= last_change_count then
            process_tracks()
            last_change_count = current_change_count
        end
        reaper.defer(check)
    end
    check()
end

-- Manual trigger function for testing
function manual_trigger()
    process_tracks()
end

-- Start the script if SWS is available
if reaper.BR_GetMediaTrackFreezeCount then
    main()
end