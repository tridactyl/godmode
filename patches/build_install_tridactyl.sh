#!/bin/sh

set -e 

cd ~/projects/tridactyl

scripts/sign nosignstable

install -Dm644 web-ext-artifacts/tridactyl*xpi /usr/lib/firefox/browser/extensions/tridactyl.vim@cmcaine.co.uk.xpi
