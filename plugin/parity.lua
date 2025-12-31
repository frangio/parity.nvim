local ns = vim.api.nvim_create_namespace("parity")
local next_id = 1

local function current_pos()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  return buf, row, col
end

local function get_mark_kind(id)
  if not id then return nil end
  return id % 2 == 1 and "open" or "close"
end

local function get_mark_left(buf, row, col)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, col - 1 }, { row, col - 1 }, { limit = 1 })
  return marks[1] and marks[1][1]
end

local function get_mark_right(buf, row, col)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, col }, { row, col }, { limit = 1 })
  return marks[1] and marks[1][1]
end

local float_buf = vim.api.nvim_create_buf(false, true)
local float_win = nil

local function draw_float()
  local function mark_char(kind)
    if not kind then return "." end
    return kind == "open" and "-" or "+"
  end

  local buf, row, col = current_pos()
  local lhs = get_mark_left(buf, row, col)
  local rhs = get_mark_right(buf, row, col)
  local text = mark_char(get_mark_kind(lhs)) .. "|" .. mark_char(get_mark_kind(rhs))
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, { text })
  local win_opts = {
    relative = "editor",
    row = 0,
    col = vim.o.columns - #text,
    width = #text,
    height = 1,
    style = "minimal",
  }
  if float_win and vim.api.nvim_win_is_valid(float_win) then
    vim.api.nvim_win_set_config(float_win, win_opts)
  else
    float_win = vim.api.nvim_open_win(float_buf, false, win_opts)
  end
end

vim.keymap.set('i', '<Plug>(parity-mark-open)', function()
  local buf, row, col = current_pos()
  if next_id % 2 == 0 then next_id = next_id + 1 end
  vim.api.nvim_buf_set_extmark(buf, ns, row, col - 1, {
    id = next_id,
    end_col = col,
    hl_group = "DiffChange",
  })
  next_id = next_id + 1
  draw_float()
end)

vim.keymap.set('i', '<Plug>(parity-mark-close)', function()
  local buf, row, col = current_pos()
  vim.api.nvim_buf_set_extmark(buf, ns, row, col - 1, {
    id = next_id,
    end_col = col,
    hl_group = "DiffChange",
  })
  next_id = next_id + 1
  draw_float()
end)

vim.keymap.set('i', '(', '(<Plug>(parity-mark-open))<Plug>(parity-mark-close)<C-g>U<Left>')

vim.keymap.set('i', ')', function()
  local buf, row, col = current_pos()
  if get_mark_right(buf, row, col) then
    return '<C-g>U<Right>'
  end
  return ')'
end, { expr = true })

vim.keymap.set('i', '<Space>', function()
  local buf, row, col = current_pos()
  local mark_left = get_mark_left(buf, row, col)
  local mark_right = get_mark_right(buf, row, col)
  if mark_left and mark_right == mark_left + 1 then
    return ' <Plug>(parity-mark-open) <Plug>(parity-mark-close)<C-g>U<Left>'
  end
  return ' '
end, { expr = true })

vim.keymap.set('i', '<Del>', function()
  vim.schedule(draw_float)
  local buf, row, col = current_pos()
  local mark_right = get_mark_right(buf, row, col)
  if mark_right then
    vim.api.nvim_buf_del_extmark(buf, ns, mark_right)
  end
  return '<Del>'
end, { expr = true })

vim.keymap.set('i', '<BS>', function()
  vim.schedule(draw_float)
  local buf, row, col = current_pos()
  local mark_left = get_mark_left(buf, row, col)
  if mark_left then
    if get_mark_kind(mark_left) == "close" then
      return '<C-g>U<Left>'
    else
      vim.api.nvim_buf_del_extmark(buf, ns, mark_left)
      local mark_right = get_mark_right(buf, row, col)
      if mark_right == mark_left + 1 then
        vim.api.nvim_buf_del_extmark(buf, ns, mark_right)
        return '<Del><BS>'
      end
    end
  end
  return '<BS>'
end, { expr = true })

vim.api.nvim_create_autocmd({ "InsertEnter", "CursorMovedI" }, {
  callback = draw_float,
})

vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function()
    if float_win and vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_hide(float_win)
      float_win = nil
    end
  end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    next_id = 1
  end,
})
