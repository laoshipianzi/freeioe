local skynet = require "skynet"
local snax = require "skynet.snax"
local socket = require "skynet.socket"
local crypt = require 'skynet.crypt'
local ioe = require 'ioe'
local websocket = require "websocket"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local cjson = require 'cjson.safe'
local log = require 'utils.log'
local sysinfo = require 'utils.sysinfo'
local restful = require 'http.restful'
local app_file_editor = require 'utils.app_file_editor'

local client_map = {}
local msg_handler = {}
local handler = {}
local http_api = nil

local client_class = {}

function client_class:send(data)
	local str, err = cjson.encode(data)
	if not str then
		log.error("::WS:: CJson encode error", err)
		return nil, err
	end

	local ws = self.ws
	local r, err = xpcall(ws.send_text, debug.traceback, ws, str)
	if not r then
		log.error("::WS:: Call send_text failed", err)
		ws:close(nil, err)
		return nil, err
	end

	self.last = skynet.now()
	return true
end

function client_class:close(code, reason)
	return self.ws:close(code, reason)
end

function client_class:ping(data)
	return self.ws:send_ping(data)
end

function client_class:id()
	return self.ws.id
end

local function handle_socket(id)
    -- limit request body size to 8 * 1024 * 1024 (you can pass nil to unlimit)
    local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), 8 * 1024 * 1024)
    if code then
        if header.upgrade == "websocket" then
            local ws = websocket.new(id, header, handler)
            ws:start()
        end
    end
end

local broadcast_id = 0
local function broadcast_msg(code, data)
	broadcast_id = broadcast_id + 1
	for id, client in pairs(client_map) do
		if client.authed then
			client:send({
				id = broadcast_id,
				code = code,
				data = data,
			})
		end
	end
end

function handler.on_open(ws)
    log.debug(string.format("::WS:: WebSocket[%d] connected", ws.id))
	local client = setmetatable({
		ws = ws,
		last = skynet.now(),
		authed = false,
		_in_ping = false,
	}, {__index=client_class})

	client_map[ws.id] = client
	-- delay send our information
	--
	skynet.timeout(20, function()
		client:send({
			id = 1,
			code = 'info',
			data = {
				sn = ioe.id(),
				beta = ioe.beta()
			}
		})
	end)
end

function handler.on_message(ws, message)
    --log.debug(string.format("::WS:: WebSocket[%d] message len :  %d", ws.id, string.len(message)))
	--ws:send_text(message .. "from server")

	local client = client_map[ws.id]
	if client then
		client.last = skynet.now()

		local msg, err = cjson.decode(message)

		assert(msg.id and tostring(msg.code))	
		assert(client or msg.code == 'login')

		local f = msg_handler[msg.code]
		if not f then
			return client:send({
				id = id,
				code = code,
				data = {
					result = false,
					message = "Unkown operation code "..msg.code
				}
			})
		else
			local r, result, err = xpcall(f, debug.traceback, client, msg.id, msg.code, msg.data)
			if not r then
				log.error(string.format("::WS:: Call msg_handler[%s]", msg.code), result)
				return client:send({
					id = msg.id,
					code = msg.code,
					data = {
						result = false,
						message = result
					}
				})
			else
				return result, err
			end
		end
	else
		-- Should not be here
		ws:close()
	end
end

function handler.on_close(ws, code, reason)
    log.debug(string.format("::WS:: WebSocket[%d] close:%s  %s", ws.id, code, reason))
	client_map[ws.id] = nil
end

function handler.on_pong(ws, data)
    log.debug(string.format("::WS:: %d on_pong %s", ws.id, data))
	local v = client_map[ws.id]
	if v then
		v.last = tonumber(data) or skynet.now()
		v._in_ping = false
	end
end

local function auth_user(user, passwd)
	if user == 'AUTH_CODE' then
		return skynet.call(".upgrader", "lua", "pkg_user_access", passwd)
	end
	local status, body = http_api:post("/user/login", nil, {username=user, password=passwd})
	if status == 200 then
		return true
	end
	return nil, body
end

function msg_handler.login(client, id, code, data)
    log.debug(string.format("::WS:: WebSocket[%d] login %s %s", client.ws.id, data.user, data.passwd))
	local r, err = auth_user(data.user, data.passwd)
	if r then
		client.authed = true
		return client:send({ id = id, code = code, data = { result = true, user = data.user }})
	else
		return client:send({ id = id, code = code, data = { result = false, message = "Login failed" }})
	end
end

local function __fire_result(client, id, code, r, err)
	local result = r and true or false
	return client:send({id = id, code = code, data = { result = result, message = err or "Done" }})
end

function msg_handler.app_new(client, id, code, data)
	if not ioe.beta() then
		return __fire_result(client, id, code, false, "Device in not in beta mode")
	end
	local args = {
		name = data.app,
		inst = data.inst,
	}
	local r, err = skynet.call(".upgrader", "lua", "create_app", id, args)
	return __fire_result(client, id, code, r, err)
end

function msg_handler.app_start(client, id, code, data)
	local appmgr = snax.queryservice('appmgr')
	--[[
	local r, err = appmgr.post.start(data.inst)
	return __fire_result(client, id, code, r, err)
	]]--
	appmgr.post.app_start(data.inst)
	return __fire_result(client, id, code, true)
end

function msg_handler.app_stop(client, id, code, data)
	local appmgr = snax.queryservice('appmgr')
	--[[
	local r, err = appmgr.req.stop(data.inst, data.reason)
	return __fire_result(client, id, code, r, err)
	]]--

	appmgr.post.app_stop(data.inst, data.reason)
	return __fire_result(client, id, code, true)
end

