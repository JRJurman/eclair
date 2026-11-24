local ffi = require("ffi")

ffi.cdef[[
	typedef enum {
		ECLAIR_OK = 0,
		ECLAIR_ERR_NOT_INITIALIZED,
		ECLAIR_ERR_NO_BACKEND,
		ECLAIR_ERR_INVALID_ARG,
		ECLAIR_ERR_BACKEND_FAILED
	} eclair_error;

	typedef enum {
		ECLAIR_ROUTE_OFF,
		ECLAIR_ROUTE_SCREEN_READER_ONLY,
		ECLAIR_ROUTE_PREFER_SCREEN_READER,
		ECLAIR_ROUTE_SYNTHESIZER_ONLY
	} eclair_route;

	typedef enum {
		ECLAIR_OUTPUT_NONE,
		ECLAIR_OUTPUT_SCREEN_READER,
		ECLAIR_OUTPUT_SYNTHESIZER
	} eclair_output;

	eclair_error eclair_init(void);
	void eclair_shutdown(void);
	eclair_error eclair_speak(const char *utf8, bool interrupt);
	eclair_error eclair_stop(void);
	void eclair_set_route(eclair_route route);
	void eclair_set_rate(float rate);
	void eclair_set_volume(float volume);
	eclair_output eclair_current_output(void);
	const char *eclair_backend_name(void);
	const char *eclair_error_string(eclair_error err);
]]

local os_name = love.system.getOS()
local base = love.filesystem.getSourceBaseDirectory()

-- repo build output, when running this example as a folder from the eclair repo
local dist = base .. "/../dist"

local macos = { base .. "/eclair/libeclair.dylib", base .. "/libeclair.dylib", dist .. "/libeclair.dylib" }

local candidates = ({
	["OS X"]  = macos,
	macOS     = macos, -- renamed in LÖVE 12
	Windows   = { base .. "\\eclair\\eclair.dll", base .. "\\eclair.dll", dist .. "/eclair.dll", "eclair" },
	Linux     = { base .. "/eclair/libeclair.so", base .. "/libeclair.so", dist .. "/libeclair.so" },
	Android   = { "eclair" },
})[os_name]

local eclair_lib
local errors = {}

if candidates then
	for _, libname in ipairs(candidates) do
		local ok, lib_or_err = pcall(ffi.load, libname)
		if ok then
			eclair_lib = lib_or_err
			break
		end
		errors[#errors + 1] = tostring(lib_or_err)
	end
else
	-- iOS: confirm the statically-linked symbol resolves, then use ffi.C.
	local ok, err = pcall(function() local _ = ffi.C.eclair_init end)
	if ok then
		eclair_lib = ffi.C
	else
		errors[#errors + 1] = tostring(err)
	end
end

if not eclair_lib then
	error("eclair load failed:\n" .. table.concat(errors, "\n"))
end

local init_err = eclair_lib.eclair_init()
if init_err ~= eclair_lib.ECLAIR_OK then
	error("eclair init failed: " .. ffi.string(eclair_lib.eclair_error_string(init_err)))
end

local routes = {
	off                = eclair_lib.ECLAIR_ROUTE_OFF,
	screenreaderonly   = eclair_lib.ECLAIR_ROUTE_SCREEN_READER_ONLY,
	preferscreenreader = eclair_lib.ECLAIR_ROUTE_PREFER_SCREEN_READER,
	synthesizeronly    = eclair_lib.ECLAIR_ROUTE_SYNTHESIZER_ONLY,
}

local outputs = {
	[tonumber(eclair_lib.ECLAIR_OUTPUT_NONE)]          = "none",
	[tonumber(eclair_lib.ECLAIR_OUTPUT_SCREEN_READER)] = "screenreader",
	[tonumber(eclair_lib.ECLAIR_OUTPUT_SYNTHESIZER)]   = "synthesizer",
}

-- true on success, otherwise false and a description of the error
local function result(err)
	if err == eclair_lib.ECLAIR_OK then
		return true
	end
	return false, ffi.string(eclair_lib.eclair_error_string(err))
end

local eclair = {}

function eclair.speak(text, interrupt)
	return result(eclair_lib.eclair_speak(tostring(text), interrupt and true or false))
end

function eclair.stop()
	return result(eclair_lib.eclair_stop())
end

function eclair.setRoute(route)
	eclair_lib.eclair_set_route(routes[route] or error("unknown eclair route: " .. tostring(route), 2))
end

function eclair.setRate(rate)
	eclair_lib.eclair_set_rate(rate)
end

function eclair.setVolume(volume)
	eclair_lib.eclair_set_volume(volume)
end

function eclair.getOutput()
	return outputs[tonumber(eclair_lib.eclair_current_output())]
end

-- nil until a backend is available
function eclair.getBackendName()
	local name = eclair_lib.eclair_backend_name()
	if name ~= nil then
		return ffi.string(name)
	end
end

function eclair.shutdown()
	eclair_lib.eclair_shutdown()
end

return eclair
