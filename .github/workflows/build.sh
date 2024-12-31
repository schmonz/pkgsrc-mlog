#!/bin/sh

set -e

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
	abi="$1"; shift
	version="$1"; shift
	pkgsrc_prefix="$1"; shift
	echo cached-${lname}-${arch}-${abi}-${version}$(echo ${pkgsrc_prefix} | sed -e 's|/|-|g')
}

compute_var_tmp() {
	if [ -e /private ]; then
		# WRKOBJDIR must not contain any symlinks
		echo /private/var/tmp
	else
		echo /var/tmp
	fi
}

restore_bootstrap_or_rebootstrap() {
	cache_prefix="$1"; shift
	abi="$1"; shift
	pkgsrc_prefix="$1"; shift
	var_tmp="$1"; shift

	if [ -d "${cache_prefix}" ]; then
		mkdir -p $(dirname "${pkgsrc_prefix}")
		mv "${cache_prefix}" "${pkgsrc_prefix}"
	else
		(
			echo "SCHMONZ: restore_bootstrap_or_rebootstrap 1: $(pwd)"
			cd pkgsrc/bootstrap
			echo "SCHMONZ: restore_bootstrap_or_rebootstrap 2: $(pwd)"

			bootstrap_args="--workdir ${var_tmp}/pkgsrc/bootstrap"
			bootstrap_args="${bootstrap_args} --prefix ${pkgsrc_prefix}"
			[ "${abi}" != default ] && bootstrap_args="${bootstrap_args} --abi ${abi}"

			./bootstrap ${bootstrap_args} \
				|| cat ${var_tmp}/pkgsrc/bootstrap/wrk/pkgtools/cwrappers/work/libnbcompat/config.log
		)
	fi
	cat ${pkgsrc_prefix}/etc/mk.conf
}

build_this_package() {
	var_tmp="$1"; shift
	(
		echo "SCHMONZ: build_this_package 1: $(pwd)"
		cd pkgsrc/${GITHUB_REPOSITORY}
		echo "SCHMONZ: build_this_package 2: $(pwd)"
		bmake WRKOBJDIR=${var_tmp}/pkgsrc/obj package
	)
}

prepare_release_artifacts() {
	lname="$1"; shift
	arch="$1"; shift
	abi="$1"; shift
	version="$1"; shift

	abi_description="-${abi}"
	[ "${abi}" = default ] && abi_description=''

	mkdir release-contents
	(
		echo "SCHMONZ: prepare_release_artifacts 1: $(pwd)"
		cd pkgsrc/${GITHUB_REPOSITORY}
		echo "SCHMONZ: prepare_release_artifacts 2: $(pwd)"

		echo "release_version=$(bmake show-var VARNAME=PKGVERSION)" \
			>> "${GITHUB_ENV}"

		mv $(bmake show-var VARNAME=PKGFILE) ../../../release-contents
	)
	(
		echo "SCHMONZ: prepare_release_artifacts 3: $(pwd)"
		cd release-contents
		echo "SCHMONZ: prepare_release_artifacts 4: $(pwd)"
		for i in *.tgz; do
			localbase=$(pkg_info -Q LOCALBASE $i | sed -e 's|/|-|g')
			cc_version=$(pkg_info -Q CC_VERSION $i)
			mv $i ${lname}-${arch}${abi_description}-${version}${localbase}-${cc_version}-$i
		done
	)

	echo "release_asset=$(echo release-contents/*.tgz)" \
		>> "${GITHUB_ENV}"
}

move_bootstrap_somewhere_cacheable() {
	cache_prefix="$1"; shift
	pkgsrc_prefix="$1"; shift
	cp -Rp "${pkgsrc_prefix}" "${cache_prefix}" || true
}

avoid_unneeded_big_slow_rsync() {
	rm -rf pkgsrc || true
}

main() {
	[ $# = 5 ] || die "usage: $0 lname arch abi version prefix"
	[ "$(id -u)" -eq 0 ] || die "script assumes it'll be run as root"

	lname="$1"; shift
	arch="$1"; shift
	abi="$1"; shift
	version="$1"; shift
	pkgsrc_prefix="$1"; shift

	cache_prefix=$(compute_cache_prefix ${lname} ${arch} ${abi} ${version} ${pkgsrc_prefix})
	var_tmp=$(compute_var_tmp)

	unset PKG_PATH
	restore_bootstrap_or_rebootstrap ${cache_prefix} ${abi} ${pkgsrc_prefix} ${var_tmp}
	PATH="${pkgsrc_prefix}"/sbin:"${pkgsrc_prefix}"/bin:${PATH}
	build_this_package ${var_tmp}
	prepare_release_artifacts ${lname} ${arch} ${abi} ${version}
	move_bootstrap_somewhere_cacheable ${cache_prefix} ${pkgsrc_prefix}
	avoid_unneeded_big_slow_rsync
}

main "$@"
exit $?
