-- CraftBox
-- A sandboxed microkernel for OpenComputers
-- (C) Saghetti 2020
-- This software is licensed under the MIT license
-- stdlib.lua: A library for CraftBox drivers that require more permissions

local drvlib = {}

function drvlib.kprint(txt)
  -- kprint(text: string)
  -- Print text to the kernel's output
  -- text: the text to print
  yield("syscall","kprint",txt)
end

function drvlib.pullEvent()
  -- pullEvent(): table: event or nil
  -- Try to get an event in the event queue. Returns the event or nil if there are no events available
  return yield("syscall","pullevent")
end

function drvlib.listenEvent(type)
  -- listenEvent(type: string): nil
  -- Listen for a certain event. This allows events of that type to be pushed to the event queue for this process.
  -- type: the type of event to listen for
  yield("syscall","listenevent",type)
end

return drvlib
