#!/bin/bash

# Vast.ai ComfyUI provisioning script
# For image: vastai/comfy:cuda-12.9-auto
# Do not paste markdown code fences into this file.

APT_PACKAGES=(
    # "package-1"
    # "package-2"
)

PIP_PACKAGES=(
    # "package-1"
    # "package-2"
)

NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/cubiq/ComfyUI_essentials"
)

CHECKPOINT_MODELS=(
)

DIFFUSION_MODELS=(
    "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/diffusion_models/anima-base-v1.0.safetensors?download=true"
    "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8rowwise.safetensors?download=true"
    "https://huggingface.co/Comfy-Org/PixelDiT/resolve/main/diffusion_models/pid_qwenimage_1024_to_4096_4step_bf16.safetensors?download=true"
)

TEXT_ENCODER_MODELS=(
    "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/text_encoders/qwen_3_06b_base.safetensors?download=true"
    "https://huggingface.co/Comfy-Org/PixelDiT/resolve/main/text_encoders/gemma_2_2b_it_elm_bf16.safetensors?download=true"
)

VAE_MODELS=(
    "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors?download=true"
)

LORA_MODELS=(
    "https://civitai.com/api/download/models/2966954?type=Model&format=SafeTensor"
    "https://civitai.com/api/download/models/2922829?type=Model&format=SafeTensor"
)

UPSCALE_MODELS=(
    "https://huggingface.co/ai-forever/Real-ESRGAN/resolve/main/RealESRGAN_x4.pth"
    "https://huggingface.co/FacehugmanIII/4x_foolhardy_Remacri/resolve/main/4x_foolhardy_Remacri.pth"
    "https://huggingface.co/Akumetsu971/SD_Anime_Futuristic_Armor/resolve/main/4x_NMKD-Siax_200k.pth"
)

CONTROLNET_MODELS=(
    "https://huggingface.co/kohya-ss/Anima-LLLite/resolve/main/anima-lllite-inpainting-v1.safetensors?download=true"
    "https://huggingface.co/kohya-ss/Anima-LLLite/resolve/main/anima-lllite-any-test-like-v2.safetensors?download=true"
)

function provisioning_start() {
    export WORKSPACE="${WORKSPACE:-/workspace}"
    export COMFYUI_DIR="${COMFYUI_DIR:-${WORKSPACE}/ComfyUI}"

    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages

    provisioning_get_models "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODER_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/loras" "${LORA_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/controlnet" "${CONTROLNET_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/upscale_models" "${UPSCALE_MODELS[@]}"

    provisioning_print_end
}

function pip_install() {
    python -m pip install --no-cache-dir "$@"
}

function provisioning_get_apt_packages() {
    if (( ${#APT_PACKAGES[@]} > 0 )); then
        printf "Installing apt package(s): %s\n" "${APT_PACKAGES[*]}"
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
    fi
}

function provisioning_get_pip_packages() {
    if (( ${#PIP_PACKAGES[@]} > 0 )); then
        printf "Installing pip package(s): %s\n" "${PIP_PACKAGES[*]}"
        pip_install "${PIP_PACKAGES[@]}"
    fi
}

function provisioning_get_nodes() {
    export WORKSPACE="${WORKSPACE:-/workspace}"
    export COMFYUI_DIR="${COMFYUI_DIR:-${WORKSPACE}/ComfyUI}"

    mkdir -p "${COMFYUI_DIR}/custom_nodes"

    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}/custom_nodes/${dir}"
        requirements="${path}/requirements.txt"

        if [[ -d "$path" ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                (
                    cd "$path" || exit 1
                    git pull
                )
                if [[ -e "$requirements" ]]; then
                    pip_install -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e "$requirements" ]]; then
                pip_install -r "$requirements"
            fi
        fi
    done
}

function provisioning_get_default_workflow() {
    export WORKSPACE="${WORKSPACE:-/workspace}"
    export COMFYUI_DIR="${COMFYUI_DIR:-${WORKSPACE}/ComfyUI}"

    if [[ -n $DEFAULT_WORKFLOW ]]; then
        workflow_json=$(curl -fsSL "$DEFAULT_WORKFLOW")
        if [[ -n $workflow_json ]]; then
            mkdir -p "${COMFYUI_DIR}/web/scripts"
            echo "export const defaultGraph = $workflow_json;" > "${COMFYUI_DIR}/web/scripts/defaultGraph.js"
        fi
    fi
}

function provisioning_get_models() {
    local dir="$1"
    shift || return 0

    if (( $# == 0 )); then
        return 0
    fi

    mkdir -p "$dir"

    printf "Downloading %s model(s) to %s...\n" "$#" "$dir"

    for url in "$@"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n"
    printf "#                                            #\n"
    printf "#          Provisioning container            #\n"
    printf "#                                            #\n"
    printf "#         This will take some time           #\n"
    printf "#                                            #\n"
    printf "# Your container will be ready on completion #\n"
    printf "#                                            #\n"
    printf "##############################################\n\n"

    if [[ -n "${DISK_GB_ALLOCATED:-}" && -n "${DISK_GB_REQUIRED:-}" ]]; then
        if (( DISK_GB_ALLOCATED < DISK_GB_REQUIRED )); then
            printf "WARNING: Your allocated disk size (%sGB) is below the recommended %sGB - Some models may not be downloaded\n" "$DISK_GB_ALLOCATED" "$DISK_GB_REQUIRED"
        fi
    fi
}

function provisioning_print_end() {
    printf "\nProvisioning complete: Web UI will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1

    local url="https://huggingface.co/api/whoami-v2"
    local response

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    [[ "$response" -eq 200 ]]
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1

    local url="https://civitai.com/api/v1/models?hidden=1&limit=1"
    local response

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    [[ "$response" -eq 200 ]]
}

function provisioning_download() {
    local url="$1"
    local dir="$2"
    local dotbytes="${3:-4M}"
    local auth_token=""

    if [[ -n "${HF_TOKEN:-}" && "$url" =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif [[ -n "${CIVITAI_TOKEN:-}" && "$url" =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi

    if [[ -n "$auth_token" ]]; then
        wget \
            --header="Authorization: Bearer $auth_token" \
            -qnc \
            --content-disposition \
            --show-progress \
            -e dotbytes="$dotbytes" \
            -P "$dir" \
            "$url"
    else
        wget \
            -qnc \
            --content-disposition \
            --show-progress \
            -e dotbytes="$dotbytes" \
            -P "$dir" \
            "$url"
    fi
}

provisioning_start
