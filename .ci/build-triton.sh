#!/bin/bash -e

# Variables
root="$1"
repository="$2"
ref="$3"
python_version="$4"

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
if [[ "$version" >= "3.4.0" ]]; then
    path="$repository/$ref"
else
    path="$repository/$ref/python"
fi

"$root/venv/bin/cibuildwheel" --output-dir "$root/dist" "$path"

# Repackage wheels
export WHEEL_HOUSE="dist/*.whl"
export WHEEL_NAME="triton_pascal"
"$root/.ci/common/repackage-wheels.sh" "$root"
