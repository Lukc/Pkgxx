
ui = require "pkgxx.ui"
fs = require "pkgxx.fs"

_M = {}

_M.download = (source, context) ->
	{:filename, :url} = source

	if source.protocol
		fs.changeDirectory context.sourcesDirectory, ->
			module = context.modules[source.protocol]
			if module and module.download
				module.download source
			else
				ui.error "Does not know how to download: #{url}"
	else
		-- Files are built-in.
		if fs.attributes source.filename
			ui.detail "Copying file: #{filename}"
			a = os.execute "cp '#{filename}' '#{context.sourcesDirectory}/#{filename}'"

			if (type a) == "number" then
				a = a == 0

			return a
		else
			ui.detail "Already downloaded: #{filename}."
			true

_M.parse = (source) ->
	url = source\gsub "%s*->%s*.*", ""
	protocol = url\gsub ":.*", ""
	protocol = url\match "^([^ ]*):"
	filename = source\match "->%s*(%S*)$"

	unless filename
		filename = url\match ":(%S*)"
		filename = (filename or url)\gsub ".*/", ""

	-- Aliases and stuff like git+http.
	if protocol
		protocol = protocol\gsub "+.*", ""
	url = url\gsub ".*+", ""

	{
		protocol: protocol,
		filename: filename,
		url: url
	}

_M.parseAll = (recipe) ->
	local sources

	sources = switch type recipe.sources
		when "string"
			{ recipe.sources }
		when "nil"
			{}
		else
			recipe.sources

	for i = 1, #sources
		sources[i] = _M.parse sources[i]

	sources

_M

