local config = require("zen-mode.config")
local plugins = require("zen-mode.plugins")
local util = require("zen-mode.util")
local M = {}

M.bg_win = nil
M.bg_buf = nil
M.parent = nil
M.win = nil
--- @type ZenOptions
M.opts = nil
M.state = {}
M.closed = false

function M.is_open()
  return M.win and vim.api.nvim_win_is_valid(M.win)
end

function M.plugins_on_open()
  for name, opts in pairs(M.opts.plugins) do
    if opts and opts.enabled then
      local plugin = plugins[name]
      M.state[name] = {}
      pcall(plugin, M.state[name], true, opts)
    end
  end
end

function M.plugins_on_close()
  for name, opts in pairs(M.opts.plugins) do
    if opts and opts.enabled then
      local plugin = plugins[name]
      pcall(plugin, M.state[name], false, opts)
    end
  end
end

function M.close()
  pcall(vim.cmd --[[@as fun(cmd: string)]], [[autocmd! Zen]])
  pcall(vim.cmd --[[@as fun(cmd: string)]], [[augroup! Zen]])

  -- Change the parent window's cursor position to match
  -- the cursor position in the zen-mode window.
  if M.parent and M.win then

    local myBuffer = vim.api.nvim_win_get_buf(M.win)
    local isSameBuffer = vim.api.nvim_win_get_buf(M.parent) == myBuffer
    if not isSameBuffer then
      vim.api.nvim_win_set_buf(M.parent, myBuffer)
    end

    vim.api.nvim_win_set_cursor(M.parent, vim.api.nvim_win_get_cursor(M.win))
  end

  if M.win and vim.api.nvim_win_is_valid(M.win) then
    vim.api.nvim_win_close(M.win, true)
    M.win = nil
  end
  if M.bg_win and vim.api.nvim_win_is_valid(M.bg_win) then
    vim.api.nvim_win_close(M.bg_win, true)
    M.bg_win = nil
  end
  if M.bg_buf and vim.api.nvim_buf_is_valid(M.bg_buf) then
    vim.api.nvim_buf_delete(M.bg_buf, { force = true })
    M.bg_buf = nil
  end
  if M.opts then
    M.plugins_on_close()
    M.opts.on_close()
    M.opts = nil
    if M.parent and vim.api.nvim_win_is_valid(M.parent) then
      vim.api.nvim_set_current_win(M.parent)
    end
  end
end

function M.open(opts)
  if not M.is_open() then
    -- close any possible remnants from a previous session
    -- shouldn't happen, but just in case
    M.close()
    M.create(opts)
  end
end

function M.toggle(opts)
  if M.is_open() then
    M.close()
  else
    M.open(opts)
  end
end

---@param num number
---@return integer
function M.round(num)
  return math.floor(num + 0.5)
end

function M.height()
  local height = vim.o.lines - vim.o.cmdheight
  return (vim.o.laststatus == 3) and height - 1 or height
end

function M.resolve(max, value)
  local ret = max
  if type(value) == "function" then
    ret = value()
  elseif value > 1 then
    ret = value
  else
    ret = ret * value
  end
  return math.min(ret, max)
end

--- @param opts ZenOptions
function M.layout(opts)
  local width = M.resolve(vim.o.columns, opts.window.width)
  local height = M.resolve(M.height(), opts.window.height)

  -- just align the floating window *as if* you had to center a window of the
  -- specified width, but actually extend the window all the way to the right.
  local actual_width = vim.o.columns
  local left_margin = (actual_width - width) / 2
  local actual_floating_width = actual_width - left_margin
  ---@class Rect
  local rect = {
    width = M.round(actual_floating_width),
    height = M.round(height),
    col = M.round((vim.o.columns - width) / 2),
    row = M.round((M.height() - height) / 2),
  }
  return rect
end

-- adjusts col/row if window was resized
function M.fix_layout(win_resized)
  if M.is_open() then
    local l = M.layout(M.opts)
    if win_resized then
      vim.api.nvim_win_set_config(M.win, { width = l.width, height = l.height })
      vim.api.nvim_win_set_config(M.bg_win, { width = vim.o.columns, height = M.height() })
    end
    local height = vim.api.nvim_win_get_height(M.win)
    local width = vim.api.nvim_win_get_width(M.win)
    local col = M.round((vim.o.columns - width) / 2)
    local row = M.round((M.height() - height) / 2)
    local cfg = vim.api.nvim_win_get_config(M.win)
    -- HACK: col is an array?
    local wcol = type(cfg.col) == "number" and cfg.col or cfg.col[false]
    local wrow = type(cfg.row) == "number" and cfg.row or cfg.row[false]
    if wrow ~= row or wcol ~= col then
      vim.api.nvim_win_set_config(M.win, { col = l.col, row = l.row, relative = "editor" })
    end
  end
