
local RegExp = require 'lwf.RegExpUtils'

local _M = {}

function _M.match(subject, regex, options, ctx, res_table)
	local regex = RegExp.compile(regex, options)
	local m, err = regex:match(subject)
	if not m then
		return nil, err
	end
	return m.submatches, m.matchee
end

function _M.find(subject, regex, options, ctx, nth)
	assert(false, "AAAAAAAA")
	--[[
	local regex = RegExp.compile(regex, options)
	return regex:search(subject)
	]]--
end

function _M.gmatch(subject, regex, options)
	assert(false, "AAAAAAAA")
end

function _M.sub(subject, regex, replace, options)
	assert(false, "AAAAAAAA")
end

function _M.gsub(subject, regex, replace, options)
	assert(false, "AAAAAAAA")
end

return _M
