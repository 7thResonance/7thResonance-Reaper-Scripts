--@description 7R Freeze Instruments to Stereo (Other FX Online)
--@author 7thResonance
--@version 1.0
--@changelog Initial
--@about Freezes Selected tracks. up to Instrument, Other FX are brough online after freezing.

-- Lua Script for Reaper: Offline non-instrument FX, Freeze Selected Tracks to Stereo, Unlock All Items Directly, Online Remaining FX

-- Main function
local function main()
    -- Get all selected tracks into a table
    local selected_tracks = {}
    local track_count = reaper.CountSelectedTracks(0)
    if track_count == 0 then
        reaper.ShowConsoleMsg("No tracks selected! Please select at least one track.\n")
        return
    end

    -- Collect all selected tracks
    for track_idx = 0, track_count - 1 do
        local track = reaper.GetSelectedTrack(0, track_idx)
        if track then
            table.insert(selected_tracks, track)
        else
            reaper.ShowConsoleMsg("Warning: Could not retrieve track at index " .. track_idx .. "\n")
        end
    end

    if #selected_tracks == 0 then
        reaper.ShowConsoleMsg("Error: No valid selected tracks found.\n")
        return
    end

    -- Store original track selection for restoration
    local original_selection = {}
    for _, track in ipairs(selected_tracks) do
        table.insert(original_selection, track)
    end

    -- Step 1: Offline non-instrument FX for all selected tracks
    for i, track in ipairs(selected_tracks) do
        local fx_count = reaper.TrackFX_GetCount(track)
        if fx_count < 0 then
            reaper.ShowConsoleMsg("Error: Invalid FX count for track " .. i .. "\n")
            goto continue_offline
        end
        
        -- Get the index of the instrument FX (if any)
        local instrument_idx = reaper.TrackFX_GetInstrument(track)
        
        -- Offline non-instrument FX
        for fx_idx = 0, fx_count - 1 do
            if fx_idx ~= instrument_idx then
                reaper.TrackFX_SetOffline(track, fx_idx, true)
            end
        end
        ::continue_offline::
    end

    -- Step 2: Freeze all selected tracks to stereo in one batch
    -- Ensure all tracks are selected
    reaper.Main_OnCommand(40289, 0) -- Unselect all tracks
    for _, track in ipairs(selected_tracks) do
        reaper.SetTrackSelected(track, true)
        reaper.SetMediaTrackInfo_Value(track, "I_NCHAN", 2) -- Set to stereo
    end
    
    -- Freeze selected tracks to stereo
    reaper.Main_OnCommand(41223, 0) -- Freeze selected tracks to stereo

    -- Step 3: Unlock all items on frozen tracks
    for i, track in ipairs(selected_tracks) do
        local item_count = reaper.CountTrackMediaItems(track)
        local locked_count = 0
        
        -- Count locked items before unlocking (debug)
        for item_idx = 0, item_count - 1 do
            local item = reaper.GetTrackMediaItem(track, item_idx)
            if item and reaper.GetMediaItemInfo_Value(item, "C_LOCK") == 1 then
                locked_count = locked_count + 1
            end
        end
        
        -- Unlock all items directly
        for item_idx = 0, item_count - 1 do
            local item = reaper.GetTrackMediaItem(track, item_idx)
            if item then
                reaper.SetMediaItemInfo_Value(item, "C_LOCK", 0)
            else
                reaper.ShowConsoleMsg("Warning: Could not retrieve item at index " .. item_idx .. " on track " .. i .. "\n")
            end
        end
        
        -- Verify lock state of all items (debug)
        local remaining_locked = 0
        for item_idx = 0, item_count - 1 do
            local item = reaper.GetTrackMediaItem(track, item_idx)
            if item then
                local is_locked = reaper.GetMediaItemInfo_Value(item, "C_LOCK")
            end
        end
    end

    -- Step 4: Online all FX for all selected tracks
    for i, track in ipairs(selected_tracks) do
        local fx_count = reaper.TrackFX_GetCount(track)
        for fx_idx = 0, fx_count - 1 do
            reaper.TrackFX_SetOffline(track, fx_idx, false)
        end
    end

    -- Restore original track selection
    reaper.Main_OnCommand(40289, 0) -- Unselect all tracks
    for _, track in ipairs(original_selection) do
        reaper.SetTrackSelected(track, true)
    end

    -- Update the UI
    reaper.UpdateArrange()
    reaper.UpdateTimeline()

end

-- Run the script with undo block
reaper.Undo_BeginBlock()
main()
reaper.Undo_EndBlock("Freeze Selected Tracks with Non-Instrument FX Handling", -1)
