local urllib = require 'http.url'
local util = require 'lwf.util'

local function create_var(doc_root)
	local ngx_var = {
		document_root = doc_root
	}
	ngx_var.bind = function(self, method, uri, header, body, sock)
		local path, query = urllib.parse(uri)
		local cookies = util.parse_cookie_string(header.cookie)

		local var = {
			method = method,
			request_method = method,
			request_uri = uri,
			uri = path,
			header = header,
			scheme = 'http',
			args = query,
			socket = sock,
			cookies = cookies,
		}

		local function var_index(tab, index)
			if index == 'args' then
				return var.args or ""
			end
			if string.match(index, '^arg_') then
				local k = string.sub(index, 5)
				if k then
					local args = var.args_table
					if not args then
						args = urllib.parse_query(var.args)
						var.args_table = args
					end
					return args[k]
				end
			end
			if string.match(index, '^cookie_') then
				local k = string.sub(index, 8)
				if k then
					return var.cookies[k]
				end
			end
			if string.match(index, '^http_') then
				local k = string.sub(index, 6)
				if k then
					return var.header[k] or var[index]
				end
			end
			return var[index] or var.header[index]
		end

		local function var_new_index(tab, index, value)
			if index == 'args' then
				var.args = value
				var.args_table = urllib.parse_query(value)
				return
			end
			var[index] = value
		end
		setmetatable(self, {__index=var_index, __newindex=var_new_index})
	end

	return setmetatable(ngx_var, {__index=var_index, __newindex=var_new_index})
end

return create_var
