---@param range? conform.Range
---@param start_lnum integer
---@param end_lnum integer
---@return boolean
local function in_range(range, start_lnum, end_lnum)
  return not range or (start_lnum <= range["end"][1] and range["start"][1] <= end_lnum)
end

---@param lines string[]
---@return string?
local function get_indent(lines)
  local indent = nil
  for _, line in ipairs(lines) do
    if line ~= "" then
      local whitespace = line:match("^%s*")
      if whitespace == "" then
        return nil
      elseif not indent or whitespace:len() < indent:len() then
        indent = whitespace
      end
    end
  end
  return indent
end

---@param original_lines string[]
---@param new_lines? string[]
local function apply_indent(original_lines, new_lines)
  if not new_lines then
    return
  end
  local indent = get_indent(original_lines)
  local already_indented = get_indent(new_lines)
  if not indent or already_indented then
    return
  end
  for i, line in ipairs(new_lines) do
    if line ~= "" then
      new_lines[i] = indent .. line
    end
  end
end

---@type conform.FileLuaFormatterConfig
return {
  meta = {
    url = "lua/conform/formatters/injected.lua",
    description = "Format treesitter injected languages.",
  },
  condition = function(ctx)
    local ok = pcall(vim.treesitter.get_parser, ctx.buf)
    return ok
  end,
  format = function(ctx, lines, callback)
    local conform = require("conform")
    local log = require("conform.log")
    local util = require("conform.util")
    local ok, parser = pcall(vim.treesitter.get_parser, ctx.buf)
    if not ok then
      callback("No treesitter parser for buffer")
      return
    end
    local root_lang = parser:lang()
    local regions = {}
    for lang, child_lang in pairs(parser:children()) do
      local formatter_names = conform.formatters_by_ft[lang]
      if formatter_names and lang ~= root_lang then
        for _, tree in ipairs(child_lang:trees()) do
          local root = tree:root()
          local start_lnum = root:start() + 1
          local end_lnum = root:end_()
          if start_lnum <= end_lnum and in_range(ctx.range, start_lnum, end_lnum) then
            table.insert(regions, { lang, start_lnum, end_lnum })
          end
        end
      end
    end
    -- Sort from largest start_lnum to smallest
    table.sort(regions, function(a, b)
      return a[2] > b[2]
    end)
    log.trace("Injected formatter regions %s", regions)

    local replacements = {}
    local format_error = nil

    local function apply_format_results()
      if format_error then
        callback(format_error)
        return
      end

      local formatted_lines = vim.deepcopy(lines)
      for _, replacement in ipairs(replacements) do
        local start_lnum, end_lnum, new_lines = unpack(replacement)
        for _ = start_lnum, end_lnum do
          table.remove(formatted_lines, start_lnum)
        end
        for i = #new_lines, 1, -1 do
          table.insert(formatted_lines, start_lnum, new_lines[i])
        end
      end
      callback(nil, formatted_lines)
    end

    local num_format = 0
    local formatter_cb = function(err, idx, start_lnum, end_lnum, new_lines)
      if err then
        format_error = err
      else
        replacements[idx] = { start_lnum, end_lnum, new_lines }
      end
      num_format = num_format - 1
      if num_format == 0 then
        apply_format_results()
      end
    end
    local last_start_lnum = #lines + 1
    for _, region in ipairs(regions) do
      local lang, start_lnum, end_lnum = unpack(region)
      -- Ignore regions that overlap (contain) other regions
      if end_lnum < last_start_lnum then
        num_format = num_format + 1
        last_start_lnum = start_lnum
        local input_lines = util.tbl_slice(lines, start_lnum, end_lnum)
        local formatter_names = conform.formatters_by_ft[lang]
        local format_opts = { async = true, bufnr = ctx.buf, quiet = true }
        local idx = num_format
        log.debug("Injected format %s:%d:%d: %s", lang, start_lnum, end_lnum, formatter_names)
        log.trace("Injected format lines %s", input_lines)
        conform.format_lines(formatter_names, input_lines, format_opts, function(err, new_lines)
          -- Preserve indentation in case the code block is indented
          apply_indent(input_lines, new_lines)
          formatter_cb(err, idx, start_lnum, end_lnum, new_lines)
        end)
      end
    end
    if num_format == 0 then
      apply_format_results()
    end
  end,
}
