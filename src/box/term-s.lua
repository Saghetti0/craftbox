-- CraftBox
-- A sandboxed microkernel for OpenComputers
-- (C) Saghetti 2020
-- term-s.lua: The terminal server for CraftBox

listenEvent("key_down")
while true do
  pullEvent()
end
