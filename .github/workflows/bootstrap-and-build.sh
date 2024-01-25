#!/bin/sh

set -e

warn() {
	echo >&2 "$@"
}

die() {
	warn "$@"
	exit 1
}

restore_bootstrap_or_rebootstrap() {
	lname="$1"; shift
	version="$1"; shift
	arch="$1"; shift

	if [ -d cached-${lname}-${version}-${arch}-opt-pkg ]; then
		mkdir -p /opt
		mv cached-${lname}-${version}-${arch}-opt-pkg /opt/pkg
	else
		(
			cd pkgsrc/bootstrap
			./bootstrap --prefix /opt/pkg
			./cleanup
		)
	fi
}

build_this_package() {
	(
		cd pkgsrc/${GITHUB_REPOSITORY}
		bmake package
	)
}

prepare_release_artifacts() {
	lname="$1"; shift
	version="$1"; shift
	arch="$1"; shift

	mkdir release-contents
	(
		cd pkgsrc/${GITHUB_REPOSITORY}

		echo "release_version=$(bmake show-var VARNAME=PKGVERSION)" \
			>> "${GITHUB_ENV}"

		mv $(bmake show-var VARNAME=PKGFILE) ../../../release-contents
	)
	(
		cd release-contents
		for i in *.tgz; do
			mv $i vmactions-${lname}-${version}-${arch}-$i
		done
	)

	echo "release_asset=$(echo release-contents/*.tgz)" \
		>> "${GITHUB_ENV}"
}

move_bootstrap_somewhere_cacheable() {
	mv /opt/pkg cached-${lname}-${version}-${arch}-opt-pkg
}

avoid_unneeded_big_slow_rsync() {
	rm -rf pkgsrc
}

main() {
	[ $# = 3 ] || die "usage: $0 lname version arch"
	[ $(id -u) eq 0 ] || die "script assumes it'll be run as root"

	lname="$1"; shift
	version="$1"; shift
	arch="$1"; shift

	unset PKG_PATH
	restore_bootstrap_or_rebootstrap ${lname} ${version} ${arch}
	PATH=/opt/pkg/sbin:/opt/pkg/bin:${PATH}
	build_this_package
	prepare_release_artifacts ${lname} ${version} ${arch}
	move_bootstrap_somewhere_cacheable ${lname} ${version} ${arch}
	avoid_unneeded_big_slow_rsync
}

main "$@"
exit $?
