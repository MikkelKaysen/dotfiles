local overseer = require("overseer")

---@param opts overseer.SearchParams
---@return nil|string
local function get_mise_file(opts)
  local function is_mise_file(name)
    name = name:lower()
    -- mise.toml, mise.<env>.toml, or .local.toml, or dot-prefixed
    return name:match("^%.?mise%.toml$") ~= nil
      or name:match("^%.?mise%.local%.toml$") ~= nil
      or name:match("^%.?mise%.%w+%.toml$") ~= nil
      or name:match("^%.?mise%.%w+%.local%.toml$") ~= nil
  end

  local function is_mise_dir(name)
    name = name:lower()
    -- (.)mise, (.)mise-tasks, or .config dir
    return name:match("^%.?mise$") ~= nil
      or name:match("^%.?mise%-tasks$") ~= nil
      or name == ".config"
  end

  return vim.fs.find(is_mise_file, { type = "file", upward = true, path = opts.dir })[1]
    or vim.fs.find(is_mise_dir, { type = "directory", upward = true, path = opts.dir })[1]
end

---@type overseer.TemplateFileProvider
local provider = {
  cache_key = function(opts)
    -- Results capture cwd, so nested search directories must not share a cache entry
    return opts.dir
  end,
  generator = function(opts, cb)
    if vim.fn.executable("mise") == 0 then
      return 'Command "mise" not found'
    end
    local mise_file = get_mise_file(opts)
    if not mise_file then
      return "No mise file or directory found"
    end

    local ret = {}
    local cwd = opts.dir
    overseer.builtin.system(
      { "mise", "tasks", "--all", "--json" },
      { cwd = cwd, text = true },
      vim.schedule_wrap(function(out)
        if out.code ~= 0 then
          local err = vim.trim(out.stderr or "")
          cb(err ~= "" and err or "mise tasks failed with exit code " .. out.code)
          return
        end
        local ok, data = pcall(vim.json.decode, out.stdout or "", { luanil = { object = true } })
        if not ok or type(data) ~= "table" then
          cb("Invalid JSON from 'mise tasks --all --json'")
          return
        end
        for _, value in pairs(data) do
          table.insert(ret, {
            name = string.format("mise %s", value.name),
            desc = value.description ~= "" and value.description or nil,
            builder = function()
              return {
                cmd = { "mise", "run", value.name },
                cwd = cwd,
              }
            end,
          })
        end
        cb(ret)
      end)
    )
  end,
}

return provider
