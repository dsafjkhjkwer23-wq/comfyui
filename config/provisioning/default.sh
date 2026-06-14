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

# Format:
#   "filename|url"
# filename을 고정해야 workflow의 LoraLoader에서 바로 잡힙니다.
LORA_MODELS=(
    "minazuki_mikka_art_style_many_characters_anima_illustrious_noobai.safetensors|https://civitai.com/api/download/models/2966954?type=Model&format=SafeTensor"
    "x_micro_bikini.safetensors|https://civitai.com/api/download/models/2922829?type=Model&format=SafeTensor"
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

    # LoRA first: small files, faster to verify CivitAI token/download behavior.
    provisioning_get_models "${COMFYUI_DIR}/models/loras" "${LORA_MODELS[@]}"

    provisioning_get_models "${COMFYUI_DIR}/models/checkpoints" "${CHECKPOINT_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODER_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/controlnet" "${CONTROLNET_MODELS[@]}"
    provisioning_get_models "${COMFYUI_DIR}/models/upscale_models" "${UPSCALE_MODELS[@]}"

    provisioning_get_default_workflow
    provisioning_print_end
}

function get_python_bin() {
    if [[ -n "${VIRTUAL_ENV:-}" && -x "${VIRTUAL_ENV}/bin/python" ]]; then
        echo "${VIRTUAL_ENV}/bin/python"
    elif [[ -x /venv/main/bin/python ]]; then
        echo "/venv/main/bin/python"
    elif command -v python >/dev/null 2>&1; then
        command -v python
    elif command -v python3 >/dev/null 2>&1; then
        command -v python3
    else
        return 1
    fi
}

function pip_install() {
    local pybin

    pybin="$(get_python_bin)" || {
        echo "WARNING: Python executable not found. Skipping pip install: $*"
        return 0
    }

    "$pybin" -m pip install --no-cache-dir "$@" || {
        echo "WARNING: pip install failed: $*"
        return 0
    }
}