end

--- @param opts ZenOptions
function M.create(opts)
  ---@type ZenOptions
  opts = vim.tbl_deep_extend("force", {}, config.options, opts or {})
  config.colors(opts)
  M.opts = opts
  M.state = {}
  M.parent = vim.api.nvim_get_current_win()
  -- should apply before calculate window's height to be able handle 'laststatus' option
  M.plugins_on_open()

  M.bg_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("filetype", "zenmode-bg", {buf=M.bg_buf})
  local ok
  ok, M.bg_win = pcall(vim.api.nvim_open_win, M.bg_buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = M.height(),
    focusable = false,
    row = 0,
    col = 0,
    style = "minimal",
    zindex = opts.zindex - 10,
  })
  if not ok then
    M.plugins_on_close()
    util.error("could not open floating window. You need a Neovim build that supports zindex (May 15 2021 or newer)")
    M.bg_win = nil
    return
  end
  M.fix_hl(M.bg_win, "ZenBg")

  local win_opts = vim.tbl_extend("keep", {
    relative = "editor",
    zindex = opts.zindex,
    border = opts.border,
  }, M.layout(opts))

  local buf = vim.api.nvim_get_current_buf()
  M.win = vim.api.nvim_open_win(buf, true, win_opts)
  vim.cmd([[norm! zz]])
  M.fix_hl(M.win)

  for k, v in pairs(opts.window.options or {}) do
    vim.api.nvim_set_option_value(k, v, {win=M.win})
  end

  opts.on_open(M.win)

  -- fix layout since some plugins might have altered the window
  M.fix_layout()

  -- TODO: listen for WinNew and BufEnter. When a new window, or bufenter in a new window, close zen mode
  -- unless it's in a float
  -- TODO: when the cursor leaves the window, we close zen mode, or prevent leaving the window
  local augroup = [[
    augroup Zen
      autocmd!
      autocmd WinClosed %d ++once ++nested lua require("zen-mode.view").close()
      autocmd WinEnter * lua require("zen-mode.view").on_win_enter()
      autocmd CursorMoved * lua require("zen-mode.view").fix_layout()
      autocmd VimResized * lua require("zen-mode.view").fix_layout(true)
      autocmd CursorHold * lua require("zen-mode.view").fix_layout()
      autocmd BufWinEnter * lua require("zen-mode.view").on_buf_win_enter()
    augroup end]]

  vim.api.nvim_exec2(augroup:format(M.win, M.win), {output=false})
end

-- TODO: normal and other fields in this codebase are actually enums.

---@param win integer
---@param normal string?
function M.fix_hl(win, normal)
  local cwin = vim.api.nvim_get_current_win()
  if cwin ~= win then
    vim.api.nvim_set_current_win(win)
  end
  normal = normal or "Normal"
  vim.cmd("setlocal winhl=NormalFloat:" .. normal .. ",FloatBorder:ZenBorder,EndOfBuffer:" .. normal)
  vim.cmd("setlocal winblend=0")
  vim.cmd([[setlocal fcs=eob:\ ,fold:\ ,vert:\]])
  -- vim.api.nvim_win_set_option(win, "winhighlight", "NormalFloat:" .. normal)
  -- vim.api.nvim_win_set_option(win, "fcs", "eob: ")
  vim.api.nvim_set_current_win(cwin)
end

---@param win integer
function M.is_float(win)
  local opts = vim.api.nvim_win_get_config(win)
  return opts and opts.relative and opts.relative ~= ""
end

function M.on_buf_win_enter()
  if vim.api.nvim_get_current_win() == M.win then
    M.fix_hl(M.win)
  end
end


function M.on_win_enter()
  local win = vim.api.nvim_get_current_win()
  if not M.is_float(win) then
    vim.defer_fn(
      function ()
        vim.api.nvim_set_current_win(M.win)
      end,
      10
    )
  end
end

return M
