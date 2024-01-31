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

compute_pkgsrc_prefix() {
	lname="$1"; shift
	case "${lname}" in
		macos)	echo "/opt/pkg"		;;
		omnios)	echo "/opt/local"	;;
		*)	echo "/usr/pkg"		;;
	esac
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
			cd pkgsrc/bootstrap

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
		cd pkgsrc/${GITHUB_REPOSITORY}
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
		cd pkgsrc/${GITHUB_REPOSITORY}

		echo "release_version=$(bmake show-var VARNAME=PKGVERSION)" \
			>> "${GITHUB_ENV}"

		mv $(bmake show-var VARNAME=PKGFILE) ../../../release-contents
	)
	(
		cd release-contents
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
	[ $# = 4 ] || die "usage: $0 lname arch abi version"
	[ "$(id -u)" -eq 0 ] || die "script assumes it'll be run as root"

	lname="$1"; shift
	arch="$1"; shift
	abi="$1"; shift
	version="$1"; shift

	pkgsrc_prefix=$(compute_pkgsrc_prefix ${lname})
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
