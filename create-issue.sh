#!/bin/bash

# --- 1. Fetch Laragear Packages via GitHub API ---
echo "Checking for available Laragear packages..."
REPOS_JSON=$(curl -s "https://api.github.com/orgs/Laragear/repos?per_page=100")

# Filter out archived repos and extract names
PACKAGES=$(echo "$REPOS_JSON" | grep -E '"archived": false|"name":' | \
    awk '/"name":/ {name=$2} /"archived": false/ {print name}' | \
    tr -d '",')

if [ -z "$PACKAGES" ]; then
    echo "Error: Could not fetch packages from Laragear GitHub."
    exit 1
fi

echo "Select a Laragear package for the reproduction:"
select PACKAGE_NAME in $PACKAGES; do
    if [ -n "$PACKAGE_NAME" ]; then
        break
    else
        echo "Invalid selection."
    fi
done

# --- 2. Determine Directory ---
REPO_NAME="${PACKAGE_NAME}-issue"
DEFAULT_DIR="$HOME/projects/$REPO_NAME"
read -p "Where should the project be created? [$DEFAULT_DIR]: " PROJECT_DIR
PROJECT_DIR=${PROJECT_DIR:-$DEFAULT_DIR}

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
    echo "Creating Laravel project and requiring Laragear/$PACKAGE_NAME..."

    $COMPOSER_CMD create-project laravel/laravel "$BASE_NAME"
    cd "$PROJECT_DIR" || exit

    # Re-run composer within the new folder to add the Laragear package
    if [[ $COMPOSER_CMD == *"docker"* || $COMPOSER_CMD == *"podman"* ]]; then
        ${COMPOSER_CMD%composer} composer require "laragear/$PACKAGE_NAME"
    else
        $COMPOSER_CMD require "laragear/$PACKAGE_NAME"
    fi
else
    echo "--------------------------------------------------------"
    echo "No suitable environment found. Run manually:"
    echo "composer create-project laravel/laravel $PROJECT_DIR"
    echo "cd $PROJECT_DIR && composer require laragear/$PACKAGE_NAME"
    echo "--------------------------------------------------------"
    exit 1
fi

# --- 5. Create publish.sh ---
cat <<EOF > "$PROJECT_DIR/publish.sh"
#!/bin/bash

REPO_NAME="$REPO_NAME"
GITHUB_USER=\$(git config user.name)
DEFAULT_REMOTE="https://github./\$GITHUB_USER/\$REPO_NAME.git"

echo "Do you want to create a repository in GitHub for this issue?"
read -p "(y/n): " CONFIRM

if [[ \$CONFIRM =~ ^[Yy]$ ]]; then
    echo "--------------------------------------------------------"
    echo "Please go to https://github.com/new and create: \$REPO_NAME"
    echo "Waiting... Press [Enter] once the repository is created."
    read -s

    read -p "Enter remote URL [\$DEFAULT_REMOTE]: " REMOTE_URL
    REMOTE_URL=\${REMOTE_URL:-\$DEFAULT_REMOTE}

    git init
    git add .
    git commit -m "Initial reproduction state for laragear/\$PACKAGE_NAME"
    git branch -M main
    git remote add origin "\$REMOTE_URL"

    echo "Pushing to GitHub..."
    git push -u origin main
    echo "Done!"
else
    echo "--------------------------------------------------------"
    echo "Automatic upload cancelled. To do it manually, run:"
    echo "  git init"
    echo "  git add ."
    echo "  git commit -m \"Initial commit\""
    echo "  git remote add origin <your-repo-url>"
    echo "  git push -u origin main"
    echo "--------------------------------------------------------"
fi
EOF

chmod +x "$PROJECT_DIR/publish.sh"

echo "---"
echo "Success! Project created at $PROJECT_DIR"
echo "To publish, run: cd $PROJECT_DIR && ./publish.sh"
