local skynet = require 'skynet'
local cjson = require 'cjson'
local md5 = require 'md5'
local urllib = require 'http.url'
local crypt = require 'skynet.crypt'
local shared = require 'lwf.skynet.shared'
local util = require 'lwf.util'

local ngx_base = {
	OK = 0,
	ERROR = -1,
	AGAIN = -2,
	DONE = -4,
	DECLINED = -5,
	null = cjson.null,

	-- HTTP Methods
	HTTP_GET = "GET",
	HTTP_HEAD = "HEAD",
	HTTP_PUT = "PUT",
	HTTP_POST = "POST",
	HTTP_DELETE = "DELETE",
	HTTP_OPTIONS = "OPTIONS",

	-- HTTP STATUS CONSTRANTS
	HTTP_CONTINUE = 100,
	HTTP_SWITCHING_PROTOCOLS = 101,
	HTTP_OK = 200,
	HTTP_CREATED = 201,
	HTTP_ACCEPTED = 202,
	HTTP_NO_CONTENT = 204,
	HTTP_PARTIAL_CONTENT = 206,
	HTTP_SPECIAL_RESPONSE = 300,
	HTTP_MOVED_PERMANENTLY = 301,
	HTTP_MOVED_TEMPORARILY = 302,
	HTTP_SEE_OTHER = 303,
	HTTP_NOT_MODIFIED = 304,
	HTTP_TEMPORARY_REDIRECT = 307,
	HTTP_BAD_REQUEST = 400,
	HTTP_UNAUTHORIZED = 401,
	HTTP_PAYMENT_REQUIRED = 402,
	HTTP_FORBIDDEN = 403,
	HTTP_NOT_FOUND = 404,
	HTTP_NOT_ALLOWED = 405,
	HTTP_NOT_ACCEPTABLE = 406,
	HTTP_REQUEST_TIMEOUT = 408,
	HTTP_CONFLICT = 409,
	HTTP_GONE = 410,
	HTTP_UPGRADE_REQUIRED = 426,
	HTTP_TOO_MANY_REQUESTS = 429,
	HTTP_CLOSE = 444,
	HTTP_ILLEGAL = 451,
	HTTP_INTERNAL_SERVER_ERROR = 500,
	HTTP_METHOD_NOT_IMPLEMENTED = 501,
	HTTP_BAD_GATEWAY = 502,
	HTTP_SERVICE_UNAVAILABLE = 503,
	HTTP_GATEWAY_TIMEOUT = 504,
	HTTP_VERSION_NOT_SUPPORTED = 505,
	HTTP_INSUFFICIENT_STORAGE = 507,

	-- HTTP LOG LEVEL constants
	STDERR = 'stderr',
	EMERG = 'emerg',
	ALERT = 'alert',
	CRIT = 'crit',
	ERR = 'err',
	WARN = 'warn',
	NOTICE = 'notice',
	INFO = 'info',
	DEBUG = 'debug',

	config = {
		subsystem = 'http',
		debug = false,
		prefix = function() return '' end,
		nginx_version = '1.4.3',
		nginx_configure = function() return '' end,
		ngx_lua_version = '0.9.3',
	},
}

local ngx_log = function(level, ...)
	print('log', level, ...)
end

local null_impl = function()
	assert(false, 'Not implementation')
end

local function shared_index(tab, key)
	local s = rawget(tab, key)
	if not s then
		s = shared.new(key)
		rawset(tab, key, s)
	end
	return s
end

local function to_ngx_header(header)
	local re = {}
	for k,v in pairs(header) do
		local key = string.lower(string.gsub(k, "-", "_"))
		re[key] = v
	end
	return re, cookies
end

local function dump_ngx_header(header)
	local re = {}
	for k,v in pairs(header) do
		local key = string.gsub(k, "_", "-")
		re[key] = v
	end
	return re
end

function ngx_base:bind(method, uri, header, body, httpver, sock, response)
	local to_ngx_req = require 'lwf.skynet.req'
	local to_ngx_resp = require 'lwf.skynet.resp'

	assert(header)
	local header = to_ngx_header(header)
	self.var:bind(method, uri, header, body, sock)

	self.req = to_ngx_req(self, body, httpver)
	self.resp = to_ngx_resp(self)
	self.ctx = {}
	self.status = nil
	self.write_response = response
	self.socket = sock

	self.update_time()
end

local function response(ngx, ...)
	assert(ngx.write_response)
	ngx.write_response(ngx.var.socket or ngx.socket, ...)
	ngx.write_response = nil
end

