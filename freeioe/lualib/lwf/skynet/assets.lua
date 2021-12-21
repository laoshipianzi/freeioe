local lfs = require "lfs"
local util = require "lwf.util"
local mime = require "lwf.skynet.mime"
local enc = require "lwf.skynet.encoding"

-- gets the mimetype from the filename's extension
local function mimefrompath (path)
	local _,_,exten = string.find (path, "%.([^.]*)$")
	if exten then
		return mime [exten]
	else
		return nil
	end
end

-- gets the encoding from the filename's extension
local function encodingfrompath (path)
	local _,_,exten = string.find (path, "%.([^.]*)$")
	if exten then
		return enc [exten]
	else
		return nil
	end
end

-- on partial requests seeks the file to
-- the start of the requested range and returns
-- the number of bytes requested.
-- on full requests returns nil
local function getrange (ngx, f)
	local range = ngx.var.header["range"]
	if not range then return nil end

	local s,e, r_A, r_B = string.find (range, "(%d*)%s*-%s*(%d*)")
	if s and e then
		r_A = tonumber (r_A)
		r_B = tonumber (r_B)

		if r_A then
			f:seek ("set", r_A)
			if r_B then return r_B + 1 - r_A end
		else
			if r_B then f:seek ("end", - r_B) end
		end
	end

	return nil
end

-- sends data from the open file f
-- to the response object res
-- sends only numbytes, or until the end of f
-- if numbytes is nil
local function sendfile (ngx, f, numbytes)
	local block
	local whole = not numbytes
	local left = numbytes
	local blocksize = 8192

	if not whole then blocksize = math.min (blocksize, left) end

	while whole or left > 0 do
		block = f:read (blocksize)
		if not block then return end
		if not whole then
			left = left - string.len (block)
			blocksize = math.min (blocksize, left)
		end
		ngx.print(block)
	end
end

local function in_base(path)
	local l = 0
	if path:sub(1, 1) ~= "/" then path = "/" .. path end
	for dir in path:gmatch("/([^/]+)") do
		if dir == ".." then
			l = l - 1
		elseif dir ~= "." then
			l = l + 1
		end
		if l < 0 then return false end
	end
	return true
end

-- main handler
local function handler(ngx, router, root, file)
	local method = ngx.var.method
	if method ~= "GET" and method ~= "HEAD" then
		return router:exit(405)
	end

	if not in_base(file) then
		return router:exit(403)
	end

	local path = root .."/".. file

	ngx.header["Content-Type"] = mimefrompath (path)
	ngx.header["Content-Encoding"] = encodingfrompath (path)

	local attr = lfs.attributes (path)
	if not attr then
		return router:exit(404)
	end
	assert (type(attr) == "table")

	if attr.mode == "directory" then
		--[[
		req.parsed_url.path = req.parsed_url.path .. "/"
		return res:redirect(util.build_url (req.parsed_url))
		]]--
		return router:exit(404)
	end

	ngx.header["Content-Length"] = attr.size

	local f = io.open(path, "rb")
	if not f then
		return router:exit(404)
	end

	local lm = os.date("!%a, %d %b %Y %H:%M:%S GMT", attr.modification)
	ngx.header["Last-Modified"] = lm

	local lms = ngx.var.header["if_modified_since"] or 0
	--print(ngx.var.request_uri, lms, lm)
	if lms == lm and false then
		f:close()
		return router:exit(304)
	end

	if ngx.var.method == "GET" then
		local range_len = getrange (ngx, f)
		if range_len then
			ngx.status = 206
			ngx.header["Content-Length"] = range_len
		end

		sendfile(ngx, f, range_len)
	end
	f:close()
end


return function (ngx)
	local ngx = ngx
	return function (router, root, file)
		return handler(ngx, router, root, file)
	end
end

