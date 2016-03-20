
ui = require "pkgxx.ui"
fs = require "pkgxx.fs"

getSize = ->
	-- -sb would have been preferable on Arch, but that ain’t
	-- supported on all distributions using pacman derivatives!
	p = io.popen "du -sk ."
	size = (p\read "*line")\gsub " .*", ""
	size = size\gsub "%s.*", ""
	size = (tonumber size) * 1024
	p\close!

	size

pkginfo = (size, f) =>
	f\write "# Generated by pkg++ (moonscript edition)\n"
	f\write "pkgname = #{@name}\n"

	if @context.packageManager == "apk"
		f\write "pkgver = #{@version}-r#{@release - 1}\n"
	else
		f\write "pkgver = #{@version}-#{@release}\n"

	if @summary
		f\write "pkgdesc = #{@summary}\n"

	if @url
		f\write "url = #{@url}\n"

	p = io.popen "LC_ALL=C date -u\n"
	date = p\read "*line\n"
	p\close!

	f\write "builddate = #{date}\n"

	f\write "buildtype = host\n"

	if @context.builder
		f\write "packager = #{@context.builder}\n"
	if @maintainer
		f\write "maintainer = #{@maintainer}\n"

	-- FIXME: check the license format — in distro modules?
	if @license
		f\write "license = #{@license}\n"

	f\write "size = #{size}\n"
	f\write "arch = #{@architecture}\n"
	f\write "origin = #{@origin.name}\n"

	for group in *@groups
		f\write "group = #{group}\n"

	for depend in *@dependencies
		f\write "depend = #{depend}\n"

	for conflict in *@conflicts
		f\write "conflict = #{conflict}\n"

	for provide in *@provides
		f\write "provides = #{provide}\n"

genPkginfo = (size) =>
	f = io.open ".PKGINFO", "w"
	pkginfo @, size, f
	f\close!

apkPackage = (size) =>
	ui.detail "Building '#{@target}'."

	os.execute [[
		tar --xattrs -c * | abuild-tar --hash | \
			gzip -9 > ../data.tar.gz

		mv .PKGINFO ../

		# append the hash for data.tar.gz
		local sha256=$(sha256sum ../data.tar.gz | cut -f1 -d' ')
		echo "datahash = $sha256" >> ../.PKGINFO

		# control.tar.gz
		cd ..
		tar -c .PKGINFO | abuild-tar --cut \
			| gzip -9 > control.tar.gz
		abuild-sign -q control.tar.gz || exit 1

		# create the final apk
		cat control.tar.gz data.tar.gz > ]] ..
			"'#{@context.packagesDirectory}/#{@target}'"

pacmanPackage = (size) =>
	ui.detail "Building '#{@target}'."

	os.execute "tar cJf " ..
		"'#{@context.packagesDirectory}/#{@target}' " ..
		".PKGINFO *"

{
	target: =>
		if @context.packageManager == "apk"
			"#{@name}-#{@version}-r#{@release - 1}.apk"
		else
			"#{@name}-#{@version}-#{@release}-" ..
				"#{@architecture}.pkg.tar.xz"

	check: =>
		if @context.packageManager == "apk"
			unless os.execute "abuild-sign --installed"
				ui.error "You need to generate a key with " ..
					"'abuild-keygen -a'."
				ui.error "No APK package can be built without " ..
					"being signed."

				return nil, "no abuild key"

	package: =>
		unless @context.builder
			ui.warning "No 'builder' was defined in your configuration!"

		size = getSize!

		genPkginfo @, size

		if @context.packageManager == "apk"
			return apkPackage @, size
		else
			return pacmanPackage @, size
}

