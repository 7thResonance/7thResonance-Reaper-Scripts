--[[
@description 7R FX Link (Relative)
@author 7thResonance
@version 1.0
@changelog - Initial
@donation https://paypal.me/7thresonance
@about Links the same FX on selected track.

Original script by zaibuyidao.
Any changes to the FX parameters on one track will be reflected on all other selected tracks with the same FX (all of them).

Uses FX focus as the starting point. If you have multiple FX windows open
wait a short time (maybe 50 to 100ms) before adjusting parameter. 
(limitation of how reaper defer cycles work, or my lack of ideas lmao)
 
--]]

function Msg(string)
  reaper.ShowConsoleMsg(tostring(string).."\n")
end

only_first = false -- true or false: Set to true, Link The first FX of the same name. Set to false, Link all FX of the same name.

-- 當前focused FX的信息
focused_fx = {
  track_idx = nil,
  item_idx = nil,
  take_idx = nil,
  fx_idx = nil,
  fx_name = nil
}

-- 參數快照，保存當前focused FX所有參數的值
param_snapshot = {}

function create_param_snapshot()
  param_snapshot = {}
  
  if not focused_fx.track_idx then return end
  
  -- 確定是item FX還是track FX
  local is_item_fx = focused_fx.item_idx and focused_fx.item_idx >= 0
  
  if is_item_fx then
    local track = reaper.GetTrack(0, focused_fx.track_idx)
    local item = reaper.GetTrackMediaItem(track, focused_fx.item_idx)
    local take = reaper.GetMediaItemTake(item, focused_fx.take_idx)
    
    if take then
      local param_count = reaper.TakeFX_GetNumParams(take, focused_fx.fx_idx)
      for i = 0, param_count - 1 do
        param_snapshot[i] = reaper.TakeFX_GetParam(take, focused_fx.fx_idx, i)
      end
    end
  else
    -- Track FX
    local track = reaper.GetTrack(0, focused_fx.track_idx)
    if track or focused_fx.track_idx == -1 then
      if focused_fx.track_idx == -1 then
        track = reaper.GetMasterTrack(0)
      end
      local param_count = reaper.TrackFX_GetNumParams(track, focused_fx.fx_idx)
      for i = 0, param_count - 1 do
        param_snapshot[i] = reaper.TrackFX_GetParam(track, focused_fx.fx_idx, i)
      end
    end
  end
end

function update_and_sync_params()
  if not focused_fx.track_idx then return end
  
  local is_item_fx = focused_fx.item_idx and focused_fx.item_idx >= 0
  local track, take
  
  if is_item_fx then
    track = reaper.GetTrack(0, focused_fx.track_idx)
    local item = reaper.GetTrackMediaItem(track, focused_fx.item_idx)
    take = reaper.GetMediaItemTake(item, focused_fx.take_idx)
    if not take then return end
  else
    if focused_fx.track_idx == -1 then
      track = reaper.GetMasterTrack(0)
    else
      track = reaper.GetTrack(0, focused_fx.track_idx)
    end
    if not track then return end
  end
  
  -- 讀取所有當前參數值並檢查變化
  local param_count = is_item_fx and reaper.TakeFX_GetNumParams(take, focused_fx.fx_idx) or reaper.TrackFX_GetNumParams(track, focused_fx.fx_idx)
  
  for param_idx = 0, param_count - 1 do
    local current_val = is_item_fx and reaper.TakeFX_GetParam(take, focused_fx.fx_idx, param_idx) or reaper.TrackFX_GetParam(track, focused_fx.fx_idx, param_idx)
    local snapshot_val = param_snapshot[param_idx] or 0
    
    -- 檢測參數變化（應用任何變化，讓REAPER處理浮點精度）
    if current_val ~= snapshot_val then
      local delta = current_val - snapshot_val
      
      -- 同步到所有選中的item/track
      if is_item_fx then
        sync_item_fx_param(param_idx, delta)
      else
        sync_track_fx_param(param_idx, delta)
      end
    end
    
    -- 更新快照為當前值
    param_snapshot[param_idx] = current_val
  end
end

