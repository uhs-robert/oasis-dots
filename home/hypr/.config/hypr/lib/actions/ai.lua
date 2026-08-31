--- AI workspace and voice command actions.
--- Recording state comes from the voxtype daemon, not a local boolean, so it can't desync from other binds/restarts.

local Config = require("config") --- @class Config
local Scripts = require("lib.scripts") --- @class Scripts
local Window = require("lib.actions.window") --- @class WindowActions

local AI = {}

local RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local VOXTYPE_STATE_FILE = RUNTIME_DIR .. "/voxtype/state"
local AI_VOICE_DIR = RUNTIME_DIR .. "/ai-voice"
local SESSION_FILE = AI_VOICE_DIR .. "/session"

local AI_CLASS = "ai-workspace"
local AI_WORKSPACE = "agents"
local AI_TMUXIFIER_SESSION = "ai"
local AI_TMUX_TARGET = "AI:Claude"

--- @param value string
--- @return string
local function shell_quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end

--- @param command string
local function exec(command) hl.dispatch(hl.dsp.exec_cmd(command)) end

--- @param message string
local function notify(message) exec("notify-send " .. shell_quote("AI") .. " " .. shell_quote(message)) end

--- @return boolean
local function window_exists() return #hl.get_windows({ class = AI_CLASS }) > 0 end

--- @return boolean
local function workspace_visible()
  local w = hl.get_active_special_workspace()
  return w ~= nil and w.name == "special:" .. AI_WORKSPACE
end

--- idle | recording | transcribing, read straight from voxtype's state file.
--- @return string
local function voxtype_state()
  local f = io.open(VOXTYPE_STATE_FILE, "r")
  if not f then return "idle" end
  local line = f:read("*l")
  f:close()
  return line or "idle"
end

--- @param prefix string
--- @param submit boolean
--- @param transcript_path string
local function write_session(prefix, submit, transcript_path)
  os.execute("mkdir -p " .. shell_quote(AI_VOICE_DIR))
  local f = io.open(SESSION_FILE, "w")
  if not f then return end
  f:write(prefix, "\n", submit and "submit" or "prefill", "\n", transcript_path, "\n")
  f:close()
end

--- @return { prefix: string, mode: string, transcript_path: string }|nil
local function read_session()
  local f = io.open(SESSION_FILE, "r")
  if not f then return nil end
  local prefix = f:read("*l")
  local mode = f:read("*l")
  local transcript_path = f:read("*l")
  f:close()
  if not (prefix and mode and transcript_path) then return nil end
  return { prefix = prefix, mode = mode, transcript_path = transcript_path }
end

local function clear_session() os.remove(SESSION_FILE) end

--- Headless so tmuxifier's attach step fails fast instead of hanging; session still gets created.
local function ensure_tmux_session()
  os.execute("tmuxifier load-session " .. AI_TMUXIFIER_SESSION .. " </dev/null >/dev/null 2>&1")
end

function AI.launch()
  ensure_tmux_session()
  if window_exists() then return end

  exec(Config.app.term_cmd .. " --class " .. AI_CLASS .. " -e tmuxifier load-session " .. AI_TMUXIFIER_SESSION)
end

function AI.show()
  if not workspace_visible() then Window.toggle_special(AI_WORKSPACE)() end

  local windows = hl.get_windows({ class = AI_CLASS })
  if #windows > 0 then
    hl.dispatch(hl.dsp.focus({ window = windows[1] }))
  else
    AI.launch()
  end
end

function AI.hide()
  if workspace_visible() then Window.toggle_special(AI_WORKSPACE)() end
end

AI.is_visible = workspace_visible

--- Paste text straight into the tmux target and submit, bypassing voxtype entirely.
--- @param text string
function AI.send_text(text)
  ensure_tmux_session()

  exec(
    string.format(
      "printf %%s %s | tmux load-buffer -b ai-voice - && tmux paste-buffer -p -d -b ai-voice -t %s && tmux send-keys -t %s Enter",
      shell_quote(text),
      shell_quote(AI_TMUX_TARGET),
      shell_quote(AI_TMUX_TARGET)
    )
  )

  AI.show()
end

--- @param prefix string
--- @param submit boolean
local function start_recording(prefix, submit)
  ensure_tmux_session()

  local transcript_path = AI_VOICE_DIR
    .. "/"
    .. os.date("%Y%m%dT%H%M%S")
    .. "-"
    .. tostring(math.random(100000, 999999))
    .. ".txt"
  write_session(prefix, submit, transcript_path)

  exec("voxtype record start --file=" .. shell_quote(transcript_path))
end

local function finish_recording()
  local session = read_session()
  clear_session()
  if not session then return end

  exec(
    string.format(
      "%s %s %s %s %s",
      Scripts.ai_send,
      shell_quote(session.transcript_path),
      shell_quote(session.prefix),
      shell_quote(session.mode),
      shell_quote(AI_TMUX_TARGET)
    )
  )

  AI.show()
end

--- Safe to call unconditionally, e.g. from the submap's on_exit: stops + sends whatever was recorded, no-op if idle.
function AI.finish()
  finish_recording()
end

--- Discards the in-progress recording instead of sending it.
function AI.cancel()
  local session = read_session()
  if not session then return end

  clear_session()
  os.remove(session.transcript_path)
  exec("voxtype record cancel")
  notify("Recording cancelled")
end

--- Same key stops/sends; a different key while recording is ignored, not redirected.
--- @param prefix string
--- @param submit boolean
function AI.toggle(prefix, submit)
  local session = read_session()

  if session then
    if session.prefix ~= prefix then
      notify("Still recording (" .. session.prefix .. ") - press it again to finish, or . to cancel")
      return
    end

    finish_recording()
    return
  end

  local state = voxtype_state()
  if state ~= "idle" then
    notify("Voxtype busy (" .. state .. ")")
    return
  end

  start_recording(prefix, submit)
end

return AI
