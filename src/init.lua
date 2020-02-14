-- CraftBox
-- A sandboxed microkernel for OpenComputers
-- (C) Saghetti 2020
-- This software is licensed under the MIT license
-- init.lua: script used to boot the system

do
  local addr, invoke = computer.getBootAddress(), component.invoke
  local function loadfile(file)
    local handle = assert(invoke(addr, "open", file))
    local buffer = ""
    repeat
      local data = invoke(addr, "read", handle, math.huge)
      buffer = buffer .. (data or "")
    until not data
    invoke(addr, "close", handle)
    local f, err = load(buffer, "=" .. file, "bt", _G)
    if not f then
      error(err)
    end
    return f
  end
  local ok = true
  local function handleError(err)
    -- save error log
    local disk = component.proxy(addr)
    local fileHandle = disk.open("/crash.txt","w")
    disk.write(fileHandle,"CraftBox Crash log:\n" .. err .. "\n" .. debug.traceback())
    disk.close(fileHandle)
    local fileHandle = disk.open("/crash_reason.txt","w")
    disk.write(fileHandle,err)
    disk.close(fileHandle)
    ok = false
  end
  local ok, err = xpcall(loadfile("/box/craftbox.lua"),handleError)
  if not ok then
    local gpu = component.proxy(component.list("gpu")())
    gpu.setBackground(16777215)
    gpu.setForeground(0)
    gpu.set(1,1,"KERNEL PANIC ")
    -- stupid workaround for xpcall being weird
    local disk = component.proxy(addr)
    local fileHandle = disk.open("/crash_reason.txt","r")
    gpu.set(1,2,disk.read(fileHandle,disk.size("/crash_reason.txt")) .. " ")
    disk.close(fileHandle)
    disk.remove("/crash_reason.txt")
    gpu.set(1,3,"Stack trace written to /crash.txt ")
    gpu.set(1,4,"System Halted! ")
    while true do computer.pullSignal() end
  end
end
computer.shutdown()
