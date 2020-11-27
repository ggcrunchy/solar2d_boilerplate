--- Stock driver code and main functions.

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

-- Apply fixes --
require("solar2d_boilerplate.FIXES")

-- Standard library imports --
local assert = assert
local error = error
local pcall = pcall
local print = print
local type = type
local unpack = unpack

-- Modules --
local call_chain = require("solar2d_utils.call_chain")
local coro_flow = require("solar2d_utils.coro_flow")
local device = require("solar2d_utils.device")
local frames = require("solar2d_utils.frames")
local var_dump = require("tektite_core.var.dump")

-- Solar2D globals --
local native = native
local Runtime = Runtime
local system = system

-- Solar2D modules --
local composer = require("composer")

--
--
--

display.setStatusBar(display.HiddenStatusBar)
display.setDefault("isShaderCompilerVerbose", true)

if system.getInfo("platform") == "android" and system.getInfo("environment") == "device" then
	native.setProperty("androidSystemUiVisibility", "immersiveSticky")
end

--
--
-- Coroutine time
--
--

local storage = coro_flow.MakeLocalStorage()

local function TimeFunc (used)
	local func = storage()

	if not func then
		local old_id, time_left = false -- use some non-number initial ID

		function func (deduct)
			local cur_id = Runtime.getFrameID()

			if cur_id ~= old_id then
				old_id, time_left = cur_id, frames.DiffTime()
			end

			if deduct == time_left then
				time_left = 0
			elseif deduct then
				time_left = time_left - deduct
			else
				return time_left
			end
		end

		storage(func)
	end

	return func(used)
end

coro_flow.SetTimeLapseFuncs(
	function() -- suppress arguments
		return TimeFunc()
	end,
	TimeFunc
)

--
--
-- "system" listener
--
--

Runtime:addEventListener("system", function(event)
	if event.type == "applicationStart" or event.type == "applicationResume" then
		device.EnumerateDevices()
	end
end)

--
--
-- "unhandledError" listener
--
--

if system.getInfo("environment") == "device" then
	Runtime:addEventListener("unhandledError", function(event)
		native.showAlert("Error!", event.errorMessage .. " \n " .. event.stackTrace, { "OK" }, native.requestExit)
	end)
end

--
--
-- "wants to go back" listener
--
--

local function AddHandledEvent (name, event_name)
	local chain = call_chain.New(event_name or name)

	composer.setVariable(name, chain)

	Runtime:addEventListener(event_name or name, chain)

	return chain
end

AddHandledEvent("wants_to_go_back")

local WantsToGoBackEvent = { name = "wants_to_go_back" }

local function WantsToGoBack ()
	Runtime:dispatchEvent(WantsToGoBackEvent)
end

composer.setVariable("WantsToGoBack", WantsToGoBack)

--
--
-- "key" listener
--
--

local handle_key = AddHandledEvent("handle_key", "key")

local VolumeChangeEvent = { name = "volume_change" }

handle_key:Push(function(event)
	local key = event.keyName

	if key == "volumeUp" or key == "volumeDown" then
		VolumeChangeEvent.change = key == "volumeUp" and "up" or "down"

		Runtime:dispatchEvent(VolumeChangeEvent)

		return true
	end
end)

handle_key:Push(function(event)
	local key = event.keyName

	if key == "back" or key == "deleteBack" then
		if event.phase == "down" then
			WantsToGoBack()
		end

		return true
	else
		return "call_next_handler" -- volume
	end
end)

handle_key:Bake()

--
--
-- "DEBUG_suppress_overlays" listener
--
--

local SuppressOverlays

Runtime:addEventListener("DEBUG_suppress_overlays", function()
	SuppressOverlays = true
end)

--
--
-- Overlay listeners
--
--

local function OverlayHandlersShell (handler, event)
	handler(event)

	return "call_next_handler"
end

local hide_overlay, oargs = AddHandledEvent("hide_overlay"), {}

hide_overlay:Push(function(event)
	if not SuppressOverlays then
		local n, effect, time = 0, event.effect, event.time

		assert(effect == nil or type(effect) == "string", "Invalid overlay hide effect")
		assert(time == nil or type(time) == "number" and time > 0, "Invalid overlay hide time")

		if event.recycleOnly == true then
			oargs[1], n = true, 2
		end

		if effect then
			oargs[n + 1], n = effect, n + 1
		end

		if time then
			oargs[n + 1], n = time, n + 1
		end

		composer.hideOverlay(unpack(oargs, 1, n))
	end
end)

hide_overlay:Bake()
hide_overlay:SetShell(OverlayHandlersShell)

local show_overlay = AddHandledEvent("show_overlay")

show_overlay:Push(function(event)
	if event.overlay_name and not SuppressOverlays then
		composer.showOverlay(event.overlay_name, event)
	elseif event.on_done then
		event.on_done(event.params)
	end
end)

show_overlay:Bake()
show_overlay:SetShell(OverlayHandlersShell)

--
--
--

--- Helper to print formatted argument.
-- @string s Format string.
-- @param ... Format arguments.
function printf (s, ...)
	print(s:format(...))
end

--
--
--

var_dump.SetDefaultOutf(printf)

--- Helper to dump generic variable.
-- @param var Variable to dump.
-- @param name As per @{tektite_core.var.dump.Print}.
-- @uint limit As per @{tektite_core.var.dump.Print}.
function vdump (var, name, limit)
	var_dump.Print(var, name and { name = name, limit = limit })
end

--
--
--

--- Helper to dump generic variable, with integer values in hex.
-- @param var Variable to dump.
-- @param name As per @{tektite_core.var.dump.Print}.
-- @uint limit As per @{tektite_core.var.dump.Print}.
function vdumpx (var, name, limit)
	var_dump.Print(var, { hex_uints = true, name = name, limit = limit })
end

--
--
--

-- Make require report the vicinity of its call site, in case of error.
local old_require = require

function require (modname)
	local ok, res = pcall(old_require, modname)

	if ok then
		return res
	else
		error(res, 2)
	end
end