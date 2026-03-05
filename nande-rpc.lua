-- nande-rpc.lua
-- by German S.
-- A cross-platform Discord Rich Presence script for mpv using the Discord IPC protocol.

local mp = require("mp")
local utils = require("mp.utils")
local msg = require("mp.msg")
local bit = require("bit")
local ffi = require("ffi")

local CLIENT_ID = "737663962677510245" -- from https://github.com/tnychn/mpv-discord, ideally replace with your own
local is_windows = package.config:sub(1,1) == '\\'

local win_handle = nil
local fd = -1
local kernel32 = nil
local handshake_sent = false

local print_debug_to_console = false
local function debug_log(...)
    if print_debug_to_console then
        msg.info(string.format(...))
    end
end

-- 1. FFI Setup based on Operating System
if is_windows then
    kernel32 = ffi.load("kernel32")
    ffi.cdef[[
        typedef void* HANDLE;
        typedef unsigned long DWORD;
        typedef int BOOL;
        HANDLE CreateFileA(const char* lpFileName, DWORD dwDesiredAccess, DWORD dwShareMode, void* lpSecurityAttributes, DWORD dwCreationDisposition, DWORD dwFlagsAndAttributes, HANDLE hTemplateFile);
        BOOL WriteFile(HANDLE hFile, const void* lpBuffer, DWORD nNumberOfBytesToWrite, DWORD* lpNumberOfBytesWritten, void* lpOverlapped);
        BOOL ReadFile(HANDLE hFile, void* lpBuffer, DWORD nNumberOfBytesToRead, DWORD* lpNumberOfBytesRead, void* lpOverlapped);
        BOOL PeekNamedPipe(HANDLE hNamedPipe, void* lpBuffer, DWORD nBufferSize, DWORD* lpBytesRead, DWORD* lpTotalBytesAvail, DWORD* lpBytesLeftThisMessage);
        BOOL CloseHandle(HANDLE hObject);
    ]]
else
    ffi.cdef[[
        typedef int ssize_t;
        struct sockaddr_un_linux {
            unsigned short sun_family;
            char sun_path[108];
        };
        struct sockaddr_un_mac {
            unsigned char sun_len;
            unsigned char sun_family;
            char sun_path[104];
        };
        int socket(int domain, int type, int protocol);
        int connect(int sockfd, const void *addr, unsigned int addrlen);
        ssize_t send(int sockfd, const void *buf, size_t len, int flags);
        ssize_t recv(int sockfd, void *buf, size_t len, int flags);
        int close(int fd);
        char* getenv(const char* name);
    ]]
end

-- 100% safe Little-Endian header packing (bypasses FFI struct padding issues)
local function pack_header(opcode, length)
    return string.char(
        bit.band(opcode, 0xFF), bit.band(bit.rshift(opcode, 8), 0xFF), bit.band(bit.rshift(opcode, 16), 0xFF), bit.band(bit.rshift(opcode, 24), 0xFF),
        bit.band(length, 0xFF), bit.band(bit.rshift(length, 8), 0xFF), bit.band(bit.rshift(length, 16), 0xFF), bit.band(bit.rshift(length, 24), 0xFF)
    )
end

local function connect_discord()
    if is_windows then
        for i = 0, 9 do
            local pipe_name = "\\\\.\\pipe\\discord-ipc-" .. i
            local h = kernel32.CreateFileA(pipe_name, 0xC0000000, 0, nil, 3, 0, nil)
            local handle_val = tonumber(ffi.cast("intptr_t", h))
            if handle_val ~= -1 and handle_val ~= 0 then
                win_handle = h
                debug_log("SUCCESS: Connected to Discord IPC on " .. pipe_name)
                return true
            end
        end
        return false
    else
        local AF_UNIX = 1
        local SOCK_STREAM = 1
        local sock = ffi.C.socket(AF_UNIX, SOCK_STREAM, 0)
        if sock < 0 then return false end
        
        local paths = {}
        local xdg = ffi.C.getenv("XDG_RUNTIME_DIR")
        if xdg ~= nil then
            local xdg_str = ffi.string(xdg)
            table.insert(paths, xdg_str .. "/discord-ipc-0")
            table.insert(paths, xdg_str .. "/app/com.discordapp.Discord/discord-ipc-0")
        end
        table.insert(paths, "/tmp/discord-ipc-0")
        
        for _, path in ipairs(paths) do
            local addr
            local addr_len
            if jit.os == "OSX" then
                addr = ffi.new("struct sockaddr_un_mac")
                addr.sun_family = AF_UNIX
                addr.sun_len = ffi.sizeof(addr)
                ffi.copy(addr.sun_path, path)
                addr_len = ffi.sizeof(addr)
            else
                addr = ffi.new("struct sockaddr_un_linux")
                addr.sun_family = AF_UNIX
                ffi.copy(addr.sun_path, path)
                addr_len = ffi.sizeof(addr)
            end
            
            if ffi.C.connect(sock, addr, addr_len) == 0 then
                fd = sock
                debug_log("SUCCESS: Connected to Discord IPC on " .. path)
                return true
            end
        end
        ffi.C.close(sock)
        return false
    end
