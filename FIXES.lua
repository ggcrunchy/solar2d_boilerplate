--- Various workarounds.

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

-- Exports --
local M = {}

-- Remove any lingering indicator.
if system.getInfo("environment") == "simulator" then
	native.setActivityIndicator(false)
end

do
	local type = type

	-- Monkey-patch display.newSnapshot(). Maintain some weak parent lookups for a snapshot's
	-- group and canvas until the snapshot has been removed.
	local WeakParent = setmetatable({}, { __mode = "v" })
	local old_newSnapshot = display.newSnapshot

	function display.newSnapshot (...)
		local snapshot = old_newSnapshot(...)

		WeakParent[snapshot.canvas], WeakParent[snapshot.group] = snapshot, snapshot

		return snapshot
	end

	-- Validity predicate, with special consideration for snapshot groups and canvases
	local function IsValid (object)
		if type(object) == "table" then
			if object.parent ~= nil then
				return true
			else
				return IsValid(WeakParent[object])
			end
		end

		return false
	end

	--- Detects whether the input is a display object that has not yet been removed.
	-- @function display.isValid
	-- @pobject object Display object.
	-- @treturn boolean Is this a valid display object?
	display.isValid = IsValid
end

-- Export the module.
return M