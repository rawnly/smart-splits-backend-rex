local M = {}

---@type string[][]
M.calls = {}

local original = {
  system = vim.system,
  executable = vim.fn.executable,
  session = vim.env.REX_SESSION,
  block = vim.env.REX_BLOCK,
}

---@type table<string, { code: integer, stdout?: string }>
local responses = {}

---Sets the response for any `rex` call whose arguments start with `prefix`.
---@param prefix string e.g. 'focus left'
---@param response { code: integer, stdout?: string }
function M.respond(prefix, response)
  responses[prefix] = response
end

local function fake_system(cmd)
  local args = vim.list_slice(cmd, 2)
  table.insert(M.calls, args)

  local joined = table.concat(args, ' ')
  local response = { code = 0, stdout = '' }
  for prefix, candidate in pairs(responses) do
    if vim.startswith(joined, prefix) then
      response = candidate
    end
  end

  return {
    wait = function()
      return { code = response.code, stdout = response.stdout or '', stderr = '' }
    end,
  }
end

function M.reset_backend()
  M.calls = {}
  responses = {}
  vim.system = fake_system
  vim.fn.executable = function()
    return 1
  end
  vim.env.REX_SESSION = 'session:test'
  vim.env.REX_BLOCK = 'block:test'
  require('smart-splits-backend-rex.config').setup()
end

function M.restore()
  vim.system = original.system
  vim.fn.executable = original.executable
  vim.env.REX_SESSION = original.session
  vim.env.REX_BLOCK = original.block
end

function M.leave_rex()
  vim.env.REX_SESSION = nil
  vim.env.REX_BLOCK = nil
end

function M.remove_cli()
  vim.fn.executable = function()
    return 0
  end
end

return M
