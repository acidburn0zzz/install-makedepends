#!/bin/sh -e
# Copyright 2021 Johannes Marbach
# SPDX-License-Identifier: GPL-3.0-or-later

cache=~/.cache/install-makedepends
install_checkdepends=false
force_aports=
force_pmaports=false

pmaports_remote_default=https://gitlab.com/postmarketOS/pmaports.git
pmaports_checkout_default=$cache/pmaports

PMAPORTS_REMOTE="${PMAPORTS_REMOTE:-$pmaports_remote_default}"
PMAPORTS_CHECKOUT="${PMAPORTS_CHECKOUT:-}"

usage() {
	cat <<-EOM
		usage: install-makedepends [OPTION]... [PKGNAME]...

		Install build (and optionally test) dependencies for the specified PKGNAMEs.

		To determine the makedepends, the respective APKBUILDs are fetched.

		For packages from aports, the APKBUILDs are fetched directly from Alpine's
		GitLab.

		For packages from pmaports, a local git checkout is used. To override the
		pmaports remote, set PMAPORTS_REMOTE. To override the local checkout location,
		set PMAPORTS_CHECKOUT. The default values are:

		PMAPORTS_REMOTE=$pmaports_remote_default
		PMAPORTS_CHECKOUT=$pmaports_checkout_default

		Note that when overriding the pmaports checkout location, the checkout is used
		as is without pulling.

		By default, sudo is used to perform the installation step. To use a different
		program, set the SUDO environment variable.

		Options:
			-a REPO  Look up APKBUILDs in aports, don't try to infer the source. The
			         respective Alpine repository (e.g. testing) needs to be specified.
			-c       Also install checkdepends if available
			-h       Show this message and exit
			-p       Look up APKBUILDs in pmaports, don't try to infer the source
		EOM
	exit 0
}

die() {
	echo "[31mError: $1[0m" >&2
	exit 1
}

while getopts ":a:chp" opt; do
	case $opt in
		'a') force_aports=$OPTARG;;
		'c') install_checkdepends=true;;
		'h') usage;;
		'p') force_pmaports=true;;
		'?') die "Unrecognized option: $OPTARG";;
	esac
done
shift $((OPTIND - 1))

if [ $# -eq 0 ]; then
	usage
	exit 1
fi

mkdir -p "$cache"

for package in "$@"; do
	echo "[32m*** Installing makedepends for $package ***[0m"

	repo=$(apk policy "$package" | tail -n1 | tr -d "[:space:]")
	if [ -z "$repo" ]; then
		die "No package named $package"
	fi
	if [ "$(expr "$repo" : '.*://.*$')" -eq 0 ]; then
		die "Could not determine repository for $package"
	fi

	if [ -n "$force_aports" ]; then
		source=aports
		repo_name=$force_aports
	elif $force_pmaports || [ "$(expr "$repo" : '.*postmarketos.*$')" -ne 0 ]; then
		source=pmaports
	else
		source=aports
		repo_name=${repo##*/}
	fi

	case $source in
		aports)
			echo "Using aports ($repo_name)"
			url=https://gitlab.alpinelinux.org/alpine/aports/-/raw/master/$repo_name/$package/APKBUILD
			echo "Downloading $url"
			cd "$cache"
			rm -f APKBUILD
			if ! wget -qO APKBUILD "$url"; then
				die "Failed to download APKBUILD for $package"
			fi
			;;
		pmaports)
			echo "Using pmaports"
			if [ -z "$PMAPORTS_CHECKOUT" ]; then
				PMAPORTS_CHECKOUT=$pmaports_checkout_default
				if ! [ -d "$PMAPORTS_CHECKOUT" ]; then
					echo "Cloning $PMAPORTS_REMOTE"
					mkdir -p "$(dirname "$PMAPORTS_CHECKOUT")"
					git clone --depth=1 "$PMAPORTS_REMOTE" "$PMAPORTS_CHECKOUT"
				else
					echo "Pulling pmaports checkout in $PMAPORTS_CHECKOUT"
					git -C "$PMAPORTS_CHECKOUT" pull --rebase
				fi
			else
				echo "Using existing pmaports checkout in $PMAPORTS_CHECKOUT"
			fi
			apkbuild=$(find "$PMAPORTS_CHECKOUT" -type f -path "*/$package/APKBUILD" | head -n1)
			if [ -z "$apkbuild" ]; then
				die "Could not find APKBUILD for $package in pmaports checkout"
			fi
			cd "$(dirname "$apkbuild")"
			;;
	esac

	(
		# shellcheck disable=SC1091
		. APKBUILD
		# shellcheck disable=SC2154
		deps=$makedepends
		if $install_checkdepends; then
			# shellcheck disable=SC2154
			deps="$deps $checkdepends"
		fi
		vpkg=.makedepends-$package
		echo "Installing dependencies under virtual package $vpkg"
		# shellcheck disable=SC2086
		${SUDO=sudo} apk add --virtual "$vpkg" $deps
	)
done
