local M = {}

---@param name string
function M.get_bg(name)
  local namespaces = vim.api.nvim_get_namespaces()
  local ok, hl = pcall(vim.api.nvim_get_hl, namespaces[name], true)
  if not ok then
    return nil
  end
  if hl.bg then
    return string.format("#%06x", hl.bg)
  end
  return nil
end

---comment
---@param hex string
---@return number? r
---@return number? g
---@return number? b
function M.hex2rgb(hex)
  hex = hex:gsub("#", "")
  return tonumber("0x" .. hex:sub(1, 2)), tonumber("0x" .. hex:sub(3, 4)), tonumber("0x" .. hex:sub(5, 6))
end

---@param r number
---@param g number
---@param b number
---@return string
function M.rgb2hex(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

---@param r number?
---@param g number?
---@param b number?
local function checkHex(r, g, b)
  if type(r) ~= "number" then
    vim.notify("invalid hex. using 255 for r", vim.log.levels.ERROR)
    r = 255
  end
  if type(g) ~= "number" then
    vim.notify("invalid hex. using 255 for g", vim.log.levels.ERROR)
    r = 255
  end
  if type(b) ~= "number" then
    vim.notify("invalid hex. using 255 for b", vim.log.levels.ERROR)
    r = 255
  end
  return r, g, b
end

---@param hex string
---@param amount number
---@return string
function M.darken(hex, amount)
  local r, g, b = checkHex(M.hex2rgb(hex))
  return M.rgb2hex(r * amount, g * amount, b * amount)
end

---@param hex string
---@return boolean
function M.is_dark(hex)
  local r, g, b = M.hex2rgb(hex)
  local lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
  return lum <= 0.5
end

---@param msg string
---@param hl string
function M.log(msg, hl)
  vim.api.nvim_echo({ { "ZenMode: ", hl }, { msg } }, true, {})
end

---@param msg string
function M.warn(msg)
  M.log(msg, "WarningMsg")
end

---@param msg string
function M.error(msg)
  M.log(msg, "ErrorMsg")
end

return M
