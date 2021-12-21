local _M = {}

local lfs_loaded, lfs = pcall(require, 'lfs')

function _M.scan(directory)
	if lfs_loaded then 
		local t = {}
		for filename in lfs.dir(directory) do
			if filename ~= '.' and filename ~= '..' then
				t[#t + 1] = directory..'/'..filename
			end
		end
		return t
	else
		local t = {}
		local f, err = io.popen('ls -a "'..directory..'"')
		if not f then
			return nil, err
		end

		for filename in f:lines() do
			if filename ~= '.' and filename ~= '..' then
				t[#t + 1] = directory..'/'..filename
			end
		end
		f:close()

		return t
	end
end

function _M.scan_file(directory, ext)
	local t = _M.scan(directory)
	if not ext then
		return t
	end

	local pattern = '%.'..ext..'$'
	for k, v in pairs(t) do
		if not v:match(pattern) then
			t[k] = nil
		end
	end
	return t
end

function _M.do_each(directory, func, ext)
	local t = _M.scan_file(directory, ext)
	if t then
		for k, v in pairs(t) do
			func(v)
		end
	end
end

return _M