local function create_wrapper(doc_root)
	local to_ngx_var = require 'lwf.skynet.var'
	local ngx_var = to_ngx_var(doc_root)
	local ngx = {
		var = ngx_var,
		arg = {},
		ctx = {},
		location = {},
		status = nil,
	}
	ngx.header = setmetatable({}, {
		__newindex = function(tab, key, value) 
			ngx.resp.set_header(key, value)
		end,
		--__index=function(tab, key) return ngx.resp.get_header(key) or ngx.var.header[key] end,
		__index=function(tab, key) return ngx.resp.get_header(key) end,
	})
	ngx.location.capture = function(uri, options)
		assert(false, "NOT Implemented")
	end
	ngx.location.capture_multi = function(list)
		local res = {}
		for _, v in ipairs(list) do
			res[#res + 1] = ngx.location.capture(table.unpack(v))
		end
		return table.unpack(res)
	end

	ngx.exec = function(uri, args)
		assert(nil, uri, args)
	end
	ngx.redirect = function(uri, status)
		local status = status or ngx.status or 302
		ngx.resp.set_header('Location', uri)
		local header = dump_ngx_header(ngx.resp.get_headers())
		response(ngx, status, ngx.resp.get_body(), header)
	end
	ngx.send_headers = function()
		assert(nil, "NNNN")
	end
	ngx.headers_send = false
	ngx.print = function(...) 
		ngx.resp.append_body(...)
	end
	ngx.say = function(...)
		ngx.resp.append_body(...)
		ngx.resp.append_body("\r\n")
	end
	ngx.log = ngx_log
	ngx.flush = function(wait)
		assert(false, "flush fake!")
		local header = dump_ngx_header(ngx.resp.get_headers())
		return response(ngx, ngx.status or 200, ngx.resp.get_body(), header)
	end
	ngx.exit = function(status)
		local header = dump_ngx_header(ngx.resp.get_headers())
		return response(ngx, status or ngx.status or 200, ngx.resp.get_body(), header)
	end
	ngx.eof = function() return true end
	ngx.sleep = function(seconds)
		skynet.sleep(seconds * 100)
	end
	ngx.escape_uri = util.escape_url
	ngx.unescape_uri = util.unescape_url
	ngx.encode_args = function(args)
		return util.encode_query_string(args)
	end
	ngx.decode_args = function(str)
		return urllib.parse_query(str)
	end
	ngx.encode_base64 = function(str, no_padding)
		assert(not no_padding)
		return crypt.base64encode(str)
	end
	ngx.decode_base64 = function(str)
		return crypt.base64decode(str)
	end
	ngx.crc32_short = function(str)
		assert(false)
	end
	ngx.crc32_long = function(str)
		assert(false)
	end
	ngx.hmac_sha1 = function(secret_key, str)
		return crypt.hmac_sha1(secret_key, str)
	end
	ngx.md5 = function(str)
		return md5.sumhexa(str)
	end
	ngx.md5_bin = function(str)
		return md5.sum(str)
	end
	ngx.sha1_bin = function(str)
		return crypt.sha1(str)
	end
	ngx.quote_sql_str = function(raw_value)
		local mysql = require 'skynet.db.mysql'
		return mysql.quote_sql_str(raw_value)
	end

	--- TIME STUFF
	local now = os.time() -- local
	local skynet_now = skynet.time() -- UTC

	ngx.today = function()
		return os.date('%Y-%m-%d', now)
	end
	ngx.time = function()
		return now + (skynet_now - math.floor(skynet_now))
	end
	ngx.now = function()
		return skynet_now
	end
	ngx.update_time = function() 
		now = os.time()
		skynet_now = skynet.time()
	end
	ngx.localtime = function()
		return os.date('%F %T', now)
	end
	ngx.utctime = function()
		return os.date('%F %T', math.floor(skynet_now))
	end
	ngx.cookie_time = function(sec)
		--return os.date('%a, %d-%b-%y %T %Z', sec)
		return os.date('%a, %d-%b-%y %H:%M:%S %Z', sec)
	end
	ngx.http_time = function(sec)
		--return os.date('%a, %d %b %Y %T %Z', sec)
		return os.date('%a, %d-%b-%y %H:%M:%S %Z', sec)
	end
	ngx.parse_http_time = function(str)
		assert(false)
	end
	ngx.is_subrequest = function() return false end
	ngx.re = require 'lwf.skynet.re' 
	--TODO:
	ngx.shared = setmetatable({}, {__index=shared_index})

	ngx.get_phase = function()
		return 'content'
	end

	return setmetatable(ngx, {__index=ngx_base})
end

return create_wrapper
