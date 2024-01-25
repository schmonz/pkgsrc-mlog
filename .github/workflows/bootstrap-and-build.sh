#!/bin/sh

set -e

SCHMONZ_PREFIX=/opt/pkg
SCHMONZ_PREFIX_CACHEABLE="$(echo ${SCHMONZ_PREFIX} | sed -e 's|/|-|g')"
SCHMONZ_CACHED_BOOTSTRAP="cached-${lname}-${version}-${arch}${SCHMONZ_PREFIX_CACHEABLE}"

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

	if [ -d "${SCHMONZ_CACHED_BOOTSTRAP}" ]; then
		mkdir -p $(dirname "${SCHMONZ_PREFIX}")
		mv "${SCHMONZ_CACHED_BOOTSTRAP}" "${SCHMONZ_PREFIX}"
	else
		(
			cd pkgsrc/bootstrap
			./bootstrap --prefix "${SCHMONZ_PREFIX}"
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
	mv "${SCHMONZ_PREFIX}" "${SCHMONZ_CACHED_BOOTSTRAP}"
}

avoid_unneeded_big_slow_rsync() {
	rm -rf pkgsrc
}

main() {
	[ $# = 3 ] || die "usage: $0 lname version arch"
	[ "$(id -u)" -eq 0 ] || die "script assumes it'll be run as root"

	lname="$1"; shift
	version="$1"; shift
	arch="$1"; shift

	unset PKG_PATH
	restore_bootstrap_or_rebootstrap ${lname} ${version} ${arch}
	PATH="${SCHMONZ_PREFIX}"/sbin:"${SCHMONZ_PREFIX}"/bin:${PATH}
	build_this_package
	prepare_release_artifacts ${lname} ${version} ${arch}
	move_bootstrap_somewhere_cacheable ${lname} ${version} ${arch}
	avoid_unneeded_big_slow_rsync
}

main "$@"
exit $?
