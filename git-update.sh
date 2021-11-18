#!/bin/bash

echo 'git-update.sh' > .gitignore
echo 'config.json' >> .gitignore
echo '*.json' >> .gitignore

rm -fr .git
git init
git remote add origin https://github.com/dream-hunter/bittrex-bot.git
git fetch origin
git checkout origin/main -ft
