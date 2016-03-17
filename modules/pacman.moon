
ui = require "pkgxx.ui"
fs = require "pkgxx.fs"

pkginfo = (size, f) =>
	f\write "# Generated by pkg++ (moonscript edition)\n"
	f\write "pkgname = #{@name}\n"
	f\write "pkgver = #{@version}-#{@release}\n"

	if @summary
		f\write "pkgdesc = #{@summary}\n"

	if @url
		f\write "url = #{@url}\n"

	p = io.popen "date\n"
	date = p\read "*line\n"
	p\close!

	f\write "builddate = #{date}\n"

	f\write "buildtype = host\n"

	if @packager
		f\write "packager = #{@packager}\n"
	if @maintainer
		f\write "maintainer = #{@maintainer}\n"

	f\write "size = #{size}\n"

	for group in *@groups
		f\write "group = #{group}\n"

	for depend in *@dependencies
		f\write "depend = #{depend}\n"

	for conflict in *@conflicts
		f\write "conflict = #{conflict}\n"

	for provide in *@provides
		f\write "provides = #{provide}\n"

{
	package: =>
		target = "#{@name}-#{@version}-#{@release}-" .. 
			"#{@architecture}.pkg.tar.xz"

		-- -sb would have been preferable on Arch, but that ain’t
		-- supported on all distributions using pacman derivatives!
		p = io.popen "du -sk ."
		size = (p\read "*line")\gsub " .*", ""
		size = size\gsub "%s.*", ""
		size = (tonumber size) * 1024
		p\close!

		f = io.open ".PKGINFO", "w"
		pkginfo @, size, f
		f\close!

		os.execute "tar cJf " ..
			"'#{@context.packagesDirectory}/#{target}' " ..
			".PKGINFO *"
}

