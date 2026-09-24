local timers = {}
local frames = {}
local sent = {}
local sendResult = 0
local serverTime = 1000
local party = {}
local inParty = true
local leader = false
local namesReadable = true
local secretBooleans = false
local db = { announceMode = "auto" }
local runGain = true
local welcome = true

local widgetMethods = {}
function widgetMethods:RegisterEvent(name) self.events[name] = true end
function widgetMethods:SetScript(name, callback) self.scripts[name] = callback end
setmetatable(widgetMethods, { __index = function() return function() end end })

_G.CreateFrame = function(_, name)
    local frame = setmetatable({ name = name, scripts = {}, events = {} }, { __index = widgetMethods })
    frames[#frames + 1] = frame
    return frame
end
_G.C_Timer = { After = function(delay, callback)
    timers[#timers + 1] = { delay = delay, callback = callback }
end }
_G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() end,
    SendAddonMessage = function(prefix, message, channel)
        sent[#sent + 1] = { prefix = prefix, message = message, channel = channel }
        return sendResult
    end,
}
_G.GetServerTime = function() return serverTime end
_G.GetRealmName = function() return "Realm" end
_G.UnitFullName = function(unit)
    local full = party[unit]
    if not full then return nil end
    if not namesReadable and unit ~= "player" then return nil end
    local name, realm = full:match("^([^%-]+)%-(.+)$")
    return name, realm
end
_G.UnitName = function(unit)
    local full = party[unit]
    if not full then return nil end
    if not namesReadable and unit ~= "player" then return nil end
    return full:match("^([^%-]+)")
end
_G.UnitExists = function(unit) return party[unit] ~= nil end
_G.IsInGroup = function() return inParty end
_G.IsInRaid = function() return false end
_G.UnitIsGroupLeader = function() return leader end
_G.LE_PARTY_CATEGORY_HOME = 1

local ns = {
    Util = {
        SafeString = function(value) return type(value) == "string" and value or nil end,
        SafeNumber = function(value)
            if type(value) == "number" and value == value then return value end
            return nil
        end,
        IsAccessible = function(value)
            if secretBooleans and type(value) == "boolean" then return false end
            return true
        end,
    },
    GetDB = function() return db end,
    GetCharacterKey = function() return "Player-1" end,
    IsRunGainAnnouncementEnabled = function() return runGain end,
    IsMemberWelcomeEnabled = function() return welcome end,
    GetAnnounceMode = function() return db.announceMode end,
}

local function LoadAnnouncer()
    assert(loadfile("Announcer.lua"))("QFXMythicRankHUD", ns)
    return frames[#frames]
end

local function RunTimers(max)
    local count = 0
    while #timers > 0 and (not max or count < max) do
        local item = table.remove(timers, 1)
        item.callback()
        count = count + 1
    end
    return count
end

local function Reset()
    timers = {}
    sent = {}
    sendResult = 0
    party = {}
    inParty = true
    leader = false
    db = { announceMode = "auto" }
    runGain = true
    welcome = true
end

-- 1. Joining a party broadcasts a HELLO and elects the only member.
Reset()
party = { player = "Me-Realm" }
local eventFrame = LoadAnnouncer()
eventFrame.scripts.OnEvent(eventFrame, "PLAYER_ENTERING_WORLD")
RunTimers()
assert(#sent == 1, "solo join did not broadcast exactly one HELLO")
assert(sent[1].prefix == "QFXMRH", "wrong addon message prefix")
assert(sent[1].message:match("^H:1:1:1:%d+:0$"), "malformed HELLO: " .. tostring(sent[1].message))
assert(sent[1].channel == "PARTY", "HELLO was not sent to the party channel")
assert(ns.Announcer.IsAnnouncer("run") == true, "solo member should announce")
assert(ns.Announcer.IsAnnouncer("welcome") == true, "solo member should welcome")

-- 2. An earlier joiner takes index 1 and is answered once.
sent = {}
party.party1 = "Aaa-Realm"
eventFrame.scripts.OnEvent(eventFrame, "CHAT_MSG_ADDON", "QFXMRH", "H:1:1:1:800:0", "PARTY", "Outsider-Realm")
eventFrame.scripts.OnEvent(eventFrame, "CHAT_MSG_ADDON", "QFXMRH", "H:1:1:1:800:0", "WHISPER", "Aaa-Realm")
assert(ns.Announcer.ComputeIndex("run") == 1, "non-party message affected the election")
eventFrame.scripts.OnEvent(eventFrame, "CHAT_MSG_ADDON", "QFXMRH", "H:1:1:1:900:0", "PARTY", "Aaa-Realm")
assert(ns.Announcer.IsAnnouncer("run") == false, "earlier joiner should announce instead")
assert(ns.Announcer.IsAnnouncer("welcome") == false, "earlier joiner should welcome instead")
RunTimers()
assert(#sent == 1, "HELLO was not answered exactly once")
assert(sent[1].message:match("^H:1:1:1:1000:0$"), "reply used the wrong join time")

-- A duplicate HELLO from the same sender must not trigger another reply.
sent = {}
eventFrame.scripts.OnEvent(eventFrame, "CHAT_MSG_ADDON", "QFXMRH", "H:1:1:1:900:0", "PARTY", "Aaa-Realm")
RunTimers()
assert(#sent == 0, "duplicate HELLO was answered twice")

-- 3. A later joiner keeps the local member at index 1.
sent = {}
party.party2 = "Bbb-Realm"
eventFrame.scripts.OnEvent(eventFrame, "CHAT_MSG_ADDON", "QFXMRH", "H:1:1:1:1100:0", "PARTY", "Bbb-Realm")
assert(ns.Announcer.IsAnnouncer("run") == false, "member with index 2 announced")
assert(ns.Announcer.ComputeIndex("run") == 2, "local member is not index 2")
leader = true
assert(ns.Announcer.ComputeIndex("run") == 1, "willing party leader did not outrank an earlier joiner")
leader = false

-- 4. When the earlier joiner leaves, the next member takes over.
party.party1 = nil
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
assert(ns.Announcer.IsAnnouncer("run") == true, "member did not take over after the announcer left")
assert(ns.Announcer.ComputeIndex("run") == 1, "local member is not index 1 after takeover")

-- 5. Willing flags are per announcement kind.
runGain = false
assert(ns.Announcer.IsAnnouncer("run") == false, "disabled run summary still elected an announcer")
assert(ns.Announcer.IsAnnouncer("welcome") == true, "welcome election ignored the run summary switch")
runGain = true

-- 6. Explicit modes bypass the election.
db.announceMode = "all"
assert(ns.Announcer.IsAnnouncer("run") == true, "mode all did not announce")
db.announceMode = "leader"
assert(ns.Announcer.IsAnnouncer("run") == false, "mode leader announced without being leader")
sent = {}
ns.Announcer.Refresh(0)
RunTimers()
assert(sent[#sent].message:match("^H:1:0:0:%d+:0$"),
    "non-leader advertised itself as willing in leader-only mode")
leader = true
assert(ns.Announcer.IsAnnouncer("run") == true, "mode leader ignored the party leader")
sent = {}
ns.Announcer.Refresh(0)
RunTimers()
assert(sent[#sent].message:match("^H:1:1:1:%d+:1$"),
    "party leader failed to advertise its willingness")
-- 6b. A secret leader flag (12.x unit-identity restriction) must degrade to
-- "not leader" instead of erroring.
secretBooleans = true
assert(ns.Announcer.IsAnnouncer("run") == false, "secret leader flag was not degraded")
secretBooleans = false
assert(ns.Announcer.IsAnnouncer("run") == true, "leader flag stopped working after the secret read")
leader = false
db.announceMode = "auto"

-- 7. Tie on the join timestamp is broken by the leader flag, then the name.
party.party1 = "Aaa-Realm"
eventFrame.scripts.OnEvent(eventFrame, "CHAT_MSG_ADDON", "QFXMRH", "H:1:1:1:1000:0", "PARTY", "Aaa-Realm")
assert(ns.Announcer.IsAnnouncer("run") == false, "name tie-break failed (Aaa sorts before Me)")
leader = true
assert(ns.Announcer.IsAnnouncer("run") == true, "leader tie-break failed")
leader = false
eventFrame.scripts.OnEvent(eventFrame, "GROUP_ROSTER_UPDATE")
RunTimers()

-- 7b. A willing party leader outranks an earlier joiner.
sent = {}
eventFrame.scripts.OnEvent(eventFrame, "CHAT_MSG_ADDON", "QFXMRH", "H:1:1:1:900:0", "PARTY", "Aaa-Realm")
RunTimers()
assert(ns.Announcer.IsAnnouncer("run") == false, "earlier joiner should win without a leader")
leader = true
assert(ns.Announcer.IsAnnouncer("run") == true, "willing leader did not outrank the earlier joiner")
leader = false

-- 8. A failed send (encounter lockdown) must not break the election.
sendResult = 11
eventFrame.scripts.OnEvent(eventFrame, "CHALLENGE_MODE_COMPLETED")
RunTimers()
assert(ns.Announcer.ComputeIndex("run") == 2, "lockdown send broke the election")
sendResult = 0

-- 9. A reload restores the election from the saved state.
local reloadedFrame = LoadAnnouncer()
serverTime = 1200
reloadedFrame.scripts.OnEvent(reloadedFrame, "PLAYER_ENTERING_WORLD")
RunTimers()
assert(ns.Announcer.IsAnnouncer("run") == false, "reload lost the earlier joiner")
assert(ns.Announcer.ComputeIndex("run") == 2, "reload changed the local index")

-- 9b. When unit names are unreadable (12.x encounter restriction), the saved
-- state and the cached peer list survive instead of being pruned away.
party = { player = "Me-Realm", party1 = "Aaa-Realm" }
local restrictedFrame = LoadAnnouncer()
serverTime = 1300
namesReadable = false
restrictedFrame.scripts.OnEvent(restrictedFrame, "PLAYER_ENTERING_WORLD")
RunTimers()
assert(ns.Announcer.ComputeIndex("run") == 2, "restricted names dropped the restored election state")
restrictedFrame.scripts.OnEvent(restrictedFrame, "GROUP_ROSTER_UPDATE")
RunTimers()
assert(ns.Announcer.ComputeIndex("run") == 2, "restricted names pruned the peer list")
namesReadable = true

-- 10. Stale state (older than a day) is dropped and the member re-joins.
local store = db.announcer["Player-1"]
assert(type(store) == "table", "election state was not persisted")
store.savedAt = serverTime - (25 * 60 * 60)
local staleFrame = LoadAnnouncer()
staleFrame.scripts.OnEvent(staleFrame, "PLAYER_ENTERING_WORLD")
RunTimers()
assert(ns.Announcer.IsAnnouncer("run") == true, "stale state was not dropped")
assert(db.announcer["Player-1"].savedAt == serverTime, "stale state was not replaced")

-- 11. A different party drops the saved state instead of inheriting it.
party = { player = "Me-Realm", party1 = "Ccc-Realm" }
local otherPartyFrame = LoadAnnouncer()
otherPartyFrame.scripts.OnEvent(otherPartyFrame, "PLAYER_ENTERING_WORLD")
RunTimers()
assert(ns.Announcer.ComputeIndex("run") == 1, "new party inherited a stale index")
assert(ns.Announcer.DescribeState():find("mode=auto", 1, true), "state description missing the mode")

-- 12. Leaving the party clears the state entirely.
inParty = false
otherPartyFrame.scripts.OnEvent(otherPartyFrame, "GROUP_ROSTER_UPDATE")
assert(db.announcer["Player-1"] == nil, "leaving the party kept the election state")
inParty = true

print("Announcer_test: OK")
