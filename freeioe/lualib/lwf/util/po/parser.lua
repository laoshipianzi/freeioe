--- Convert po to lmo
--
local parse = function(path)
	local f, err = io.open(path)
	if not f then
		return nil, err
	end

	local t = {}

	local id = nil
	for l in f:lines() do
		if not id then
			id = l:match('^msgid%s+"(.+)"$')
		elseif id then
	--		print(id)
			local str = l:match('^msgstr%s+"(.*)"$')
			if str then
	--			print(str)
				t[id] = str
				id = nil
			end
		end
	end
	f:close()

	return t
end

return parse
