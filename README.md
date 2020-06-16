# blacken-scripts

Scripts to help in applying black to a Python repo and its open PRs

## Preparing for Black

1. Run `./add-pre-black-labels.sh YOUR_ORG/YOUR_REPO YOUR_BASE_BRANCH` to add a
   `pre-black-conflict` to all open PRs with merge conflicts before black.

2. Resolve conflicts and re-run.
