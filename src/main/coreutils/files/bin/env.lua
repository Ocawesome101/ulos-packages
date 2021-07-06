-- env

local args, opts = require("argutil").parse(...)

if opts.help then
  io.stderr:write([[
usage: env [options] PROGRAM ...
Executes PROGRAM with the specified options.

Options:
  --unset=KEY,KEY,... Unset all specified
                      variables in the child
                      process's environment.
  --chdir=DIR         Set the child process's
                      working directory to DIR.
                      DIR is not checked for
                      existence.
  -i                  Execute the child process
                      with an empty environment.

ULOS Coreutils (c) 2021 Ocawesome101 under the
DSLv2.
]])
  os.exit(1)
end

local program = table.concat(args, " ")

local pge = require("process").info().data.env

-- TODO: support short opts with arguments, and maybe more opts too

if opts.unset and type(opts.unset) == "string" then
  for v in opts.unset:gmatch("[^,]+") do
    pge[v] =  ""
  end
end

if opts.i then
  pge = {}
end

if opts.chdir and type(opts.chdir) == "string" then
  pge["PWD"] = opts.chdir
end

os.execute(program)
