#!/bin/bash
# mkrelease - create a ULOS release image

SRCDIR=$PWD/src
OUTDIR=/tmp/ulos-build
PKGLIST=$OUTDIR/etc/upm/installed.list

addpkg () {
	cp -rv $SRCDIR/$1/files/* $OUTDIR
	find $SRCDIR/$1/files -type f | lua genpkent.lua $1 $SRCDIR/$1/files >> $PKGLIST
}

rm -rf $OUTDIR
mkdir -p $OUTDIR
rm $PKGLIST
mkdir -p $(dirname $PKGLIST)

echo "{" >> $PKGLIST
for package in $(echo cldr cynosure refinement coreutils corelibs gpuproxy installer upm); do
	echo $package
	addpkg main/$package #1>/dev/null
done
echo "}" >> $PKGLIST

wget https://raw.github.com/ocawesome101/ulos-external/master/motd.txt -cO $OUTDIR/etc/motd.txt

find $OUTDIR -type f | ./mtar.lua $OUTDIR > release.mtar
cat /tmp/cynosure/mtarldr.lua release.mtar /tmp/cynosure/mtarldr_2.lua > release_noautostart.lua

mkdir -p $OUTDIR/usr/share/installer
cp $OUTDIR/{etc,usr/share/installer}/rf.cfg
wget https://github.com/ocawesome101/oc-ulos/raw/master/inst_config/rf.cfg -O $OUTDIR/etc/rf.cfg
wget https://github.com/ocawesome101/oc-ulos/raw/master/inst_config/startinst.lua -O $OUTDIR/etc/rf/startinst.lua

find $OUTDIR -type f | ./mtar.lua $OUTDIR > release.mtar
cat /tmp/cynosure/mtarldr.lua release.mtar /tmp/cynosure/mtarldr_2.lua > release.lua
rm release.mtar
