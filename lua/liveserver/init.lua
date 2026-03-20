local store = require("liveserver.store")
local uv = vim.loop
local M = {}

local function log(message, level)
	vim.notify(string.format("liveserver: %s", message), vim.log.levels[level])
end

-- Detect if OS is Windows
local function is_windows()
	return uv.os_uname().version:match("Windows")
end

if not vim.fn.executable("live-server") and not (is_windows() and vim.fn.executable("live-server.cmd")) then
	log("is not executable. Ensure the npm module is properly installed", vim.log.levels.ERROR)
	return
end

M.config = require("liveserver.config")
M.state = {}

local jobs = {} --> store process job id(s)
local stack = {} --> store configs each process

local function find(source, key, val)
	for _, tbl in pairs(source) do
		for k, v in pairs(tbl) do
			if k == key and v == val then
				return tbl
			end
		end
	end
end

local function resolve_path(path)
	path = path and not path:match("^%d+$") and path or "%:p:h" -- absolute path / head path
	return vim.fn.fnamemodify(vim.fn.expand(path), ":p") -- convert to absolute path
end

function M.state.set(path, name, text)
	M.state[path] = vim.deepcopy(M.config.states[name])
	M.state.path = path

	local state = M.state[path]
	state.name = name
	state.text = state.text .. tostring(text or "")
	require("lualine").refresh() -- refresh lualine immediately (no delay)
end

local function resolve_stop(args)
	local path = resolve_path(args)
	local opts = stack[path]
	local port = args ~= "" and args or opts and opts.port --> if port not specified in cmdline then use current running port.
	local saved = port and find(store.get(), "port", tonumber(port))
	return path, port, saved and saved.jobpid
end

local function timeout(fn, ms) -- runs a function after a delay asynchronously
	vim.defer_fn(fn, ms or 0)
end

local function is_port_in_use(port, host, time)
	local tcp = uv.new_tcp()
	local used = false
	local done = false

	host = host or "127.0.0.1"
	time = time or 100

	tcp:connect(host, port, function(err)
		used = (err == nil)
		done = true
		tcp:close()
	end)

	-- wait until timeout for connect result synchronously
	vim.wait(time, function()
		return done
	end)

	return used
end

local function is_pid_alive(pid)
	-- uv.kill returns:
	--   0 on success (process exists)
	--   -1 on failure (process does NOT exist)
	local ok, _ = uv.kill(pid, 0)
	return ok
end

math.randomseed(os.time())
local function next_port()
	return math.random(3000, 9000) -- range of dev ports
end

M.toggle = function(path, opts)
	local job = jobs[path]
	if not job then
		M.start(path, opts)
		return
	end
	M.stop(path, opts.port, job.jobpid)
end

