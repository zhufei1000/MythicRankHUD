local ADDON_NAME, ns = ...
local Util = ns.Util

-- Party announcement election: when several party members run this addon,
-- only the elected announcer posts the run summary and member welcomes.
-- Every member broadcasts a HELLO when it joins the party (or reloads) and
-- answers every HELLO it receives, so all clients see the same roster of
-- addon users. A willing party leader takes priority, then the party join
-- timestamp and full name break ties. Index 1 announces, the others keep a
-- local record only.
--
-- 12.x restricts addon messages during active encounters (M+ timers, boss
-- fights): a send that fails is not fatal, the cached peer list is used and
-- the election runs again when the run completes (out of combat).

local PREFIX = "QFXMRH"
local PROTOCOL_VERSION = 1
local STATE_TTL = 24 * 60 * 60
local REFRESH_DEBOUNCE = 1.0
local REHELLO_DELAY = 0.35
local RESULT_SUCCESS = 0

local peers = {} -- [fullName] = { joinTime, runGain, welcome, leader, at }
local repliedTo = {}
local joinTime
local wasInParty = false
local refreshScheduled = false
local lastSendIssue = "none"

local function Now()
    if type(GetServerTime) == "function" then
        local ok, value = pcall(GetServerTime)
        if ok and type(value) == "number" and value > 0 then
            return value
        end
    end
    local timeFn = type(time) == "function" and time or (type(os) == "table" and os.time) or nil
    if timeFn then
        local ok, value = pcall(timeFn)
        if ok and type(value) == "number" and value > 0 then
            return value
        end
    end
    return 0
end

local function NormalizeRealm(realm)
    local value = Util.SafeString(realm)
    if not value or value == "" then
        return nil
    end
    return value
end

local function GetFullName(unit)
    unit = unit or "player"
    if type(UnitFullName) == "function" then
        local ok, name, realm = pcall(UnitFullName, unit)
        name = ok and Util.SafeString(name) or nil
        realm = ok and NormalizeRealm(realm) or nil
        if name and name ~= "" then
            if not realm and type(GetRealmName) == "function" then
                local okRealm, selfRealm = pcall(GetRealmName)
                realm = okRealm and NormalizeRealm(selfRealm) or nil
            end
            if realm then
                return name .. "-" .. realm
            end
            return name
        end
    end
    if type(UnitName) == "function" then
        local ok, name = pcall(UnitName, unit)
        name = ok and Util.SafeString(name) or nil
        if name and name ~= "" then
            return name
        end
    end
    return nil
end

-- The player's own full name never changes during a session; it is cached so
-- the election keeps working when 12.x hides unit identities mid-encounter.
local cachedSelfName

local function GetSelfName()
    if cachedSelfName then
        return cachedSelfName
    end
    local name = GetFullName("player")
    if name and name ~= "" then
        cachedSelfName = name
    end
    return cachedSelfName
end

-- Used only as a fallback while unit identities are hidden; the stored name
-- belongs to this character because the state is keyed per character.
local function SetSelfNameFallback(name)
    if not cachedSelfName and type(name) == "string" and name ~= "" then
        cachedSelfName = name
    end
end

-- Addon message senders omit the realm on the same realm; align them with the
-- "Name-Realm" keys used for party members.
local function NormalizeSender(sender)
    local value = Util.SafeString(sender)
    if not value or value == "" then
        return nil
    end
    value = value:gsub("%(%*%)$", ""):gsub("%-%*$", "")
    if not value:find("-", 1, true) then
        local selfName = GetSelfName()
        local selfRealm
        if selfName then
            _, _, selfRealm = selfName:find("^[^%-]+%-(.+)$")
        end
        if selfRealm then
            return value .. "-" .. selfRealm
        end
    end
    return value
end

local function IsInParty()
    if type(IsInGroup) ~= "function" then
        return false
    end
    local ok, grouped = pcall(IsInGroup, _G.LE_PARTY_CATEGORY_HOME or 1)
    if not ok or not grouped then
        return false
    end
    if type(IsInRaid) == "function" then
        local okRaid, raid = pcall(IsInRaid)
        if okRaid and raid then
            return false
        end
    end
    return true
end

