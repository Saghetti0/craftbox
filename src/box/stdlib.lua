-- CraftBox
-- A sandboxed microkernel for OpenComputers
-- (C) Saghetti 2020
-- This software is licensed under the MIT license
-- stdlib.lua: The standard library for CraftBox programs

local stdlib = {}

function stdlib.sleep(amount)
  -- sleep(time: number): nil
  -- Sleep for a certain amount of time
  -- amount: the length of time to sleep for (in seconds)
  yield("syscall","sleep",amount or 0)
end

function stdlib.exit(exitCode)
  -- exit([exitCode: number]): nil
  -- Exit out of the program
  -- exitCode: the status to return when exiting
  yield("syscall","exit",exitCode or 0)
end

return stdlib
