--@description 7R Insert Project/Take Marker at mouse pointer
--@author 7thResonance
--@version 1.0
--@changelog Initial
--@about Allows to add markers on items themselves or the ruler (project markers), just point and press shortcut!

function Main()
  -- Get mouse position
  local mouse_x, mouse_y = reaper.GetMousePosition()
  local mouse_pos = reaper.BR_PositionAtMouseCursor(true) -- Precise timeline position
  
  if mouse_pos < 0 then return end -- Exit if mouse is not in valid position
  
  -- Check if mouse is over timeline (ruler)
  local window, segment, details = reaper.BR_GetMouseCursorContext()
  if segment == "timeline" then
    -- Create project marker at mouse timeline position
    reaper.AddProjectMarker(0, false, mouse_pos, 0, "", -1)
    reaper.Undo_OnStateChange("Add project marker at mouse position")
    return
  end
  
  -- Check if mouse is over an item
  local item, take = reaper.GetItemFromPoint(mouse_x, mouse_y, true)
  if item and take then
    -- Get item start and convert mouse position to item-relative time
    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local relative_pos = mouse_pos - item_start
    
    -- Ensure position is within item bounds
    local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    if relative_pos >= 0 and relative_pos <= item_length then
      -- Add take marker
      reaper.SetTakeMarker(take, -1, "", relative_pos)
      reaper.Undo_OnStateChange("Add take marker at mouse position")
    end
  end
end

-- Run script with undo block
reaper.Undo_BeginBlock()
Main()
reaper.Undo_EndBlock("Create Project or Take Marker", -1)
