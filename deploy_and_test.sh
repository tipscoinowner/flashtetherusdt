#!/usr/bin/env bash
set -euo pipefail

# -------------------------
# CONFIGURE BEFORE RUNNING
# -------------------------
# Replace these placeholders or export them in your shell before running:
#   GITHUB_USER_OR_ORG  -> GitHub kullanıcı veya organizasyon adı
#   GITHUB_REPO         -> Repo adı (ör: flashtether-trc20)
#   PRIVATE_KEY         -> Deployer account private key (keep secret)
#   INITIAL_OWNER       -> Multisig owner address (T...)
#
# You can export them in the shell:
# export GITHUB_USER_OR_ORG="youruser"
# export GITHUB_REPO="flashtether-trc20"
# export PRIVATE_KEY="your_private_key_here"
# export INITIAL_OWNER="TMCUDVJ1r63QH7dvccpdUXgkEEDFRDd8wP"
#
# Or edit the variables below directly (not recommended for PRIVATE_KEY).

GITHUB_USER_OR_ORG="${GITHUB_USER_OR_ORG:-YOUR_GITHUB_USER_OR_ORG}"
GITHUB_REPO="${GITHUB_REPO:-flashtether-trc20}"
PRIVATE_KEY="${PRIVATE_KEY:-}"
INITIAL_OWNER="${INITIAL_OWNER:-TMCUDVJ1r63QH7dvccpdUXgkEEDFRDd8wP}"

# -------------------------
# CHECK PREREQUISITES
# -------------------------
command -v git >/dev/null 2>&1 || { echo "git not found. Install git and retry."; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "gh CLI not found. Install GitHub CLI and retry."; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node not found. Install Node.js and retry."; exit 1; }
command -v npx >/dev/null 2>&1 || { echo "npx not found. Ensure npm is installed."; exit 1; }
command -v tronbox >/dev/null 2>&1 || echo "Warning: tronbox not found globally. Using npx tronbox where needed."

# -------------------------
# SAFETY CHECKS
# -------------------------
if [ -z "$PRIVATE_KEY" ]; then
  echo "Error: PRIVATE_KEY is empty. Export PRIVATE_KEY in your shell before running."
  exit 1
fi

if [ "$GITHUB_USER_OR_ORG" = "YOUR_GITHUB_USER_OR_ORG" ]; then
  echo "Warning: GITHUB_USER_OR_ORG not set. Edit the script or export GITHUB_USER_OR_ORG."
  echo "Continuing but you will need to confirm repo creation interactively."
fi

# -------------------------
# INITIALIZE GIT IF NEEDED
# -------------------------
if [ ! -d .git ]; then
  echo "Initializing git repository..."
  git init
  git checkout -b main || git checkout -b master
fi

# Create sensible .gitignore if missing
if [ ! -f .gitignore ]; then
  cat > .gitignore <<'GITIGNORE'
node_modules/
.env
.DS_Store
build/
coverage/
GITIGNORE
  git add .gitignore
fi

# Stage and commit
echo "Staging files and creating commit..."
git add .
if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "feat(test): add short-lock test contract and automated lock-test script" || true
fi

# -------------------------
# CREATE GITHUB REPO IF NEEDED
# -------------------------
REPO_EXISTS=false
if gh repo view "${GITHUB_USER_OR_ORG}/${GITHUB_REPO}" >/dev/null 2>&1; then
  REPO_EXISTS=true
  echo "GitHub repo ${GITHUB_USER_OR_ORG}/${GITHUB_REPO} already exists."
else
  echo "Creating GitHub repo ${GITHUB_USER_OR_ORG}/${GITHUB_REPO}..."
  if gh repo create "${GITHUB_USER_OR_ORG}/${GITHUB_REPO}" --public --source=. --remote=origin --push >/dev/null 2>&1; then
    echo "Repository created and pushed."
  else
    echo "gh repo create failed non-interactively. Attempting interactive creation..."
    gh repo create "${GITHUB_USER_OR_ORG}/${GITHUB_REPO}" --public --source=. --remote=origin --push
  fi
fi

# If remote not set, set it
if ! git remote get-url origin >/dev/null 2>&1; then
  git remote add origin "git@github.com:${GITHUB_USER_OR_ORG}/${GITHUB_REPO}.git"
fi

# Push commits and tags
echo "Pushing commits to origin..."
git push -u origin main || git push -u origin master || true

# -------------------------
# SET GITHUB SECRETS
# -------------------------
echo "Setting GitHub Actions secrets: INITIAL_OWNER and PRIVATE_KEY"
echo -n "$INITIAL_OWNER" | gh secret set INITIAL_OWNER --body - >/dev/null 2>&1 || gh secret set INITIAL_OWNER --body "$INITIAL_OWNER"
echo -n "$PRIVATE_KEY" | gh secret set PRIVATE_KEY --body - >/dev/null 2>&1 || gh secret set PRIVATE_KEY --body "$PRIVATE_KEY"
echo "Secrets set."

# -------------------------
# COMPILE CONTRACTS
# -------------------------
echo "Installing npm dependencies and compiling contracts..."
npm ci
npx tronbox compile

# -------------------------
# DEPLOY TO SHASTA (TESTNET)
# -------------------------
echo "Deploying to Shasta testnet..."
export INITIAL_OWNER="$INITIAL_OWNER"
export PRIVATE_KEY="$PRIVATE_KEY"
npx tronbox migrate --network shasta --reset
echo "Shasta deploy finished. Check output above for contract addresses."

# -------------------------
# RUN AUTOMATED LOCK TEST
# -------------------------
echo "Running automated lock test script test/lock-test.js"
if [ ! -f test/lock-test.js ]; then
  echo "Error: test/lock-test.js not found in repo. Aborting test run."
  exit 1
fi
PRIVATE_KEY="$PRIVATE_KEY" node test/lock-test.js
echo "Automated lock test finished."

# -------------------------
# CLEANUP AND NEXT STEPS
# -------------------------
echo "All done."
echo "If tests passed, revert test-only changes before mainnet deploy:"
echo "- Restore MIN_LOCK_SECONDS to 120 days in production contract"
echo "- Remove test-only migration or keep it on a separate branch"
echo "- Tag release and configure production environment with required reviewers in GitHub"
echo ""
echo "To deploy to mainnet via GitHub Actions, ensure production environment exists and secrets are set, then run the Deploy to Mainnet workflow in Actions UI."

exit 0
