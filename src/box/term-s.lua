-- CraftBox
-- A sandboxed microkernel for OpenComputers
-- (C) Saghetti 2020
-- This software is licensed under the MIT license
-- term-s.lua: The terminal server for CraftBox

listenEvent("key_down")
while true do
  pullEvent()
end
