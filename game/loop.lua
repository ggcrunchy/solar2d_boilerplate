--- Common game loop logic.

--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--
-- [ MIT license: http://www.opensource.org/licenses/mit-license.php ]
--

-- Standard library imports --
local assert = assert
local running = coroutine.running
local status = coroutine.status
local type = type
local wrap = coroutine.wrap
local yield = coroutine.yield

-- Modules --
local bind = require("tektite_core.bind")
local game_loop_config = require("config.GameLoop")
local persistence = require("corona_utils.persistence")
local scenes = require("corona_utils.scenes")

-- Corona globals --
local Runtime = Runtime

-- Corona modules --
local composer = require("composer")

-- Exports --
local M = {}

-- Assorted values, during normal play... --
local NormalValues = game_loop_config.normal_values

-- ...those same values, if the level was launched from the editor... --
local TestingValues = game_loop_config.testing_values

-- ...or from the intro / title screen... --
local QuickTestValues = game_loop_config.quick_test_values

-- ...the current set of values in effect  --
local Values

--- DOCME
function M.GetWaitToEndTime ()
	return Values.wait_to_end
end

-- Helper to call a possibly non-existent function
local function Call (func, ...)
	if func then
		return func(...)
	end
end

-- Decodes a level blob into a level list-compatible form
local function Decode (str)
	local level = persistence.Decode(str)

	Call(game_loop_config.on_decode, level)

	return level
end

-- State of in-progress level --
local CurrentLevel

-- In-progress loading coroutine --
local Loading

-- Running coroutine: used to detect runaway errors --
local Running

-- Loads part of the scene, and handles completion
local function LoadSome ()
	-- After the first frame, we have a handle to the running coroutine. The coroutine will
	-- go dead either when the loading finishes or if there was an error along the way, and
	-- in both cases we remove it.
	if Running and status(Running) == "dead" then
		Loading, Running = nil

		Runtime:removeEventListener("enterFrame", LoadSome)

	-- Coroutine still alive: run it another frame.
	else
		Loading()
	end
end

-- Cues an overlay scene
local function DoOverlay (name, func, arg)
	if name and Values == NormalValues then
		scenes.Send("message:show_overlay", name, func, arg)
	else
		func(arg)
	end
end

-- Coming from -> values map; fallback values --
local ComingFromValues, DefValues = {}, NormalValues

-- Set up the value associations.
for what, values in pairs{ normal = NormalValues, quick_test = QuickTestValues, testing = TestingValues } do
	local come_from = game_loop_config["coming_from_" .. what]

	if come_from then
		ComingFromValues[come_from] = values
	end

	if what == game_loop_config.default_values then
		DefValues = values
	end
end

--- Loads a level.
--
-- The level information is gathered into a table and the **enter_level** event list is
-- dispatched with said table as argument. It has the following fields:
--
-- * **ncols**, **nrows**: Columns wide and rows tall of level, respectively.
-- * **w**, **h**: Tile width and height, respectively.
-- * **game_group**, **hud_group**: Primary display groups.
-- * **bg_layer**, **tiles_layer**, **decals_layer**, **things_layer**, **markers_layer**:
-- Game group sublayers.
--
-- After tiles and game objects have been added to the level, the **things_loaded** event
-- list is dispatched, with the same argument.
-- @pgroup view Level scene view.
-- @param which As a **uint**, a level index as per @{game.LevelsList.GetLevel}. As a
-- **string**, a level as archived by @{corona_utils.persistence.Encode}.
function M.LoadLevel (view, which)
	assert(not CurrentLevel, "Level not unloaded")
	assert(not Loading, "Load already in progress")

	Values = ComingFromValues[scenes.ComingFrom()] or DefValues

	Loading = wrap(function()
		Running = running()

		-- Get the level info, either by decoding a database blob or grabbing it from the list.
		local level

		if type(which) == "string" then
			level, which = Decode(which), ""
		else
			level = game_loop_config.level_list.GetLevel(which)
		end

		-- Do some preparation before entering.
		CurrentLevel = { which = which }

		Call(game_loop_config.before_entering, view, CurrentLevel, level, game_loop_config.level_list)

		-- Dispatch to "enter level" observers, now that the basics are in place.
		bind.Reset("loading_level")

		CurrentLevel.name = "enter_level"

		Runtime:dispatchEvent(CurrentLevel)

		-- Add things to the level.
		Call(game_loop_config.add_things, CurrentLevel, level)

		-- Patch up deferred objects.
		bind.Resolve("loading_level")

		-- Some of the loading may have been expensive, which can lead to an unnatural
		-- start, since various things will act as if that time had passed for them as
		-- well. We try to account for this by waiting a frame and getting a fresh start.
		-- This will actually go several frames in the typical (i.e. non-testing) case
		-- that we are showing a "starting the level" overlay at the same time.
		local is_done = false

		DoOverlay(game_loop_config.start_overlay, function()
			is_done = true
		end)

		repeat yield() until is_done

		-- Dispatch to "things_loaded" observers, now that most objects are in place.
		CurrentLevel.name = "things_loaded"

		Runtime:dispatchEvent(CurrentLevel)

		CurrentLevel.is_loaded = true
	end)

	Runtime:addEventListener("enterFrame", LoadSome)
end

-- Helper to leave level
local function Leave (info)
	Runtime:dispatchEvent{ name = "leave_level", why = info.why }

	--
	local return_to = Values.return_to

	if type(return_to) == "function" then
		return_to = return_to(info)
	end

	composer.gotoScene(return_to, game_loop_config.leave_effect)
end

-- Possible overlays to play on unload --
local Overlay = { won = game_loop_config.win_overlay, lost = game_loop_config.lost_overlay }

--- Unloads the current level and returns to a menu.
--
-- This will be the appropriate game or editor menu, depending on how the level was launched.
--
-- The **leave_level** event list is dispatched, with _why_ as argument.
-- @string why Reason for unloading, which should be **won"**, **"lost"**, or **"quit"**.
function M.UnloadLevel (why)
	assert(not Loading, "Cannot unload: load in progress")
	assert(CurrentLevel, "No level to unload")

	if CurrentLevel.is_loaded then
		CurrentLevel.is_loaded = false

		Runtime:dispatchEvent{ name = "level_done", why = why }

		DoOverlay(Overlay[why], Leave, { which = CurrentLevel.which, why = why })
	end
end

-- Perform any other initialization.
Call(game_loop_config.on_init)

-- Listen to events.
Runtime:addEventListener("enter_menus", function()
	Call(game_loop_config.cleanup, CurrentLevel)

	CurrentLevel = nil
end)

-- Export the module.
return M