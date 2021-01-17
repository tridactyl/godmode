#!/bin/sh

mkdir -p workingdir/omni
mkdir -p workingdir/raw
cp /usr/lib/firefox/omni.ja workingdir/omni
cd workingdir/raw
unzip -q ../omni/omni.ja

echo "Omni.ja extracted"
