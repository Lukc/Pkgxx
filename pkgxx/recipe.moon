
toml = require "toml"

ui = require "pkgxx.ui"
fs = require "pkgxx.fs"
macro = require "pkgxx.macro"
sources = require "pkgxx.sources"

macroList = =>
	l = {
		pkg: @\packagingDirectory "_"
	}

	for name in *@context.__class.prefixes
		l[name] = @context\getPrefix name

	-- We should remove those. They may generate clashes with the collections’
	-- prefixes generated by Context\getPrefix.
	for name, value in pairs @context.configuration
		l[name] = value

	l

swapKeys = (tree, oldKey, newKey) ->
	tree[oldKey], tree[newKey] = tree[newKey], tree[oldKey]

	for key, value in pairs tree
		if (type value) == "table"
			tree[key] = swapKeys value, oldKey, newKey

	tree

class
	new: (filename, context) =>
		file = io.open filename, "r"

		unless file
			error "could not open recipe", 0

		recipe, e = toml.parse (file\read "*all"), {strict: false}

		swapKeys recipe, "build-dependencies", "buildDependencies"

		file\close!

		@context = context

		recipe = macro.parse recipe, macroList @

		-- FIXME: sort by name or something.
		@splits = @\parseSplits recipe

		@origin = @

		@\applyDiff recipe

		@class = @class or @\guessClass @

		@packager = recipe.packager
		@maintainer = recipe.maintainer or @packager
		@url = recipe.url

		@release = @release or 1

		@dirname = recipe.dirname
		unless @dirname
			if @version
				@dirname = "#{@name}-#{@version}"
			else
				@dirname = recipe.name

		@conflicts    = @conflicts or {}
		@dependencies = @dependencies or {}
		@buildDependencies = @buildDependencies or {}
		@provides     = @provides or {}
		@groups       = @groups or {}
		@options      = @options or {}

		@architecture = @context.architecture
		@sources = sources.parseAll recipe

		bs = recipe["build-system"]
		@buildInstructions =
			configure: recipe.configure or bs,
			build: recipe.build or bs,
			install: recipe.install or bs

		@recipe = recipe -- Can be required for module-defined fields.
		@recipeAttributes = lfs.attributes filename

		@\applyDistributionRules recipe

		for package in *{self, unpack self.splits}
			if package.context.collection
				package.name = package.context.collection ..
					"-" .. package.name

				for list in *{
					"conflicts",
					"dependencies",
					"buildDependencies",
					"provides",
					"groups",
					"options",
				}
					for index, name in pairs package[list]
						package[list][index] = package.context.collection ..
							"-" .. name

		@\setTargets!

		@\checkRecipe!

	parse: (string) =>
		parsed = true
		while parsed
			string, parsed = macro.parseString string, (macroList @), {}

		string

	-- Is meant to be usable after package manager or architecture
	-- changes, avoiding the creation of a new context.
	setTargets: =>
		module = @context.modules[@context.packageManager]

		unless module and module.target
			ui.error "Could not set targets. Wrong package manager module?"
			return nil

		@target = module.target @
		for split in *@splits
			split.target = module.target split

	getTargets: =>
		i = 0

		return ->
			i = i + 1

			if i - 1 == 0
				return @target
			elseif i - 1 <= #@splits
				return @splits[i - 1].target

	parseSplits: (recipe) =>
		splits = {}

		if recipe.splits
			for splitName, data in pairs recipe.splits
				if not data.name
					data.name = splitName

				-- Splits will need much more data than this.
				split = setmetatable {
					os: data.os,
					files: data.files
				}, __index: @

				splits[#splits+1] = split

				@@.applyDiff split, data

				split.class = split.class or @\guessClass split

		splits

	applyDistributionRules: (recipe) =>
		distribution = @context.configuration.distribution
		module = @context.modules[distribution]

		if module
			if module.alterRecipe
				module.alterRecipe @

			ui.debug "Distribution: #{module.name}"
			if module.autosplits
				oldIndex = #@splits

				newSplits = module.autosplits @
				newSplits = macro.parse newSplits, macroList @

				for split in *@\parseSplits splits: newSplits
					ui.debug "Registering automatic split: #{split.name}."

					if not @\hasSplit split.name
						split.automatic = true
						@splits[#@splits+1] = split
					else
						ui.debug " ... split already exists."
		else
			ui.warning "No module found for this distribution: " ..
				"'#{distribution}'."
			ui.warning "Your package is very unlike to comply to " ..
				"your OS’ packaging guidelines."

		-- Not very elegant.
		if recipe.os and recipe.os[distribution]
			@@.applyDiff @, recipe.os[distribution]

		for split in *@splits
			os = split.os

			if os and os[distribution]
				@@.applyDiff split, os[distribution]

	guessClass: (split) =>
		if split.name\match "-doc$"
			"documentation"
		elseif split.name\match "-dev$" or split.name\match "-devel$"
			"headers"
		elseif split.name\match "^lib"
			"library"
		else
			"binary"

	checkRecipe: =>
		module = @context.modules[@context.packageManager]
		if module and module.check
			r, e = module.check @

			if e and not r
				error e, 0

	hasSplit: (name) =>
		for split in *@splits
			if split.name == name
				return true

	hasOption: (option) =>
		for opt in *@options
			if opt == option
				return true

	applyDiff: (diff) =>
		if diff.name
			@name = diff.name
		if diff.version
			@version = diff.version
		if diff.release
			@release = diff.release

		if diff.dependencies
			@dependencies = diff.dependencies
		if diff.buildDependencies
			@buildDependencies = diff.buildDependencies
		if diff.conflicts
			@conflicts = diff.conflicts
		if diff.provides
			@provides = diff.provides
		if diff.groups
			@groups = diff.groups
		if diff.options
			@options = diff.options

		if diff.summary
			@summary = diff.summary
		if diff.description
			@description = diff.description

		if diff.license
			@license = diff.license
		if diff.copyright
			@copyright = diff.copyright

		if diff.class
			@class = diff.class

	checkOwnership: =>
		local uid, gid

		ui.detail "Checking ownership..."

		with io.popen "id -u"
			uid = tonumber \read "*line"
			\close!

		with io.popen "id -g"
			gid = tonumber \read "*line"
			\close!

	stripFiles: =>
		ui.detail "Stripping binaries..."

		fs.changeDirectory (@\packagingDirectory "_"), ->
			find = io.popen "find . -type f"

			line = find\read "*line"
			while line
				p = io.popen "file -b '#{line}'"
				type = p\read "*line"
				p\close!

				if type\match ".*ELF.*executable.*not stripped"
					ui.debug "Stripping '#{line}'."
					os.execute "strip --strip-all '#{line}'"
				elseif type\match ".*ELF.*shared object.*not stripped"
					ui.debug "Stripping '#{line}'."
					os.execute "strip --strip-unneeded '#{line}'"
				elseif type\match "current ar archive"
					ui.debug "Stripping '#{line}'."
					os.execute "strip --strip-debug '#{line}'"

				line = find\read "*line"

			find\close!

	compressManpages: =>
		ui.detail "Compressing manpages..."

		fs.changeDirectory (@\packagingDirectory "_"), ->
			prefix = @\parse @context\getPrefix "mandir"

			-- FIXME: hardcoded directory spotted.
			unless fs.attributes "./#{prefix}"
				ui.debug "No manpage found: not compressing manpages."
				return

			find = io.popen "find ./#{prefix} -type f"

			file = find\read "*line"
			while file
				unless file\match "%.gz$" or file\match "%.xz$" or
				       file\match "%.bz2$"
					ui.debug "Compressing manpage: #{file}"

					switch @context.compressionMethod
						when "gz"
							os.execute "gzip -9 '#{file}'"
						when "bz2"
							os.execute "bzip2 -9 '#{file}'"
						when "xz"
							os.execute "xz -9 '#{file}'"

				file = find\read "*line"

			find\close!

	buildingDirectory: =>
		"#{@context.buildingDirectory}/src/" ..
			"#{@name}-#{@version}-#{@release}"

	packagingDirectory: (name) =>
		"#{@context.buildingDirectory}/pkg/#{name}"

	buildNeeded: =>
		for self in *{self, unpack self.splits}
			if self.automatic
				continue

			attributes = lfs.attributes "" ..
				"#{@context.packagesDirectory}/#{@target}"
			unless attributes
				return true

			if attributes.modification < @recipeAttributes.modification
				ui.info "Recipe is newer than packages."
				return true

	checkDependencies: =>
		module = @context.modules[@context.packageManager]

		unless module and module.isInstalled
			-- FIXME: Make this a real warning once it’s implemented.
			return nil, "unable to check dependencies"

		deps = {}
		for name in *@dependencies
			table.insert deps, name
		for name in *@buildDependencies
			table.insert deps, name

		for name in *deps
			if not module.isInstalled name
				-- FIXME: Check the configuration to make sure it’s tolerated.
				--        If it isn’t, at least ask interactively.
				ui.detail "Installing missing dependency: #{name}"
				@\installDependency name

	installDependency: (name) =>
		module = @context.modules[@context.dependenciesManager]
		if not (module and module.installDependency)
			module = @context.modules[@context.packageManager]

		if not (module and module.installDependency)
			return nil, "no way to install packages"

		module.installDependency name

	download: =>
		ui.info "Downloading…"

		for source in *@sources
			if (sources.download source, @context) ~= true
				return

		true

	updateVersion: =>
		local v

		for source in *@sources
			module = @context.modules[source.protocol]

			unless module
				continue

			if module.getVersion
				v = fs.changeDirectory @context.sourcesDirectory, ->
					module.getVersion source

				if not @version
					@version = v

		@\setTargets!

	prepareBuild: =>
		fs.mkdir @\buildingDirectory!
		fs.mkdir @\packagingDirectory "_"

		for split in *@splits
			fs.mkdir @\packagingDirectory split.name

	extract: =>
		ui.info "Extracting…"

		fs.changeDirectory @\buildingDirectory!, ->
			for source in *@sources
				if source.filename\match "%.tar%.[a-z]*$"
					ui.detail "Extracting '#{source.filename}'."
					os.execute "tar xf " ..
						"'#{@context.sourcesDirectory}/" ..
						"#{source.filename}'"
				else
					ui.detail "Copying '#{source.filename}'."
					-- FIXME: -r was needed for repositories and stuff.
					--        We need to modularize “extractions”.
					os.execute "cp -r " ..
						"'#{@context.sourcesDirectory}/" ..
						"#{source.filename}' ./"

	-- @param name The name of the “recipe function” to execute.
	execute: (name, critical) =>
		ui.debug "Executing '#{name}'."

		if (type @buildInstructions[name]) == "table"
			code = table.concat @buildInstructions[name], "\n"

			code = "set -x -e\n#{code}"

			if @context.configuration.verbosity < 5
				logfile =  "#{@context.packagesDirectory}/" ..
					"#{@name}-#{@version}-#{@release}.log"

				lf = io.open logfile, "w"
				if lf
					lf\close!

				code = "(#{code}) 2>> #{logfile} >> #{logfile}"

			fs.changeDirectory @\buildingDirectory!, ->
				return os.execute code
		else
			@\executeModule name, critical

	executeModule: (name, critical) =>
		if (type @buildInstructions[name]) == "string"
			module = @context.modules[@buildInstructions[name]]

			return fs.changeDirectory @\buildingDirectory!, ->
				module[name] @
		else
			testName = "can#{(name\sub 1, 1)\upper!}#{name\sub 2, #name}"

			for _, module in pairs @context.modules
				if module[name]
					local finished

					r, e = fs.changeDirectory @\buildingDirectory!, ->
						if module[testName] @
							finished = true

							return module[name] @

					if finished
						return r, e

		return nil, "no suitable module found"

	build: =>
		@\prepareBuild!

		@\extract!

		ui.info "Building…"

		success, e = @\execute "configure"
		if not success
			ui.error "Build failure. Could not configure."
			return nil, e

		success, e = @\execute "build", true
		if not success
			ui.error "Build failure. Could not build."
			return nil, e

		success, e = @\execute "install"
		if not success
			ui.error "Build failure. Could not install."
			return nil, e

		ui.info "Doing post-build verifications."
		@\checkOwnership!
		@\stripFiles!
		@\compressManpages!

		true

	split: =>
		mainPkgDir = @\packagingDirectory "_"

		for split in *@splits
			if split.files
				if split.automatic and not @\splitHasFiles split, mainPkgDir
					ui.debug "No file detected for #{split.name}. Ignoring."
					return

				ui.detail "Splitting '#{split.name}'."

				for file in *split.files
					source = (@\packagingDirectory "_") .. file
					destination = (@\packagingDirectory split.name) ..
						file
					ui.debug "split: #{source} -> #{destination}"

					-- XXX: We need to be more cautious about
					--      permissions here.
					if fs.attributes source
						fs.mkdir destination\gsub "/[^/]*$", ""
						os.execute "mv '#{source}' '#{destination}'"

	splitHasFiles: (split, baseDir) =>
		baseDir = baseDir or @\packagingDirectory split.name
		for file in *split.files
			fileName = baseDir .. "/" .. file

			if not fs.attributes fileName
				return false

		return true

	package: =>
		ui.info "Packaging…"
		@\split!

		module = @context.modules[@context.packageManager]

		if module.package
			@\packageSplit module, @

			for split in *@splits
				@\packageSplit module, split
		else
			-- Should NOT happen.
			error "No module is available for the package manager "..
				"'#{@configuration['package-manager']}'."

	-- Checks that the split has the files it’s supposed to have in .files.

	packageSplit: (module, split) =>
		local splitName
		if split == @
			splitName = "_"
		else
			splitName = split.name

		if split.automatic and not @\splitHasFiles split
			ui.debug "Not building automatic split: #{split.name}"

			return

		fs.changeDirectory (@\packagingDirectory splitName), ->
			module.package split

	clean: =>
		ui.info "Cleaning…"
		ui.detail "Removing '#{@\buildingDirectory!}'."

		-- Sort of necessary, considering the directories and files are
		-- root-owned. And they have to if we want our packages to be valid.
		os.execute "sudo rm -rf '#{@\buildingDirectory!}'"

	lint: =>
		e = 0

		unless @name
			ui.error "no 'name' field"
			e = e + 1
		unless @sources
			ui.error "no 'sources' field"
			e = e + 1

		unless @version
			isVersionable = false

			for source in *@sources
				m = @context.modules[source.protocol]

				if m and m.getVersion
					isVersionable = true

					break

			unless isVersionable
				-- FIXME: Check there’s no VCS in the sources
				ui.error "no 'version' field"
				e = e + 1

		unless @summary
			ui.warning "no 'summary' field"
			e = e + 1
		unless @description
			ui.warning "no 'description' field"
			e = e + 1

		unless @url
			ui.warning "no 'url' field"
			e = e + 1

		unless @packager
			ui.warning "no 'packager' field"
			e = e + 1
		unless @options
			ui.warning "no 'options' field"
			e = e + 1

		unless @dependencies
			ui.warning "no 'dependencies' field"
			e = e + 1

		e

	__tostring: =>
		if @version
			"<pkgxx:Recipe: #{@name}-#{@version}-#{@release}>"
		else
			"<pkgxx:Recipe: #{@name}-[devel]-#{@release}>"

