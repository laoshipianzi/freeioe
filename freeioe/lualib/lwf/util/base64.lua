
local CHUNK_LENGTH=78

local base64_loaded, base64 = pcall(require, "base64")
if not base64_loaded then
	local mime_loaded, mime = pcall(require, 'mime')
	if mime_loaded then
		base64 = {
			encode = mime.b64,
			decode = mime.unb64,
		}
	else
		base64 = require("lwf.util.base64_implementation")
	end
end

return {
	encode = base64.encode,
	decode = base64.decode,
	encode_and_wrap = function(binary_content) 
		local encoded = base64.encode(binary_content)
		local wrapped = "\n"
		for i=1, encoded:len(),CHUNK_LENGTH-1 do
			wrapped = wrapped..encoded:sub(i, i+CHUNK_LENGTH-2).."\n"
		end
		return wrapped
	end,
}
