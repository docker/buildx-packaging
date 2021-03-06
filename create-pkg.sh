#!/usr/bin/env bash

# Copyright 2022 buildx-packaging authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -eu -o pipefail

: "${NFPM_CONFIG=}"
: "${OUTPUT=.}"
: "${BUILDX_SRC=}"

: "${BUILDX_VERSION=}"
: "${PKG_TYPES=}"
: "${PKG_APK_RELEASES=}"
: "${PKG_DEB_RELEASES=}"
: "${PKG_RPM_RELEASES=}"
: "${PKG_VENDOR=}"
: "${PKG_PACKAGER=}"

if ! type nfpm > /dev/null 2>&1; then
  echo >&2 "ERROR: nfpm is required"
  exit 1
fi
if ! type xx-info > /dev/null 2>&1; then
  echo >&2 "ERROR: xx-info is required"
  exit 1
fi
if [ ! -d "$BUILDX_SRC/.git" ]; then
  echo >&2 "ERROR: BUILDX_SRC is not a valid directory"
  exit 1
fi

if [[ $BUILDX_VERSION =~ ^[a-f0-9]{7}$ ]]; then
  BUILDX_VERSION="v0.0.0+${BUILDX_VERSION}"
fi

workdir=$(mktemp -d -t buildx-pkg.XXXXXXXXXX)
trap 'set -x ; rm -rf -- "$workdir"' EXIT
mkdir -p "$workdir/docker-buildx-plugin"

PKG_OUTPUT="${OUTPUT}/$(xx-info os)/$(xx-info arch)"
if [ -n "$(xx-info variant)" ]; then
  PKG_OUTPUT="${PKG_OUTPUT}/$(xx-info variant)"
fi
mkdir -p "${PKG_OUTPUT}"

os=$(xx-info os)
arch=$(xx-info march)
for pkgtype in ${PKG_TYPES//,/ }; do
  releases=0
  if [ $pkgtype = "static" ]; then
    echo "using static packager"
    (
      set -x
      cp ${BUILDX_SRC}/LICENSE ${BUILDX_SRC}/README.md "$workdir/docker-buildx-plugin/"
    )
    if [ "$os" = "windows" ]; then
      (
        cp /usr/bin/buildx "$workdir/docker-buildx-plugin/docker-buildx.exe"
        cd "$workdir"
        zip -r "$PKG_OUTPUT/docker-buildx-plugin_${BUILDX_VERSION#v}.zip" docker-buildx-plugin
      )
    else
      (
        set -x
        cp /usr/bin/buildx "$workdir/docker-buildx-plugin/docker-buildx"
        tar -czf "${PKG_OUTPUT}/docker-buildx-plugin_${BUILDX_VERSION#v}.tgz" -C "$workdir" docker-buildx-plugin
      )
    fi
    continue
  fi
  if [ "$os" != "linux" ]; then
    continue
  fi
  case $pkgtype in
    apk)
      arch=$(xx-info alpine-arch)
      releases=$PKG_APK_RELEASES
      ;;
    deb)
      arch=$(xx-info debian-arch)
      releases=$PKG_DEB_RELEASES
      ;;
    rpm)
      arch=$(xx-info rhel-arch)
      releases=$PKG_RPM_RELEASES
      ;;
  esac
  for release in ${releases//,/ }; do
    (set -x ; ARCH="${arch}" VERSION="${BUILDX_VERSION}" RELEASE="$release" VENDOR="${PKG_VENDOR}" PACKAGER="${PKG_PACKAGER}" nfpm package --config $NFPM_CONFIG --packager $pkgtype --target "$PKG_OUTPUT")
  done
done
