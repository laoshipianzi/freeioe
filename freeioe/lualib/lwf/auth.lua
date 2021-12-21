local cjson = require 'cjson.safe'
local class = {}
local user_class = {}


function user_class.new(auth, session)
	assert(session)
	local obj = setmetatable({ _impl = auth._impl }, { __index = user_class })
	obj:load(session)
	return obj
end

function user_class:load(session)
	self.session = session
	self.user = session.data.user
	self.user_sid = session.data.user_sid
	self.meta = {}
	self:verify()
end

function user_class:save()
	local session = self.session
	if not session then
		return nil, "Session not binded"
	end
	session.data.user = self.user
	session.data.user_sid = self.user_sid
	self._impl:set_metadata(self.user, self.meta)
	session:save()
	return true
end

function user_class:clear()
	self.user = 'Guest'
	self.user_sid = nil
	self.meta = {}
end

function user_class:verify()
	local impl = self._impl
	local user = self.user
	local sid = self.user_sid
	if user and sid then
		local r, err = impl:verify(user, sid)
		if r then
			self.meta = impl:get_metadata(username) or {}
			return true
		end
	end
	self:clear()
	return false
end

function user_class:login(username, password, ...)
	self:clear()
	local impl = self._impl
	local r, err = impl:authenticate(username, password, ...)
	if not r then
		return nil, err
	end
	local sid, err = impl:get_sid(username)
	if not sid then
		return nil, err
	end

	self.user = username
	self.user_sid = sid
	self.meta = impl:get_metadata(username) or {}

	return true
end

function user_class:login_as(username)
	assert(username)
	local impl = self._impl
	self.user = username
	self.user_sid = impl:get_sid(username)
	self.meta = impl:get_metadata(username) or {}
	return true
end

function user_class:logout()
	if self.user ~= 'Guest' then
		self._impl:clear_sid(self.user)
	end
	self:clear()
end

function user_class:update_password(password)
	if self.user == 'Guest' then
		return nil, "Guest cannot update password"
	end
	self._impl:set_password(self.user, password)
	return true
end

function class:create_user(session)
	return user_class.new(self, session)
end

function class:init()
	local impl = self._impl
	if impl.startup then
		impl:startup()
	end
end

function class:destroy()
	local impl = self._impl
	if impl.teardown then
		impl:teardown()
	end
end

local function load_auth(realm, cfg)
	local auth = nil
	local cfgt = {}
	if type(cfg) == 'string' then
		auth = require('lwf.auth.'..cfg)
	elseif type(cfg) == 'table' then
		auth = require('lwf.auth.'..cfg.name)
		cfgt = cfg
	elseif type(cfg) == 'function' then
		auth = { new = cfg }
	else
		assert('Incorrect configuration for auth')
	end
	assert(auth)
	return auth.new(realm, cfgt)
end

function class.new(realm, cfg)
	assert(cfg)
	local auth = load_auth(realm, cfg)

	return setmetatable({
		realm=realm,
		cfg=cfg,
		_impl=auth,
	}, {
		__index=class,
		__gc = function(self)
			self:destroy()
		end
	})
end

return function (realm, cfg)
	local auth = class.new(realm, cfg)
	auth:init()
	return auth
end
