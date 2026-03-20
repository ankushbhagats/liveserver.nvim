local M = {}

local path = vim.fn.stdpath("state") .. "/liveserver.nvim.json"

-- READ
local function read()
  local f = io.open(path, "r")
  if not f then return {} end

  local content = f:read("*a") --> *a = read the entire file
  f:close()

  local ok, data = pcall(vim.json.decode, content)
  return ok and data or {}
end

-- WRITE
local function write(data)
  vim.fn.writefile({ vim.json.encode(data) }, path)
end

-- SET
function M.set(a, b)
  local tbl = type(a) == "table" and a or { [tostring(a)] = b }
  local data = vim.tbl_deep_extend("force", read(), tbl)
  write(data)
end

-- GET
function M.get(key)
  local data = read()
  if not key then return data end
  return data[tostring(key)]
end

-- DELETE
function M.delete(key)
  local data = read()
  data[tostring(key)] = nil
  write(data)
end

return M
