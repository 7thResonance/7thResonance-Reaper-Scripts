--[[
@description 7R Insert FX Based on selection under Mouse cursor (Track or Item)
@author 7thResonance
@version 1.0
@changelog Initial
@about Opens add FX insert for track or item under cursor
--]]

-- Function to open FX insert window for item or track under mouse cursor
function OpenFXInsert()
    -- Store original selection to restore later
    local selected_items = {}
    local selected_tracks = {}
    local sel_item_count = reaper.CountSelectedMediaItems(0)
    local sel_track_count = reaper.CountSelectedTracks(0)
    
    -- Save selected items
    for i = 0, sel_item_count - 1 do
        selected_items[#selected_items + 1] = reaper.GetSelectedMediaItem(0, i)
    end
    
    -- Save selected tracks
    for i = 0, sel_track_count - 1 do
        selected_tracks[#selected_tracks + 1] = reaper.GetSelectedTrack(0, i)
    end
    
    -- Begin undo block
    reaper.Undo_BeginBlock()
    
    -- Prevent UI refresh to avoid flicker
    reaper.PreventUIRefresh(1)
    
    -- Get mouse cursor context
    reaper.BR_GetMouseCursorContext()
    
    -- Get item under mouse cursor
    local item = reaper.BR_GetMouseCursorContext_Item()
    
    if item then
        -- Clear item selection and select only the item under mouse
        reaper.SelectAllMediaItems(0, false)
        reaper.SetMediaItemSelected(item, true)
        
        -- Open FX insert window for the item under mouse
        reaper.Main_OnCommand(40638, 0) -- Item/Take: Add FX to item (as specified)
    else
        -- No item under mouse, get track under mouse
        local track = reaper.BR_GetMouseCursorContext_Track()
        
        if track then
            -- Clear track selection and select track under mouse (works for master track too)
            reaper.SetOnlyTrackSelected(track)
            reaper.Main_OnCommand(40271, 0) -- Track/Master: Add FX to track (as specified)
        end
    end
    
    -- Restore original item selection
    reaper.SelectAllMediaItems(0, false)
    for _, sel_item in ipairs(selected_items) do
        reaper.SetMediaItemSelected(sel_item, true)
    end
    
    -- Restore original track selection
    for i = 0, reaper.CountTracks(0) - 1 do
        local tr = reaper.GetTrack(0, i)
        reaper.SetTrackSelected(tr, false)
    end
    for _, sel_track in ipairs(selected_tracks) do
        reaper.SetTrackSelected(sel_track, true)
    end
    
    -- Re-enable UI refresh
    reaper.PreventUIRefresh(-1)
    
    -- End undo block
    reaper.Undo_EndBlock("Open FX insert window for item/track under mouse", -1)
end

-- Run the function
OpenFXInsert()