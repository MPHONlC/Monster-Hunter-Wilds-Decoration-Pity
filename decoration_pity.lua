local CONF = "decoration_pity.json"
local DATA = json.load_file(CONF) or {}
if type(DATA.sett) ~= "table" then DATA.sett = {} end
if type(DATA.history) ~= "table" then DATA.history = {} end
local S = DATA.sett

local function default(key, value)
    if S[key] == nil then S[key] = value end
end
default("enabled", true)
default("threshold", 3)
default("window_hours", 24)
default("arm_seconds", 600)
default("watch_always", false)
default("pool_all", false)
default("match_slot", true)
default("match_type", true)

local HISTORY_LIMIT = 2000
local HISTORY_MAX_AGE = 14 * 24 * 3600
local POLL_ARMED = 0.5
local POLL_IDLE = 5
local NUM_CAP = 999

math.randomseed(os.time())

local config_dirty = false
local config_save_at = 0
local function markDirty()
    config_dirty = true
    config_save_at = os.clock() + 0.6
end

local SlotMethod, TypeMethod, NameMethod, GetMsg = nil, nil, nil, nil
pcall(function()
    SlotMethod = sdk.find_type_definition("app.EquipDef"):get_method("SlotLevelAcc(app.EquipDef.ACCESSORY_ID)")
end)
pcall(function()
    TypeMethod = sdk.find_type_definition("app.EquipDef"):get_method("AccessoryType(app.EquipDef.ACCESSORY_ID)")
end)
pcall(function()
    NameMethod = sdk.find_type_definition("app.EquipDef"):get_method("Name(app.EquipDef.ACCESSORY_ID)")
end)
pcall(function()
    GetMsg = sdk.find_type_definition("via.gui.message"):get_method("get(System.Guid)")
end)

local function struct_to_number(r)
    if type(r) == "number" then return r end
    if type(r) == "userdata" then
        local okd, def = pcall(function() return r:get_type_definition() end)
        if okd and def then
            for _, f in ipairs(def:get_fields()) do
                if not f:is_static() then
                    local okv, v = pcall(function() return f:get_data(r) end)
                    if okv and type(v) == "number" then return v end
                end
            end
        end
    end
    return nil
end

local function call_static(method, id)
    if not method then return nil end
    local ok, r = pcall(function() return method:call(nil, id) end)
    if not ok then return nil end
    if type(r) == "number" then return r end
    return struct_to_number(r)
end

local name_cache = {}
local function decoName(id)
    if name_cache[id] ~= nil then return name_cache[id] or nil end
    local result = false
    if NameMethod and GetMsg then
        local ok, guid = pcall(function() return NameMethod:call(nil, id) end)
        if ok and guid ~= nil then
            local okn, name = pcall(function() return GetMsg:call(nil, guid) end)
            if okn and type(name) == "string" and name ~= "" then result = name end
        end
    end
    name_cache[id] = result
    return result or nil
end

local valid_cache = {}
local function isValidDeco(id)
    if valid_cache[id] ~= nil then return valid_cache[id] end
    local valid = false
    if NameMethod and GetMsg then
        local name = decoName(id)
        if name and not (name:sub(1, 8) == "[INVALID" or name:find("Rejected", 1, true) or name:find("---", 1, true)) then
            valid = true
        end
    else
        valid = true
    end
    valid_cache[id] = valid
    return valid
end

local function label(id)
    return decoName(id) or ("Decoration #" .. tostring(id))
end

