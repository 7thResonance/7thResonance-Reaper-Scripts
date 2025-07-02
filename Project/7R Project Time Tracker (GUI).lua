--[[
@version 1.0
--]]

-- REAPER Project Timer GUI (live display, AFK status, full window background)
local WINDOW_TITLE = "REAPER Project Timer & Stats"
local WIDTH, HEIGHT = 480, 440
local PROJ_KEY = "REAPERTIMER"

local function format_seconds(sec)
  sec = math.floor(tonumber(sec) or 0)
  local d = math.floor(sec / 86400)
  local h = math.floor((sec % 86400) / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  return string.format("%02d:%02d:%02d:%02d", d, h, m, s)
end

local function get_system_time12()
  return os.date("%I:%M:%S %p")
end

local function get_state()
  local proj, projfn = reaper.EnumProjects(-1, "")
  local _, val = reaper.GetProjExtState(proj, PROJ_KEY, "timer")
  local state = {
    work_total = 0,
    work_session = 0,
    play_time = 0,
    pause_time = 0,
    reaper_start = 0,
    session_start = 0,
    last_project_name = "",
    project_creation = 0,
    project_path = projfn or "",
    project_name = reaper.GetProjectName(proj, "") or "",
    item_count = reaper.CountMediaItems(proj),
    track_count = reaper.CountTracks(proj),
    fx_count = 0,
    afk = false,
    last_save_unix = os.time(),
  }
  if val and val ~= "" then
    -- total;session;play;pause;reaper_start;session_start;last_name;creation;afk;last_save_unix
    local a, b, c, d, e, f, g, h, i, j = val:match("(%d+);(%d+);(%d+);(%d+);(%d+);(%d+);(.*);(%d+);(%d+);(%d+)")
    if not a then -- fallback to old format
      a, b, c, d, e, f, g, h = val:match("(%d+);(%d+);(%d+);(%d+);(%d+);(%d+);(.*);(%d+)")
    end
    if a then
      state.work_total = tonumber(a)
      state.work_session = tonumber(b)
      state.play_time = tonumber(c)
      state.pause_time = tonumber(d)
      state.reaper_start = tonumber(e)
      state.session_start = tonumber(f)
      state.last_project_name = g or ""
      state.project_creation = tonumber(h)
      state.afk = (i and tonumber(i) or 0) == 1
      state.last_save_unix = tonumber(j) or os.time()
    end
  end
  -- FX count (sum for all tracks)
  local fx = 0
  for i = 0, state.track_count-1 do
    local tr = reaper.GetTrack(proj, i)
    fx = fx + reaper.TrackFX_GetCount(tr)
  end
  state.fx_count = fx
  return state
end

local last_update = 0
local cached_state = get_state()

local function draw_gui()
  local t = cached_state
  local now = os.time()
  local elapsed = now - (t.last_save_unix or now)

  -- If NOT AFK, add "live" elapsed time since last save
  local work_total = t.work_total
  local work_session = t.work_session
  local play_time = t.play_time

  if not t.afk then
    work_total = work_total + elapsed
    work_session = work_session + elapsed
    -- Optionally: play_time live update if REAPER is playing
    if reaper.GetPlayState() == 1 then
      play_time = play_time + elapsed
    end
  end

  gfx.set(1,1,1,1)
  gfx.setfont(1, "Arial", 18)
  gfx.x, gfx.y = 20, 20
  gfx.drawstr(WINDOW_TITLE)

  gfx.setfont(1, "Arial", 15)
  local y = 60
  gfx.x, gfx.y = 20, y
  gfx.drawstr("Work Time (total): " .. format_seconds(work_total))
  y = y + 24
  gfx.x, gfx.y = 20, y
  gfx.drawstr("Work Time (this session): " .. format_seconds(work_session))
  y = y + 24

  local reaper_uptime = 0
  if t.reaper_start > 0 and t.reaper_start < os.time() then
    reaper_uptime = os.time() - t.reaper_start
    if reaper_uptime > 365*86400 then reaper_uptime = 0 end
  end
  if reaper_uptime > 0 then
    gfx.x, gfx.y = 20, y
    gfx.drawstr("REAPER Open For: " .. format_seconds(reaper_uptime))
    y = y + 24
  end

  gfx.x, gfx.y = 20, y
  gfx.drawstr("Time Spent Playing: " .. format_seconds(play_time))
  y = y + 24
  gfx.x, gfx.y = 20, y
  gfx.drawstr("Current System Time: " .. get_system_time12())
  y = y + 24

  -- AFK display
  if t.afk then
    gfx.set(1,0.3,0.3,1)
    gfx.x, gfx.y = 20, y
    gfx.drawstr("Status: AFK (not tracking work time)", 0)
    y = y + 26
    gfx.set(1,1,1,1)
  else
    gfx.set(0.3,1,0.3,1)
    gfx.x, gfx.y = 20, y
    gfx.drawstr("Status: ACTIVE", 0)
    y = y + 26
    gfx.set(1,1,1,1)
  end

  gfx.set(0.8,0.8,0.8,1)
  gfx.x, gfx.y = 20, y
  gfx.drawstr("Project Information:")
  y = y + 22
  gfx.set(1,1,1,1)
  gfx.x, gfx.y = 36, y
  if t.project_creation and t.project_creation > 0 then
    gfx.drawstr("Project Created: " .. os.date("%Y-%m-%d %I:%M:%S %p", t.project_creation))
  else
    gfx.drawstr("Project Created: Unknown")
  end
  y = y + 20
  gfx.x, gfx.y = 36, y
  gfx.drawstr("Project Path: " .. (t.project_path or ""))
  y = y + 20
  gfx.x, gfx.y = 36, y
  gfx.drawstr("Project Name: " .. (t.project_name or ""))
  y = y + 20
  gfx.x, gfx.y = 36, y
  gfx.drawstr("Item Count: " .. (t.item_count or 0))
  y = y + 20
  gfx.x, gfx.y = 36, y
  gfx.drawstr("Track Count: " .. (t.track_count or 0))
  y = y + 20
  gfx.x, gfx.y = 36, y
  gfx.drawstr("FX Count: " .. (t.fx_count or 0))
  y = y + 18
end

local function mainloop()
  local now = reaper.time_precise()
  if now - last_update > 0.95 then
    cached_state = get_state()
    last_update = now
  end
  gfx.set(0.13,0.13,0.13,1)
  gfx.rect(0,0,gfx.w,gfx.h,1)
  draw_gui()
  if gfx.getchar() >= 0 then
    reaper.defer(mainloop)
  else
    gfx.quit()
  end
end

gfx.init(WINDOW_TITLE, WIDTH, HEIGHT, 0, 100, 100)
mainloop()