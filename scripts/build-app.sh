#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
configuration="${1:-release}"
app_dir="${project_dir}/build/Hermes Config Guardian.app"
icon_source="${project_dir}/Resources/AppIcon.png"
swift_arguments=()
plist_name="Info.plist"

if [[ "${HCG_UI_TEST_WINDOW:-0}" == "1" ]]; then
    swift_arguments=(-Xswiftc -DGUARDIAN_UI_TEST_WINDOW)
    plist_name="Info-Test.plist"
fi

cd "${project_dir}"
swift build -c "${configuration}" "${swift_arguments[@]}"

mkdir -p "${app_dir}/Contents/MacOS" "${app_dir}/Contents/Resources"
cp ".build/${configuration}/HermesConfigGuardian" "${app_dir}/Contents/MacOS/HermesConfigGuardian"
cp "Resources/${plist_name}" "${app_dir}/Contents/Info.plist"

if [[ -f "${icon_source}" ]]; then
    icon_work_dir=$(mktemp -d "${TMPDIR:-/tmp}/hermes-config-guardian-icon.XXXXXX")
    trap 'rm -rf -- "${icon_work_dir}"' EXIT
    iconset_dir="${icon_work_dir}/AppIcon.iconset"
    mkdir -p "${iconset_dir}"

    for size in 16 32 128 256 512; do
        sips -z "${size}" "${size}" "${icon_source}" --out "${iconset_dir}/icon_${size}x${size}.png" >/dev/null
        doubled=$((size * 2))
        sips -z "${doubled}" "${doubled}" "${icon_source}" --out "${iconset_dir}/icon_${size}x${size}@2x.png" >/dev/null
    done

    iconutil -c icns "${iconset_dir}" -o "${app_dir}/Contents/Resources/AppIcon.icns"
fi

chmod 755 "${app_dir}/Contents/MacOS/HermesConfigGuardian"
codesign --force --sign - "${app_dir}"

echo "Built ${app_dir}"
