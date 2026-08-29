#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
configuration="${1:-release}"
app_dir="${project_dir}/build/Hermes Config Guardian.app"
swift_arguments=()
plist_name="Info.plist"

if [[ "${HCG_UI_TEST_WINDOW:-0}" == "1" ]]; then
    swift_arguments=(-Xswiftc -DGUARDIAN_UI_TEST_WINDOW)
    plist_name="Info-Test.plist"
fi

cd "${project_dir}"
swift build -c "${configuration}" "${swift_arguments[@]}"

mkdir -p "${app_dir}/Contents/MacOS"
cp ".build/${configuration}/HermesConfigGuardian" "${app_dir}/Contents/MacOS/HermesConfigGuardian"
cp "Resources/${plist_name}" "${app_dir}/Contents/Info.plist"
chmod 755 "${app_dir}/Contents/MacOS/HermesConfigGuardian"
codesign --force --sign - "${app_dir}"

echo "Built ${app_dir}"