function provisioning_get_apt_packages() {
    if (( ${#APT_PACKAGES[@]} > 0 )); then
        printf "Installing apt package(s): %s\n" "${APT_PACKAGES[*]}"
        apt-get update || {
            echo "WARNING: apt-get update failed"
            return 0
        }
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}" || {
            echo "WARNING: apt-get install failed"
            return 0
        }
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
            if [[ "${AUTO_UPDATE,,}" != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                (
                    cd "$path" || exit 0
                    git pull || true
                )
                if [[ -e "$requirements" ]]; then
                    pip_install -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive || {
                echo "WARNING: Failed to clone node: ${repo}"
                continue
            }
            if [[ -e "$requirements" ]]; then
                pip_install -r "$requirements"
            fi
        fi
    done
}

function provisioning_get_default_workflow() {
    export WORKSPACE="${WORKSPACE:-/workspace}"
    export COMFYUI_DIR="${COMFYUI_DIR:-${WORKSPACE}/ComfyUI}"

    if [[ -n "${DEFAULT_WORKFLOW:-}" ]]; then
        workflow_json=$(curl -fsSL "$DEFAULT_WORKFLOW" || true)
        if [[ -n "$workflow_json" ]]; then
            mkdir -p "${COMFYUI_DIR}/web/scripts"
            echo "export const defaultGraph = $workflow_json;" > "${COMFYUI_DIR}/web/scripts/defaultGraph.js"
        else
            echo "WARNING: Failed to download DEFAULT_WORKFLOW"
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

    for item in "$@"; do
        provisioning_download "${item}" "${dir}"
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

    printf "WORKSPACE: %s\n" "${WORKSPACE:-/workspace}"
    printf "COMFYUI_DIR: %s\n\n" "${COMFYUI_DIR:-/workspace/ComfyUI}"

    if [[ -n "${DISK_GB_ALLOCATED:-}" && -n "${DISK_GB_REQUIRED:-}" ]]; then
        if (( DISK_GB_ALLOCATED < DISK_GB_REQUIRED )); then
            printf "WARNING: Your allocated disk size (%sGB) is below the recommended %sGB - Some models may not be downloaded\n" "$DISK_GB_ALLOCATED" "$DISK_GB_REQUIRED"
        fi
    fi

    if [[ -z "${HF_TOKEN:-}" ]]; then
        printf "WARNING: HF_TOKEN is not set. Gated Hugging Face models may fail.\n"
    fi

    if [[ -z "${CIVITAI_TOKEN:-}" ]]; then
        printf "WARNING: CIVITAI_TOKEN is not set. CivitAI downloads may fail.\n"
    fi

    printf "\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete: Web UI will start now\n\n"
}

function append_query_param() {
    local url="$1"
    local key="$2"
    local value="$3"

    if [[ "$url" == *"${key}="* ]]; then
        echo "$url"
    elif [[ "$url" == *"?"* ]]; then
        echo "${url}&${key}=${value}"
    else
        echo "${url}?${key}=${value}"
    fi
}

function provisioning_has_valid_hf_token() {
    [[ -n "${HF_TOKEN:-}" ]] || return 1

    local url="https://huggingface.co/api/whoami-v2"
    local response

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    [[ "$response" -eq 200 ]]
}

function provisioning_has_valid_civitai_token() {
    [[ -n "${CIVITAI_TOKEN:-}" ]] || return 1

    local url="https://civitai.com/api/v1/models?hidden=1&limit=1"
    local response

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    [[ "$response" -eq 200 ]]
}

function provisioning_download() {
    local item="$1"
    local dir="$2"
    local dotbytes="${3:-4M}"

    local filename=""
    local url="$item"
    local download_url=""
    local outfile=""
    local tmpfile=""

    if [[ "$item" == *"|"* ]]; then
        filename="${item%%|*}"
        url="${item#*|}"
    fi

    printf "Downloading: %s\n" "${url}"

    if [[ -n "$filename" ]]; then
        outfile="${dir}/${filename}"

        if [[ -s "$outfile" ]]; then
            printf "Already exists, skipping: %s\n" "$outfile"
            return 0
        fi
    fi

    download_url="$url"

    if [[ "$url" =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        if [[ -n "${CIVITAI_TOKEN:-}" ]]; then
            download_url="$(append_query_param "$download_url" "token" "$CIVITAI_TOKEN")"
        fi

        if [[ -n "$filename" ]]; then
            tmpfile="${outfile}.part"
            rm -f "$tmpfile"

            wget \
                --show-progress \
                --tries=3 \
                --timeout=60 \
                --waitretry=5 \
                -e dotbytes="$dotbytes" \
                -O "$tmpfile" \
                "$download_url" || {
                    echo "WARNING: CivitAI download failed: ${url}"
                    rm -f "$tmpfile"
                    return 0
                }

            mv "$tmpfile" "$outfile"
            printf "Saved: %s\n" "$outfile"
            return 0
        fi

        wget \
            --content-disposition \
            --show-progress \
            --tries=3 \
            --timeout=60 \
            --waitretry=5 \
            -e dotbytes="$dotbytes" \
            -P "$dir" \
            "$download_url" || {
                echo "WARNING: CivitAI download failed: ${url}"
                return 0
            }

        return 0
    fi

    if [[ "$url" =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        if [[ -n "$filename" ]]; then
            tmpfile="${outfile}.part"
            rm -f "$tmpfile"

            if [[ -n "${HF_TOKEN:-}" ]]; then
                wget \
                    --header="Authorization: Bearer $HF_TOKEN" \
                    --show-progress \
                    --tries=3 \
                    --timeout=60 \
                    --waitretry=5 \
                    -e dotbytes="$dotbytes" \
                    -O "$tmpfile" \
                    "$url" || {
                        echo "WARNING: Hugging Face download failed: ${url}"
                        rm -f "$tmpfile"
                        return 0
                    }
            else
                wget \
                    --show-progress \
                    --tries=3 \
                    --timeout=60 \
                    --waitretry=5 \
                    -e dotbytes="$dotbytes" \
                    -O "$tmpfile" \
                    "$url" || {
                        echo "WARNING: Hugging Face download failed: ${url}"
                        rm -f "$tmpfile"
                        return 0
                    }
            fi

            mv "$tmpfile" "$outfile"
            printf "Saved: %s\n" "$outfile"
            return 0
        fi

        if [[ -n "${HF_TOKEN:-}" ]]; then
            wget \
                --header="Authorization: Bearer $HF_TOKEN" \
                -qnc \
                --content-disposition \
                --show-progress \
                --tries=3 \
                --timeout=60 \
                --waitretry=5 \
                -e dotbytes="$dotbytes" \
                -P "$dir" \
                "$url" || {
                    echo "WARNING: Hugging Face download failed: ${url}"
                    return 0
                }
        else
            wget \
                -qnc \
                --content-disposition \
                --show-progress \
                --tries=3 \
                --timeout=60 \
                --waitretry=5 \
                -e dotbytes="$dotbytes" \
                -P "$dir" \
                "$url" || {
                    echo "WARNING: Hugging Face download failed: ${url}"
                    return 0
                }
        fi

        return 0
    fi

    if [[ -n "$filename" ]]; then
        tmpfile="${outfile}.part"
        rm -f "$tmpfile"

        wget \
            --show-progress \
            --tries=3 \
            --timeout=60 \
            --waitretry=5 \
            -e dotbytes="$dotbytes" \
            -O "$tmpfile" \
            "$url" || {
                echo "WARNING: Download failed: ${url}"
                rm -f "$tmpfile"
                return 0
            }

        mv "$tmpfile" "$outfile"
        printf "Saved: %s\n" "$outfile"
        return 0
    fi

    wget \
        -qnc \
        --content-disposition \
        --show-progress \
        --tries=3 \
        --timeout=60 \
        --waitretry=5 \
        -e dotbytes="$dotbytes" \
        -P "$dir" \
        "$url" || {
            echo "WARNING: Download failed: ${url}"
            return 0
        }
}

provisioning_start
