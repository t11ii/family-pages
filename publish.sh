#!/usr/bin/env bash
# Usage: ./publish.sh <file.html> [category] [new-name.html]
# Copies the file into pages/<category>/, commits, pushes, and prints its URL.
set -euo pipefail
cd "$(dirname "$0")"

src="${1:?usage: ./publish.sh <file.html> [category] [new-name.html]}"
category="${2:-misc}"
name="${3:-$(basename "$src")}"
# Spaces and odd characters make ugly URLs; keep names URL-safe.
name="$(echo "$name" | tr ' ' '-' | tr -cd 'A-Za-z0-9._-')"
[[ "$name" == *.html ]] || name="$name.html"

mkdir -p "pages/$category"
dest="pages/$category/$name"
cp "$src" "$dest"

git add "$dest"
if git diff --cached --quiet; then
  echo "No changes to publish (file is identical)."
else
  git commit -q -m "Publish $category/$name"
  git push -q
fi

remote="$(git remote get-url origin)"
repo_path="$(echo "$remote" | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
user="${repo_path%%/*}"
repo="${repo_path#*/}"
if [[ "$repo" == "$user.github.io" ]]; then base="https://$user.github.io"; else base="https://$user.github.io/$repo"; fi

echo "Published! Live in about a minute at:"
echo "  $base/$category/$name"
echo "Index: $base/"