end

local function read_discord_pipe()
    if is_windows then
        if not win_handle then return end
        local avail = ffi.new("DWORD[1]")
        if kernel32.PeekNamedPipe(win_handle, nil, 0, nil, avail, nil) ~= 0 and avail[0] > 8 then
            local buf = ffi.new("char[?]", avail[0])
            local read = ffi.new("DWORD[1]")
            kernel32.ReadFile(win_handle, buf, avail[0], read, nil)
            local json_str = ffi.string(buf + 8, read[0] - 8)
            debug_log("DISCORD REPLIED: " .. json_str)
        end
    else
        if fd < 0 then return end
        -- Non-blocking recv to drain the socket buffer
        local MSG_DONTWAIT = (jit.os == "OSX") and 0x80 or 0x40
        local buf = ffi.new("char[1024]")
        local bytes = ffi.C.recv(fd, buf, 1024, MSG_DONTWAIT)
        if bytes > 8 then
            local json_str = ffi.string(buf + 8, bytes - 8)
            debug_log("DISCORD REPLIED: " .. json_str)
        end
    end
end

local function send_msg(opcode, payload)
    local payload_str = utils.format_json(payload)
    if not payload_str then return end
    
    debug_log(string.format("SENDING (Opcode %d): %s", opcode, payload_str))
    local buffer = pack_header(opcode, #payload_str) .. payload_str
    
    if is_windows then
        if win_handle then
            local written = ffi.new("DWORD[1]")
            if kernel32.WriteFile(win_handle, buffer, #buffer, written, nil) == 0 then
                kernel32.CloseHandle(win_handle)
                win_handle = nil
                handshake_sent = false
            end
        end
    else
        if fd >= 0 then
            local MSG_NOSIGNAL = (jit.os == "Linux") and 0x4000 or 0
            if ffi.C.send(fd, buffer, #buffer, MSG_NOSIGNAL) < 0 then
                ffi.C.close(fd)
                fd = -1
                handshake_sent = false
            end
        end
    end
end

local function draw_ascii_progress_bar(current, total, width)
    local progress = math.floor((current / total) * width)
    return "[" .. string.rep("=", progress) .. string.rep(" ", width - progress) .. "]"
end

local function update_presence()
    local connected = (is_windows and win_handle ~= nil) or (not is_windows and fd >= 0)
    
    if not connected then
        if connect_discord() then
            send_msg(0, { v = 1, client_id = CLIENT_ID })
            handshake_sent = true
        end
        return
    end

    read_discord_pipe()
    if not handshake_sent then return end

    -- Determine if Audio or Video by checking if a Video track ID exists
    local vid = mp.get_property("vid")
    local is_video = (vid and vid ~= "no")
    
    local title = mp.get_property("media-title") or "Unknown Media"
    local artist = mp.get_property("metadata/by-key/ARTIST") or 
                   mp.get_property("metadata/by-key/artist") or 
                   mp.get_property("metadata/by-key/Artist")
                   
    local time_pos = mp.get_property_number("time-pos")
    local pause = mp.get_property_bool("pause")
    
    -- Format state text based on media type and pause state
    local state_str = is_video and "Watching" or "Listening"
    if pause then state_str = "Paused" end
    
    if artist then
        state_str = "by " .. artist:sub(1, 100)
        if pause then state_str = state_str .. " (Paused)" end
    end

    local ascii_progress = ""

    local activity = {
        type = is_video and 3 or 2, -- 3 = Watching, 2 = Listening
        details = title:sub(1, 127),
        state = state_str,
        assets = {
            large_image = "mpv",
            -- large_text is actually a subtitle, but also displays when you hover?
            large_text = is_video and "mpv Media Player" or "mpv Audio Player",
            small_image = pause and "pause" or "play",
            small_text = pause and "Paused" or "Active"
        }
    }
    
    -- Only attach timestamps if playing (removes Discord's timer entirely when paused)
    if not pause and time_pos then
        activity.timestamps = {
            ["start"] = math.floor(os.time() - time_pos),
            ["end"] = math.floor(os.time() + (mp.get_property_number("duration") - time_pos))
        }
    end

    send_msg(1, {
        cmd = "SET_ACTIVITY",
        args = { pid = utils.getpid() or 0, activity = activity },
        nonce = tostring(os.time())
    })
end

local function disconnect()
    if is_windows and win_handle then
        kernel32.CloseHandle(win_handle)
        win_handle = nil
    elseif not is_windows and fd >= 0 then
        ffi.C.close(fd)
        fd = -1
    end
end

debug_log("Nande RPC Script Loaded. Waiting for first tick...")
mp.add_periodic_timer(1, update_presence)
mp.register_event("shutdown", disconnect)
