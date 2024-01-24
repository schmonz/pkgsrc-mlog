#!/bin/sh

set -e
# work around vmactions bug
mkdir -p $(dirname ${GITHUB_ENV})
# fetch pkgsrc + this package
echo "SCHMONZ 1: $(date)"
git clone --verbose --depth=1 ${GITHUB_SERVER_URL}/NetBSD/pkgsrc
echo "SCHMONZ 2: $(date)"
mkdir pkgsrc/schmonz
mv move-under-pkgsrc-once-you-have-pkgsrc pkgsrc/${GITHUB_REPOSITORY}
# bootstrap pkgsrc
unset PKG_PATH
if [ -d ${GITHUB_WORKSPACE}/cached-${{ matrix.os.lname }}-${{ matrix.os.version }}-${{ matrix.os.arch }}-opt-pkg ]; then
mkdir -p /opt
mv ${GITHUB_WORKSPACE}/cached-${{ matrix.os.lname }}-${{ matrix.os.version }}-${{ matrix.os.arch }}-opt-pkg /opt/pkg
else
cd pkgsrc/bootstrap
./bootstrap --prefix /opt/pkg
./cleanup
cd ../..
fi
echo "SCHMONZ 3: $(date)"
# build this package
PATH=/opt/pkg/sbin:/opt/pkg/bin:${PATH}
cd pkgsrc/${GITHUB_REPOSITORY}
bmake package
echo "SCHMONZ 4: $(date)"
# gather up artifacts
release_version=$(bmake show-var VARNAME=PKGVERSION)
echo "release_version=${release_version}" >> "${GITHUB_ENV}"
mkdir ${GITHUB_WORKSPACE}/release-contents
mv $(bmake show-var VARNAME=PKGFILE) ${GITHUB_WORKSPACE}/release-contents
cd ${GITHUB_WORKSPACE}/release-contents
for i in *.tgz; do mv $i vmactions-${{ matrix.os.lname }}-${{ matrix.os.version }}-${{ matrix.os.arch }}-$i; done
release_asset=$(echo *.tgz)
echo "release_asset=${GITHUB_WORKSPACE}/release-contents/${release_asset}" >> "${GITHUB_ENV}"
# put bootstrap somewhere cacheable
mv /opt/pkg ${GITHUB_WORKSPACE}/cached-${{ matrix.os.lname }}-${{ matrix.os.version }}-${{ matrix.os.arch }}-opt-pkg
echo "SCHMONZ 5: $(date)"
# avoid unneeded big slow rsync
rm -rf ${GITHUB_WORKSPACE}/pkgsrc
echo "SCHMONZ 6: $(date)"
