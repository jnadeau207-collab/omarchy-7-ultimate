
local M = {}

local function shell_quote(path)
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

function M.files(dir, module_prefix, options)
  local exclude = options and options.exclude or {}
  local handle = io.popen("find " .. shell_quote(dir) .. " -maxdepth 1 -type f -name '*.lua' -printf '%f\\n' 2>/dev/null | sort")
  if handle then
    for filename in handle:lines() do
      local name = filename:gsub("%.lua$", "")
      if not exclude[name] then
        local module = name
        if module_prefix then
          module = module_prefix .. "." .. module
        end

        if options and options.reload then
          package.loaded[module] = nil
        end

        require(module)
      end
    end
    handle:close()
  end
end

return M
