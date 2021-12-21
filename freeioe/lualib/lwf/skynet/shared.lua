local skynet = require 'skynet'
local dc = require 'skynet.datacenter'

local class = {}

local function get_time()
	local now = skynet.time()
	return os.time() + (now - math.floor(now))
end

function class:gen_key(key)
	return 'shared.'..self.name..'.'..key
end

function class:dc_get(key)
	return dc.get('lwf_shared', self.name, key)
end

function class:dc_set(key, value)
	dc.set('lwf_shared', self.name, key, value)
	return true
end

function class:get(key)
	local v = self:dc_get(key)
	if not v then
		return false, "not exists"
	end

	if v.exptime and v.exptime < get_time() then
		return false, "expired"
	end
	return v.value, v.flags
end

function class:get_stale(key)
	local v = self:dc_get(key)
	if not v then
		return false, "not exists"
	end
	return v.value, v.flags, v.exptime and v.exptime < get_time() or false
end

function class:set(key, value, exptime, flags)
	if not value then
		local r, err = self:dc_set(key, nil)
		return true, 'ok', false
	end

	local exptime = exptime and tonumber(exptime) or nil
	local flags = flags ~= 0 and nil or flags

	local r = self:dc_get(key)
	local f = r and 'update' or 'new'

	local r, err = self:dc_set(key, {
		value = value,
		exptime = exptime,
		flags = flags,
	})
	if not r then
		return false, err
	end
	return true, 'ok', false
end

function class:safe_set(key, value, exptime, flags)
	return self:set(key, value, exptime, flags)
end

function class:add(key, value, exptime, flags)
	local exptime = exptime and tonumber(exptime) or nil
	local flags = flags ~= 0 and nil or flags
	local v = self:dc_get(key)

	if not v then
		local r, err = self:dc_set(key, {
			value = value,
			exptime = exptime,
			flags = flags,
		})
		if not r then
			return false, err
		end
		return true, 'ok', false
	end
	return false, 'exists'
end

function class:safe_add(key, value, exptime, flags)
	return self:add(key, value, exptime, flags)
end

function class:replace(key, value, exptime, flags)
	local exptime = exptime and tonumber(exptime) or nil
	local flags = flags ~= 0 and nil or flags
	local v = self:dc_get(key)

	if v then
		local r, err = self:dc_set(key, {
			value = value,
			exptime = exptime,
			flags = flags,
		})
		if not r then
			return false, err
		end
		return true, 'ok', false
	end
	return false, 'not found'
end

function class:delete(key)
	self:dc_set(key, nil)
end

function class:incr(key, value, init)
	if type(value) ~= 'number' then
		return nil, "not a number"
	end
	local init = tonumber(init)
	local v = self:dc_get(key)
	if v then
		v.value = v.value + value
		local r, err = self:dc_set(key, v)
		if r then
			return v.value, 'ok', false
		end
		return nil, err, false
	else
		if not init then
			return nil, "not found"
		end
		local value = init + value
		local r, err = self:dc_set(key, { value=value })
		if r then
			return value, 'ok', false
		end
		return nil, err
	end
end

function class:lpush(key, value)
	local v = self:dc_get(key)
	if v and type(v.value) ~= 'table' then
		return nil, "value not a list"
	end
	if not v then
		local r, err = self:dc_set(key, { value={ value } })
		if not r then
			return nil, err
		end
		return 1
	else
		table.insert(v.value, 1, value)
		local r, err = self:dc_set(key, v)
		if not r then
			return nil, err
		end
		return #v.value
	end
end

function class:rpush(key, value)
	local v = self:dc_get(key)
	if v and type(v.value) ~= 'table' then
		return nil, "value not a list"
	end
	if not v then
		local r, err = self:dc_set(key, { value={ value } })
		if not r then
			return nil, err
		end
		self:push_key(key)
		return 1
	else
		table.insert(v.value, value)
		local r, err = self:dc_set(key, v)
		if not r then
			return nil, err
		end
		return #v.value
	end
end

function class:lpop(key)
	local v = self:dc_get(key)
	if not v then
		return nil, 'not exists'
	end
	local value = v.value
	if type(value) ~= 'table' then
		return nil, "value not a list"
	end
	local val = table.remove(value, 1)
	self:dc_set(key, v)
	return val
end

function class:rpop(key)
	local v = self:dc_get(key)
	if not v then
		return nil, 'not exists'
	end
	local value = v.value
	if type(value) ~= 'table' then
		return nil, "value not a list"
	end
	local val = table.remove(value)
	self:dc_set(key, v)
	return val
end

function class:llen(key)
	local v = self:dc_get(key)
	if not v then
		return nil, 'not exists'
	end
	local value = v.value
	if type(value) ~= 'table' then
		return nil, "value not a list"
	end
	return #value
end

function class:flush_all()
	local keys = dc.get('lwf_shared', self.name)
	if not keys then
		return
	end
	for k, v in pairs(keys) do
		if v.exptime >= get_time() then
			v.exptime = get_time() - 60
			dc.set('lwf_shared', self.name, k, v)
		end
	end
end

function class:flush_expired()
	local keys = dc.get('lwf_shared', self.name)
	if not keys then
		return
	end
	local count = 0
	for k, v in pairs(keys) do
		if v.exptime < get_time() then
			dc.set('lwf_shared', self.name, k, nil)
			count = count + 1
		end
	end
	return count
end

function class:get_keys()
	local keys = dc.get('lwf_shared', self.name)
	for k, _ in pairs(v) do
		keys[#keys + 1] = k
	end
	return keys
end

function class.new(name)
	return setmetatable({name=name}, {__index=class})
end

return class
