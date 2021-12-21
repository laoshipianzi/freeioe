
local function map_key(k)
	return string.lower(string.gsub(k, "-", "_"))
end

local function to_ngx_resp(ngx)
	local ngx = ngx
	local headers = {
		content_type = 'text/html; charset=utf-8',
		server = 'skynet/lwf',
		connection = 'close',
		date = ngx.http_time(math.floor(ngx.now())),
	}
	local body = {}
	return {
		get_headers = function() return headers end,
		set_header = function(header_name, header_value)
			local header_name = map_key(header_name)
			headers[header_name] = header_value
		end,
		get_header = function(header_name)
			local header_name = map_key(header_name)
			return headers[header_name]
		end,
		get_body = function() return table.concat(body) end,
		append_body = function(...) 
			for _,v in ipairs({...}) do
				body[#body + 1] = v
			end
		end,
		has_body = function()
			return #body == 0
		end,
	}
end

return to_ngx_resp
