#!/bin/sh

set -e

# XXX parameterize
SCHMONZ_PREFIX=/opt/pkg

warn() {
	echo >&2 "$@"
}

die() {
	warn "$@"
	exit 1
}

compute_cache_prefix() {
	lname="$1"; shift
	arch="$1"; shift
	version="$1"; shift
	echo cached-${lname}-${arch}-${version}$(echo ${SCHMONZ_PREFIX} | sed -e 's|/|-|g')
}

restore_bootstrap_or_rebootstrap() {
	cache_prefix="$1"; shift

	if [ -d "${cache_prefix}" ]; then
		mkdir -p $(dirname "${SCHMONZ_PREFIX}")
		mv "${cache_prefix}" "${SCHMONZ_PREFIX}"
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
	arch="$1"; shift
	version="$1"; shift

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
			mv $i ${lname}-${arch}-${version}-$i
		done
	)

	echo "release_asset=$(echo release-contents/*.tgz)" \
		>> "${GITHUB_ENV}"
}

move_bootstrap_somewhere_cacheable() {
	cache_prefix="$1"; shift
	mv "${SCHMONZ_PREFIX}" "${cache_prefix}"
}

avoid_unneeded_big_slow_rsync() {
	rm -rf pkgsrc
}

main() {
	[ $# = 3 ] || die "usage: $0 lname arch version"
	[ "$(id -u)" -eq 0 ] || die "script assumes it'll be run as root"

	lname="$1"; shift
	arch="$1"; shift
	version="$1"; shift
	cache_prefix=$(compute_cache_prefix ${lname} ${arch} ${version})

	unset PKG_PATH
	restore_bootstrap_or_rebootstrap ${cache_prefix}
	PATH="${SCHMONZ_PREFIX}"/sbin:"${SCHMONZ_PREFIX}"/bin:${PATH}
	build_this_package
	prepare_release_artifacts ${lname} ${arch} ${version}
	move_bootstrap_somewhere_cacheable ${cache_prefix}
	avoid_unneeded_big_slow_rsync
}

main "$@"
exit $?
