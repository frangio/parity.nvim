local ns = vim.api.nvim_create_namespace("parity")
local next_id = 1

local TAG = {
  OPEN  = 0b0001,
  CLOSE = 0b0010,
  EXIT  = 0b0100,
  SPACE = 0b1000,
}
local TAG_BITS = 4
local TAG_MASK = 0b1111
local TAGS_OPEN_CLOSE = bit.bor(TAG.OPEN, TAG.CLOSE)

local DELIMITERS = { "()", "[]", "{}" }

local function reindent(keys)
  if vim.bo.indentexpr ~= '' or vim.bo.cindent then
    return keys .. '<C-F>'
  else
    return keys
  end
end

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

local function compute_indent(row)
  local indentexpr = vim.bo.indentexpr
  local use_indentexpr = indentexpr ~= ""

  if vim.bo.lisp and use_indentexpr then
    if vim.opt_local.lispoptions:get("expr") ~= 1 then
      use_indentexpr = false
    end
  end

  if use_indentexpr then
    vim.v.lnum = row + 1
    local ok, indent = pcall(vim.fn.eval, indentexpr)
    if ok and indent ~= -1 then
      return indent
    end
  end

  if vim.bo.lisp then
    return vim.fn.lispindent(row + 1)
  elseif vim.bo.cindent then
    return vim.fn.cindent(row + 1)
  elseif vim.bo.autoindent then
    return vim.fn.indent(row)
  else
    return 0
  end
end

local function get_mark(base, tag)
  local pos = vim.api.nvim_buf_get_extmark_by_id(0, ns, base + tag, {})
  return pos[1], pos[2]
end

local function get_marks(row, col)
  local marks = vim.api.nvim_buf_get_extmarks(0, ns, { row, col }, { row, col }, {})
  local base = nil
  local tags = 0
  for _, m in ipairs(marks) do
    local id = m[1]
    local b = id - bit.band(id, TAG_MASK)
    if base == nil then
      base = b
    end
    if base == b then
      tags = bit.bor(tags, bit.band(id, TAG_MASK))
    end
  end
  return base, tags
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
end

