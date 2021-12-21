-- Authentification module
--

local dc = require 'skynet.datacenter'
local md5 = require 'md5'

local _M = {}
local class = {}
local default_salt = "SimpleAuth"
local default_file = ".htpasswd.lwf"

local function load_auth_file(path, salt)
	local keys = {}

	if not path then
		return keys
	end

	local file, err = io.open(path)
	if file then
		for c in file:lines() do
			local k, v = string.match(c, "([^=]+)=(%w+)")
			keys[k] = v
		end
		file:close()
	end

	if keys['__salt'] ~= salt then
		return {
			admin = md5.sumhexa('admin1'..salt)
		}
	end

	return keys
end

local function save_auth_file(path, keys, salt)
	if not path then
		return nil, "file not configured"
	end

	local file, err = io.open(path, 'w+')
	if not file then
		return nil, err
	end

	file:write(string.format('%s=%s\n', '__salt', salt))
	for k, v in pairs(keys) do
		file:write(string.format('%s=%s\n', k, v))
	end

	file:close()

	return true
end

_M.new = function(realm, cfg)
	local salt = cfg.salt or default_salt
	local file = cfg.file or default_file
	if not dc.get('LWF', 'AUTH', '__salt') then
		local keys = load_auth_file(file, salt)
		dc.set('LWF', 'AUTH', keys)
	end
	local obj = {
		realm = realm,
		cfg = cfg,
		_salt = salt,
		_file = file,
	}

	return setmetatable(obj, {__index=class})
end

function class:authenticate(username, password)
	local md5passwd = md5.sumhexa(password..self._salt)
	if dc.get('LWF', 'AUTH', username) == md5passwd then
		return true
	end
	return false, 'Incorrect username or password'
end

function class:verify(username, sid)
	if not dc.get('LWF', 'AUTH', username) then
		return false, 'No such user'
	end
	return self:get_sid(username) == sid
end

function class:get_sid(username)
	local key = username..(dc.get('LWF', 'AUTH', username) or '')
	return  md5.sumhexa(key..self._salt)
end

function class:clear_sid(username)
	return true
end

function class:set_password(username, password)
	dc.set('LWF', 'AUTH', username, md5.sumhexa(password..self._salt))
	local keys = dc.get('LWF', 'AUTH')
	save_auth_file(self._file, keys, self._salt)
end

function class:add_user(username, password, mt)
	dc.set('LWF', 'AUTH', username, md5.sumhexa(password..self._salt))
	local keys = dc.get('LWF', 'AUTH')
	save_auth_file(self._file, keys, self._salt)
end

function class:get_metadata(username)
	return nil, 'Meta data is not support by simple auth module'
end

function class:set_metadata(username, meta)
	return nil, 'Meta data is not support by simple auth module'
end

function class:has(username)
	if dc.get('LWF', 'AUTH', username) then
		return true
	else
		return false
	end
end

return _M
