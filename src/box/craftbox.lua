-- CraftBox
-- A sandboxed microkernel for OpenComputers
-- craftbox.lua: main kernel

local nextPID = 1
local processes = {}
local newProcesses = {}
local deleteProcesses = {}
local runSystem = true
local processData = {}
local signalQueue = {}
local messagingBuffers = {}
local initProcessList = {"/box/fs-s.lua","/box/term-s.lua"}
local version = "CraftBox Experimental"
local servers = {}

-- early logging

local screen = component.list("screen")()
local gpu = component.proxy(component.list("gpu")())
local scrRow = 1
local scrColumn = 1

local function splitByChunk(text, chunkSize)
  local s = {}
  for i=1, #text, chunkSize do
    s[#s+1] = text:sub(i,i+chunkSize - 1)
  end
  return s
end

local function logInit(s)
  gpu.bind(screen,true)
  gpu.setResolution(80,25)
  scrRow = 1
  scrColumn = 1
  local w, h = gpu.getResolution()
  gpu.fill(1, 1, w, h, " ")
end

local function logScroll()
  local w, h = gpu.getResolution()
  gpu.copy(1,1,w,h,0,-1)
  gpu.fill(1,h,w,1," ")
end

local function logPrint(s)
  local w, h = gpu.getResolution()
  local stringChunks = splitByChunk(s,w)
  for k,v in pairs(stringChunks) do
    gpu.set(scrColumn,scrRow,v)
    scrRow = scrRow + 1
    if scrRow > h then
      logScroll()
      scrRow = h
    end
  end
end
logInit()
-- end early logging

local function tableMerge(t1, t2)
  for k,v in pairs(t2) do
    if type(v) == "table" then
      if type(t1[k] or false) == "table" then
        tableMerge(t1[k] or {}, t2[k] or {})
      else
        t1[k] = v
      end
    else
      t1[k] = v
    end
  end
  return t1
end

function tableContains(table, element)
  for _, value in pairs(table) do
    if value == element then
      return true
    end
  end
  return false
end

local function loadPrimitiveLibrary(file,env)
  local addr, invoke = computer.getBootAddress(), component.invoke
  local handle = assert(invoke(addr, "open", file))
  local buffer = ""
  repeat
    local data = invoke(addr, "read", handle, math.huge)
    buffer = buffer .. (data or "")
  until not data
  invoke(addr, "close", handle)
  return load(buffer, "=" .. file, "t", env)
end

-- load stdlib and drvlib
local stdlib = loadPrimitiveLibrary("/box/stdlib.lua",{yield = coroutine.yield})()
local drvlib = loadPrimitiveLibrary("/box/drvlib.lua",{yield = coroutine.yield})()

local function createEnvironment()
  local e = setmetatable({},{__index=stdlib})
  -- main functions
  e["assert"] = assert
  e["error"] = error
  e["getmetatable"] = getmetatable
  e["ipairs"] = ipairs
  e["load"] = load
  e["next"] = next
  e["pairs"] = pairs
  e["pcall"] = pcall
  e["rawequal"] = rawequal
  e["rawget"] = rawget
  e["rawlen"] = rawlen
  e["rawset"] = rawset
  e["select"] = select
  e["setmetatable"] = setmetatable
  e["tonumber"] = tonumber
  e["tostring"] = tostring
  e["type"] = type
  e["xpcall"] = xpcall
  e["checkArg"] = checkArg
  -- bit32
  e["bit32"] = setmetatable({},{__index=bit32})
  -- debug
  e["debug"] = setmetatable({},{__index=debug})
  -- math
  e["math"] = setmetatable({},{__index=math})
  -- os
  e["os"] = setmetatable({},{__index=os})
  -- string
  e["string"] = setmetatable({},{__index=string})
  -- table
  e["table"] = setmetatable({},{__index=table})
  -- unicode
  e["unicode"] = setmetatable({},{__index=unicode})
  e.yield = coroutine.yield
  -- info strings
  e["_OSVERSION"] = version
  return e
end

local function createEnvironmentDriver()
  local e = createEnvironment()
  tableMerge(e,drvlib)
  e["component"] = setmetatable({},{__index=component})
  e["computer"] = setmetatable({},{__index=computer})
  return e
end

-- function for starting processes in early boot
local function createProcessRaw(file, env)
  local addr, invoke = computer.getBootAddress(), component.invoke
  local handle = assert(invoke(addr, "open", file))
  local buffer = ""
  local pid = nextPID
  nextPID = nextPID + 1
  repeat
    local data = invoke(addr, "read", handle, math.huge)
    buffer = buffer .. (data or "")
  until not data
  invoke(addr, "close", handle)
  local func = load(buffer, ("=" .. file .. " (PID " .. tostring(pid) .. ")"), "t", env)
  if not func then return end
  newProcesses[pid] = coroutine.create(func)
  return pid
end

local function createProcess(file, permissionLevel)
  local pid = 0
  if permissionLevel == 1 then
    pid = createProcessRaw(file,createEnvironment())
  elseif permissionLevel == 2 then
    pid = createProcessRaw(file,createEnvironment())
  elseif permissionLevel == 3 then
    pid = createProcessRaw(file,createEnvironmentDriver())
  elseif permissionLevel == 4 then
    pid = createProcessRaw(file,createEnvironmentDriver())
  end
  processData[pid] = {
    permissionLevel = permissionLevel,
    nextWakeup = 0,
    path = file,
    resumeData = {},
    listeningEvents = {},
    eventQueue = {},
  }
  return pid
end

-- getters and setters for processData
local function setResumeData(pid,resumeData)
  processData[pid].resumeData = resumeData
end

local function getResumeData(pid)
  return processData[pid].resumeData
end

local function getPermissionLevel(pid)
  return processData[pid].permissionLevel
end

local function getEvents(pid)
  return processData[pid].eventQueue
end

local function addListeningEvent(pid,ev)
  table.insert(processData[pid].listeningEvents,ev)
end

local function pushEvent(pid,ev)
  table.insert(processData[pid].eventQueue,ev)
end

local function pullEvent(pid)
  if #processData[pid].eventQueue > 0 then
    local ev = processData[pid].eventQueue[1]
    table.remove(processData[pid].eventQueue,1)
    return ev
  end
  return nil
end

-- handle syscalls
local function handleSyscall(pid,processCoroutine,args)
  --logPrint("Handling syscall from PID " .. tostring(pid))
  if #args < 1 then
    logPrint("Error: invalid syscall from PID " .. tostring(pid) .. "!")
    return
  end
  --logPrint("Got syscall " .. args[1])
  permissionLevel = getPermissionLevel(pid)
  -- user level syscalls
  if args[1] == "exit" then
    if #args < 2 then
      logPrint("Error: invalid syscall from PID " .. tostring(pid) .. "!")
      return
    end
    --logPrint("Marked process " .. tostring(pid) .. " for deletion. Reason: exited")
    logPrint("Process " .. tostring(pid) .. " exited with code " .. tostring(args[2]))
    table.insert(deleteProcesses,pid)
  end
  -- driver syscalls
  if permissionLevel > 2 then
    if args[1] == "kprint" then
      if #args < 2 then
        -- no text specified to print
        logPrint("Error: invalid syscall from PID " .. tostring(pid) .. "!")
        return
      end
      logPrint("PID " .. tostring(pid) .. ": " .. args[2])
      return
    end
    if args[1] == "listenevent" then
      if #args < 2 then
        -- no event specified to listen to
        logPrint("Error: invalid syscall from PID " .. tostring(pid) .. "!")
        return
      end
      addListeningEvent(pid,args[2])
      logPrint("PID " .. tostring(pid) .. " now listens to event " .. args[2])
      return
    end
    if args[1] == "pullevent" then
      local ev = pullEvent(pid)
      if not ev then
        -- no events in queue
        setResumeData(pid,nil)
        return
      else
        -- send event to process
        --logPrint("Sending event " .. ev[1] .. " to PID " .. tostring(pid))
        setResumeData(pid,ev)
      end
    end
  end
end

logPrint("Welcome to a buggy test of CraftBox")

-- start init processes
for k,v in ipairs(initProcessList) do
  logPrint("Starting process " .. v)
  createProcess(v,4)
end

while runSystem do
  -- get signal(s)
  local events = {}
  while true do
    local event = {computer.pullSignal(0)}
    if #event < 1 then
      break
    else
      table.insert(events,event)
    end
  end
  -- add pending processes
  processes = tableMerge(processes, newProcesses)
  newProcesses = {}
  -- delete processes marked in last tick
  for _, p in pairs(deleteProcesses) do
    processes[p] = nil
    messagingBuffers[p] = nil
    --logPrint("Deleted process " .. tostring(p))
  end
  -- iterate over processes
  deleteProcesses = {}
  for p, c in pairs(processes) do
    -- check processes
    if coroutine.status(c) == "dead" then
      --logPrint("Marked process " .. tostring(p) .. " for deletion. Reason: dead")
      --table.insert(deleteProcesses,p)
      handleSyscall(p,c,{"exit",0}) -- simulate process exiting
    else
      --logPrint("Resuming process " .. tostring(p))
      -- give process execution time
      local processReturn = {coroutine.resume(c,getResumeData(p))}
      setResumeData(p,{})
      local ok = processReturn[1]
      if not ok then
        local err = processReturn[2]
        --logPrint("Marked process " .. tostring(p) .. " for deletion. Reason: error")
        logPrint(tostring(err))
        handleSyscall(p,c,{"exit",-1}) -- simulate process exiting (-1: process error)
      else
        if #processReturn > 1 then
          if processReturn[2] == "syscall" then
            -- process did a syscall, handle it
            table.remove(processReturn,1)
            table.remove(processReturn,1)
            handleSyscall(p,c,processReturn)
          end
        end
      end
    end
  end
  -- send events to processes
  for k,ev in pairs(events) do
    local eventType = ev[1]
    for pid, pdata in pairs(processData) do
      if tableContains(processData[pid].listeningEvents,eventType) then
        pushEvent(pid,ev)
        --logPrint("Queued event " .. eventType .. " for PID " .. tostring(pid) .. " " .. tostring(computer.uptime()))
      end
    end
  end
end
