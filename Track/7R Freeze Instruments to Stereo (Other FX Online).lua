--@description 7R Freeze Instruments to Stereo (Other FX Online)
--@author 7thResonance
--@version 1.1
--@changelog -Unselects Folder tracks before freezing
--@about Freezes Selected tracks. up to Instrument, Other FX are brough online after freezing.

-- Lua Script for Reaper: Offline non-instrument FX, Freeze Selected Tracks to Stereo, Unlock All Items Directly, Online Remaining FX

-- Main function
local function main()
    -- Step 0: Unselect folder tracks at the very start
    local original_selection = {}
    local track_count = reaper.CountSelectedTracks(0)
    if track_count == 0 then
        return
    end

    -- Store original selection and unselect folder tracks
    for track_idx = 0, track_count - 1 do
        local track = reaper.GetSelectedTrack(0, track_idx)
        if track then
            table.insert(original_selection, track)
            local is_folder = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
            local track_index = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
            local next_track_idx = track_index + 1
            local next_track = reaper.GetTrack(0, next_track_idx)
            local has_child = next_track and reaper.GetTrackDepth(next_track) > reaper.GetTrackDepth(track)
            if is_folder or has_child then
                reaper.SetTrackSelected(track, false)
            end
        end
    end

    -- Re-check track count after unselecting folder tracks
    track_count = reaper.CountSelectedTracks(0)
    if track_count == 0 then
        reaper.Main_OnCommand(40289, 0) -- Unselect all tracks
        for _, track in ipairs(original_selection) do
            reaper.SetTrackSelected(track, true)
        end
        return
    end

    -- Original script: Get all selected tracks into a table
    local selected_tracks = {}
    for track_idx = 0, track_count - 1 do
        local track = reaper.GetSelectedTrack(0, track_idx)
        if track then
            table.insert(selected_tracks, track)
        end
    end

    if #selected_tracks == 0 then
        reaper.Main_OnCommand(40289, 0) -- Unselect all tracks
        for _, track in ipairs(original_selection) do
            reaper.SetTrackSelected(track, true)
        end
        return
    end

    -- Step 1: Offline non-instrument FX for all selected tracks
    for i, track in ipairs(selected_tracks) do
        local fx_count = reaper.TrackFX_GetCount(track)
        if fx_count < 0 then
            goto continue_offline
        end
        local instrument_idx = reaper.TrackFX_GetInstrument(track)
        for fx_idx = 0, fx_count - 1 do
            if fx_idx ~= instrument_idx then
                reaper.TrackFX_SetOffline(track, fx_idx, true)
            end
        end
        ::continue_offline::
    end

    -- Step 2: Freeze all selected tracks to stereo in one batch
    reaper.Main_OnCommand(40289, 0) -- Unselect all tracks
    for _, track in ipairs(selected_tracks) do
        reaper.SetTrackSelected(track, true)
        reaper.SetMediaTrackInfo_Value(track, "I_NCHAN", 2) -- Set to stereo
    end
    reaper.Main_OnCommand(41223, 0) -- Freeze selected tracks to stereo

    -- Step 3: Unlock all items on frozen tracks
    for i, track in ipairs(selected_tracks) do
        local item_count = reaper.CountTrackMediaItems(track)
        for item_idx = 0, item_count - 1 do
            local item = reaper.GetTrackMediaItem(track, item_idx)
            if item then
                reaper.SetMediaItemInfo_Value(item, "C_LOCK", 0)
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
reaper.Undo_EndBlock("Freeze Non-Folder Tracks with Non-Instrument FX Handling", -1)