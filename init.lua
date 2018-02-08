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
require("corona_boilerplate.FIXES")

-- Standard library imports --
local error = error
local pcall = pcall
local print = print

-- Modules --
local debug = require("debug")
local device = require("corona_utils.device")
local errors = require("tektite_core.errors")
local flow_bodies = require("coroutine_ops.flow_bodies")
local frames = require("corona_utils.frames")
local per_coroutine = require("coroutine_ops.per_coroutine")
local scenes = require("corona_utils.scenes")
local var_dump = require("tektite_core.var.dump")

-- Corona globals --
local native = native
local Runtime = Runtime
local system = system

-- Display setup.
display.setStatusBar(display.HiddenStatusBar)
display.setDefault("isShaderCompilerVerbose", true)

if system.getInfo("platform") == "android" and system.getInfo("environment") == "device" then
	native.setProperty("androidSystemUiVisibility", "immersiveSticky")
end

-- Install the coroutine time logic.
flow_bodies.SetTimeLapseFuncs(per_coroutine.TimeLapse(frames.DiffTime, frames.GetFrameID))

-- Use standard tracebacks.
errors.SetTracebackFunc(debug.traceback)

-- Install various events.
do
	-- Handler helper
	local function Handles (what)
		what = "message:handles_" .. what

		return function(event)
			if scenes.Send(what, event) then
				return true
			end
		end
	end

	-- "axis" listener --
	Runtime:addEventListener("axis", Handles("axis"))

	-- "system" listener --
	Runtime:addEventListener("system", function(event)
		if event.type == "applicationStart" or event.type == "applicationResume" then
			device.EnumerateDevices()
		end
	end)

	-- "key" listener --
	local HandleKey = Handles("key")

	Runtime:addEventListener("key", function(event)
		if HandleKey(event) then
			return true
		else
			local key = event.keyName
			local go_back = key == "back" or key == "deleteBack"

			if go_back or key == "volumeUp" or key == "volumeDown" then
				if event.phase == "down" then
					if go_back then
						scenes.WantsToGoBack()
					else
						-- VOLUME
					end
				end

				return true
			end
		end
	end)
end

-- "unhandledError" listener --
if system.getInfo("environment") == "device" then
	Runtime:addEventListener("unhandledError", function(event)
		native.showAlert("Error!", event.errorMessage .. " \n " .. event.stackTrace, { "OK" }, native.requestExit)
	end)
end

-- Intercept new "enterFrame" events so that we can do once-per-frame actions.
frames.InterceptEnterFrameEvents()

--- Helper to print formatted argument.
-- @string s Format string.
-- @param ... Format arguments.
function printf (s, ...)
	print(s:format(...))
end

-- Install printf as the default var dump routine.
var_dump.SetDefaultOutf(printf)

--- Helper to dump generic variable.
-- @param var Variable to dump.
-- @param name As per @{tektite_core.var.dump.Print}.
-- @uint limit As per @{tektite_core.var.dump.Print}.
function vdump (var, name, limit)
	var_dump.Print(var, name and { name = name, limit = limit })
end

--- Helper to dump generic variable, with integer values in hex.
-- @param var Variable to dump.
-- @param name As per @{tektite_core.var.dump.Print}.
-- @uint limit As per @{tektite_core.var.dump.Print}.
function vdumpx (var, name, limit)
	var_dump.Print(var, { hex_uints = true, name = name, limit = limit })
end

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