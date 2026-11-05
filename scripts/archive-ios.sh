#!/bin/bash
# Create a signed archive and export an IPA locally; does not upload or submit.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team ID}"
xcodegen generate --spec ios/ATVRemote/project.yml
build_dir="$PWD/ios/ATVRemote/build/distribution"
mkdir -p "$build_dir"
build_args=("DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM")
if [[ -n "${REVENUECAT_PUBLIC_API_KEY:-}" ]]; then
  [[ "$REVENUECAT_PUBLIC_API_KEY" == appl_* ]] || { echo 'Expected an Apple public SDK key.' >&2; exit 1; }
  build_args+=("REVENUECAT_PUBLIC_API_KEY=$REVENUECAT_PUBLIC_API_KEY")
fi
xcodebuild archive -project ios/ATVRemote/ATVRemote.xcodeproj -scheme ATVRemote \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$build_dir/DerivedData" \
  -archivePath "$build_dir/PocketRemote.xcarchive" \
  -allowProvisioningUpdates "${build_args[@]}"
archive_info="$build_dir/PocketRemote.xcarchive/Products/Applications/ATVRemote.app/Info.plist"
sdk_key=$(/usr/libexec/PlistBuddy -c 'Print :RevenueCatPublicAPIKey' "$archive_info")
[[ "$sdk_key" == appl_* && ${#sdk_key} -gt 5 ]] || { echo 'Archive is missing the Apple SDK key.' >&2; exit 1; }
export_options="$build_dir/ExportOptions.plist"
/usr/bin/plutil -create xml1 "$export_options"
/usr/bin/plutil -insert method -string app-store-connect "$export_options"
/usr/bin/plutil -insert destination -string export "$export_options"
/usr/bin/plutil -insert signingStyle -string automatic "$export_options"
/usr/bin/plutil -insert teamID -string "$DEVELOPMENT_TEAM" "$export_options"
/usr/bin/plutil -insert uploadSymbols -bool YES "$export_options"
xcodebuild -exportArchive -archivePath "$build_dir/PocketRemote.xcarchive" \
  -exportPath "$build_dir/export" -exportOptionsPlist "$export_options" -allowProvisioningUpdates