for _, pair in ipairs(DELIMITERS) do
  assert(#pair == 2, "DELIMITERS must contain strings of length 2")
  local open, close = pair:sub(1, 1), pair:sub(2, 2)
  vim.keymap.set('i', open, pair .. '<C-g>U<Left><Cmd>lua parity_mark_pair()<CR>')
  vim.keymap.set('i', close, function()
    local row, col = current_pos()
    local base, tags = get_marks(row, col)
    if base and bit.band(tags, bit.bor(TAG.CLOSE, TAG.SPACE)) ~= 0 then
      local exit_row, exit_col = get_mark(base, TAG.EXIT)
      if exit_row ~= row then
        if col == vim.fn.indent(row + 1) then
          return reindent('<Del>' .. string.rep('<Right>', exit_col))
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
  if indent_size == nil then
    if vim.bo.autoindent then
      indent_size = vim.fn.indent(row + 1)
    else
      indent_size = 0
    end
  end
  local indent = string.rep(" ", indent_size)
  vim.api.nvim_buf_set_text(0, row, col, row, col, { "", indent })
end

function parity_mark_space(base)
  local row, col = current_pos()
  vim.api.nvim_buf_set_extmark(0, ns, row, col, {
    id = base + TAG.SPACE,
    right_gravity = true,
  })
end

vim.keymap.set('i', '<CR>', function()
  local row, col = current_pos()
  local base, tags = get_marks(row, col)
  if base and bit.band(tags, TAGS_OPEN_CLOSE) == TAGS_OPEN_CLOSE then
    return string.format('<Cmd>lua parity_insert_cr()<CR><CR><Cmd>lua parity_mark_space(%d)<CR>', base)
  end
  return '<CR>'
end, { expr = true })

vim.keymap.set('i', '<Space>', function()
  local row, col = current_pos()
  local base, tags = get_marks(row, col)
  if base and bit.band(tags, TAGS_OPEN_CLOSE) == TAGS_OPEN_CLOSE then
    return string.format('  <C-g>U<Left><Cmd>lua parity_mark_space(%d)<CR>', base)
  end
  return ' '
end, { expr = true })

vim.keymap.set('i', '<Del>', function()
  local row, col = current_pos()
  local base, tags = get_marks(row, col)
  if base and bit.band(tags, TAG.CLOSE) ~= 0 then
    vim.api.nvim_buf_del_extmark(0, ns, base + TAG.CLOSE)
  end
  return '<Del>'
end, { expr = true })

vim.keymap.set('i', '<BS>', function()
  local row, col = current_pos()
  local base, tags = get_marks(row, col)
  if base then
    if bit.band(tags, TAG.EXIT) ~= 0 then
      -- at exit mark: move left into the parens (or spaces if present)
      local open_row, open_col = get_mark(base, TAG.OPEN)
      local space_row, space_col = get_mark(base, TAG.SPACE)
      if space_row and open_row ~= space_row then
        local indent_size = vim.fn.indent(row + 1)
        if space_row == row then
          local distance = col - space_col
          return reindent(string.rep('<C-g>U<Left>', distance)
          .. string.format('<Cmd>lua parity_insert_cr(%d)<CR>', indent_size))
          .. string.format('<Cmd>lua parity_mark_space(%d)<CR>', base)
        else
          return reindent('<C-g>U<Left>0<C-D><BS>')
          .. string.format('<Cmd>lua parity_insert_cr(%d)<CR>', indent_size)
          .. string.format('<Cmd>lua parity_mark_space(%d)<CR>', base)
        end
      else
        local close_row, close_col = get_mark(base, TAG.CLOSE)
        local target_col = space_row and space_col or close_col
        local distance = (close_row ~= row) and 1 or (col - target_col)
        return string.rep('<C-g>U<Left>', distance)
      end
    elseif bit.band(tags, TAG.SPACE) ~= 0 then
      local open_row, open_col = get_mark(base, TAG.OPEN)
      if open_row == row - 1 and col == compute_indent(row) then
        -- delete matched spaces and marks
        local close_row, close_col = get_mark(base, TAG.CLOSE)
        vim.api.nvim_buf_del_extmark(0, ns, base + TAG.SPACE)
        local result = ''
        if close_row ~= row then
          result = '<Del>'
        else
          result = string.rep('<Del>', close_col - col)
        end
        result = result .. '0<C-D><BS>'
        return result
      elseif open_row == row and col - open_col <= 1 then
        -- open and space on same row with minimal distance: delete open paren and spaces, and close paren if on same row
        local close_row, close_col = get_mark(base, TAG.CLOSE)
        vim.api.nvim_buf_del_extmark(0, ns, base + TAG.SPACE)
        local result = string.rep('<BS>', col - open_col)
        if close_row == row then
          result = result .. string.rep('<Del>', close_col - col)
        end
        return result
      end
    elseif bit.band(tags, TAGS_OPEN_CLOSE) == TAGS_OPEN_CLOSE then
      vim.api.nvim_buf_del_extmark(0, ns, base + TAG.OPEN)
      vim.api.nvim_buf_del_extmark(0, ns, base + TAG.CLOSE)
      vim.api.nvim_buf_del_extmark(0, ns, base + TAG.EXIT)
      vim.api.nvim_buf_del_extmark(0, ns, base + TAG.SPACE)
      return '<BS><Del>'
    end
  end
  if col == compute_indent(row) then
    return reindent('0<C-D><BS>')
  end
  return '<BS>'
end, { expr = true })

vim.api.nvim_create_autocmd("InsertEnter", {
  callback = function()
    local row, col = current_pos()
    if col == 0 then return end
    local chars = vim.api.nvim_buf_get_text(0, row, col - 1, row, col + 1, {})[1]
    for _, pair in ipairs(DELIMITERS) do
      if chars == pair then
        parity_mark_pair()
        break
      end
    end
  end,
})

vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function()
    vim.api.nvim_buf_clear_namespace(0, ns, 0, -1)
    next_id = 1
  end,
})
