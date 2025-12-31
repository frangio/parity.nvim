local ns = vim.api.nvim_create_namespace("parity")

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

local function cancel_matching_close(buf, row, col, closing)
  local marks = vim.api.nvim_buf_get_extmarks(
    buf,
    ns,
    { row, col },
    { row, col },
    { details = true, limit = 1 }
  )

  for _, mark in ipairs(marks) do
    local virt_text = mark[4].virt_text
    if virt_text[1][1] == closing then
      vim.api.nvim_buf_del_extmark(buf, ns, mark[1])
      return true
    end
  end

  return false
end

local function insert_open_paren()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  vim.api.nvim_buf_set_extmark(buf, ns, row, col, {
    virt_text = { { ")", "DiffAdd" } },
    virt_text_pos = "inline",
    right_gravity = true,
  })

  return "("
end

local function insert_close_paren()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  cancel_matching_close(buf, row, col, ")")

  return ")"
end

local function insert_backspace()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local keys = "<BS>"

  if col > 0 then
    local prev = vim.api.nvim_buf_get_text(buf, row, col - 1, row, col, {})[1]
    if prev == "(" then
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
vim.keymap.set("i", "<BS>", insert_backspace, { expr = true, silent = true })

vim.api.nvim_create_autocmd("InsertLeave", {
  callback = function(ev)
    materialize_extmarks(ev.buf)
  end,
})
