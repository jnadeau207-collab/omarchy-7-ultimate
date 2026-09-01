
local M = {}

function M.module(module)
  if package.searchpath(module, package.path) then
    return require(module)
  end
end

return M