function sync_item_fx_param(param_idx, delta)
  local source_track = reaper.GetTrack(0, focused_fx.track_idx)
  local source_item = reaper.GetTrackMediaItem(source_track, focused_fx.item_idx)
  local source_take = reaper.GetMediaItemTake(source_item, focused_fx.take_idx)
  
  -- 只有當source item被選中時才同步
  if not reaper.IsMediaItemSelected(source_item) then return end
  
  local items_count = reaper.CountSelectedMediaItems(0)
  
  for i = 0, items_count - 1 do
    local selected_item = reaper.GetSelectedMediaItem(0, i)
    local selected_take = reaper.GetActiveTake(selected_item)
    
    if not selected_take then goto continue_item end
    
    for selected_fx_number = 0, reaper.TakeFX_GetCount(selected_take) - 1 do
      local _, dest_fxname = reaper.TakeFX_GetFXName(selected_take, selected_fx_number, '')
      
      -- 跳過source FX本身，並檢查名稱匹配
      if selected_take == source_take or dest_fxname ~= focused_fx.fx_name then goto continue_fx_item end
      
      -- 應用delta
      local other_current_val = reaper.TakeFX_GetParam(selected_take, selected_fx_number, param_idx)
      local new_val = other_current_val + delta
      new_val = math.max(0, math.min(1, new_val))
      reaper.TakeFX_SetParam(selected_take, selected_fx_number, param_idx, new_val)
      
      if only_first then break end
      
      ::continue_fx_item::
    end
    
    ::continue_item::
  end
end

function sync_track_fx_param(param_idx, delta)
  local source_track = focused_fx.track_idx == -1 and reaper.GetMasterTrack(0) or reaper.GetTrack(0, focused_fx.track_idx)
  
  -- 只有當source track被選中時才同步
  if not reaper.IsTrackSelected(source_track) then return end
  
  local selected_tracks = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    table.insert(selected_tracks, reaper.GetSelectedTrack(0, i))
  end
  local master_track = reaper.GetMasterTrack(0)
  if reaper.IsTrackSelected(master_track) then
    table.insert(selected_tracks, master_track)
  end
  
  for _, selected_track in pairs(selected_tracks) do
    for selected_fx_number = 0, reaper.TrackFX_GetCount(selected_track) - 1 do
      local _, dest_fxname = reaper.TrackFX_GetFXName(selected_track, selected_fx_number, "")
      
      -- 跳過source FX本身，並檢查名稱匹配
      if selected_track == source_track or dest_fxname ~= focused_fx.fx_name then goto continue_fx_track end
      
      -- 應用delta
      local other_current_val = reaper.TrackFX_GetParam(selected_track, selected_fx_number, param_idx)
      local new_val = other_current_val + delta
      new_val = math.max(0, math.min(1, new_val))
      reaper.TrackFX_SetParam(selected_track, selected_fx_number, param_idx, new_val)
      
      if only_first then break end
      
      ::continue_fx_track::
    end
  end
end

function main()
  reaper.PreventUIRefresh(1)
  
  -- 查詢當前focused FX
  local retval, track_idx, item_idx, take_idx, fx_idx, parm_idx = reaper.GetTouchedOrFocusedFX(1)
  
  -- 檢查focused FX是否改變
  local fx_changed = false
  if retval then
    if track_idx ~= focused_fx.track_idx or item_idx ~= focused_fx.item_idx or 
       take_idx ~= focused_fx.take_idx or fx_idx ~= focused_fx.fx_idx then
      fx_changed = true
    end
  end
  
  -- 如果focused FX改變，建立新快照
  if fx_changed and retval then
    focused_fx.track_idx = track_idx
    focused_fx.item_idx = item_idx
    focused_fx.take_idx = take_idx
    focused_fx.fx_idx = fx_idx
    
    -- 獲取FX名稱
    local is_item_fx = item_idx and item_idx >= 0
    if is_item_fx then
      local track = reaper.GetTrack(0, track_idx)
      local item = reaper.GetTrackMediaItem(track, item_idx)
      local take = reaper.GetMediaItemTake(item, take_idx)
      if take then
        _, focused_fx.fx_name = reaper.TakeFX_GetFXName(take, fx_idx, '')
      end
    else
      local track = track_idx == -1 and reaper.GetMasterTrack(0) or reaper.GetTrack(0, track_idx)
      if track then
        _, focused_fx.fx_name = reaper.TrackFX_GetFXName(track, fx_idx, "")
      end
    end
    
    create_param_snapshot()
  elseif not retval then
    -- No focused FX
    focused_fx.track_idx = nil
    focused_fx.item_idx = nil
    focused_fx.take_idx = nil
    focused_fx.fx_idx = nil
    focused_fx.fx_name = nil
    param_snapshot = {}
  end
  
  -- 如果有focused FX，更新並同步參數
  if focused_fx.track_idx ~= nil then
    update_and_sync_params()
  end
  
  reaper.PreventUIRefresh(-1)
  reaper.defer(main)
end

local _, _, sectionId, cmdId = reaper.get_action_context()
if sectionId ~= -1 then
  reaper.SetToggleCommandState(sectionId, cmdId, 1)
  reaper.RefreshToolbar2(sectionId, cmdId)
  main()
  reaper.atexit(function()
    reaper.SetToggleCommandState(sectionId, cmdId, 0)
    reaper.RefreshToolbar2(sectionId, cmdId)
  end)
end
