local ns = vim.api.nvim_create_namespace("parity")
local next_id = 1

local TAG_NAMES = { "OPEN", "CLOSE", "EXIT", "SPACE_L", "SPACE_R" }
local TAG_BITS = math.ceil(math.log(#TAG_NAMES, 2))
local TAG_MASK = bit.lshift(1, TAG_BITS) - 1
local TAG = {}
for i, name in ipairs(TAG_NAMES) do
  TAG[name] = i - 1
end

local DELIMITERS = { ["("] = ")", ["["] = "]", ["{"] = "}" }

local function alloc_id()
  local base = bit.lshift(next_id, TAG_BITS)
  next_id = next_id + 1
  return base
end

local function current_pos()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  return row, col
end

local function get_mark(base, tag)
  local pos = vim.api.nvim_buf_get_extmark_by_id(0, ns, base + tag, {})
  return pos[1], pos[2]
end

local function get_mark_left(row, col)
  local marks = vim.api.nvim_buf_get_extmarks(
    0, ns, { row, col }, { row, col }, { limit = 2 }
  )
  for _, m in ipairs(marks) do
    local id = m[1]
    local tag = bit.band(id, TAG_MASK)
    if tag == TAG.OPEN or tag == TAG.EXIT or tag == TAG.SPACE_L then
      return id - tag, tag
    end
  end
end

local function get_mark_right(row, col)
  local marks = vim.api.nvim_buf_get_extmarks(
    0, ns, { row, col }, { row, col }, { limit = 2 }
  )
  for _, m in ipairs(marks) do
    local id = m[1]
    local tag = bit.band(id, TAG_MASK)
    if tag == TAG.CLOSE or tag == TAG.SPACE_R then
      return id - tag, tag
    end
  end
end

local float_buf = vim.api.nvim_create_buf(false, true)
local float_win = nil

local function draw_float()
  local function mark_char(tag)
    if not tag then return "." end
    if tag == TAG.OPEN then return "(" end
    if tag == TAG.CLOSE then return ")" end
    if tag == TAG.EXIT then return "X" end
    if tag == TAG.SPACE_L then return "<" end
    if tag == TAG.SPACE_R then return ">" end
    return "?"
  end

  local row, col = current_pos()
  local _, lhs_tag = get_mark_left(row, col)
  local _, rhs_tag = get_mark_right(row, col)
  local text = mark_char(lhs_tag) .. "|" .. mark_char(rhs_tag)
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

function parity_mark_pair()
  local row, col = current_pos()
  local base = alloc_id()
  -- OPEN: left gravity, sticks to opening paren
  vim.api.nvim_buf_set_extmark(0, ns, row, col, {
    id = base + TAG.OPEN,
    right_gravity = false,
  })
  -- CLOSE: right gravity, sticks to closing paren (inside)
  vim.api.nvim_buf_set_extmark(0, ns, row, col, {
    id = base + TAG.CLOSE,
    right_gravity = true,
  })
  -- EXIT: left gravity, after closing paren (exit point)
  vim.api.nvim_buf_set_extmark(0, ns, row, col + 1, {
    id = base + TAG.EXIT,
    right_gravity = false,
  })
  vim.schedule(draw_float)
end

for open, close in pairs(DELIMITERS) do
  vim.keymap.set('i', open, open .. close .. '<C-g>U<Left><Cmd>lua parity_mark_pair()<CR>')
  vim.keymap.set('i', close, function()
    local row, col = current_pos()
    local base, tag = get_mark_right(row, col)
    if base and (tag == TAG.CLOSE or tag == TAG.SPACE_R) then
      local exit_row, exit_col = get_mark(base, TAG.EXIT)
      if exit_row ~= row then
        if col == vim.fn.indent(row + 1) then
          return '<Del>' .. string.rep('<Right>', exit_col) .. '<C-F>'
        else
          return '<Del><CR>' .. string.rep('<Right>', exit_col)
        end
      else
        local distance = exit_col - col
        return string.rep('<C-g>U<Right>', distance)
      end
    end
    return close
  end, { expr = true })
end

function parity_insert_cr(indent_size)
  local row, col = current_pos()
  indent_size = indent_size or vim.fn.indent(row + 1)
  local indent = string.rep(" ", indent_size)
  vim.api.nvim_buf_set_text(0, row, col, row, col, { "", indent })
end

function parity_reposition_mark(base)
  local row, col = current_pos()
  vim.api.nvim_buf_set_extmark(0, ns, row, col, {
    id = base + TAG.OPEN,
    right_gravity = false,
  })
  vim.api.nvim_buf_set_extmark(0, ns, row, col, {
    id = base + TAG.CLOSE,
    right_gravity = true,
  })
end

function parity_mark_space(base)
  local row, col = current_pos()
  vim.api.nvim_buf_set_extmark(0, ns, row, col, {
    id = base + TAG.SPACE_L,
    right_gravity = false,
  })
  vim.api.nvim_buf_set_extmark(0, ns, row, col, {
    id = base + TAG.SPACE_R,
    right_gravity = true,
  })
end

function parity_mark_space_r(base)
  local row, col = current_pos()
  vim.api.nvim_buf_set_extmark(0, ns, row, col, {
    id = base + TAG.SPACE_R,
    right_gravity = true,
  })
end

function parity_adjust_space_l()
  local row = current_pos()
  local marks = vim.api.nvim_buf_get_extmarks(0, ns, {row, 0}, {row, 0}, {})
  for _, m in ipairs(marks) do
    local id = m[1]
    local tag = bit.band(id, TAG_MASK)
    if tag == TAG.SPACE_L then
      vim.api.nvim_buf_set_extmark(0, ns, row, vim.fn.indent(row + 1), {
        id = id,
        right_gravity = false,
      })
    end
  end
end

vim.keymap.set('i', '<CR>', function()
  vim.schedule(draw_float)
  local row, col = current_pos()
  local base, tag = get_mark_left(row, col)
  if base and tag == TAG.OPEN then
    local close_row, close_col = get_mark(base, TAG.CLOSE)
    if close_row == row and close_col == col then
      return string.format('<Cmd>lua parity_insert_cr()<CR><CR><Cmd>lua parity_mark_space(%d)<CR>', base)
    end
  end
  return '<CR>'
end, { expr = true })

vim.keymap.set('i', '<Space>', function()
  vim.schedule(draw_float)
  local row, col = current_pos()
  local base, tag = get_mark_left(row, col)
  if base and tag == TAG.OPEN then
    local close_row, close_col = get_mark(base, TAG.CLOSE)
    if close_row == row and close_col == col then
      return string.format('  <C-g>U<Left><Cmd>lua parity_mark_space(%d)<CR>', base)
    end
  end
  return ' '
end, { expr = true })

vim.keymap.set('i', '<Del>', function()
  vim.schedule(draw_float)
  local row, col = current_pos()
  local base = get_mark_right(row, col)
  if base then
    vim.api.nvim_buf_del_extmark(0, ns, base + TAG.CLOSE)
  end
  return '<Del>'
end, { expr = true })

vim.keymap.set('i', '<BS>', function()
  vim.schedule(draw_float)
  local row, col = current_pos()
  local base, tag = get_mark_left(row, col)
  if base then
    if tag == TAG.EXIT then
      -- at exit mark: move left into the parens (or spaces if present)
      local open_row, open_col = get_mark(base, TAG.OPEN)
      local space_r_row, space_r_col = get_mark(base, TAG.SPACE_R)
      if space_r_row and open_row ~= space_r_row then
        if space_r_row == row then
          local distance = col - space_r_col
          return string.rep('<C-g>U<Left>', distance)
            .. '<Cmd>lua parity_insert_cr()<CR><C-F>'
            .. '<Cmd>lua parity_adjust_space_l()<CR>'
            .. string.format('<Cmd>lua parity_mark_space_r(%d)<CR>', base)
        else
          local indent_size = vim.fn.indent(row + 1)
          return '<C-g>U<Left>0<C-D><BS><C-F>'
            .. '<Cmd>lua parity_adjust_space_l()<CR>'
            .. string.format('<Cmd>lua parity_insert_cr(%d)<CR>', indent_size)
            .. string.format('<Cmd>lua parity_mark_space_r(%d)<CR>', base)
        end
      end
      local close_row, close_col = get_mark(base, TAG.CLOSE)
      local target_col = space_r_row and space_r_col or close_col
      local distance = (close_row ~= row) and 1 or (col - target_col)
      return string.rep('<C-g>U<Left>', distance)
    elseif tag == TAG.SPACE_L then
      local space_r_row, space_r_col = get_mark(base, TAG.SPACE_R)
      if space_r_row == row and space_r_col == col then
        -- delete matched spaces and marks
        local open_row, open_col = get_mark(base, TAG.OPEN)
        local close_row, close_col = get_mark(base, TAG.CLOSE)
        vim.api.nvim_buf_del_extmark(0, ns, base + TAG.SPACE_L)
        vim.api.nvim_buf_del_extmark(0, ns, base + TAG.SPACE_R)
        local result = ''
        if close_row ~= row then
          result = '<Del>'
        else
          result = string.rep('<Del>', close_col - col)
        end
        if open_row ~= row then
          result = result .. '0<C-D><BS>'
        else
          result = result .. string.rep('<BS>', col - open_col)
        end
        return result
      end
    elseif tag == TAG.OPEN then
      local close_row, close_col = get_mark(base, TAG.CLOSE)
      if close_row == row and close_col == col then
        -- open and close marks together: cursor is between matching delimiters
        -- delete both delimiters and marks
        vim.api.nvim_buf_del_extmark(0, ns, base + TAG.OPEN)
        vim.api.nvim_buf_del_extmark(0, ns, base + TAG.CLOSE)
        vim.api.nvim_buf_del_extmark(0, ns, base + TAG.EXIT)
        return '<BS><Del>'
      end
    end
  end
  if col == vim.fn.indent(row + 1) then
    return '0<C-D><BS><C-F><Cmd>lua parity_adjust_space_l()<CR>'
  end
  return '<BS>'
end, { expr = true })

vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    local row, col = current_pos()
    if col == 0 then return end
    local chars = vim.api.nvim_buf_get_text(0, row, col - 1, row, col + 1, {})[1]
    local expected_close = DELIMITERS[chars:sub(1, 1)]
    if expected_close and chars:sub(2, 2) == expected_close then
      parity_mark_pair()
    end
  end,
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
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    next_id = 1
  end,
})
