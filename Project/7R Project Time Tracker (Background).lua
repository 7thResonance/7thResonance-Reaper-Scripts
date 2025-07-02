-- @version 1.0

-- REAPER Project Timer (background tracker, AFK detection: mouse, track, [envelope if available], cursor, playback)
local PROJ_KEY = "REAPERTIMER"
local POLL_INTERVAL = 1 -- seconds
local AFK_TIMEOUT = 5 -- seconds

local t = {
  work_total = 0,      -- all-time work for this project
  work_session = 0,    -- session work (since last reset or script start)
  play_time = 0,
  pause_time = 0,
  last_activity = reaper.time_precise(),
  afk = false,
  reaper_start = os.time(),
  session_start = os.time(),
  last_poll = reaper.time_precise(),
  last_playstate = reaper.GetPlayState(),
  project_creation = nil,
  last_saved_time = 0,
  last_project_name = "",
  project_name = "",
  awaiting_rename_decision = false,
  last_save_tick = reaper.time_precise(),
}

-- For detecting mouse and edit activity:
local last_mouse_x, last_mouse_y = reaper.GetMousePosition()
local last_touched_track = reaper.GetLastTouchedTrack()
local last_touched_env = reaper.GetLastTouchedEnvelope and reaper.GetLastTouchedEnvelope() or nil
local last_cursor_pos = reaper.GetCursorPosition()

local function save_state()
  local proj = 0
  local now = os.time()
  local state = string.format("%d;%d;%d;%d;%d;%d;%s;%d;%d;%d",
    t.work_total, t.work_session, t.play_time, t.pause_time, t.reaper_start,
    t.session_start, t.last_project_name or "", t.project_creation or 0,
    t.afk and 1 or 0, now)
  -- total;session;play;pause;reaper_start;session_start;last_name;creation;afk;last_save_unix
  reaper.SetProjExtState(proj, PROJ_KEY, "timer", state)
end

local function load_state()
  local proj = 0
  local _, val = reaper.GetProjExtState(proj, PROJ_KEY, "timer")
  if val and val ~= "" then
    -- support old and new formats
    local a, b, c, d, e, f, g, h, i, j = val:match("(%d+);(%d+);(%d+);(%d+);(%d+);(%d+);(.*);(%d+);(%d+);(%d+)")
    if not a then -- fallback to old format
      a, b, c, d, e, f, g, h = val:match("(%d+);(%d+);(%d+);(%d+);(%d+);(%d+);(.*);(%d+)")
    end
    if a then
      t.work_total = tonumber(a)
      t.work_session = tonumber(b)
      t.play_time = tonumber(c)
      t.pause_time = tonumber(d)
      t.reaper_start = tonumber(e)
      t.session_start = tonumber(f)
      t.last_project_name = g or ""
      t.project_creation = tonumber(h)
      t.afk = (i and tonumber(i) or 0) == 1
      t.last_save_unix = tonumber(j) or os.time()
    end
  end
end

local function get_project_info()
  local proj, _ = reaper.EnumProjects(-1, "")
  t.project_name = reaper.GetProjectName(proj, "")
  if not t.project_creation or t.project_creation == 0 then
    local _, val = reaper.GetProjExtState(proj, PROJ_KEY, "timer")
    if val and val ~= "" then
      local h = val:match(".*;(%d+)$")
      if h then t.project_creation = tonumber(h) end
    end
    if not t.project_creation or t.project_creation == 0 then
      t.project_creation = os.time()
    end
  end
end

local function detect_activity()
  local playstate = reaper.GetPlayState()
  if playstate == 1 then -- Playing
    t.last_activity = reaper.time_precise()
    t.afk = false
    return
  end

  -- Mouse movement
  local mx, my = reaper.GetMousePosition()
  if mx ~= last_mouse_x or my ~= last_mouse_y then
    t.last_activity = reaper.time_precise()
    t.afk = false
  end
  last_mouse_x, last_mouse_y = mx, my

  -- Last touched track
  local touched_track = reaper.GetLastTouchedTrack()
  if touched_track ~= last_touched_track then
    t.last_activity = reaper.time_precise()
    t.afk = false
  end
  last_touched_track = touched_track

  -- Last touched envelope (only if available)
  if reaper.GetLastTouchedEnvelope then
    local touched_env = reaper.GetLastTouchedEnvelope()
    if touched_env ~= last_touched_env then
      t.last_activity = reaper.time_precise()
      t.afk = false
    end
    last_touched_env = touched_env
  end

  -- Edit cursor movement
  local curpos = reaper.GetCursorPosition()
  if curpos ~= last_cursor_pos then
    t.last_activity = reaper.time_precise()
    t.afk = false
  end
  last_cursor_pos = curpos
end

local function update_time_counters(dt)
  local playstate = reaper.GetPlayState()
  if not t.afk and not t.awaiting_rename_decision then
    t.work_total = t.work_total + dt
    t.work_session = t.work_session + dt
    if playstate == 1 then
      t.play_time = t.play_time + dt
    elseif playstate == 2 then
      t.pause_time = t.pause_time + dt
    end
  end
end

local function mainloop()
  local now = reaper.time_precise()
  if now - t.last_poll >= POLL_INTERVAL then
    get_project_info()
    if t.last_project_name ~= "" and t.project_name ~= t.last_project_name and not t.awaiting_rename_decision then
      t.awaiting_rename_decision = true
    end
    detect_activity()
    if now - t.last_activity > AFK_TIMEOUT then
      t.afk = true
    else
      t.afk = false
    end
    update_time_counters(POLL_INTERVAL)
    t.last_poll = now

    -- Save state every second
    if now - t.last_saved_time > 1 then
      t.last_project_name = t.project_name
      save_state()
      t.last_saved_time = now
    end
  end
  reaper.defer(mainloop)
end

load_state()
get_project_info()
t.last_project_name = t.last_project_name or t.project_name
mainloop()