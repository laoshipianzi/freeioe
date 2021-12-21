-- Authentification module
--

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
	local keys = load_auth_file(file, salt)
	local obj = {
		realm = realm,
		cfg = cfg,
		_salt = salt,
		_file = file,
		_keys = keys,
	}

	return setmetatable(obj, {__index=class})
end

function class:authenticate(username, password)
	local md5passwd = md5.sumhexa(password..self._salt)
	if self._keys[username] and self._keys[username] == md5passwd then
		return true
	end
	return false, 'Incorrect username or password'
end

function class:verify(username, sid)
	if not self._keys[username] then
		return false, 'No such user'
	end
	return self:get_sid(username) == sid
end

function class:get_sid(username)
	local key = username..(self._keys[username] or '')
	return  md5.sumhexa(key..self._salt)
end

function class:clear_sid(username)
	return true
end

function class:set_password(username, password)
	self._keys[username] = md5.sumhexa(password..self._salt)
	save_auth_file(self._file, self._keys, self._salt)
end

function class:add_user(username, password, mt)
	self._keys[username] = md5.sumhexa(password..self._salt)
	save_auth_file(self._file, self._keys, self._salt)
end

function class:get_metadata(username)
	return nil, 'Meta data is not support by simple auth module'
end

function class:set_metadata(username, meta)
	return nil, 'Meta data is not support by simple auth module'
end

function class:has(username)
	if self._keys[username] then
		return true
	else
		return false
	end
end

return _M