M.setup = function(user_config)
	M.config = vim.tbl_deep_extend("force", M.config, user_config or {})
	M.default_port = M.config.args.port
	vim.g.liveserver_state = "OK"

	local path = resolve_path()
	local saved = store.get(path)
	local state = saved and saved.state or "idle"
	local port = saved and saved.port
	M.state.set(path, state, port)

	-- function to parse key=value and resolve args
	local function resolve_args(str)
		local args = {}
		for word in str:gmatch("%S+") do
			local k, v = word:match("^([%w-]+)=(.+)$")
			if k then
				args[k] = v
			elseif not args.port and word:match("^%d+$") then
				args.port = word
			elseif not args.path then
				args.path = word
			end
		end

		local opts = find(stack, "port", args.port) or {}
		args.path = resolve_path(args.path)

		args = vim.tbl_deep_extend("force", M.config.args, args, opts)
		stack[args.path] = stack[args.path] or vim.deepcopy(args)
		return args.path, stack[args.path]
	end

	vim.api.nvim_create_user_command("LiveServerStart", function(opts)
		M.start(resolve_args(opts.args))
	end, { nargs = "*" })

	vim.api.nvim_create_user_command("LiveServerStop", function(opts)
		M.stop(resolve_stop(opts.args))
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("LiveServerSelect", function()
		M.select()
	end, { nargs = "*" })

	vim.api.nvim_create_user_command("LiveServerToggle", function(opts)
		M.toggle(resolve_args(opts.args))
	end, { nargs = "*" })
end

M.start = function(path, opts)
	local saved = store.get(path)
	local running_port = is_port_in_use(opts.port)
	local running_default_port = is_port_in_use(M.default_port)
	local running_job = saved and is_pid_alive(saved.pid)

	if running_job then
		-- log(string.format('port %s is already running for %s', saved.port, saved.path), 'INFO')
		-- NOTE: ADD PROMPT TO ASK FOR STOP.
		local msg =
			string.format("The port %s is already running for this workspace,\nDo you want to stop?", saved.port)
		local choice = vim.fn.confirm(msg, "&Yes\n&No", 2)

		if choice == 1 then
			M.stop(saved.path, saved.port, saved.jobpid)
		end
		return
	elseif running_port then
		local oldport = opts.port
		local newport

		if running_default_port then
			newport = next_port()
		else
			newport = M.default_port
		end

		log(string.format("port %s is already in use. Trying port %s.", oldport, newport), "INFO")
		opts.port = newport
	end

	M.state.set(path, "start")

	local cmd_exe = "live-server"
	if is_windows() then
		cmd_exe = "live-server.cmd"
	end

	local function build_cmd(opts)
		local args = {}

		for key, val in pairs(opts or {}) do
			if type(val) == "table" then
				args[#args + 1] = "--" .. key .. "=" .. table.concat(val, ",")
			elseif val == true then
				args[#args + 1] = "--" .. key
			elseif val ~= nil then
				args[#args + 1] = "--" .. key .. "=" .. tostring(val)
			end
		end
		return args
	end

	local cmd = { cmd_exe, path }
	local args = build_cmd(opts)

	vim.list_extend(cmd, args)

	local job_id = vim.fn.jobstart(cmd, {
		on_stderr = function(_, data)
			if not data or data[1] == "" then
				return
			end
			-- Remove color from error if present
			log(data[1]:match(".-m(.-)\27") or data[1], "ERROR")
		end,

		on_exit = function(_, exit_code)
			M.state.set(path, "stop")
			store.delete(path) --> clean saved data immediately

			timeout(function()
				stack[path] = nil
				jobs[path] = nil
				M.state.set(path, "idle")
			end, 300) --> run this func after 300ms delay

			if exit_code == 143 then -- instance killed with SIGTERM
				return
			end

			log(string.format("stopped with code %s", exit_code), "INFO")
		end,
	})

	timeout(function()
		local data = {
			state = "running",
			jobid = job_id,
			jobpid = vim.fn.jobpid(job_id),
			pid = vim.fn.getpid(),
			path = opts.path,
			host = opts.host,
			port = tonumber(opts.port),
		}

		jobs[path] = data
		store.set(path, data)
		M.state.set(path, "running", opts.port)

		log(string.format("running on %s:%s", opts.host, opts.port), "INFO")
	end, 500)
end

M.stop = function(path, port, pid)
	if pid then
		uv.kill(pid, "sigterm") --> gracefully stop.

		M.state.set(path, "stop")
		timeout(function()
			M.state.set(path, "idle")
		end, 300)

		log(string.format("port:%s has been stopped", port), "INFO")
	end
end

local choose_option = function(option)
	local choice = vim.fn.confirm("", "&Open Workspace\n&Kill Port\n&Cancel", 2)
	if choice == 1 then
		vim.cmd.Explore(option.path)
	elseif choice == 2 then
		M.stop(option.path, option.port, option.jobpid)
	end
end

M.select = function()
	local store = require("liveserver.store")
	local items = {}
	for _, value in pairs(store.get()) do
		table.insert(items, {
			option = value,
			label = string.format("%s:%s", value.host, value.port),
		})
	end

	vim.ui.select(items, {
		prompt = "Select Process:",
		format_item = function(item)
			return item.label
		end,
	}, function(choice)
		if choice then
			choose_option(choice.option)
		end
	end)
end

return M
