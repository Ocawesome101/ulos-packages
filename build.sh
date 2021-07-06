#!/bin/bash

set -e

repo=$1

if [ -z $repo ]; then
  repo=main
fi

path=src/$repo/

export PREPROCESSOR="$PWD/proc.lua"

mkdir -p $repo/pkg/

printf "{packages={" > $repo/packages.list

for f in $(ls $path); do
  printf "Build package: $f\n"
  if [ -e "$path/$f/setup" ]; then
    opwd=$PWD
    cd $path/$f
    bash setup
    cd $opwd
  fi
  printf "$f={" >> $repo/packages.list
  printf "$(cat $path/$f/info | lua -e "print((io.read('a'):gsub('\n', ',')))")mtar=\"pkg/$f.mtar\"" >> $repo/packages.list $f
  printf "}," >> $repo/packages.list
  find $path/$f/files -type f | ./mtar.lua "$path/$f/files/" > $repo/pkg/$f.mtar
done

printf "}}" >> $repo/packages.list
