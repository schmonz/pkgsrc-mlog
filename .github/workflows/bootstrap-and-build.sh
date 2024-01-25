#!/bin/sh

set -e

warn() {
	echo >&2 "$@"
}

die() {
	warn "$@"
	exit 1
}

[ $# = 3 ] || die "usage: $0 lname version arch"

lname="$1"; shift
version="$1"; shift
arch="$1"; shift

# bootstrap pkgsrc
unset PKG_PATH
if [ -d ${GITHUB_WORKSPACE}/cached-${lname}-${version}-${arch}-opt-pkg ]; then
mkdir -p /opt
mv ${GITHUB_WORKSPACE}/cached-${lname}-${version}-${arch}-opt-pkg /opt/pkg
else
cd pkgsrc/bootstrap
./bootstrap --prefix /opt/pkg
./cleanup
cd ../..
fi
warn "SCHMONZ 3: $(date)"

# build this package
PATH=/opt/pkg/sbin:/opt/pkg/bin:${PATH}
cd pkgsrc/${GITHUB_REPOSITORY}
bmake package
warn "SCHMONZ 4: $(date)"

# gather up artifacts
release_version=$(bmake show-var VARNAME=PKGVERSION)
echo "release_version=${release_version}" >> "${GITHUB_ENV}"
mkdir ${GITHUB_WORKSPACE}/release-contents
mv $(bmake show-var VARNAME=PKGFILE) ${GITHUB_WORKSPACE}/release-contents
cd ${GITHUB_WORKSPACE}/release-contents
for i in *.tgz; do mv $i vmactions-${lname}-${version}-${arch}-$i; done
release_asset=$(echo *.tgz)
echo "release_asset=${GITHUB_WORKSPACE}/release-contents/${release_asset}" >> "${GITHUB_ENV}"

# put bootstrap somewhere cacheable
mv /opt/pkg ${GITHUB_WORKSPACE}/cached-${lname}-${version}-${arch}-opt-pkg
echo "SCHMONZ 5: $(date)"

# avoid unneeded big slow rsync
rm -rf ${GITHUB_WORKSPACE}/pkgsrc
warn "SCHMONZ 6: $(date)"
