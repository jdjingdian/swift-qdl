#!/usr/bin/env bash
set -euo pipefail

# bump-version.sh
# 半自动脚本：根据传入的 version (例如 1.2.3 或 v1.2.3) 或最近的 git tag 设置所有 Info.plist 的
# CFBundleShortVersionString 和 CFBundleVersion（build number 使用 git commit count）。
# 默认不提交到 git；使用 --commit 会把修改提交到仓库，使用 --tag 会创建带注释的 git tag。

usage() {
  cat <<EOF
Usage: $0 [version] [--commit] [--tag]

If version is omitted, the script will try to use the most recent tag matching vMAJOR.MINOR.PATCH.
Options:
  --commit    Commit modified Info.plist files (default: no commit)
  --tag       Create an annotated tag v<version> after commit (requires --commit)
  --no-commit Don't commit even if default behavior changes (explicit)
  -h,--help   Show this help
EOF
}

if [[ "${1-}" == "-h" || "${1-}" == "--help" ]]; then
  usage
  exit 0
fi

POSITIONAL=()
COMMIT=false
CREATE_TAG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)
      COMMIT=true;
      shift;;
    --no-commit)
      COMMIT=false;
      shift;;
    --tag)
      CREATE_TAG=true;
      shift;;
    -*|--*)
      echo "Unknown option $1" >&2; usage; exit 1;;
    *)
      POSITIONAL+=("$1"); shift;;
  esac
done

set -- "${POSITIONAL[@]-}"

# repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
cd "$REPO_ROOT"

# determine version
if [[ ${1-} ]]; then
  VER_CAND=${1}
  # strip leading v if present
  VERSION=${VER_CAND#v}
else
  if git describe --tags --match "v[0-9]*" --abbrev=0 >/dev/null 2>&1; then
    VERSION=$(git describe --tags --match "v[0-9]*" --abbrev=0 | sed 's/^v//')
  else
    VERSION="0.1.0"
  fi
fi

# build number: simple commit count
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || date +%s)

echo "Using version: $VERSION"
echo "Using build number: $BUILD_NUMBER"

PROJECT_PBXPROJ="$(git ls-files | grep -E '\.xcodeproj/project.pbxproj$' | head -n1 || true)"

use_agv=false
if [[ -n "$PROJECT_PBXPROJ" ]]; then
  if grep -q "VERSIONING_SYSTEM = apple-generic" "$PROJECT_PBXPROJ" 2>/dev/null; then
    use_agv=true
  fi
fi

PLISTS=()
while IFS= read -r plist; do
  [[ -z "$plist" ]] && continue
  PLISTS+=("$plist")
done < <(git ls-files -- ':!:Pods/**' | grep -E 'Info.plist$' || true)

if [[ ${#PLISTS[@]} -eq 0 ]]; then
  echo "No Info.plist files found in the repo (searched tracked files)." >&2
  # continue: may still update pbxproj
fi

echo "Detected project.pbxproj: ${PROJECT_PBXPROJ:-<none>}"
echo "agvtool applicable: $use_agv"

if [[ "$use_agv" == "true" && -x "$(command -v agvtool)" ]]; then
  echo "Using agvtool to set marketing version and project version"
  # set marketing version
  agvtool new-marketing-version "$VERSION" >/dev/null
  # set project/current version to BUILD_NUMBER
  agvtool new-version -all "$BUILD_NUMBER" >/dev/null
else
  # fallback: directly update project.pbxproj if present
  if [[ -n "$PROJECT_PBXPROJ" ]]; then
    echo "Updating $PROJECT_PBXPROJ CURRENT_PROJECT_VERSION and MARKETING_VERSION"
    # Update CURRENT_PROJECT_VERSION entries
    # Use sed in-place (compatible with macOS sed)
    # First, make a backup in case sed -i behaves differently
    cp "$PROJECT_PBXPROJ" "$PROJECT_PBXPROJ.bak" || true
    # Replace CURRENT_PROJECT_VERSION = <num>;
    /usr/bin/perl -0777 -pe "s/CURRENT_PROJECT_VERSION = \d+;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/gms" -i "$PROJECT_PBXPROJ"
    # Replace or add MARKETING_VERSION = x.y.z;
    if grep -q "MARKETING_VERSION" "$PROJECT_PBXPROJ" 2>/dev/null; then
      /usr/bin/perl -0777 -pe "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $VERSION;/gms" -i "$PROJECT_PBXPROJ"
    else
      # try to inject MARKETING_VERSION near the end of the first project section - best-effort
      /usr/bin/perl -0777 -pe "s/(\n\s*\);\n\s*\/\* End PBXProject section \*\/)/\n\t	MARKETING_VERSION = $VERSION;\n\1/" -i "$PROJECT_PBXPROJ" || true
    fi
  else
    echo "No project.pbxproj found; skipping project-level update"
  fi
fi

MODIFIED=()
if [[ ${#PLISTS[@]} -gt 0 ]]; then
  for PLIST in "${PLISTS[@]}"; do
    echo "Updating $PLIST"
  # set CFBundleShortVersionString
  if /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
  else
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST"
  fi

  # set CFBundleVersion
  if /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
  else
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$PLIST"
  fi

    MODIFIED+=("$PLIST")
  done

  echo "Updated ${#MODIFIED[@]} Info.plist file(s):"
  for f in "${MODIFIED[@]}"; do echo "  - $f"; done
else
  echo "No Info.plist files were updated (none found)."
fi

if [[ "$COMMIT" == "true" ]]; then
  if [[ ${#MODIFIED[@]} -gt 0 ]]; then
    git add "${MODIFIED[@]}"
  fi
  if [[ -n "$PROJECT_PBXPROJ" ]]; then
    git add "$PROJECT_PBXPROJ"
  fi
  git commit -m "chore(release): bump to $VERSION (build $BUILD_NUMBER)" || echo "No changes to commit"
  if [[ "$CREATE_TAG" == "true" ]]; then
    git tag -a "v$VERSION" -m "Release $VERSION"
    echo "Created tag v$VERSION"
  fi
else
  echo "Not committing changes (use --commit to commit modified Info.plist files)."
fi

echo "Done."
