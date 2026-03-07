#!/bin/sh

cd workingdir/raw
zip -qr9XD /tmp/newomni.ja .
cp /usr/lib/firefox-developer-edition/omni.ja{,.bak}
cp /tmp/newomni.ja /usr/lib/firefox-developer-edition/omni.ja

echo "Omni.ja packed and installed"
