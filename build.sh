#!/bin/bash

set -e

repo=$1

if [ -z $repo ]; then
  repo=main
fi

path=src/$repo/

wget https://raw.github.com/ocawesome101/oc-ulos/master/utils/env.sh -O /tmp/env.sh
source /tmp/env.sh
rm -rf /tmp/ulos && git clone https://github.com/ocawesome101/oc-ulos/ /tmp/ulos

#rm -rf $repo/pkg && \
       mkdir -p $repo/pkg/

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
  if [ -e "$path/$f/info" ]; then
    pkver=$(cat /tmp/ulos/versions/$f)
    printf "[\"$f\"]={" >> $repo/packages.list
    printf "$(cat $path/$f/info | \
        lua -e "print((io.read('a'):gsub('\n', ',')) .. 'version=\"$pkver\",')")mtar=\"pkg/$f-$pkver.mtar\"" >> $repo/packages.list $f
    find $path/$f/files -type f | ./mtar.lua "$path/$f/files/" > $repo/pkg/$f-$pkver.mtar
    printf ",size=%s}," $(stat -c %s $repo/pkg/$f-$pkver.mtar) >> $repo/packages.list
  fi
done

printf "}}" >> $repo/packages.list
