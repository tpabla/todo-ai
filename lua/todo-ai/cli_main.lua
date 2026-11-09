-- Entry point for `nvim -l`; arg[1] is the plugin root, the rest is argv.
local root = table.remove(_G.arg, 1)
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path

local cli = require('todo-ai.cli')
os.exit(cli.run(_G.arg, cli.default_deps()))
