#!/usr/bin/env bash
set -euo pipefail

MIRROR_FILE="./mirrors_list.yaml"
MIRROR_URL="https://raw.githubusercontent.com/MiravaOrg/Mirava/refs/heads/main/mirrors_list.yaml"

function check_dependency() {
	if ! command -v $1 &> /dev/null; then
		echo "❌ Error: '$1' is not installed."
		if [[ $# -gt 1 ]]; then
			shift
			echo $@
		else
			echo "Please install '$1' first."
		fi
		exit 1
	fi
}

function check_resource() {
	if [[ ! -f $1 ]]; then
		echo "Resource '$1' not found"
		if [[ $# -ge 2 && $2 != - ]]; then
			echo "Trying to download resource '$1' from '$2'"
			if curl -fsSL "$2" -o "$1"; then
				echo "Downloaded resource '$1' from '$2'"
			else
				echo "Failed to download resource '$1' from '$2'"
				exit 1
			fi
		else
			exit 1
		fi
	fi
}

check_dependency curl
check_dependency yq Please install yq from: https://github.com/mikefarah/yq/
check_dependency seq
check_resource "$MIRROR_FILE" "$MIRROR_URL"

declare -A PACKAGE_PATHS=(
  ["Ubuntu"]="ubuntu"
  ["Debian"]="debian"
  ["Arch Linux"]="archlinux"
  ["PyPI"]="pypi"
  ["npm"]="npm"
  ["CentOS"]="centos"
  ["Alpine"]="alpine"
  ["Composer"]="packages.json"
  ["Docker Registry"]="v2/"
  ["Homebrew"]="brew"
)

function check_url() {
  local url=$1
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" || true)
  echo "$status"
}

function check_docker_registry() {
  local url=$1
  # Docker Registry requires a GET to /v2/ and must respond with 200 or 401
  status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url/v2/" || true)
  if [[ "$status" == "200" || "$status" == "401" ]]; then
    echo "✅ Docker Registry OK ($status)"
  else
    echo "❌ Docker Registry Failed ($status)"
  fi
}

for idx in $(seq 0 $(yq -er '.mirrors | length - 1' "$MIRROR_FILE")); do
  name=$(yq -er ".mirrors[$idx].name" "$MIRROR_FILE")
  base_url=$(yq -er ".mirrors[$idx].url" "$MIRROR_FILE")
  echo -e "\n🔍 Checking mirror: $name"
  echo "URL: $base_url"

  package_count=$(yq -er ".mirrors[$idx].packages | length" "$MIRROR_FILE")

  for j in $(seq 0 $((package_count - 1))); do
    package=$(yq -er ".mirrors[$idx].packages[$j]" "$MIRROR_FILE")
    
    # Safely get path with set -u enabled
    if [[ -v PACKAGE_PATHS["$package"] ]]; then
      path=${PACKAGE_PATHS["$package"]}
    else
      path=""
    fi

    if [[ "$package" == "Docker Registry" ]]; then
      check_docker_registry "$base_url"
    elif [[ -n "$path" ]]; then
      full_url="$base_url/$path"
      status=$(check_url "$full_url")
      if [[ "$status" == "200" || "$status" == "301" || "$status" == "302" ]]; then
        echo "✅ $package -> $full_url ($status)"
      else
        echo "❌ $package -> $full_url ($status)"
      fi
    else
      echo "⚠️ Unknown package type: $package"
    fi
  done

  echo "----------------------------"
done
