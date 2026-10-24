#!/bin/sh
# Xcode Cloud: Config/Secrets.xcconfig is gitignored but is the project's base
# configuration, so generate it from the workflow's secret environment variable.
# An empty key still builds; the Deepgram engine then reports it's unconfigured.
set -eu
cd "$CI_PRIMARY_REPOSITORY_PATH"
printf 'DEEPGRAM_API_KEY = %s\n' "${DEEPGRAM_API_KEY:-}" > Config/Secrets.xcconfig
if [ -n "${DEEPGRAM_API_KEY:-}" ]; then key_status=set; else key_status="not set"; fi
echo "Wrote Config/Secrets.xcconfig (Deepgram key $key_status)"

# App Store Connect rejects a build number it has already accepted; Xcode Cloud
# hands us a monotonically increasing one. MARKETING_VERSION stays manual.
if [ -n "${CI_BUILD_NUMBER:-}" ]; then
  /usr/bin/sed -i '' -E \
    "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER;/" \
    teleprompt.live.xcodeproj/project.pbxproj
  echo "build number set to $CI_BUILD_NUMBER"
fi
