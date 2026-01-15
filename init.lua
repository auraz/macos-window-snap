--[[
================================================================================
HAMMERSPOON WINDOW SNAP
================================================================================

Automatically snaps windows to screen edges when dragged within a threshold.
Position-only snapping - does not resize windows.

INSTALLATION:
    1. Install Hammerspoon: brew install --cask hammerspoon
    2. Copy this file to: ~/.hammerspoon/init.lua
    3. Grant Accessibility permissions when prompted
    4. Reload config: Click menubar icon → Reload Config

USAGE:
    Just drag any window near a screen edge and release.
    The window will snap to the edge if within SNAP_THRESHOLD pixels.

CONFIGURATION:
    Modify the Config table below to customize behavior.

TESTING IN CONSOLE (Hammerspoon menubar → Console):
    -- Get focused window
    win = hs.window.focusedWindow()

    -- Check current position
    print(win:frame())

    -- Test snap detection
    print(hs.inspect(WindowSnap.getSnapPosition(win)))

    -- Manually trigger snap
    WindowSnap.snapWindow(win)

    -- Move window to test position (near left edge)
    f = win:frame(); f.x = 50; win:setFrame(f)

AUTHOR: Generated with Claude
LICENSE: MIT
================================================================================
--]]

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

--[[
Config table - modify these values to customize behavior.

Fields:
    snapThreshold (number): Distance in pixels from edge to trigger snap.
                           Default: 100
    snapDelay (number):     Seconds to wait after movement stops before snapping.
                           Prevents snapping while still dragging.
                           Default: 0.1
    enabledEdges (table):   Which edges to snap to.
                           Default: all true
    edgeOffsets (table):    Offset in pixels from each edge.
                           Positive = inward from edge.
                           Example: bottom = 200 snaps 200px above screen bottom.
                           Default: all 0

Example - increase threshold and disable bottom snapping:
    Config.snapThreshold = 150
    Config.enabledEdges.bottom = false

Example - snap bottom edge 200px above actual bottom (for widgets):
    Config.edgeOffsets.bottom = 200
--]]
Config = {
    snapThreshold = 200,
    snapDelay = 0.01,
    enabledEdges = {
        left = true,
        right = true,
        top = true,
        bottom = true
    },
    edgeOffsets = {
        left = 0,
        right = 0,
        top = 0,
        bottom = 200  -- Space for widgets
    }
}

--------------------------------------------------------------------------------
-- WINDOW SNAP MODULE
--------------------------------------------------------------------------------

--[[
WindowSnap module - core snapping functionality.

This module provides functions to detect and apply window snapping.
All functions are exposed globally for easy console testing.

Functions:
    WindowSnap.getScreenFrame(win) -> frame or nil
    WindowSnap.getSnapPosition(win) -> {x, y, w, h} or nil
    WindowSnap.snapWindow(win) -> nil
    WindowSnap.debouncedSnap(win) -> nil
--]]
WindowSnap = {}

-- Private state
local _state = {
    moveTimer = nil,
    lastMovedWindow = nil
}

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

--[[
Get the usable screen frame for a window.

The frame excludes the menu bar and dock, giving the actual
usable area where windows can be positioned.

Parameters:
    win (hs.window): The window to get screen frame for.

Returns:
    hs.geometry.rect: The usable screen frame.
    nil: If window has no associated screen.

Example:
    win = hs.window.focusedWindow()
    frame = WindowSnap.getScreenFrame(win)
    print(frame)  -- hs.geometry.rect(0,25,1920,1055)
--]]
function WindowSnap.getScreenFrame(win)
    if not win then return nil end

    local screen = win:screen()
    if screen then
        return screen:frame()
    end
    return nil
end

--------------------------------------------------------------------------------
-- SNAP DETECTION
--------------------------------------------------------------------------------

--[[
Calculate snap position for a window based on proximity to screen edges.

Checks each enabled edge and determines if the window should snap.
Does NOT resize the window - only adjusts position.

Parameters:
    win (hs.window): The window to check.

Returns:
    table: {x, y, w, h} - New position if snap should occur.
    nil: If window is not near any enabled edge.

Example:
    win = hs.window.focusedWindow()

    -- Move window near left edge
    f = win:frame()
    f.x = 50
    win:setFrame(f)

    -- Check if it should snap
    snapPos = WindowSnap.getSnapPosition(win)
    print(hs.inspect(snapPos))
    -- Output: { h = 800, w = 1200, x = 0, y = 100 }
    --         (x changed from 50 to 0 - snapped to left edge)
--]]
function WindowSnap.getSnapPosition(win)
    if not win then return nil end

    local frame = win:frame()
    local screenFrame = WindowSnap.getScreenFrame(win)

    if not screenFrame then return nil end

    local newX = frame.x
    local newY = frame.y
    local snapped = false
    local threshold = Config.snapThreshold
    local offsets = Config.edgeOffsets

    -- Check left edge
    -- Window's left side near screen's left edge (+ offset)
    if Config.enabledEdges.left then
        local snapTarget = screenFrame.x + offsets.left
        local distanceFromLeft = frame.x - snapTarget
        if distanceFromLeft >= -threshold and distanceFromLeft <= threshold then
            newX = snapTarget
            snapped = true
        end
    end

    -- Check right edge
    -- Window's right side near screen's right edge (- offset)
    if Config.enabledEdges.right then
        local windowRightEdge = frame.x + frame.w
        local snapTarget = screenFrame.x + screenFrame.w - offsets.right
        local distanceFromRight = windowRightEdge - snapTarget
        if distanceFromRight >= -threshold and distanceFromRight <= threshold then
            newX = snapTarget - frame.w
            snapped = true
        end
    end

    -- Check top edge
    -- Window's top side near screen's top edge (+ offset)
    if Config.enabledEdges.top then
        local snapTarget = screenFrame.y + offsets.top
        local distanceFromTop = frame.y - snapTarget
        if distanceFromTop >= -threshold and distanceFromTop <= threshold then
            newY = snapTarget
            snapped = true
        end
    end

    -- Check bottom edge
    -- Window's bottom side near screen's bottom edge (- offset)
    if Config.enabledEdges.bottom then
        local windowBottomEdge = frame.y + frame.h
        local snapTarget = screenFrame.y + screenFrame.h - offsets.bottom
        local distanceFromBottom = windowBottomEdge - snapTarget
        if distanceFromBottom >= -threshold and distanceFromBottom <= threshold then
            newY = snapTarget - frame.h
            snapped = true
        end
    end

    if snapped then
        return {
            x = newX,
            y = newY,
            w = frame.w,
            h = frame.h
        }
    end
    return nil
