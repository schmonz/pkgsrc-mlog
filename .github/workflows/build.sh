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
	version="$1"; shift
	pkgsrc_prefix="$1"; shift
	echo cached-${lname}-${arch}-${version}$(echo ${pkgsrc_prefix} | sed -e 's|/|-|g')
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
	version="$1"; shift
	pkgsrc_prefix="$1"; shift

	mkdir release-contents
	(
		echo "SCHMONZ: prepare_release_artifacts 1: $(pwd)"
		cd pkgsrc/${GITHUB_REPOSITORY}
		echo "SCHMONZ: prepare_release_artifacts 2: $(pwd)"

		echo "release_version=$(bmake show-var VARNAME=PKGVERSION)" \
			>> ../../../release-contents/PKGVERSION

		mv $(bmake show-var VARNAME=PKGFILE) ../../../release-contents
	)
	(
		echo "SCHMONZ: prepare_release_artifacts 3: $(pwd)"
		cd release-contents
		echo "SCHMONZ: prepare_release_artifacts 4: $(pwd)"
		for i in *.tgz; do
			echo "SCHMONZ: prepare_release_artifacts 5: ${i}"
			localbase=$(pkg_info -Q LOCALBASE $i | sed -e 's|/|-|g')
			echo "SCHMONZ: prepare_release_artifacts 6: ${localbase}"
			cc_version=$(pkg_info -Q CC_VERSION $i)
			echo "SCHMONZ: prepare_release_artifacts 7: ${cc_version}"
			prefix="$(echo ${pkgsrc_prefix} | sed -e 's|/||' -e 's|/|-|g')"
			echo "SCHMONZ: prepare_release_artifacts 8: ${prefix}"
			new_name="${lname}-${version}-${arch}-${prefix}-${cc_version}-$i"
			echo "SCHMONZ: prepare_release_artifacts 9: ${new_name}"
			mv $i "${new_name}"
		done
	)

	echo "release_asset=$(echo release-contents/PKGVERSION release-contents/*.tgz)" \
		>> "${GITHUB_ENV}"
}

move_bootstrap_somewhere_cacheable() {
	cache_prefix="$1"; shift
	pkgsrc_prefix="$1"; shift
	cp -Rp "${pkgsrc_prefix}" "${cache_prefix}" || true
}

main() {
	[ $# = 4 ] || die "usage: $0 lname arch version prefix"
	[ "$(id -u)" -eq 0 ] || die "script assumes it'll be run as root"

	lname="$1"; shift
	arch="$1"; shift
	version="$1"; shift
	pkgsrc_prefix="$1"; shift

	cache_prefix=$(compute_cache_prefix ${lname} ${arch} ${version} ${pkgsrc_prefix})
	var_tmp=$(compute_var_tmp)

	unset PKG_PATH
	restore_bootstrap_or_rebootstrap ${cache_prefix} ${pkgsrc_prefix} ${var_tmp}
	PATH="${pkgsrc_prefix}"/sbin:"${pkgsrc_prefix}"/bin:${PATH}
	build_this_package ${var_tmp}
	prepare_release_artifacts ${lname} ${arch} ${version} ${pkgsrc_prefix}
	move_bootstrap_somewhere_cacheable ${cache_prefix} ${pkgsrc_prefix}
}

main "$@"
exit $?