-- UnitIsGroupLeader covers parties and raids; IsPartyLeader was removed in
-- 5.0.4 and does not exist on modern clients. The API is marked
-- SecretWhenUnitIdentityRestricted on 12.x, so a secret (or failed) read is
-- treated as "not the leader" instead of erroring.
local function IsLeader()
    if type(UnitIsGroupLeader) ~= "function" then
        return false
    end
    local ok, leader = pcall(UnitIsGroupLeader, "player")
    if not ok then
        return false
    end
    if type(leader) ~= "boolean" or not Util.IsAccessible(leader) then
        return false
    end
    return leader
end

local function UnitExistsSafe(unit)
    if type(UnitExists) ~= "function" then
        return true
    end
    local ok, exists = pcall(UnitExists, unit)
    return ok and exists == true
end

local function GetPartyNames()
    local names = {}
    local selfName = GetSelfName()
    if selfName then
        names[selfName] = true
    end
    for index = 1, 4 do
        local unit = "party" .. index
        if UnitExistsSafe(unit) then
            local name = GetFullName(unit)
            if name then
                names[name] = true
            end
        end
    end
    return names
end

-- 12.x can hide unit identities (and therefore names) during encounters. When
-- a party member exists but their name is unreadable, every name-based
-- decision is skipped so the cached peer list and the saved election state
-- survive the restriction instead of being treated as "member left".
local function IsNameReadable()
    if type(UnitExists) ~= "function" then
        return true
    end
    for index = 1, 4 do
        local unit = "party" .. index
        if UnitExistsSafe(unit) and not GetFullName(unit) then
            return false
        end
    end
    return true
end

local function CountOtherMembers()
    local selfName = GetSelfName()
    local count = 0
    for name in pairs(GetPartyNames()) do
        if name ~= selfName then
            count = count + 1
        end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Persisted election state (per character)
-- ---------------------------------------------------------------------------

local cachedCharacterKey

-- The character key read is defensive: UnitGUID can be restricted on 12.x
-- clients, and a failure must not abort the election bookkeeping. The key is
-- stable for the session, so a successful read is cached.
local function GetCharacterKeySafe()
    if cachedCharacterKey then
        return cachedCharacterKey
    end
    if type(ns.GetCharacterKey) ~= "function" then
        return nil
    end
    local ok, key = pcall(ns.GetCharacterKey)
    key = ok and Util.SafeString(key) or nil
    if key and key ~= "" then
        cachedCharacterKey = key
    end
    return cachedCharacterKey
end

local function GetStore(create)
    local db = type(ns.GetDB) == "function" and ns.GetDB() or nil
    local key = GetCharacterKeySafe()
    if type(db) ~= "table" or not key or key == "" then
        return nil
    end
    if type(db.announcer) ~= "table" then
        if not create then
            return nil
        end
        db.announcer = {}
    end
    local store = db.announcer[key]
    if type(store) ~= "table" then
        if not create then
            return nil
        end
        store = {}
        db.announcer[key] = store
    end
    return store
end

local function ClearStore()
    local db = type(ns.GetDB) == "function" and ns.GetDB() or nil
    local key = GetCharacterKeySafe()
    if type(db) == "table" and type(db.announcer) == "table" and key then
        db.announcer[key] = nil
    end
end

