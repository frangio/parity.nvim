local ns = vim.api.nvim_create_namespace("parity")

local function current_pos()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  return buf, row, col
end

local function materialize_extmarks(buf)
  local marks = vim.api.nvim_buf_get_extmarks(
    buf,
    ns,
    { -1, -1 },
    { 0, 0 },
    { details = true }
  )

  for _, mark in ipairs(marks) do
    local id = mark[1]
    local row = mark[2]
    local col = mark[3]
    local virt_text = mark[4].virt_text
    assert(#virt_text == 1, "parity: unexpected virt_text shape")
    vim.api.nvim_buf_set_text(buf, row, col, row, col, {
      virt_text[1][1],
    })
    vim.api.nvim_buf_del_extmark(buf, ns, id)
  end
end

local function find_matching_close(buf, row, col, closing)
  local marks = vim.api.nvim_buf_get_extmarks(
    buf,
    ns,
    { row, col },
    { row, col },
    { details = true, limit = 1 }
  )

  for _, mark in ipairs(marks) do
    local virt_text = mark[4].virt_text
    local text = virt_text[1][1]
    if text:sub(-1) == closing then
      return mark[1], text
    end
  end

  return nil, nil
end

local function cancel_matching_close(buf, row, col, closing)
  local id = find_matching_close(buf, row, col, closing)
  if id then
    vim.api.nvim_buf_del_extmark(buf, ns, id)
    return true
  end

  return false
end

local function add_space_to_close(buf, row, col, closing)
  local id, text = find_matching_close(buf, row, col, closing)
  if id then
    vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
      id = id,
      virt_text = { { " " .. text, "DiffAdd" } },
      virt_text_pos = "inline",
      right_gravity = true,
    })
  end
end

local function insert_open_paren()
  local buf, row, col = current_pos()

  vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
    virt_text = { { ")", "DiffAdd" } },
    virt_text_pos = "inline",
    right_gravity = true,
  })

  return "("
end

local function insert_close_paren()
  local buf, row, col = current_pos()

  cancel_matching_close(buf, row, col, ")")

  return ")"
end

local function insert_space()
  local buf, row, col = current_pos()

  add_space_to_close(buf, row, col, ")")

  return " "
end

local function insert_backspace()
  local buf, row, col = current_pos()
  local keys = "<BS>"

  if col > 0 then
    local prev = vim.api.nvim_buf_get_text(buf, row, col - 1, row, col, {})[1]
    if prev == " " then
      local id, text = find_matching_close(buf, row, col, ")")
      if id and text:sub(1, 1) == " " then
        vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
          id = id,
          virt_text = { { text:sub(2), "DiffAdd" } },
          virt_text_pos = "inline",
          right_gravity = true,
        })
      end
    elseif prev == "(" then
      local canceled = cancel_matching_close(buf, row, col, ")")
      if not canceled then
        local next = vim.api.nvim_buf_get_text(buf, row, col, row, col + 1, {})[1]
        if next == ")" then
          keys = "<BS><Del>"
        end
      end
    end
  end

  return keys
end

vim.keymap.set("i", "(", insert_open_paren, { expr = true, silent = true })
vim.keymap.set("i", ")", insert_close_paren, { expr = true, silent = true })
vim.keymap.set("i", "<Space>", insert_space, { expr = true, silent = true })
vim.keymap.set("i", "<BS>", insert_backspace, { expr = true, silent = true })

vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function(ev)
    materialize_extmarks(ev.buf)
  end,
})
