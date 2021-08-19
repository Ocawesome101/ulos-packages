#!/bin/bash

set -e

repo=$1

if [ -z $repo ]; then
  repo=main
fi

path=src/$repo/

ULOSREL="1.4.2"

export OS="ULOS $(date +%y.%m)-$ULOSREL"
export PREPROCESSOR="$PWD/proc.lua"

rm -rf $repo/pkg && mkdir -p $repo/pkg/

printf "{packages={" > $repo/packages.list

files=$(ls $path)

for f in $files; do
  printf "Build package: $f\n"
  if [ -e "$path/$f/setup" ]; then
    opwd=$PWD
    cd $path/$f
    bash setup
    cd $opwd
  fi
  printf "[\"$f\"]={" >> $repo/packages.list
  printf "$(cat $path/$f/info | lua -e "print((io.read('a'):gsub('\n', ',')))")mtar=\"pkg/$f.mtar\"" >> $repo/packages.list $f
  find $path/$f/files -type f | ./mtar.lua "$path/$f/files/" > $repo/pkg/$f.mtar
  printf ",size=%s}," $(stat -c %s $repo/pkg/$f.mtar) >> $repo/packages.list
done

printf "}}" >> $repo/packages.list
