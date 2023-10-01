local util = require("conform.util")

---@type conform.FileFormatterConfig
return {
  meta = {
    url = "https://github.com/shufo/blade-formatter",
    description = "An opinionated blade template formatter for Laravel that respects readability",
  },
  command = util.find_executable({
    "tools/blade-formatter/vendor/bin/blade-formatter",
    "vendor/bin/blade-formatter",
  }, "blade-formatter"),
  args = { "$FILENAME" },
  stdin = false,
}
