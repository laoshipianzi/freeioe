local skynet = require 'skynet'
local util = require "lwf.util"
local urllib = require 'http.url'
local cjson = require 'cjson.safe'

local _M = {}

local function split_filename(path)
  local name_patt = "[/\\]?([^/\\]+)$"
  return (string.match(path, name_patt))
end

local function insert_field (tab, name, value, overwrite)
  if overwrite or not tab[name] then
    tab[name] = value
  else
    local t = type (tab[name])
    if t == "table" then
      table.insert (tab[name], value)
    else
      tab[name] = { tab[name], value }
    end
  end
end

local function parse_qs(qs, tab, overwrite)
  tab = tab or {}
  if type(qs) == "string" then
    local url_decode = util.url_decode
    for key, val in string.gmatch(qs, "([^&=]+)=([^&=]*)&?") do
      insert_field(tab, url_decode(key), url_decode(val), overwrite)
    end
  elseif qs then
    error("WSAPI Request error: invalid query string")
  end
  return tab
end

local function get_boundary(content_type)
  local boundary = string.match(content_type, "boundary%=(.-)$")
  return "--" .. tostring(boundary)
end

local function break_headers(header_data)
  local headers = {}
  for type, val in string.gmatch(header_data, '([^%c%s:]+):%s+([^\n]+)') do
    type = string.lower(type)
    headers[type] = val
  end
  return headers
end

local function read_field_headers(input, pos)
  local EOH = "\r\n\r\n"
  local s, e = string.find(input, EOH, pos, true)
  if s then
    return break_headers(string.sub(input, pos, s-1)), e+1
  else return nil, pos end
end

local function get_field_names(headers)
  local disp_header = headers["content-disposition"] or ""
  local attrs = {}
  for attr, val in string.gmatch(disp_header, ';%s*([^%s=]+)="(.-)"') do
    attrs[attr] = val
  end
  return attrs.name, attrs.filename and split_filename(attrs.filename)
end

local function read_field_contents(input, boundary, pos)
  local boundaryline = "\r\n" .. boundary
  local s, e = string.find(input, boundaryline, pos, true)
  if s then
    return string.sub(input, pos, s-1), s-pos, e+1
  else return nil, 0, pos end
end

local function file_value(file_contents, file_name, file_size, headers)
  local value = { contents = file_contents, name = file_name,
    size = file_size }
  for h, v in pairs(headers) do
    if h ~= "content-disposition" then
      value[h] = v
    end
  end
  return value
end

local function fields(input, boundary)
  local state, _ = { }
  _, state.pos = string.find(input, boundary, 1, true)
  state.pos = state.pos + 1
  return function (state, _)
     local headers, name, file_name, value, size
     headers, state.pos = read_field_headers(input, state.pos)
     if headers then
       name, file_name = get_field_names(headers)
       if file_name then
         value, size, state.pos = read_field_contents(input, boundary,
            state.pos)
         value = file_value(value, file_name, size, headers)
       else
         value, size, state.pos = read_field_contents(input, boundary,
            state.pos)
       end
     end
     return name, value
   end, state
end

local function parse_multipart_data(input, input_type, tab, overwrite)
  tab = tab or {}
  local boundary = get_boundary(input_type)
  for name, value in fields(input, boundary) do
    insert_field(tab, name, value, overwrite)
  end
  return tab
end

local function parse_post_data(header, body, tab, overwrite)
  tab = tab or {}
  local input_type = header["content_type"] or ""
  if string.find(input_type, "x-www-form-urlencoded", 1, true) then
    local length = tonumber(header["content_length"]) or 0
    parse_qs(body:sub(1, length) or "", tab, overwrite)
  elseif string.find(input_type, "multipart/form-data", 1, true) then
    local length = tonumber(header["content_length"]) or 0
    if length > 0 then
       parse_multipart_data(body:sub(1, length) or "", input_type, tab, overwrite)
    end
  elseif string.find(input_type, "application/json", 1, true) then
    local length = tonumber(header["content_length"]) or 0
	if length > 0 then
      local post_data = body:sub(1, length) or ""
      tab = cjson.decode(post_data)
    end
  else
    local length = tonumber(header["content_length"]) or 0
    tab.post_data = body:sub(1, length) or ""
  end
  return tab
end


local function to_ngx_req(ngx, body, httpver)
	assert(ngx)
	local var = ngx.var
	local start_time = skynet.now()
	local post_args = {}
	local body = body
	local __socket = nil
	return {
		is_internal = function() return false end,
		start_time = start_time,
		http_version = httpver,
		raw_header = function(no_request_line) return ngx.var.header end,
		get_method = function() return var.method end,
		set_method = function(m) var.method = m end,
		set_uri = function(uri, jump) 
			assert(not jump)
			local path, query = urllib.parse(uri)
			var.uri = uri
			var.path = path
			var.args = query
		end,
		set_uri_args = function(args)
			if type(args) == 'table' then
				local q = {}
				for k,v in pairs(query) do
					table.insert(q, string.format("%s=%s",util.url_encode(k),util.url_encode(v)))
				end
				var.args = table.concat(q, '&')
			else
				var.args = args
			end
		end,
		get_uri_args = function()
			return urllib.parse_query(var.args)
		end,
		get_post_args = function()
			return post_args
		end,
		get_headers = function()
			return var.header
		end,
		set_header = function(header_name, header_value)
			var.header[header_name] = header_value
		end,
		clear_header = function(header_name)
			var.header[header_name] = nil
		end,
		read_body = function()
			post_args = parse_post_data(var.header, body)
		end,
		discard_body = function() body = nil end,
		get_body_data = function() return body end,
		set_body_data = function(data) 
			body = data 
			post_args = parse_post_data(var.header, body)
		end,
		get_body_file = function() return post_args.filename end,
		set_body_file = function(file_name, auto_clean)
			post_args.filename = file_name
		end,
		init_body = function() body = "" end,
		append_body = function(data_chunk) body = body..data_chunk end,
		finish_body = function()
			post_args = parse_post_data(var.header, body)
		end,
		socket = function()
			assert(false, "not implemented")
			local to_ngx_socket = require 'lwf.skynet.socket'
			if not __socket then
				__socket = to_ngx_socket(ngx, body)
			end
			return __socket
		end,
	}
end

return to_ngx_req
