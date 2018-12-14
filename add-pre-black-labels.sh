#!/bin/bash
set -eu
set -o pipefail
USAGE="Add a 'pre-black-conflict' label to all open PRs with merge conflicts.

Requires hub and ghi: brew install hub ghi
Login with hub: hub ci-status
Login with ghi: ghi config --auth [username]

Usage: $0 REPO BASE_BRANCH_OR_COMMIT

REPO is the GH org and repo, e.g. GoodRx/test-repo
BASE_BRANCH_OR_COMMIT is the branch (or commit) PRs should not conflict with, e.g. 'master' or 'develop'"

if [ "$#" -ne 2 ]; then
    echo "${USAGE}"
    exit 1
fi

REPO=$1
BASE="${2}"

# First ensure dependencies are installed
hash hub 2>/dev/null || (echo "Install hub: brew install hub" >&2; exit 1)
hash ghi 2>/dev/null || (echo "Install ghi: brew install ghi" >&2; exit 1)

REPO_DIR=$(mktemp -d)
trap 'rm -rf "${REPO_DIR}"' EXIT

hub clone "${REPO}" "${REPO_DIR}" && cd "${REPO_DIR}"

# Label to track PRs that need updating before we can apply Black
LABEL="pre-black-conflict"
ghi label "${LABEL}" --color gray

for pr in $(hub pr list --format='%I%n'); do
   PR_BRANCH="pr/${pr}"
   hub pr checkout "${pr}" "${PR_BRANCH}"

   # Manage the "pre-black-conflict" label by checking whether the PR can be
   # merged without conflicts
   if ! git merge -q --no-edit "${BASE}"; then
      ghi label "${pr}" --add "${LABEL}"
      git merge --abort
   else
      if ghi label "${pr}" --list | grep -q "\b${LABEL}\b"; then
         ghi label "${pr}" --delete "${LABEL}"
      fi
   fi
done
