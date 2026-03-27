#!/bin/bash

# --- 1. Fetch Laragear Packages via GitHub API ---
echo "Checking for available Laragear packages..."
REPOS_JSON=$(curl -s "https://api.github.com/orgs/Laragear/repos?per_page=100")

if command -v jq &> /dev/null; then
    PACKAGES=$(echo "$REPOS_JSON" | jq -r '.[] | select(.archived == false) | .name')
else
    # Improved fallback: finds name, checks if following archived is false
    PACKAGES=$(echo "$REPOS_JSON" | grep -B 1 '"archived": false' | grep '"name":' | sed -E 's/.*"name": "([^"]+)".*/\1/')
fi

if [ -z "$PACKAGES" ]; then
    echo "Error: Could not fetch packages from Laragear GitHub."
    exit 1
fi

echo "Select a Laragear package for the reproduction:"
PS3="Enter number: "
# IMPORTANT: Connect stdin to the terminal for the select menu
select PACKAGE_NAME in $PACKAGES; do
    if [ -n "$PACKAGE_NAME" ]; then break; else echo "Invalid selection."; fi
done < /dev/tty

COMPOSER_PACKAGE="laragear/$(echo "$PACKAGE_NAME" | tr '[:upper:]' '[:lower:]')"

# --- 2. Determine Directory ---
REPO_NAME="${PACKAGE_NAME}-issue"
DEFAULT_DIR="$HOME/projects/$REPO_NAME"

# IMPORTANT: Connect stdin to the terminal for the read prompt
echo -n "Where should the project be created? [$DEFAULT_DIR]: "
read -r PROJECT_DIR < /dev/tty
PROJECT_DIR=${PROJECT_DIR:-$DEFAULT_DIR}

# Resolve absolute path in case user used ~/
PROJECT_DIR="${PROJECT_DIR/#\~/$HOME}"
mkdir -p "$PROJECT_DIR"
PARENT_DIR=$(dirname "$PROJECT_DIR")
BASE_NAME=$(basename "$PROJECT_DIR")

# --- 3. Determine Execution Method ---
COMPOSER_CMD=""

if command -v composer &> /dev/null; then
    COMPOSER_CMD="composer"
elif command -v php &> /dev/null; then
    echo "Downloading temporary composer..."
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/tmp --filename=composer.phar
    COMPOSER_CMD="php /tmp/composer.phar"
elif command -v docker &> /dev/null; then
    COMPOSER_CMD="docker run --rm -it -v $PARENT_DIR:/app -w /app composer"
elif command -v podman &> /dev/null; then
    COMPOSER_CMD="podman run --rm -it -v $PARENT_DIR:/app -w /app composer"
fi

# --- 4. Execute Project Creation ---
if [ -n "$COMPOSER_CMD" ]; then
    echo "Creating Laravel project: $BASE_NAME..."
    
    # We execute from the parent dir to ensure create-project works with the folder name
    cd "$PARENT_DIR" || exit
    $COMPOSER_CMD create-project laravel/laravel "$BASE_NAME"
    
    cd "$PROJECT_DIR" || exit
    echo "Requiring laragear/$PACKAGE_NAME..."

    if [[ $COMPOSER_CMD == *"docker"* || $COMPOSER_CMD == *"podman"* ]]; then
        # Inside the container, we are already in /app (the project dir)
        ${COMPOSER_CMD%composer} composer require "$COMPOSER_PACKAGE"
    else
        $COMPOSER_CMD require "$COMPOSER_PACKAGE"
    fi
else
    echo "No suitable environment found. Install Composer, PHP, or Docker."
    exit 1
fi

# --- 5. Create publish.sh ---
# We use 'EOF' to ensure $ variables are not evaluated until publish.sh is run.
cat <<'EOF' > "publish.sh"
#!/bin/bash
REPO_NAME=$(basename "$(pwd)")
GITHUB_USER=$(git config user.name)
DEFAULT_REMOTE="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"

if [ ! -d ".git" ]; then
    git init
    git add .
    git commit -m "Initial reproduction state"
fi

# 1. Try GitHub CLI
if command -v gh &> /dev/null; then
    read -p "Do you want to create a repository '$REPO_NAME' on GitHub? (y/n): " confirm
    if [[ $confirm == [yY] ]]; then
        gh repo create "$REPO_NAME" --public --source=. --push
        echo "Successfully published via gh!"
        exit 0
    fi
fi

# 2. Manual Fallback
read -p "Create the repository manually on GitHub? (y/n): " manual_confirm
if [[ $manual_confirm == [yY] ]]; then
    echo "Go to: https://github.com/new and create '$REPO_NAME'"
    echo "Press [ENTER] once created..."
    read -r
    
    read -p "Enter remote URL [$DEFAULT_REMOTE]: " REMOTE_URL
    REMOTE_URL=${REMOTE_URL:-$DEFAULT_REMOTE}
    
    git remote add origin "$REMOTE_URL"
    git branch -M main
    git push -u origin main
else
    echo "Manual commands:"
    echo "  git remote add origin <url>"
    echo "  git push -u origin main"
fi
EOF

chmod +x "publish.sh"

echo "---"
echo "Success! Project created at $PROJECT_DIR"
echo "To publish, run: cd $PROJECT_DIR && ./publish.sh"
