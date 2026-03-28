#!/bin/bash

# Regex to validate the type pattern
REGEX="^((Merge (pull request|branch).*)|(Revert .+)|((build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([^[:space:])]+\))?!?: .+))"

MSG=$(cat "$1") # Message content from the commit message file

RED='\033[0;31m'		# Red Text
GREEN='\033[0;32m'	# Green Text
NC='\033[0m'				# No Color / Reset

if ! [[ $MSG =~ $REGEX ]]; then
	echo -e "$RED ❌Commit aborted for not following the Conventional Commit standard.$NC"
	exit 1
else
	echo >&2 -e "$GREEN ✔ Valid commit message.$NC"
fi

