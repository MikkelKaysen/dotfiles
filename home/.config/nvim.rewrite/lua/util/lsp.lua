-- LSP helpers (ported from LazyVim's lsp util/keymaps).
local M = {}

---@alias LspKeySpec {lhs?:string, rhs?:any, desc?:string, mode?:string|string[], has?:string|string[], enabled?:fun(buf:number):boolean, nowait?:boolean, buffer?:number}
--- @note lhs/rhs may also be given positionally as { lhs, rhs, ... }

--- Register LSP keymaps with a capability (`has`) filter.
--- The keymap is only active in buffers where a client matching
--- `filter` + the `has` method(s) is attached.
---@param filter vim.lsp.get_clients.Filter
---@param spec LspKeySpec[]
function M.set(filter, spec)
  for _, keys in ipairs(spec) do
    local lhs = keys.lhs or keys[1]
    local rhs = keys.rhs or keys[2]
    if type(lhs) ~= "string" or rhs == nil then
      error(("bad LSP keymap spec: lhs=%s rhs=%s"):format(tostring(lhs), type(rhs)), 2)
    end
    local filters = {} ---@type vim.lsp.get_clients.Filter[]
    if keys.has then
      local methods = type(keys.has) == "string" and { keys.has } or keys.has --[[@as string[] ]]
      for _, method in ipairs(methods) do
        method = method:find("/") and method or ("textDocument/" .. method)
        filters[#filters + 1] = vim.tbl_extend("force", vim.deepcopy(filter or {}), { method = method })
      end
    else
      filters[#filters + 1] = filter or {}
    end

    for _, f in ipairs(filters) do
      local opts = {
        desc = keys.desc,
        nowait = keys.nowait,
        buffer = keys.buffer,
      }
      ---@cast opts snacks.keymap.set.Opts
      opts.lsp = f
      opts.enabled = keys.enabled
      require("snacks.keymap").set(keys.mode or "n", lhs, rhs, opts)
    end
  end
end

--- An LSP formatter for the util.format registry.
---@param opts? {name?:string, primary?:boolean, priority?:number, filter?:string}
---@return Formatter
function M.formatter(opts)
  opts = opts or {}
  return {
    name = opts.name or "LSP",
    primary = opts.primary or false,
    priority = opts.priority or 10,
    format = function(buf)
      vim.lsp.buf.format({
        bufnr = buf,
        filter = opts.filter or nil,
        timeout_ms = 3000,
      })
    end,
    sources = function(buf)
      local ret = {}
      for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, method = "textDocument/formatting" })) do
        if not opts.filter or client.name == opts.filter then
          ret[#ret + 1] = client.name
        end
      end
      return ret
    end,
  }
end

--- Code action helpers: M.action.source, M.action["source.organizeImports"], ...
M.action = setmetatable({}, {
  __index = function(_, kind)
    return function()
      vim.lsp.buf.code_action({
        context = {
          only = { kind },
          apply = true,
        },
      })
    end
  end,
})

return M