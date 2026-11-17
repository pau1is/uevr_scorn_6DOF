--[[
  UEVR hot-reload loader (template)
  Put this in <profile>/scripts/, put the real logic in <profile>/data/<CORE_FILE>.
  Loads data/<CORE_FILE> through load() with a proxy uevr.sdk.callbacks and hot-reloads it
  whenever the file changes (old core gets on_script_reset first),
  so the mod can be updated without restarting the game or pressing "Reset scripts".
]]

UEVR_UObjectHook.activate()

local CORE_FILE = "mod_core.lua"       -- file in the profile data/ folder
local STATE_FILE = "mod_loader.txt"
local real_callbacks = uevr.sdk.callbacks

local handlers = {}
local current_src = nil
local loaded_at = "never"
local last_error = ""
local check_timer = 0.0

local function loader_log(msg)
    print("[loader] " .. tostring(msg))
end

local function dispatch(name, ...)
    local list = handlers[name]
    if list == nil then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then
            last_error = name .. ": " .. tostring(err)
            loader_log(last_error)
        end
    end
end

local function make_env()
    local fake_callbacks = setmetatable({}, {
        __index = function(_, name)
            return function(fn)
                handlers[name] = handlers[name] or {}
                table.insert(handlers[name], fn)
            end
        end,
    })
    local fake_sdk = setmetatable({ callbacks = fake_callbacks }, {
        __index = function(_, k) return uevr.sdk[k] end,
    })
    local fake_uevr = setmetatable({ sdk = fake_sdk }, {
        __index = function(_, k) return uevr[k] end,
    })
    return setmetatable({ uevr = fake_uevr }, { __index = _G })
end

local function write_state()
    pcall(fs.write, STATE_FILE, "loaded_at=" .. loaded_at .. "\nlast_error=" .. last_error .. "\n")
end

local function load_core(src)
    if current_src ~= nil then
        dispatch("on_script_reset")
    end
    handlers = {}
    last_error = ""
    local chunk, err = load(src, "=" .. CORE_FILE, "t", make_env())
    if not chunk then
        last_error = "compile: " .. tostring(err)
        loader_log(last_error)
        current_src = src
        write_state()
        return
    end
    local ok, e = pcall(chunk)
    if not ok then
        last_error = "run: " .. tostring(e)
        loader_log(last_error)
    end
    current_src = src
    loaded_at = os.date("%H:%M:%S")
    loader_log("core loaded at " .. loaded_at)
    write_state()
end

local function check_core()
    local ok, src = pcall(fs.read, CORE_FILE)
    if not ok or type(src) ~= "string" or #src == 0 then
        if last_error ~= "core file missing" then
            last_error = "core file missing"
            loader_log("data/" .. CORE_FILE .. " not found")
            write_state()
        end
        return
    end
    if src ~= current_src then load_core(src) end
end

for _, name in ipairs({
    "on_pre_engine_tick", "on_post_engine_tick",
    "on_pre_calculate_stereo_view_offset", "on_post_calculate_stereo_view_offset",
    "on_xinput_get_state", "on_draw_ui",
}) do
    real_callbacks[name](function(...) dispatch(name, ...) end)
end

real_callbacks.on_pre_engine_tick(function(engine, dt)
    check_timer = check_timer - (dt or 0.016)
    if check_timer <= 0.0 then
        check_timer = 1.0
        check_core()
    end
end)

real_callbacks.on_draw_ui(function()
    imgui.text("Mod loader: core loaded at " .. loaded_at .. (last_error ~= "" and ("  |  " .. last_error) or ""))
end)

real_callbacks.on_script_reset(function()
    dispatch("on_script_reset")
    handlers = {}
    current_src = nil
end)

check_core()