local function SaveState()
    local store = GetStore(true)
    if not store then
        return
    end
    store.joinTime = joinTime
    store.savedAt = Now()
    store.selfName = GetSelfName()
    local savedPeers = {}
    for name, peer in pairs(peers) do
        savedPeers[name] = {
            joinTime = peer.joinTime,
            runGain = peer.runGain == true,
            welcome = peer.welcome == true,
            leader = peer.leader == true,
        }
    end
    store.peers = savedPeers
    local members = {}
    for name in pairs(GetPartyNames()) do
        members[#members + 1] = name
    end
    store.members = members
end

-- Restores the election state after a reload or reconnect. The stored party
-- fingerprint must overlap the current party, otherwise the character joined
-- a different group and the state is dropped.
local function TryRestoreState()
    local store = GetStore(false)
    if not store then
        return false
    end
    local now = Now()
    local savedAt = tonumber(store.savedAt)
    if not savedAt or now <= 0 or (now - savedAt) > STATE_TTL then
        ClearStore()
        return false
    end
    local restoredJoin = tonumber(store.joinTime)
    if not restoredJoin or restoredJoin <= 0 then
        ClearStore()
        return false
    end
    SetSelfNameFallback(store.selfName)

    -- The name-based fingerprint check only runs when the client can read
    -- party names; during an encounter the restriction hides them, and the
    -- saved state is trusted (it still passes the age check above).
    local readable = IsNameReadable()
    local partyNames = GetPartyNames()
    local selfName = GetSelfName()
    if readable then
        local savedMembers = type(store.members) == "table" and store.members or {}
        local matched = false
        for _, name in ipairs(savedMembers) do
            if name ~= selfName and partyNames[name] then
                matched = true
                break
            end
        end
        if not matched and CountOtherMembers() > 0 then
            ClearStore()
            return false
        end
    end

    joinTime = restoredJoin
    peers = {}
    repliedTo = {}
    if type(store.peers) == "table" then
        for name, peer in pairs(store.peers) do
            if name ~= selfName and type(peer) == "table"
                and (not readable or partyNames[name])
            then
                peers[name] = {
                    joinTime = tonumber(peer.joinTime) or 0,
                    runGain = peer.runGain == true,
                    welcome = peer.welcome == true,
                    leader = peer.leader == true,
                    at = now,
                }
            end
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Protocol
-- ---------------------------------------------------------------------------

local function IsWilling(kind)
    local mode = type(ns.GetAnnounceMode) == "function" and ns.GetAnnounceMode() or "auto"
    if mode == "leader" and not IsLeader() then
        return false
    end
    if kind == "welcome" then
        return type(ns.IsMemberWelcomeEnabled) == "function" and ns.IsMemberWelcomeEnabled() or false
    end
    return type(ns.IsRunGainAnnouncementEnabled) == "function" and ns.IsRunGainAnnouncementEnabled() or false
end

local function SendHello()
    if not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then
        lastSendIssue = "addon messages unavailable"
        return false
    end
    if not IsInParty() then
        lastSendIssue = "not in party"
        return false
    end
    if not joinTime or joinTime <= 0 then
        joinTime = Now()
    end
    local message = string.format(
        "H:%d:%d:%d:%d:%d",
        PROTOCOL_VERSION,
        IsWilling("run") and 1 or 0,
        IsWilling("welcome") and 1 or 0,
        math.floor(joinTime or 0),
        IsLeader() and 1 or 0
    )
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, "PARTY")
    if not ok then
        lastSendIssue = "send error"
        return false
    end
    if result == RESULT_SUCCESS or result == true then
        lastSendIssue = "none"
        return true
    end
    -- Enum.SendAddonMessageResult.AddOnMessageLockdown (11) is expected while
    -- an encounter is active; the cached peer list keeps working.
    lastSendIssue = "send result " .. tostring(result)
    return false
end

local function PrunePeers()
    if not IsNameReadable() then
        return
    end
    local partyNames = GetPartyNames()
    for name in pairs(peers) do
        if not partyNames[name] then
            peers[name] = nil
            repliedTo[name] = nil
        end
    end
end

local function OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX or channel ~= "PARTY" or not IsInParty() then
        return
    end
    message = Util.SafeString(message)
    sender = NormalizeSender(sender)
    if not message or not sender then
        return
    end
    local selfName = GetSelfName()
    if selfName and sender == selfName then
        return
    end
    -- Sender validation is skipped when names are unreadable (12.x encounter
    -- restriction); addon messages already only travel within the party.
    if IsNameReadable() and not GetPartyNames()[sender] then
        return
    end
    local version, runGain, welcome, peerJoin, leader =
        message:match("^H:(%d+):(%d+):(%d+):(%d+):(%d+)$")
    version = tonumber(version)
    if version ~= PROTOCOL_VERSION then
        return
    end
    peers[sender] = {
        joinTime = tonumber(peerJoin) or 0,
        runGain = runGain == "1",
        welcome = welcome == "1",
        leader = leader == "1",
        at = Now(),
    }
    if not repliedTo[sender] then
        repliedTo[sender] = true
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(REHELLO_DELAY, SendHello)
        else
            SendHello()
        end
    end
