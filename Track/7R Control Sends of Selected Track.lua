--[[
@description 7R Control Send volume of Selected Track
@author 7thResonance
@version 1.1
@changelog consoldidated undo points
@about When mulltiple tracks are selected, can change the relative volume of the send over those tracks.

due to my lack of knowledge, or limitation of API (i wouldnt know lmao) 
alt key is the temporary override button, but you have to press it before dragging the mouse and it will stay active untill the mouse is released.

Known issues; Undo doesnt work properly, have to undo untill track seletion changes for intial values to be restored. (idk how to fix this)
--]]

-- Function to convert linear volume to dB
function LinearToDB(linear)
    if linear <= 0 then return -math.huge end
    return 20 * math.log(linear, 10)
end

-- Function to convert dB to linear volume
function DBToLinear(db)
    return 10 ^ (db / 20)
end

-- Function to get send info for a track
function GetSendInfo(track, send_idx)
    local _, send_name = reaper.GetTrackSendName(track, send_idx)
    local send_vol = reaper.GetTrackSendInfo_Value(track, 0, send_idx, "D_VOL")
    return send_name, send_vol
end

-- Function to check if a send with the same name exists on a track
function HasSendWithName(track, target_send_name)
    local send_count = reaper.GetTrackNumSends(track, 0)
    for i = 0, send_count - 1 do
        local _, send_name = reaper.GetTrackSendName(track, i)
        if send_name == target_send_name then
            return true, i
        end
    end
    return false, -1
end

-- Function to store send volumes for selected tracks (in dB)
function StoreSendVolumes()
    local track_sends = {}
    local sel_track_count = reaper.CountSelectedTracks(0)
    for i = 0, sel_track_count - 1 do
        local track = reaper.GetSelectedTrack(0, i)
        track_sends[track] = {}
        local send_count = reaper.GetTrackNumSends(track, 0)
        for j = 0, send_count - 1 do
            local send_name, vol = GetSendInfo(track, j)
            track_sends[track][send_name] = LinearToDB(vol)
        end
    end
    return track_sends
end

-- Main function
function Main()
    local track_sends = StoreSendVolumes()
    local last_sel_count = reaper.CountSelectedTracks(0)
    local alt_latched = false
    local mouse_was_down = false
    local changes_during_drag = {}

    local function GetAltAndMouseState()
        local alt_held = false
        local mouse_down = false
        if reaper.JS_VKeys_GetState then
            local state = reaper.JS_VKeys_GetState(-1)
            alt_held = state:byte(18) == 1 -- VK_MENU (Alt)
        end
        if reaper.JS_Mouse_GetState then
            mouse_down = reaper.JS_Mouse_GetState(1) == 1 -- Left mouse button
        end
        return alt_held, mouse_down
    end

    local function CheckAndUpdate()
        local sel_track_count = reaper.CountSelectedTracks(0)

        if sel_track_count < 2 then
            track_sends = StoreSendVolumes()
            last_sel_count = sel_track_count
            reaper.defer(CheckAndUpdate)
            return
        end

        if sel_track_count ~= last_sel_count then
            track_sends = StoreSendVolumes()
            last_sel_count = sel_track_count
            reaper.defer(CheckAndUpdate)
            return
        end

        -- Check Alt and mouse state
        local alt_held, mouse_down = GetAltAndMouseState()

        -- Update latch: Set if Alt is held and mouse is down, clear if mouse is up
        if mouse_down and alt_held then
            alt_latched = true
        elseif not mouse_down then
            alt_latched = false
        end

        -- Check for send volume changes across all sends
        local changes = {}
        for i = 0, sel_track_count - 1 do
            local track = reaper.GetSelectedTrack(0, i)
            local send_count = reaper.GetTrackNumSends(track, 0)
            for j = 0, send_count - 1 do
                local send_name, current_vol = GetSendInfo(track, j)
                local current_vol_db = LinearToDB(current_vol)
                if track_sends[track] and track_sends[track][send_name] and math.abs(track_sends[track][send_name] - current_vol_db) > 0.01 then
                    local vol_change_db = current_vol_db - track_sends[track][send_name]
                    table.insert(changes, {
                        track = track,
                        send_idx = j,
                        send_name = send_name,
                        vol_change_db = vol_change_db
                    })
                end
            end
        end

        -- Apply volume changes to matching sends on other selected tracks
        if #changes > 0 and not alt_latched then
            for _, change in ipairs(changes) do
                local target_send_name = change.send_name
                local vol_change_db = change.vol_change_db
                local changed_track = change.track

                for i = 0, sel_track_count - 1 do
                    local track = reaper.GetSelectedTrack(0, i)
                    if track ~= changed_track then
                        local has_send, send_idx = HasSendWithName(track, target_send_name)
                        if has_send then
                            local current_vol = reaper.GetTrackSendInfo_Value(track, 0, send_idx, "D_VOL")
                            local current_vol_db = LinearToDB(current_vol)
                            local new_vol_db = current_vol_db + vol_change_db
                            local new_vol = DBToLinear(new_vol_db)
                            reaper.SetTrackSendInfo_Value(track, 0, send_idx, "D_VOL", new_vol)
                            -- Store change for undo consolidation
                            table.insert(changes_during_drag, {
                                track = track,
                                send_idx = send_idx,
                                send_name = target_send_name,
                                vol_change_db = vol_change_db
                            })
                        end
                    end
                end
            end
            -- Update stored send volumes
            track_sends = StoreSendVolumes()
        end

        -- Create undo block only when mouse is released after changes
        if mouse_was_down and not mouse_down and #changes_during_drag > 0 then
            reaper.Undo_BeginBlock()
            -- No need to re-apply changes; just create the undo point
            reaper.Undo_EndBlock("Adjust send volumes across selected tracks", -1)
            changes_during_drag = {} -- Clear changes after creating undo point
        end

        -- Update mouse state
        mouse_was_down = mouse_down

        -- Continue monitoring
        reaper.defer(CheckAndUpdate)
    end

    reaper.defer(CheckAndUpdate)
end

-- Run the script
Main()