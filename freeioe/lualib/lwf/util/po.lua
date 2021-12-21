--- i18n po files loader module
--

local parser = require 'lwf.util.po.parser'

local _M = {}

_M.loaded = {}
_M.translations = {
	FALLBACKS = {
		en = "en_US",
		zh = "zh_CN",
		_all = "en_US",
	}
}

function _M.attach(directory, lang, reload)
	if not reload and  _M.loaded[directory] then
--		print('folder already attached ', directory)
		return
	end

	_M.loaded[directory] = true

	-- load files
	local utildir = require 'lwf.util.dir'
	utildir.do_each(directory, function(path)
		--- Find the lang if not specified
		local lang = lang
		if not lang then
			lang = path:match('([^/]+)/[^/]+%.po$')
		end
		if lang:len() ~= 2 and lang:len() ~= 5 then
			print('lang name is incorrect ', lang)
			return
		end
		if lang:len() == 5 and not lang:match('.+_.+') then
			print('lang name is incorrect5 ', lang)
			return
		end
		---
		local t = parser(path)
		for k, v in pairs(t) do
			if v and v ~= '' then
				_M.translations[k] = _M.translations[k] or {}
				_M.translations[k][lang] = v
			end
		end
	end, 'po')
end

function _M.get_translations()
	return _M.translations
end

return _M
