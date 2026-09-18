#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$PROJECT_ROOT/dist/FrameRelay.app"
CONTENTS_PATH="$APP_PATH/Contents"
FRAMEWORKS_PATH="$CONTENTS_PATH/Frameworks"
PLUGIN_PATH="$CONTENTS_PATH/Resources/gstreamer-1.0"
CORE_SOURCE="$PROJECT_ROOT/build/uxplay/uxplay-core.dylib"
BREW_PREFIX="$(brew --prefix)"
GSTREAMER_PREFIX="$(brew --prefix gstreamer)"

cd "$PROJECT_ROOT"

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle is missing. Run Scripts/build-app.sh first." >&2
    exit 1
fi
if [[ ! -f "$CORE_SOURCE" ]]; then
    echo "uxplay-core.dylib is missing. Run Scripts/build-core.sh first." >&2
    exit 1
fi

GSTREAMER_PLUGIN_SOURCE="$GSTREAMER_PREFIX/lib/gstreamer-1.0"
GSTREAMER_SCANNER_SOURCE="$GSTREAMER_PREFIX/libexec/gstreamer-1.0/gst-plugin-scanner"
REQUIRED_GSTREAMER_PLUGINS=(
    libgstapp.dylib
    libgstaudioconvert.dylib
    libgstaudioresample.dylib
    libgstlevel.dylib
    libgstvolume.dylib
    libgstosxaudio.dylib
    libgstautodetect.dylib
    libgstapplemedia.dylib
    libgstcoreelements.dylib
    libgstlibav.dylib
    libgstplayback.dylib
    libgsttypefindfunctions.dylib
    libgstvideoconvertscale.dylib
    libgstvideofilter.dylib
    libgstvideoparsersbad.dylib
)

if [[ ! -d "$GSTREAMER_PLUGIN_SOURCE" ]]; then
    echo "GStreamer plugin directory is missing: $GSTREAMER_PLUGIN_SOURCE" >&2
    exit 1
fi
if [[ ! -f "$GSTREAMER_SCANNER_SOURCE" ]]; then
    echo "GStreamer plugin scanner is missing: $GSTREAMER_SCANNER_SOURCE" >&2
    exit 1
fi

mkdir -p "$FRAMEWORKS_PATH" "$PLUGIN_PATH"

bundle_files=()

queue_file() {
    local file_path="$1"
    local known
    for known in "${bundle_files[@]-}"; do
        if [[ "$known" == "$file_path" ]]; then
            return
        fi
    done
    bundle_files+=("$file_path")
}

copy_framework_file() {
    local source_path="$1"
    local base_name="$(basename "$source_path")"
    local destination_path="$FRAMEWORKS_PATH/$base_name"
    if [[ ! -f "$destination_path" ]]; then
        cp -L "$source_path" "$destination_path"
    fi
    queue_file "$destination_path"
}

copy_plugin_file() {
    local source_path="$1"
    local base_name="$(basename "$source_path")"
    local destination_path="$PLUGIN_PATH/$base_name"
    if [[ ! -f "$destination_path" ]]; then
        cp -L "$source_path" "$destination_path"
    fi
    queue_file "$destination_path"
}

