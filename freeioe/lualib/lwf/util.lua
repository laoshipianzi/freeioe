
local lpeg = require 'lpeg'
local cjson = require 'cjson'
local unpack = table.unpack or unpack

-----------------------------------------------------------------------------
-- Defines utility functions for LWF
-----------------------------------------------------------------------------

local _M = {}

-----------------------------------------------------------------------------
-- Splits a string on a delimiter. 
-- Adapted from http://lua-users.org/wiki/SplitJoin.
-- 
-- @param text           the text to be split.
-- @param delimiter      the delimiter.
-- @return               unpacked values.
-----------------------------------------------------------------------------
function _M.split(text, delimiter)
   local list = {}
   local pos = 1
   if string.find("", delimiter, 1) then 
      error("delimiter matches empty string!")
   end
   while 1 do
      local first, last = string.find(text, delimiter, pos)
      if first then -- found?
	 table.insert(list, string.sub(text, pos, first-1))
	 pos = last+1
      else
	 table.insert(list, string.sub(text, pos))
	 break
      end
   end
   return unpack(list)
end

-----------------------------------------------------------------------------
-- Escapes a text for using in a text area.
-- 			
-- @param text           the text to be escaped.
-- @return               the escaped text.
-----------------------------------------------------------------------------
--[[
function _M.escape(text) 
   text = text or ""
   text = text:gsub("&", "&amp;"):gsub(">","&gt;"):gsub("<","&lt;")
   return text:gsub("\"", "&quot;")
end
]]
local html_escape_entities = {
	['&'] = '&amp;',
	['<'] = '&lt;',
	['>'] = '&gt;',
	['"'] = '&quot;',
	["'"] = '&#039;'
}
function _M.escape(text)
	text = text or ""
	return (text:gsub([=[["><'&]]=], html_escape_entities))
end

-----------------------------------------------------------------------------
-- Escapes a URL.
-- 
-- @param text           the URL to be escaped.
-- @return               the escaped URL.
-----------------------------------------------------------------------------

function _M.escape_url(text)
   return text:gsub("[^a-zA-Z0-9]",
                    function(character) 
                       return string.format("%%%02x", string.byte(character))
                    end)
end

function _M.unescape_url(text)
	return (string.gsub(text, "%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end


----------------------------------------------------------------------------
-- Decode an URL-encoded string (see RFC 2396)
----------------------------------------------------------------------------
function _M.url_decode(str)
  if not str then return nil end
  str = string.gsub (str, "+", " ")
  str = string.gsub (str, "%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
  str = string.gsub (str, "\r\n", "\n")
  return str
end
----------------------------------------------------------------------------
-- URL-encode a string (see RFC 2396)
----------------------------------------------------------------------------
function _M.url_encode(str)
  if not str then return nil end
  str = string.gsub (str, "\n", "\r\n")
  str = string.gsub (str, "([^%w ])",
        function (c) return string.format ("%%%02X", string.byte(c)) end)
  str = string.gsub (str, " ", "+")
  return str
end

-----------------------------------------------------------------------------
-- An auxiliary function for sendmail, to extract an actual email address
-- from a address field with a name.
-----------------------------------------------------------------------------
local function _extract_email_address(from)
   local from_email_address
   for match in from:gmatch("[a-zA-Z]%S*@%S*[a-zA-Z]") do
      from_email_address = match
   end
   if not from_email_address then
      error("Could not find an email address in "..args.from)
   end
   return from_email_address
end

-----------------------------------------------------------------------------
-- An auxiliary function for sendmail, to collect email addresses in the
-- to, cc, and bcc fields.
--
-- @param recepients     a table for collecting results
-- @param field          the field
-----------------------------------------------------------------------------
local function _collect_recepients_for_sendmail(recepients, field)
   if type(field)=="string" then     
      table.insert(recepients, "<".._extract_email_address(field)..">")
   elseif type(field)==type({}) then
      for i, addr in ipairs(field) do
         table.insert(recepients, "<".._extract_email_address(addr)..">")
      end
   else
      error("to, cc and bcc fields must be a string or a table")
   end
end

-----------------------------------------------------------------------------
-- Sends email on Sputnik's behalf.
--
-- @param args           a table of parameters
-- @param config         the configuration for smtp stuff
-- @return               status (boolean) and possibly an error message
-----------------------------------------------------------------------------
function _M.sendmail(args, config)
   assert(args.to, "No recepient specified")
   assert(args.subject, "No subject specified")
   assert(args.from, "No source specified")

   local from_email_address = _extract_email_address(args.from)
  
   local recepients = {}
   assert(args.to, "The destination address must be specified")
   _collect_recepients_for_sendmail(recepients, args.to)
   _collect_recepients_for_sendmail(recepients, args.bcc or {})

   local smtp = require("socket.smtp")
   local status, err = smtp.send{
            from = from_email_address,
            rcpt = recepients,
            source = smtp.message{
               headers = {
                  from = args.from,
                  to = args.to,
                  subject = args.subject
               },
               body = args.body or "",
            },
            server = config.SMTP_SERVER or "localhost",
            port   = config.SMTP_SERVER_PORT or 25,
            user   = config.SMTP_USER,
            password   = config.SMTP_PASSWORD,
         }
   return status, err
end

-----------------------------------------------------------------------------
-- 
-----------------------------------------------------------------------------
function _M.build_url (parts)
	local out = parts.path or ""
	if parts.query then
		out = out .. ("?" .. parts.query)
	end
	if parts.fragment then
		out = out .. ("#" .. parts.fragment)
	end

	local host = parts.host
	if host then
		host = "//" .. host
		if parts.port then
			host = host .. (":" .. parts.port)
		end
		if parts.scheme then
			host = parts.scheme .. ":" .. host
		end
		if parts.path and out:sub(1, 1) ~= "/" then
			out = "/" .. out
		end
		out = host .. out
	end

	return out
end

function _M.escape_pattern (str)
	local punct = "[%^$()%.%[%]*+%-?%%]"
	return (str:gsub(punct, function(p)
		return "%" .. p
	end))
end

function _M.encode_query_string (t, sep)
	local sep = sep or "&"
	local i = 0
	local buf = { }
	for k, v in pairs(t) do
		if type(k) == "number" and type(v) == "table" then
			k, v = v[1], v[2]
		end
		buf[i + 1] = escape(k)
		buf[i + 2] = "="
		buf[i + 3] = escape(v)
		buf[i + 4] = sep
		i = i + 4
	end
	buf[i] = nil
	return table.concat(buf)
end

function _M.inject_tuples (t)
	for i = 1, #t do
		local tuple = t[i]
		t[tuple[1]] = tuple[2] or true
	end
end


do
	local C, R, P, S, Ct, Cg = lpeg.C, lpeg.R, lpeg.P, lpeg.S, lpeg.Ct, lpeg.Cg
	local white = S(" \t") ^ 0
	local token = C((R("az", "AZ", "09") + S("._-")) ^ 1)
	local value = (token + P('"') * C((1 - S('"')) ^ 0) * P('"')) / _M.unescape_url
	local param = Ct(white * token * white * P("=") * white * value)
	local patt = Ct(Cg(token, "type") * (white * P(";") * param) ^ 0)
	_M.parse_content_disposition = function(str)
		do
			local out = patt:match(str)
			if out then
				_M.inject_tuples(out)
			end
			return out
		end
	end
end

function _M.parse_cookie_string (str)
	if not (str) then
		return { }
	end
	local t = { }
	for key, value in str:gmatch("([^=%s]*)=([^;]*)") do
		t[key] = _M.unescape_url(value)
	end
	return t 
end

do
	local chunk = lpeg.C((lpeg.P(1) - lpeg.S("=&")) ^ 1)
	local tuple = lpeg.Ct(chunk / _M.unescape_url * "=" * (chunk / _M.unescape_url) + chunk)
	local query = lpeg.S("?#") ^ -1 * lpeg.Ct(tuple * (lpeg.P("&") * tuple) ^ 0)
	_M.parse_query_string = function(str)
		local out = query:match(str)
		if out then
			_M.inject_tuples(out)
		end
		return out
	end
end

function _M.read_all(filename)
	local file, err = io.open(filename, "r")
	local data = ((file and file:read("*a")) or nil)
	if file then
		file:close()
	end
	return data
end

function _M.loadfile(file, env)
	local loadfile = loadfile
	if _VERSION == 'Lua 5.1' then
		local CE = require 'lwf.util.compat_env'
		loadfile = CE.loadfile
	end

	------------- for skynet loading -------------
	local ff, err = io.open(file, "r")
	if not ff then
		return nil, err
	end
	local f, err = load(ff:read('*a'), nil, nil, env)
	ff:close()
	------------------ else ----------------------
	--local f, err = loadfile(file, nil, env)
	-------------------end------------------------
	if not f then
		return nil, err
	end

	local r, re = pcall(f)
	if not r then
		assert(r, re)
	end

	return r, re
end

function _M.loadfile_as_table(file, env)
	local env = env or _ENV
	local new_env = _M.auto_table(function() return env end)

	local loadfile = loadfile
	if _VERSION == 'Lua 5.1' then
		local CE = require 'lwf.util.compat_env'
		loadfile = CE.loadfile
	end

	local f, err = loadfile(file, nil, new_env)
	if not f then
		return nil, err
	end

	local r, re = pcall(f)
	if not r then
		return nil, re
	end

	return re, new_env--setmetatable(new_env, {__index={}})
end

function _M.to_json (obj)
	return cjson.encode(obj)
end

function _M.from_json(str)
	return cjson.decode(str)
end

_M.auto_table = function(fn)
	return setmetatable({ }, {
		__index = function(self, name)
			local result = fn()
			getmetatable(self).__index = result
			return result[name]
		end
	})
end

_M.lazy_table = function(t, index)
	return setmetatable(t, {
		__index = function(self, key)
			local fn = index[key]
			if fn then
				do
					local res = fn(self)
					self[key] = res
					return res
				end
			end
		end
	})
end

_M.args_to_table = function(...)
	return {...}
end

_M.guess_lang = function(header)
	local accept_lang = header['accept_language'] or header['Accept-Language']
	if accept_lang then
		accept_lang = accept_lang:match('^(.-),')
	end
	if accept_lang then
		accept_lang = accept_lang:gsub('-', '_')
	end
	return accept_lang or 'zh_CN'
end

return _M
