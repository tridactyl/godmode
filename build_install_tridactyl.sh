#!/bin/sh

set -e 

cd ~/projects/tridactyl

scripts/sign nosignstable

sudo install -Dm644 web-ext-artifacts/tridactyl*xpi /usr/lib/firefox-developer-edition/browser/extensions/tridactyl.vim@cmcaine.co.uk.xpi