is_system_dependency() {
    case "$1" in
        /System/*|/usr/lib/*|/usr/lib/swift/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

resolve_rpath_dependency() {
    local dependency="$1"
    local origin="$2"
    local base_name="$(basename "$dependency")"
    local origin_directory="$(dirname "$origin")"
    local candidate
    local rpath

    if [[ -f "$FRAMEWORKS_PATH/$base_name" ]]; then
        printf '%s\n' "$FRAMEWORKS_PATH/$base_name"
        return 0
    fi

    while IFS= read -r rpath; do
        [[ -z "$rpath" ]] && continue
        candidate="${rpath//@loader_path/$origin_directory}"
        candidate="${candidate//@executable_path/$CONTENTS_PATH/MacOS}"
        if [[ -f "$candidate/$base_name" ]]; then
            printf '%s\n' "$candidate/$base_name"
            return 0
        fi
    done < <(otool -l "$origin" | awk '$1 == "path" { print $2 }')

    find "$BREW_PREFIX/Cellar" \( -type f -o -type l \) -name "$base_name" -print -quit 2>/dev/null || true
}

resolve_dependency() {
    local dependency="$1"
    local origin="$2"
    local base_name
    local candidate

    case "$dependency" in
        @rpath/*)
            resolve_rpath_dependency "$dependency" "$origin"
            ;;
        @loader_path/*)
            base_name="$(basename "$dependency")"
            candidate="$(dirname "$origin")/${dependency#@loader_path/}"
            if [[ -f "$candidate" ]]; then
                printf '%s\n' "$candidate"
            elif [[ -f "$FRAMEWORKS_PATH/$base_name" ]]; then
                printf '%s\n' "$FRAMEWORKS_PATH/$base_name"
            fi
            ;;
        @executable_path/*)
            base_name="$(basename "$dependency")"
            candidate="$CONTENTS_PATH/MacOS/${dependency#@executable_path/}"
            if [[ -f "$candidate" ]]; then
                printf '%s\n' "$candidate"
            elif [[ -f "$FRAMEWORKS_PATH/$base_name" ]]; then
                printf '%s\n' "$FRAMEWORKS_PATH/$base_name"
            fi
            ;;
        /*)
            if [[ -f "$dependency" ]]; then
                printf '%s\n' "$dependency"
            fi
            ;;
        *)
            base_name="$(basename "$dependency")"
            if [[ -f "$FRAMEWORKS_PATH/$base_name" ]]; then
                printf '%s\n' "$FRAMEWORKS_PATH/$base_name"
            else
                find "$BREW_PREFIX/Cellar" \( -type f -o -type l \) -name "$base_name" -print -quit 2>/dev/null || true
            fi
            ;;
    esac
}

copy_framework_file "$CORE_SOURCE"
for plugin_name in "${REQUIRED_GSTREAMER_PLUGINS[@]}"; do
    plugin="$GSTREAMER_PLUGIN_SOURCE/$plugin_name"
    if [[ ! -f "$plugin" ]]; then
        echo "Required GStreamer plugin is missing: $plugin" >&2
        exit 1
    fi
    copy_plugin_file "$plugin"
done
copy_plugin_file "$GSTREAMER_SCANNER_SOURCE"

index=0
while [[ "$index" -lt "${#bundle_files[@]}" ]]; do
    origin="${bundle_files[$index]}"
    index=$((index + 1))

    while IFS= read -r dependency; do
        [[ -z "$dependency" ]] && continue
        if is_system_dependency "$dependency"; then
            continue
        fi

        source_path="$(resolve_dependency "$dependency" "$origin")"
        if [[ -z "$source_path" ]]; then
            echo "Unable to resolve non-system dependency $dependency from $origin" >&2
            exit 1
        fi
        if is_system_dependency "$source_path"; then
            continue
        fi

        copy_framework_file "$source_path"
    done < <(otool -L "$origin" | awk 'NR > 1 { print $1 }')
done

add_rpath_if_missing() {
    local file_path="$1"
    local rpath="$2"
    if ! otool -l "$file_path" | grep -Fq "path $rpath"; then
        install_name_tool -add_rpath "$rpath" "$file_path" 2>/dev/null
    fi
}

rewrite_load_commands() {
    local file_path="$1"
    local is_plugin="$2"
    local base_name="$(basename "$file_path")"
    local dependency
    local dependency_base
    local replacement

    if [[ "$is_plugin" == "yes" ]]; then
        add_rpath_if_missing "$file_path" "@loader_path/../../Frameworks"
    elif [[ "$file_path" == "$CONTENTS_PATH/MacOS/FrameRelay" ]]; then
        add_rpath_if_missing "$file_path" "@executable_path/../Frameworks"
    else
        add_rpath_if_missing "$file_path" "@loader_path"
    fi

    if [[ "$file_path" == *.dylib ]]; then
        install_name_tool -id "@rpath/$base_name" "$file_path" 2>/dev/null
    fi

    while IFS= read -r dependency; do
        [[ -z "$dependency" ]] && continue
        if is_system_dependency "$dependency"; then
            continue
        fi
        dependency_base="$(basename "$dependency")"
        if [[ -f "$FRAMEWORKS_PATH/$dependency_base" ]]; then
            replacement="@rpath/$dependency_base"
        elif [[ -f "$PLUGIN_PATH/$dependency_base" ]]; then
            replacement="@loader_path/$dependency_base"
        else
            echo "No bundled replacement for $dependency in $file_path" >&2
            exit 1
        fi
        install_name_tool -change "$dependency" "$replacement" "$file_path" 2>/dev/null
    done < <(otool -L "$file_path" | awk 'NR > 1 { print $1 }')
}

for file_path in "${bundle_files[@]}"; do
    if [[ "$file_path" == "$PLUGIN_PATH"/* ]]; then
        rewrite_load_commands "$file_path" yes
    else
        rewrite_load_commands "$file_path" no
    fi
done

rewrite_load_commands "$CONTENTS_PATH/MacOS/FrameRelay" no

# Sign every nested Mach-O after all install names and rpaths have been
# rewritten.  A single outer --deep pass can leave a pre-existing linker
# signature on one of the hundreds of GStreamer plugins; signing the nested
# files explicitly makes the final app seal deterministic.
while IFS= read -r -d '' file_path; do
    if file "$file_path" | grep -q 'Mach-O'; then
        codesign --force --sign - "$file_path"
    fi
done < <(find "$CONTENTS_PATH/Frameworks" "$PLUGIN_PATH" -type f -print0)

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Bundled GStreamer and recursive non-system dylib dependencies."
echo "Signed app bundle: $APP_PATH"
