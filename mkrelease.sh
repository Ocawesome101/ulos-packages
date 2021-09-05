#!/bin/bash
# mkrelease - create a ULOS release image

SRCDIR=$PWD/src
OUTDIR=/tmp/ulos-build
PKGLIST=$OUTDIR/etc/upm/installed.list

wget https://raw.github.com/ocawesome101/oc-ulos/master/utils/env.sh -O /tmp/env.sh
source /tmp/env.sh

addpkg () {
	cp -rv $SRCDIR/$1/files/* $OUTDIR
	find $SRCDIR/$1/files -type f | lua genpkent.lua $1 $SRCDIR/$1/files >> $PKGLIST
}

rm -rf $OUTDIR
mkdir -p $OUTDIR
rm $PKGLIST
mkdir -p $(dirname $PKGLIST)

echo "{" >> $PKGLIST
for package in $(echo cldr cynosure usysd coreutils corelibs gpuproxy installer upm); do
	echo $package
	addpkg main/$package #1>/dev/null
done
echo "}" >> $PKGLIST

wget https://raw.github.com/ocawesome101/ulos-external/master/motd.txt -cO $OUTDIR/etc/motd.txt

cat /tmp/external/os-release
find $OUTDIR -type f | ./mtar.lua $OUTDIR > release.mtar
cat /tmp/cynosure/mtarldr.lua release.mtar /tmp/cynosure/mtarldr_2.lua > release.lua

echo "MAKE GUI IMAGE"

addpkg extra/uwm
echo "uwm-login@tty0" > $OUTDIR/etc/usysd/autostart

find $OUTDIR -type f | ./mtar.lua $OUTDIR > release.mtar
cat /tmp/cynosure/mtarldr.lua release.mtar /tmp/cynosure/mtarldr_2.lua > release_uwm.lua
rm release.mtar
