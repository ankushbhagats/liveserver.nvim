local M = require("lualine.component"):extend()
local config = require("liveserver").config
local state = require("liveserver").state
local path = state.path

local function gethl(hl, attr)
	local ok, h = pcall(vim.api.nvim_get_hl, 0, { name = hl, link = false })
	if not ok or not h[attr] then
		return nil
	end
	return string.format("#%06x", h[attr])
end

function M:init(options)
	options.color = function()
		local state = state[path]
		if state then
			if config.colortype == "hex" then
				state.color.gui = state.gui
				return state.color
			elseif config.colortype == "hl" then
				local hl = state.hl
				return {
					fg = gethl(hl.fg[1], hl.fg[2]),
					bg = gethl(hl.bg[1], hl.bg[2]),
					gui = state.gui,
				}
			end
		end
	end

	options.cond = function()
		local ft = vim.bo.filetype
		return config.filetypes == "*" or config.filetypes[ft]
	end

	options.on_click = function()
		if state[path].name == "idle" or state[path].name == "running" then
			vim.cmd("LiveServerToggle")
		end
	end

	M.super.init(self, options)
end

function M:update_status()
	return state[path].icon .. " %#lualine_c_normal#" .. state[path].text
end

return M
