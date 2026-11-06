#!/bin/bash
# Builds and drives BetterFinder under a throwaway bundle ID. See SKILL.md.
#
#   drive.sh build [--release] [--tag NAME] [--ref GIT_REF]
#   drive.sh fixtures [--count N] [--name NAME]
#   drive.sh run --out NAME [--tag NAME] [--fixture NAME | --folder PATH]
#                [--mode thumbnails|list] [--timeout SECONDS] < script
#   drive.sh path
#   drive.sh clean
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="${BF_WORK:-${TMPDIR:-/tmp}/betterfinder-agent}"
WORK="${WORK%/}"
# A separate bundle ID gives the test app its own UserDefaults, so it can't touch
# the developer's last location, favorites, or per-folder view settings.
BUNDLE_ID="com.KatzStudio.BetterFinder.agent"

die() { echo "error: $*" >&2; exit 1; }

remove_app_state() {
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    rm -rf "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
}

running_instances() {
    pgrep -f "$WORK/.*/BetterFinder.app/Contents/MacOS/BetterFinder" || true
}

cmd_build() {
    local config=Debug tag=current ref=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --release) config=Release; shift ;;
            --tag) tag="$2"; shift 2 ;;
            --ref) ref="$2"; shift 2 ;;
            *) die "unknown build option: $1" ;;
        esac
    done

    mkdir -p "$WORK"
    local source="$REPO"
    if [ -n "$ref" ]; then
        # An exported copy leaves the working tree and git state untouched.
        source="$WORK/src-$tag"
        rm -rf "$source"
        mkdir -p "$source"
        git -C "$REPO" archive "$ref" | tar -x -C "$source"
    fi

    local derived="$WORK/build-$tag" log="$WORK/build-$tag.log"
    echo "Building $config (tag: $tag)..."
    if ! (cd "$source" && xcodebuild build \
            -project BetterFinder.xcodeproj -scheme BetterFinder -configuration "$config" -quiet \
            -derivedDataPath "$derived" -clonedSourcePackagesDirPath "$WORK/packages" \
            PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" ENABLE_HARDENED_RUNTIME=NO \
            CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=) >"$log" 2>&1; then
        grep -E ' error:|BUILD FAILED' "$log" || tail -20 "$log"
        die "build failed; full log: $log"
    fi
    local app="$derived/Build/Products/$config/BetterFinder.app"
    [ -d "$app" ] || die "build product not found at $app"
    echo "$app" >"$WORK/$tag.apppath"
    echo "Built $app"
}

cmd_fixtures() {
    local count=12 name=photos
    while [ $# -gt 0 ]; do
        case "$1" in
            --count) count="$2"; shift 2 ;;
            --name) name="$2"; shift 2 ;;
            *) die "unknown fixtures option: $1" ;;
        esac
    done
    mkdir -p "$WORK"
    swiftc -O "$HERE/make_fixtures.swift" -o "$WORK/make_fixtures"
    rm -rf "${WORK:?}/fixtures/$name"
    "$WORK/make_fixtures" "$WORK/fixtures/$name" "$count"
    # A folder to open, since double-clicking a JPEG would launch Preview.
    mkdir -p "$WORK/fixtures/nested/Album"
    touch "$WORK/fixtures/nested/Album/inside.txt"
}

cmd_run() {
    local out="" tag=current folder="$WORK/fixtures/photos" mode=thumbnails timeout=60
    while [ $# -gt 0 ]; do
        case "$1" in
            --out) out="$2"; shift 2 ;;
            --tag) tag="$2"; shift 2 ;;
            --fixture) folder="$WORK/fixtures/$2"; shift 2 ;;
            --folder) folder="$2"; shift 2 ;;
            --mode) mode="$2"; shift 2 ;;
            --timeout) timeout="$2"; shift 2 ;;
            *) die "unknown run option: $1" ;;
        esac
    done
    [ -n "$out" ] || die "--out NAME is required"
    [ -f "$WORK/$tag.apppath" ] || die "no build for tag '$tag'; run: drive.sh build --tag $tag"
    [ -d "$folder" ] || die "folder not found: $folder"

    # Two driven copies fight over focus, and results from the loser are invalid.
    local others
    others="$(running_instances)"
    [ -z "$others" ] || die "another driven instance is running (pid $others); wait for it or kill it"

    local app dylib="$WORK/driver.dylib" dir="$WORK/out/$out"
    app="$(cat "$WORK/$tag.apppath")"
    if [ ! -f "$dylib" ] || [ "$HERE/driver.m" -nt "$dylib" ]; then
        clang -dynamiclib -fobjc-arc -framework Cocoa -Wno-deprecated-declarations "$HERE/driver.m" -o "$dylib"
    fi

    rm -rf "$dir"
    mkdir -p "$dir"
    cat >"$dir/script.txt"

    local status=0
    DRIVER_SCRIPT="$dir/script.txt" DRIVER_OUT="$dir" DRIVER_TIMEOUT="$timeout" \
    DRIVER_FOLDER="$folder" DRIVER_FIXTURES="$WORK/fixtures" \
    DYLD_INSERT_LIBRARIES="$dylib" \
        "$app/Contents/MacOS/BetterFinder" \
        -settings.general.defaultViewMode "$mode" \
        -settings.general.defaultLocation custom \
        -settings.general.customDefaultLocationPath "$folder" \
        -ApplePersistenceIgnoreState YES \
        >"$dir/app.log" 2>&1 || status=$?
    remove_app_state

    cat "$dir/driver.log"
    if [ "$status" -eq 0 ] && grep -q 'WARNING' "$dir/driver.log"; then
        echo "INVALID RUN: see the WARNING above; discard these results and run again" >&2
        status=4
    fi
    echo "Output: $dir (exit $status)"
    return "$status"
}

cmd_clean() {
    local others
    others="$(running_instances)"
    [ -z "$others" ] || die "a driven instance is still running (pid $others)"
    remove_app_state
    rm -rf "$WORK"
    echo "Removed $WORK"
}

command="${1:-}"
[ $# -gt 0 ] && shift
case "$command" in
    build) cmd_build "$@" ;;
    fixtures) cmd_fixtures "$@" ;;
    run) cmd_run "$@" ;;
    path) echo "$WORK" ;;
    clean) cmd_clean "$@" ;;
    *) die "usage: drive.sh build|fixtures|run|path|clean (see SKILL.md)" ;;
esac