end

-- ---------------------------------------------------------------------------
-- Election
-- ---------------------------------------------------------------------------

local function BuildEntries(kind)
    local selfName = GetSelfName()
    if not selfName then
        return nil, nil
    end
    local entries = {
        {
            name = selfName,
            joinTime = joinTime or 0,
            leader = IsLeader(),
            willing = IsWilling(kind),
        },
    }
    for name, peer in pairs(peers) do
        entries[#entries + 1] = {
            name = name,
            joinTime = peer.joinTime or 0,
            leader = peer.leader == true,
            willing = kind == "welcome" and peer.welcome == true or peer.runGain == true,
        }
    end
    local willing = {}
    for _, entry in ipairs(entries) do
        if entry.willing then
            willing[#willing + 1] = entry
        end
    end
    table.sort(willing, function(left, right)
        if left.leader ~= right.leader then
            return left.leader
        end
        local leftTime = left.joinTime > 0 and left.joinTime or math.huge
        local rightTime = right.joinTime > 0 and right.joinTime or math.huge
        if leftTime ~= rightTime then
            return leftTime < rightTime
        end
        return left.name < right.name
    end)
    return willing, selfName
end

local function ComputeIndex(kind)
    local entries, selfName = BuildEntries(kind)
    if not entries or not selfName then
        return nil
    end
    for index, entry in ipairs(entries) do
        if entry.name == selfName then
            return index
        end
    end
    return nil
end

local function GetMode()
    if type(ns.GetAnnounceMode) == "function" then
        return ns.GetAnnounceMode()
    end
    return "auto"
end

local function IsAnnouncer(kind)
    kind = kind or "run"
    local mode = GetMode()
    if mode == "all" then
        return true
    end
    if mode == "leader" then
        return IsLeader()
    end
    if not IsInParty() then
        return true
    end
    return ComputeIndex(kind) == 1
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

local function DoRefresh()
    if not IsInParty() then
        return
    end
    if not joinTime or joinTime <= 0 then
        joinTime = Now()
    end
    PrunePeers()
    SendHello()
    SaveState()
end

local function RequestRefresh(delay)
    if refreshScheduled then
        return
    end
    local wait = delay or REFRESH_DEBOUNCE
    if C_Timer and type(C_Timer.After) == "function" then
        refreshScheduled = true
        C_Timer.After(wait, function()
            refreshScheduled = false
            DoRefresh()
        end)
    else
        DoRefresh()
    end
end

local function HandlePartyState()
    if not IsInParty() then
        if wasInParty then
            peers = {}
            repliedTo = {}
            joinTime = nil
            ClearStore()
        end
        wasInParty = false
        return
    end
    if not wasInParty then
        wasInParty = true
        if not joinTime or joinTime <= 0 then
            if not TryRestoreState() then
                joinTime = Now()
                peers = {}
                repliedTo = {}
            end
        end
        RequestRefresh(0)
        return
    end
    PrunePeers()
    RequestRefresh(0.5)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("CHALLENGE_MODE_COMPLETED")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        OnAddonMessage(prefix, message, channel, sender)
    elseif event == "PLAYER_ENTERING_WORLD" then
        HandlePartyState()
    elseif event == "GROUP_ROSTER_UPDATE" then
        HandlePartyState()
    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- The timer has ended and combat is over, so the election can run
        -- again before the delayed run summary is posted.
        RequestRefresh(2)
    end
end)

if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
end

local function CountPeers()
    local count = 0
    for _ in pairs(peers) do
        count = count + 1
    end
    return count
end

local function DescribeState()
    return string.format(
        "announcer: mode=%s joinTime=%s peers=%d index=%s leader=%s send=%s",
        tostring(GetMode()),
        tostring(joinTime),
        CountPeers(),
        tostring(ComputeIndex("run")),
        tostring(IsLeader()),
        tostring(lastSendIssue)
    )
end

ns.Announcer = {
    IsAnnouncer = IsAnnouncer,
    Refresh = RequestRefresh,
    ComputeIndex = ComputeIndex,
    DescribeState = DescribeState,
}
