#!/bin/sh

cd workingdir/raw
zip -qr9XD /tmp/newomni.ja
cp /usr/lib/firefox/omni.ja{,.bak}
cp /tmp/newomni.ja /usr/lib/firefox/omni.ja

echo "Omni.ja packed and installed"
