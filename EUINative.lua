local ADDON_NAME, ns = ...

-- Native window shells for the two stock whole-UI looks (Blizzard Style and
-- Classic WoW UI) that can be picked on EllesmereUI's Style page. EUI's
-- third-party skin only ever resolves to its own two house themes, so while
-- a stock look is active the bridge (EUI.lua) skips the facade entirely and
-- the addon paints its own shell here instead: Blizzard's dialog art for the
-- Blizzard look, the vanilla rock window for Classic. Everything is plain
-- SetBackdrop work on frames the addon owns -- no EUI internals, no hooks,
-- and the look only changes with a UI reload, so a frame is painted once at
-- registration and never migrates mid-session.
--
-- Callers re-tint afterwards through SetBackdropColor / BorderColor: the
-- dark fill set here matches the addon's own windows, and the gold border is
-- left untinted so the art keeps its colors.

local BACKDROPS = {
    blizzard = {
        -- Blizzard's static-dialog art: the stock window behind every
        -- confirmation popup. The main window wears this.
        shell = {
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        },
        -- The tooltip frame: thin gold border, black fill. The HUD panels
        -- read as information boxes rather than dialogs.
        panel = {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        },
    },
    classic = {
        -- The vanilla window: rock background with the tooltip border, as
        -- the original quest log and character panes wore it.
        shell = {
            bgFile = "Interface\\FrameGeneral\\UI-Background-Rock",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 512,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        },
        panel = {
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        },
    },
}

-- The backdrop fill every native shell is tinted with: the addon's own dark
-- blue-black, so a stock-look window sits in the same color family as the
-- unit frames and Blizzard's own windows. The art textures are multiplied by
-- this, so a light source texture (the vanilla rock) still reads dark while
-- keeping its grain.
local BG_R, BG_G, BG_B = 0.05, 0.05, 0.06

-- frame -> { kind, style } for every frame already wearing a native shell.
-- Weak keys: the frames own the entries, so a discarded frame leaves nothing
-- behind.
local shells = setmetatable({}, { __mode = "k" })

-- The fill callers re-apply (with their own opacity) after the shell is up.
function ns.GetNativeShellBackdropColor()
    return BG_R, BG_G, BG_B
end

-- Paint (or repaint) the native shell for one registered frame. Idempotent:
-- the backdrop table is only re-set when the frame's kind or the resolved
-- look changed, so style-refresh paths may call this freely.
function ns.ApplyNativeShell(frame, kind, style)
    if not frame or not frame.SetBackdrop then return end
    local defs = BACKDROPS[style]
    local def = defs and defs[kind]
    if not def then return end
    local applied = shells[frame]
    if not applied or applied.kind ~= kind or applied.style ~= style then
        frame:SetBackdrop(def)
        shells[frame] = { kind = kind, style = style }
    end
    frame:SetBackdropColor(BG_R, BG_G, BG_B, 1)
    frame:SetBackdropBorderColor(1, 1, 1, 1)
end
