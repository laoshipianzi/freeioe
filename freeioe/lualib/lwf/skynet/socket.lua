local class = {}

function class:connect(...)
	assert(false)
end

function class:send(data)
	assert(false)
end

function class:receive(p)
	local s = self._body
	if not s then
		assert(false)
		return nil, "no body"
	end
	if type(p) == 'number' then
		local r = string.sub(s, 1, p)
		self._body = string.sub(s, p + 1)
		return r
	end
	if p == '*a' or p == 'a' then
		self._body = ""
		return s
	end
	if p == '*l' or p == 'l' then
		local r = string.match(s, '^(.-)\r\n*')
		s = string.sub(s, string.len(r) + 1)
		while (s and string.len(s) > 1) and (s[1] == '\n' or s[1] == '\r') do
			s = string.sub(s, 2)
		end
		self._body = s
		return r	
	end
	return nil, "pattern error"
end

local function create_iterator(s)
	local s = s
	return function(size)
		if not size then
			return s, nil, false
		end
		if not s or string.len(s) <= 0 then
			return nil, "end", false
		end
		local r = string.sub(s, 1, size)
		if r then
			s = string.sub(s, size + 1)
			return r, nil, s and (string.len(s) > 0)
		end
		local r = s
		s = nil
		return r, nil, false
	end
end

function class:receiveuntil(pattern, options)
	local s = self._body
	if not s then
		return nil, "no body"
	end

	local b, e = string.find(s, pattern, 1, true)
	if b then
		local r = ""
		if options and options.inclusive then
			r = string.sub(s, 1, e)
		else
			if b > 1 then
				r = string.sub(s, 1, b)
				print("b > 1", b)
			else
				print("b == 1")
			end
		end
		self._body = string.sub(s, e + 1)
		return create_iterator(r)
	end

	return nil, "not found"
end

function class:close()
end

function class:settimeout()
end

function class:settimeouts()
end

function class:setoption()
end

function class:setkeepalive()
end

return function(ngx, body)
	return setmetatable({
		_body = body,
	}, {__index = class})
end
