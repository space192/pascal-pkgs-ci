#!/bin/bash -e

# Variables
root="$1"
repository="$2"
ref="$3"
python_version="$4"
AWS_ENDPOINT="$5"
AWS_ACCESS_KEY_ID="$6"
AWS_SECRET_ACCESS_KEY="$7"

export SCCACHE_DOWNLOAD_URL=https://github.com/mozilla/sccache/releases/download/v0.8.1/sccache-v0.8.1-x86_64-unknown-linux-musl.tar.gz

# Use root directory
cd "$root"

# Prepare virtual environment
"$root/.ci/common/prepare-venv.sh" "$root"

# Checkout repository
"$root/.ci/common/checkout.sh" "$root" "$repository" "$ref"

# Apply patches
"$root/.ci/common/apply-patches.sh" "$root" "$repository" "$ref"

# Build wheels
export CIBW_BUILD="cp$python_version-manylinux_x86_64"
export CIBW_BUILD_VERBOSITY="1"
# Assuming you have the version in a variable called $version
version=${ref#v}  # Remove leading 'v'
IFS='.' read -r major minor patch <<< "$version"

# Compare version components numerically
if (( 10#$major > 3 )) || \
   (( 10#$major == 3 && 10#$minor > 4 )) || \
   (( 10#$major == 3 && 10#$minor == 4 && 10#$patch >= 0 )); then
    path="$repository/$ref"
else
    path="$repository/$ref/python"
fi

export CIBW_BEFORE_ALL_LINUX="curl -L -o sccache.tar.gz ${SCCACHE_DOWNLOAD_URL} &&\
tar -xzf sccache.tar.gz &&\
mv sccache-v0.8.1-x86_64-unknown-linux-musl/sccache /usr/bin/sccache &&\
rm -rf sccache.tar.gz sccache-v0.8.1-x86_64-unknown-linux-musl"
export CIBW_ENVIRONMENT="SCCACHE_BUCKET='triton-sccache' SCCACHE_REGION='eu-west-1' SCCACHE_ENDPOINT=${AWS_ENDPOINT} AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID} AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY} SCCACHE_IDLE_TIMEOUT=0 TRITON_APPEND_CMAKE_ARGS='-DCMAKE_C_COMPILER_LAUNCHER=sccache -DCMAKE_CXX_COMPILER_LAUNCHER=sccache'"
export CIBW_BEFORE_BUILD_LINUX="sccache --show-stats"
export CIBW_BEFORE_TEST_LINUX="sccache --show-stats"
export CIBW_TEST_COMMAND="echo 'No tests'"


"$root/venv/bin/cibuildwheel" --output-dir "$root/dist" "$path"

# Repackage wheels
export WHEEL_HOUSE="dist/*.whl"
export WHEEL_NAME="triton_pascal"
"$root/.ci/common/repackage-wheels.sh" "$root"