local all_ids = nil
local function allAccessoryIds()
    if all_ids then return all_ids end
    all_ids = {}
    local def = sdk.find_type_definition("app.EquipDef.ACCESSORY_ID")
    if not def then return all_ids end
    for _, f in ipairs(def:get_fields()) do
        if f:is_static() then
            local up = f:get_name():upper()
            if up ~= "VALUE__" and up ~= "MAX" and up ~= "INVALID" and up ~= "NONE" then
                local ok, v = pcall(function() return f:get_data(nil) end)
                if ok and type(v) == "number" and v >= 0 then all_ids[#all_ids + 1] = v end
            end
        end
    end
    return all_ids
end

local function getEquip()
    local mgr = sdk.get_managed_singleton("app.SaveDataManager")
    if not mgr then return nil end
    local ok, ep = pcall(function() return mgr:getCurrentUserSaveData()._Equip end)
    return ok and ep or nil
end

local function getBox(ep)
    local box
    pcall(function() box = ep._AccessoryBox end)
    return box
end

local function snapshot(box)
    local snap = {}
    local n = 0
    pcall(function() n = box:get_Count() end)
    for i = 0, n - 1 do
        local w
        pcall(function() w = box:get_Item(i) end)
        if w then
            local id, num
            pcall(function()
                id = w.ID
                num = w.Num
            end)
            if id and id >= 0 and num and num > 0 then
                snap[id] = (snap[id] or 0) + num
            end
        end
    end
    return snap
end

local function setNum(box, id, target)
    local n = 0
    pcall(function() n = box:get_Count() end)
    for i = 0, n - 1 do
        local w
        pcall(function() w = box:get_Item(i) end)
        if w then
            local wid
            pcall(function() wid = w.ID end)
            if wid == id then
                local ok = pcall(function()
                    w.Num = target
                    if target <= 0 then w.ID = -1 end
                end)
                return ok
            end
        end
    end
    return false
end

local function windowStart()
    local hours = tonumber(S.window_hours) or 24
    if hours <= 0 then
        local d = os.date("*t")
        d.hour, d.min, d.sec = 0, 0, 0
        return os.time(d)
    end
    return os.time() - hours * 3600
end

local function countInWindow(id)
    local since = windowStart()
    local total = 0
    for _, h in ipairs(DATA.history) do
        if h.id == id and h.t >= since then total = total + (h.n or 1) end
    end
    return total
end

local function record(id, n, swapped)
    DATA.history[#DATA.history + 1] = { id = id, n = n, t = os.time(), swapped = swapped or false }
    local cutoff = os.time() - HISTORY_MAX_AGE
    local kept = {}
    for _, h in ipairs(DATA.history) do
        if h.t >= cutoff then kept[#kept + 1] = h end
    end
    while #kept > HISTORY_LIMIT do table.remove(kept, 1) end
    DATA.history = kept
    markDirty()
end

local function pickReplacement(id, current)
    local slot = call_static(SlotMethod, id)
    local dtype = call_static(TypeMethod, id)

    local source = {}
    if S.pool_all then
        for _, cid in ipairs(allAccessoryIds()) do source[#source + 1] = cid end
    else
        for cid in pairs(current) do source[#source + 1] = cid end
    end

    local unseen, fewest, fewest_n = {}, nil, math.huge
    for _, cid in ipairs(source) do
        if cid ~= id and isValidDeco(cid) and (current[cid] or 0) < NUM_CAP then
            local ok = true
            if S.match_slot and slot ~= nil and call_static(SlotMethod, cid) ~= slot then ok = false end
            if ok and S.match_type and dtype ~= nil and call_static(TypeMethod, cid) ~= dtype then ok = false end
            if ok then
                local n = countInWindow(cid)
                if n == 0 then
                    unseen[#unseen + 1] = cid
                elseif n < fewest_n then
                    fewest, fewest_n = cid, n
                end
            end
        end
    end
    if #unseen > 0 then return unseen[math.random(#unseen)], "unseen" end
    if fewest then return fewest, "least seen" end
    return nil, nil
end

local swap_log = {}
local function logSwap(msg)
    table.insert(swap_log, 1, os.date("%H:%M:%S") .. "  " .. msg)
    while #swap_log > 30 do table.remove(swap_log) end
    log.info("[DecoPity] " .. msg)
end

local function handleGain(ep, box, id, gain, current)
    local seen = countInWindow(id)
    local threshold = math.max(1, tonumber(S.threshold) or 3)

    if S.enabled and seen >= threshold then
        local repl, how = pickReplacement(id, current)
        if repl then
            local before_repl = snapshot(box)[repl] or 0
            local have = current[id] or 0

            if setNum(box, id, have - gain) then
                local ok = pcall(function() ep:call("addAccessoryBox", repl, gain) end)
                local after = snapshot(box)
                if ok and (after[repl] or 0) == before_repl + gain then
                    logSwap(string.format("%s x%d (seen %d in window)  ->  %s x%d (%s)",
                        label(id), gain, seen, label(repl), gain, how))
                    record(repl, gain, true)
                    return
                end

                setNum(box, id, have)
                if (snapshot(box)[id] or 0) ~= have then
                    pcall(function() ep:call("addAccessoryBox", id, gain) end)
                end
                logSwap(string.format("%s x%d swap FAILED, original restored", label(id), gain))
            else
                logSwap(string.format("%s x%d swap FAILED, could not edit the box", label(id), gain))
            end
        else
            logSwap(string.format("%s x%d seen %d but no replacement of the same slot/type", label(id), gain, seen))
        end
    end

    record(id, gain, false)
end

local baseline = nil
local armed = false
local armed_until = 0
local next_poll = 0
local last_box_id = nil

local function boxId(box)
    local ok, addr = pcall(function() return box:get_address() end)
    if ok and addr then return addr end
    return tostring(box)
end

local function poll(ep, box)
    local current = snapshot(box)
    if baseline ~= nil then
        local gains = {}
        for id, num in pairs(current) do
            local diff = num - (baseline[id] or 0)
            if diff > 0 and isValidDeco(id) then gains[#gains + 1] = { id = id, n = diff } end
        end
        table.sort(gains, function(a, b) return a.id < b.id end)
        for _, g in ipairs(gains) do
            handleGain(ep, box, g.id, g.n, current)
            current = snapshot(box)
        end
    end
    baseline = snapshot(box)
end

local function arm()
    if not S.enabled then return end
    armed = true
    armed_until = os.clock() + (tonumber(S.arm_seconds) or 600)
    next_poll = 0
end

local hooked = false
local qm = sdk.find_type_definition("app.MissionMusicManager.QuestMusicManager")
local clear_method = qm and qm:get_method("onQuestClear")
if clear_method then
    sdk.hook(clear_method, function(args) end, function(retval)
        arm()
        return retval
    end)
    hooked = true
end

re.on_frame(function()
    local now = os.clock()
    if config_dirty and now >= config_save_at then
        config_dirty = false
        json.dump_file(CONF, DATA)
    end
    if not S.enabled then return end

    local ep = getEquip()
    local box = ep and getBox(ep)
    if not box then
        baseline = nil
        return
    end
    local id = boxId(box)
    if id ~= last_box_id then
        last_box_id = id
        baseline = nil
        armed = false
    end

    if S.watch_always or armed then
        if now >= next_poll then
            next_poll = now + POLL_ARMED
            local ok, err = pcall(poll, ep, box)
            if not ok then log.error("[DecoPity] poll failed: " .. tostring(err)) end
        end
        if armed and not S.watch_always and now > armed_until then armed = false end
    elseif now >= next_poll then
        next_poll = now + POLL_IDLE
        baseline = snapshot(box)
    end
end)

re.on_draw_ui(function()
    if not imgui.tree_node("Decoration Pity") then return end
    local changed

    changed, S.enabled = imgui.checkbox("Enable", S.enabled)
    if changed then markDirty() end

    changed, S.threshold = imgui.slider_int("Swap after this many copies in window", S.threshold, 1, 20)
    if changed then markDirty() end

    changed, S.window_hours = imgui.slider_int("Window in hours (0 = today)", S.window_hours, 0, 168)
    if changed then markDirty() end

    changed, S.arm_seconds = imgui.slider_int("Watch seconds after quest clear", S.arm_seconds, 30, 1800)
    if changed then markDirty() end

    changed, S.match_slot = imgui.checkbox("Replacement keeps the slot level", S.match_slot)
    if changed then markDirty() end

    changed, S.match_type = imgui.checkbox("Replacement keeps the type (weapon / armor)", S.match_type)
    if changed then markDirty() end

    changed, S.pool_all = imgui.checkbox("Pick from all decorations (not just owned)", S.pool_all)
    if changed then markDirty() end

    changed, S.watch_always = imgui.checkbox("Watch all the time (counts every gain)", S.watch_always)
    if changed then markDirty() end

    imgui.text(hooked and "Quest clear hook: active" or "Quest clear hook: NOT found, enable 'Watch all the time'")
    imgui.text(armed and "Status: watching for quest rewards" or "Status: idle")

    local since, total = windowStart(), 0
    for _, h in ipairs(DATA.history) do
        if h.t >= since then total = total + (h.n or 1) end
    end
    imgui.text(string.format("Decorations received in window: %d   Logged entries: %d", total, #DATA.history))

    if imgui.button("Clear history") then
        DATA.history = {}
        markDirty()
    end

    if imgui.tree_node("Recent swaps (this session)") then
        if #swap_log == 0 then imgui.text("None yet") end
        for _, line in ipairs(swap_log) do imgui.text(line) end
        imgui.tree_pop()
    end

    imgui.tree_pop()
end)