end

--------------------------------------------------------------------------------
-- SNAP APPLICATION
--------------------------------------------------------------------------------

--[[
Apply snap position to a window.

Checks if window should snap and applies the new position if so.
Wrapped in pcall for safety - handles windows that may have closed.

Parameters:
    win (hs.window): The window to snap.

Returns:
    nil

Example:
    win = hs.window.focusedWindow()

    -- Move near edge then snap
    f = win:frame()
    f.x = 30
    win:setFrame(f)

    WindowSnap.snapWindow(win)
    -- Window is now at x=0 (snapped to left edge)
--]]
function WindowSnap.snapWindow(win)
    if not win then return end

    -- Use pcall to safely handle windows that may have closed
    local success, err = pcall(function()
        if not win:isStandard() then return end

        local snapPos = WindowSnap.getSnapPosition(win)
        if snapPos then
            win:setFrame(hs.geometry.rect(
                snapPos.x,
                snapPos.y,
                snapPos.w,
                snapPos.h
            ))
        end
    end)

    if not success then
        print("WindowSnap: Error snapping window - " .. tostring(err))
    end
end

--------------------------------------------------------------------------------
-- DEBOUNCING
--------------------------------------------------------------------------------

--[[
Debounced snap - waits for movement to stop before snapping.

While dragging, many windowMoved events fire rapidly. This function
resets a timer on each call. Snap only occurs after no events for
Config.snapDelay seconds.

Flow:
    Drag starts → windowMoved fires → timer starts
    Still dragging → windowMoved fires → timer resets
    Still dragging → windowMoved fires → timer resets
    Release mouse → no more events → timer expires → SNAP!

Parameters:
    win (hs.window): The window being moved.

Returns:
    nil

Example:
    -- This is called automatically by the window filter.
    -- Manual testing:
    win = hs.window.focusedWindow()
    WindowSnap.debouncedSnap(win)
    -- Wait 0.1 seconds... snap occurs
--]]
function WindowSnap.debouncedSnap(win)
    _state.lastMovedWindow = win

    -- Cancel any existing timer
    if _state.moveTimer then
        _state.moveTimer:stop()
        _state.moveTimer = nil
    end

    -- Start new timer
    _state.moveTimer = hs.timer.doAfter(Config.snapDelay, function()
        if _state.lastMovedWindow then
            WindowSnap.snapWindow(_state.lastMovedWindow)
            _state.lastMovedWindow = nil
        end
        _state.moveTimer = nil
    end)
end

--------------------------------------------------------------------------------
-- EVENT LISTENER
--------------------------------------------------------------------------------

--[[
Window filter setup - listens for window movement events.

Uses Hammerspoon's hs.window.filter to detect when any standard
window is moved. More reliable than tracking mouse events.

The filter:
    - Watches all visible standard windows
    - Fires windowMoved event when position changes
    - Calls debouncedSnap to handle the movement
--]]
local function setupWindowFilter()
    local windowFilter = hs.window.filter.new()
        :setDefaultFilter()
        :setOverrideFilter({
            visible = true,
            allowRoles = {'AXStandardWindow'}
        })

    windowFilter:subscribe(
        hs.window.filter.windowMoved,
        function(win, appName, event)
            if win and win:isStandard() then
                WindowSnap.debouncedSnap(win)
            end
        end
    )

    return windowFilter
end

--------------------------------------------------------------------------------
-- INITIALIZATION
--------------------------------------------------------------------------------

--[[
Initialize the window snap functionality.

Called automatically when this config loads.
Sets up the window filter and shows confirmation alert.
--]]
local function init()
    -- Keep reference to prevent garbage collection
    _state.windowFilter = setupWindowFilter()

    -- Confirmation
    hs.alert.show("Window Snap Ready!")
    print("================================================================================")
    print("WINDOW SNAP LOADED")
    print("================================================================================")
    print("Snap threshold: " .. Config.snapThreshold .. " pixels")
    print("Snap delay: " .. Config.snapDelay .. " seconds")
    print("Enabled edges: left=" .. tostring(Config.enabledEdges.left) ..
          ", right=" .. tostring(Config.enabledEdges.right) ..
          ", top=" .. tostring(Config.enabledEdges.top) ..
          ", bottom=" .. tostring(Config.enabledEdges.bottom))
    print("")
    print("Test in console:")
    print("  win = hs.window.focusedWindow()")
    print("  print(hs.inspect(WindowSnap.getSnapPosition(win)))")
    print("================================================================================")
end

-- Run initialization
init()