function msg_handler.app_restart(client, id, code, data)
	local appmgr = snax.queryservice('appmgr')
	appmgr.post.app_restart(data.inst, data.reason)
	return __fire_result(client, id, code, true)
end

function msg_handler.app_download(client, id, code, data)
	local post_ops = app_file_editor.post_ops
	local inst = data.inst
	local version = tonumber(data.version)
	local path, err = post_ops.pack_app(inst, version)
	if not path then
		return __fire_result(client, id, code, false, err)
	end

	local f, err = io.open(app_file_editor.app_pack_path..path, "rb")
	if not f then
		return __fire_result(client, id, code, false, err)
	end

	local data = f:read('*a')
	f:close()
	local content = crypt.base64encode(data)
	return client:send({id = id, code = code, data = { result = true, content = content}})
end

function msg_handler.app_list(client, id, code, data)
	local dc = require 'skynet.datacenter'
	local apps = dc.get('APPS') or {}
	local appmgr = snax.queryservice('appmgr')
	local applist = appmgr.req.list()
	for k, v in pairs(apps) do
		v.running = applist[k] and applist[k].inst or nil
		v.running = v.running and true or false
		v.version = math.floor(tonumber(v.version) or 0)
		v.auto = math.floor(tonumber(v.auto or 1))
	end

	return client:send({id = id, code = code, data = apps})
end

function msg_handler.editor_get(client, id, code, data)
	local get_ops = app_file_editor.get_ops

	local app = data.app
	local operation = data.operation
	local node_id = data.id ~= '/' and data.id or ''
	local f = get_ops[operation]
	local content, err = f(app, node_id, data)
	if content then
		return client:send({id = id, code = code, data = { result = true, content = content}})
	else
		return __fire_result(client, id, code, false, err)
	end
end

function msg_handler.editor_post(client, id, code, data)
	if not ioe.beta() then
		return __fire_result(client, id, code, false, "Device in not in beta mode")
	end

	local post_ops = app_file_editor.post_ops

	local app = data.app
	local operation = data.operation
	local node_id = data.id
	local f = post_ops[operation]
	local content, err = f(app, node_id, data)
	if content then
		return client:send({id = id, code = code, data = { result = true, content = content}})
	else
		return __fire_result(client, id, code, false, err)
	end
end

function msg_handler.app_pack(client, id, code, data)
	if not ioe.beta() then
		return __fire_result(client, id, code, false, "Device in not in beta mode")
	end

	local pack_app = app_file_editor.post_ops.pack_app

	local app = data.app
	local r, err = pack_app(app)
	if r then
		return client:send({id = id, code = code, data = { result = true, content = r}})
	else
		return __fire_result(client, id, code, false, err)
	end
end

function msg_handler.event_list(client, id, code, data)
	local buffer = snax.queryservice('buffer')
	local events = buffer.req.get_event()
	client:send({id = id, code = code, data = { result = true, data = events}})
end

function msg_handler.device_info(client, id, code, data)
	local dc = require 'skynet.datacenter'
	local cloud = snax.queryservice('cloud')

	local cfg = {
		sys = dc.get("SYS") or {},
		cloud = dc.get("CLOUD") or {},
		-- app = dc.get("APP") or {}
	}

	local status = {
		cloud = cloud.req.get_status(),
		mem = sysinfo.meminfo(),
		uptime = sysinfo.uptime(),
		loadavg = sysinfo.loadavg(),
		network = sysinfo.network(),
		version = sysinfo.version(),
		skynet_version = sysinfo.skynet_version(),
		cpu_arch = sysinfo.cpu_arch(),
		platform = sysinfo.platform(),
	}

	client:send({id = id, code = code, data = { result = true, data = { cfg=cfg, status=status } } })
end

function accept.app_event(event, inst_name, ...)
	broadcast_msg('app_event', {event=event, app = inst_name, data = {...}})
end

function accept.app_list(applist)
	broadcast_msg('app_list', list)
end

function accept.on_log(data)
	broadcast_msg('log', data)
end

function accept.on_comm(data)
	broadcast_msg('comm', data)
end

function accept.on_event(data)
	broadcast_msg('event', data)
end

local function connect_buffer_service(enable)
	local buffer = snax.queryservice('buffer')
	local appmgr = snax.queryservice('appmgr')
	local obj = snax.self()
	if enable then
		buffer.post.listen(obj.handle, obj.type)
		appmgr.post.listen(obj.handle, obj.type, true) -- Listen on application events
	else
		buffer.post.unlisten(obj.handle)
		appmgr.post.unlisten(obj.handle)
	end
end

local ws_socket = nil

function init()
	http_api = restful("127.0.0.1:8808")
	local address = "0.0.0.0:8818"
    log.notice("::WS:: listening on", address)

    local id = assert(socket.listen(address))
    socket.start(id , function(id, addr)
       socket.start(id)
       pcall(handle_socket, id)
    end)
	ws_socket = id

	skynet.fork(function()
		connect_buffer_service(true)
	end)

	skynet.fork(function()
		while true do

			local now = skynet.now()
			local remove_list = {}
			for k, v in pairs(client_map) do
				local diff = math.abs(now - v.last)
				if diff > 60 * 100 then
					log.debug(string.format("::WS:: %d ping timeout %d-%d", v:id(), v.last, now))
					v:close(nil, 'Ping timeout')
					table.insert(remove_list, k)
				end
				if not v._in_ping and diff >= (30 * 100) then
					log.trace(string.format("::WS:: %d send ping", v:id()))
					v:ping(tostring(now))
					v._in_ping = true
				end
			end

			for _, v in ipairs(remove_list) do
				client_map[v] = nil
			end

			skynet.sleep(100)
		end
	end)
end

function exit(...)
	connect_buffer_service(false)
	socket.close(ws_socket)
	log.notice("::WS:: Service stoped!")
end
