#!/bin/bash
set -eu
set -o pipefail
USAGE="Reformat all open PRs with Black, adding a comment with instructions if this fails.

Requires hub and ghi: brew install hub ghi
Login with hub: hub ci-status
Login with ghi: ghi config --auth [username]

Usage: $0 REPO PRE_BLACK_COMMIT BLACKENED_COMMIT BASE_BRANCH

REPO is the GH org and repo, e.g. GoodRx/test-repo
PRE_BLACK_COMMIT is the last commit to master/develop that is not formatted with Black
BLACKEND_COMMIT is the commit that applies Black to the codebase
BASE_BRANCH is the main branch of the repo, e.g. 'master' or 'develop'"

if [ "$#" -ne 4 ]; then
    echo "${USAGE}"
    exit 1
fi

REPO=$1
PRE_BLACK_COMMIT="${2}"
BLACKENED_COMMIT="${3}"
BASE_BRANCH="${4}"

# First ensure dependencies are installed
hash hub 2>/dev/null || (echo "Install hub: brew install hub" >&2; exit 1)
hash ghi 2>/dev/null || (echo "Install ghi: brew install ghi" >&2; exit 1)

# Get the directory of this script
SCRIPT_DIR=$(python -s -c "import os.path; print(os.path.dirname(os.path.abspath('${BASH_SOURCE[0]}')))")

# Add the 'pre-black-conflict' label to PRs were merge conflicts that pre-date
# black
"${SCRIPT_DIR}"/add-pre-black-labels.sh "${REPO}" "${PRE_BLACK_COMMIT}"

REPO_DIR=$(mktemp -d)
trap 'rm -rf "${REPO_DIR}"' EXIT

hub clone "${REPO}" "${REPO_DIR}" && cd "${REPO_DIR}"

LABEL="black-conflict"
ghi label "${LABEL}" --color black

FAILURE_COMMENT=$(cat <<EOF
**WARNING:** Your pull-request could not be automatically updated with [Black](https://black.rtfd.io)! This comment contains step-by-step instructions to resolve conflicts and update your pull request with Black. If any of these steps fail, or if you need help, join **#python-black-help** on Slack and share your PR.

To update your pull request manually, follow these steps:

1. Checkout your branch.

2. Merge the latest pre-Black commit into your branch, and resolve any conflicts, if necessary:

   \`\`\`sh
   git merge ${PRE_BLACK_COMMIT}
   \`\`\`

3. Merge the first commit using Black into your branch, but do not resolve any conflicts yet:

   \`\`\`sh
   git merge ${BLACKENED_COMMIT}
   \`\`\`

4. Run the following commands to resolve all Python merge conflicts by running Black on your PR:

   \`\`\`sh
   git ls-files -- "*.py" | xargs git checkout --ours --
   tox -e format
   git ls-files -- "*.py" | xargs git add --
   \`\`\`

5. Check for additional merge conflicts:

   \`\`\`sh
   git status
   \`\`\`

   If the output shows any additional "Unmerged paths", then your PR has non-Python conflicts to resolve. Join us on Slack for assistance.

6. If there were no additional "Unmerged paths", commit and push your merge:

   \`\`\`sh
   git commit
   git push
   \`\`\`

7. Congratulations, you survived the Black migration! :tada:

**NOTE:** The diff for your PR will be very messy at this point. Merge and push the latest \`${BASE_BRANCH}\` into your PR and it will get back to normal.
EOF
)

BASE_BRANCH_FAILURE_COMMENT=$(cat <<EOF
**WARNING:** Your pull-request has a merge conflict with ${BASE_BRANCH}!

Right now, the diff looks very confusing and messy because of the migration to Black. To fix this, checkout your PR, pull the latest changes, and merge the latest ${BASE_BRANCH}, resolving any conflicts.

If you have any questions, join **#python-black-help** on Slack and share your PR.
EOF
)

# Update all open PRs by applying Black, leaving a comment and adding a GitHub
# label if the update failed.
for pr in $(hub pr list --format='%I%n'); do
   PR_BRANCH="pr/${pr}"
   hub pr checkout "${pr}" "${PR_BRANCH}"

   if ghi label --list "${pr}" | grep -q '\bpre-black-conflict\b'; then
      # Add a comment with instructions on updating this PR for Black
      ghi comment -m "${FAILURE_COMMENT}" "${pr}"
      echo "UNABLE TO BLACKEN ${pr}: conflicts with ${PRE_BLACK_COMMIT}"
      continue
   fi

   # Merge PRE_BLACK_COMMIT into the PR
   git merge -q --no-edit "${PRE_BLACK_COMMIT}"

   # Merge BLACKENED_COMMIT into the PR
   if ! git merge -q --no-edit "${BLACKENED_COMMIT}"; then
      # Resolve Python conflicts by checking out all Python files as of this
      # branch and then running Black on all of them
      git ls-files -- "*.py" | xargs git checkout --ours --
      tox -e format
      git ls-files -- "*.py" | xargs git add --

      if ! git commit -F .git/MERGE_MSG; then
         echo "UNABLE TO BLACKEN ${pr}: conflicts with ${BLACKENED_COMMIT}"
         # Add a comment with instructions on updating this PR for Black
         ghi comment -m "${FAILURE_COMMENT}" "${pr}"
         # Add a 'black-conflict' label to the PR and abort
         ghi label "${pr}" --add "${LABEL}"
         git merge --abort
         continue
      fi
   fi

   # Remove the 'black-conflict' label if it was present for whatever reason
   if ghi label "${pr}" --list | grep -q "\b${LABEL}\b"; then
      ghi label "${pr}" --delete "${LABEL}"
   fi

   # Push the updated PR
   echo "SUCCESSFULLY BLACKENED ${pr}, pushing!"
   git push

   # Merge the latest BASE_BRANCH into the PR to keep the diff clean
   if ! git merge -q --no-edit "${BASE_BRANCH}"; then
      echo "${BASE_BRANCH} MERGE FAILED FOR ${pr}"
         # Add a comment with instructions on merging BASE_BRANCH
         ghi comment -m "${BASE_BRANCH_FAILURE_COMMENT}" "${pr}"
   else
      echo "SUCCESSFULLY MERGED ${BASE_BRANCH} INTO ${pr}, pushing!"
      git push
   fi
done
