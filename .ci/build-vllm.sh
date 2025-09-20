#!/bin/bash -e

# Variables
root="$1"
repository="$2"
ref="$3"
ghcr_user="$4"
ghcr_token="$5"
AWS_ENDPOINT="$6"
AWS_ACCESS_KEY_ID="$7"
AWS_SECRET_ACCESS_KEY="$8"

# Use root directory
cd "$root"

# Prepare virtual environment
"$root/.ci/common/prepare-venv.sh" "$root"

# Checkout repository
"$root/.ci/common/checkout.sh" "$root" "$repository" "$ref"

# Apply patches
"$root/.ci/common/apply-patches.sh" "$root" "$repository" "$ref"

# Compute vLLM version
# {
  # setuptools
  # {
    if [[ "$ref" == "main" ]]; then
      export SETUPTOOLS_SCM_PRETEND_VERSION_FOR_VLLM="999.999.999"
    elif [[ "$ref" == v* ]]; then
      export SETUPTOOLS_SCM_PRETEND_VERSION_FOR_VLLM="${ref:1}"
    fi
  # }

  # docker
  # {
    if [[ "$ref" == "main" ]]; then
      docker_tag="ghcr.io/$ghcr_user/vllm:latest"
    else
      docker_tag="ghcr.io/$ghcr_user/vllm:$ref"
    fi
  # }
# }

# Determine Dockerfile location
# {
  if [ -f "$root/$repository/$ref/docker/Dockerfile" ]; then
    dockerfile="$root/$repository/$ref/docker/Dockerfile"
  else
    dockerfile="$root/$repository/$ref/Dockerfile"
  fi
# }

# Build wheels
mkdir -p "$root/tmp"
docker build \
  --build-arg "CUDA_VERSION=12.1.0" \
  --build-arg "USE_SCCACHE=1" \
  --build-arg "SCCACHE_REGION_NAME=eu-west-1" \
  --build-arg "SCCACHE_ENDPOINT=$AWS_ENDPOINT" \
  --build-arg "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
  --build-arg "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
  --build-arg "torch_cuda_arch_list=6.0 6.1" \
  --build-arg "max_jobs=16" \
  --build-arg "nvcc_threads=16" \
  --file "$dockerfile" \
  --output "type=tar,dest=$root/tmp/build.tar" \
  --secret "id=SETUPTOOLS_SCM_PRETEND_VERSION_FOR_VLLM" \
  --tag "$docker_tag" \
  --target "build" \
  "$root/$repository/$ref"

# Copy wheel files
tar --extract --file="$root/tmp/build.tar" --strip-components=1 workspace/dist
rm "$root/tmp/build.tar"

# Repackage wheels
export WHEEL_HOUSE="dist/*.whl"
export WHEEL_NAME="vllm_pascal"
"$root/.ci/common/repackage-wheels.sh" "$root"

# If GHCR token is provided
if [ -n "$ghcr_token" ]; then
  # Login to GitHub Container Registry
  echo "$ghcr_token" | docker login ghcr.io -u "$ghcr_user" --password-stdin

  # Build image
  docker build \
    --build-arg "CUDA_VERSION=12.1.0" \
    --build-arg "USE_SCCACHE=1" \
    --build-arg "SCCACHE_REGION_NAME=eu-west-1" \
    --build-arg "SCCACHE_ENDPOINT=$AWS_ENDPOINT" \
    --build-arg "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
    --build-arg "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
    --build-arg "torch_cuda_arch_list=6.0 6.1" \
    --build-arg "max_jobs=16" \
    --build-arg "nvcc_threads=16" \
    --file "$dockerfile" \
    --secret "id=SETUPTOOLS_SCM_PRETEND_VERSION_FOR_VLLM" \
    --tag "$docker_tag" \
    --target "vllm-openai" \
    "$root/$repository/$ref"

  # Push image
  docker push "$docker_tag"
fi
