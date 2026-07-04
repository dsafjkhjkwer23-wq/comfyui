#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Minimal ANIMA benchmark provisioning for Vast.ai
# Requested only:
#   1) Download ANIMA support models except official bf16 diffusion:
#      - qwen_3_06b_base.safetensors
#      - qwen_image_vae.safetensors
#   2) Download ANIMA INT8 diffusion models:
#      - anima-base-v1.0-int8rowwise.safetensors
#      - anima-base-v1.0-int8convrot.safetensors
#   3) Install custom nodes:
#      - ComfyUI-Spectrum-KSampler
#      - ComfyUI-Anima-BlockCompile
#      - ComfyUI-Anima-PiD
#   4) Optional SageAttention install, non-fatal.
# Nothing else.
# ============================================================

export WORKSPACE="${WORKSPACE:-/workspace}"
export COMFY_ROOT="${COMFY_ROOT:-${WORKSPACE}/ComfyUI}"
CUSTOM_NODES_DIR="${COMFY_ROOT}/custom_nodes"
MODELS_DIR="${COMFY_ROOT}/models"

ARIA2_CONNECTIONS="${ARIA2_CONNECTIONS:-16}"
ARIA2_SPLIT="${ARIA2_SPLIT:-16}"
ARIA2_MIN_SPLIT_SIZE="${ARIA2_MIN_SPLIT_SIZE:-1M}"
INSTALL_SAGEATTENTION="${INSTALL_SAGEATTENTION:-1}"

mkdir -p "${CUSTOM_NODES_DIR}"
mkdir -p "${MODELS_DIR}/text_encoders" \
         "${MODELS_DIR}/vae" \
         "${MODELS_DIR}/diffusion_models/ANIMA"

log() { echo -e "\n== $* =="; }
warn() { echo -e "\n[WARN] $*" >&2; }

# Use the ComfyUI venv when it exists, but do not fail if activation is unavailable.
if [ -f /venv/main/bin/activate ]; then
  # shellcheck disable=SC1091
  . /venv/main/bin/activate || true
fi

log "GPU / CUDA check"
nvidia-smi || true
python - <<'PY' || true
try:
    import torch
    print('torch:', torch.__version__)
    print('cuda:', torch.version.cuda)
    print('gpu:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NO CUDA')
except Exception as e:
    print('torch probe skipped:', repr(e))
PY

log "Install minimal system tools"
apt-get update -y
apt-get install -y git aria2 ca-certificates

clone_or_update() {
  local repo_url="$1"
  local dst="$2"
  if [ -d "${dst}/.git" ]; then
    git -C "${dst}" pull --ff-only || git -C "${dst}" pull --rebase
  else
    git clone "${repo_url}" "${dst}"
  fi
}

install_requirements_only() {
  local dst="$1"
  if [ -f "${dst}/requirements.txt" ]; then
    python -m pip install -r "${dst}/requirements.txt"
  fi
}

hf_aria() {
  local url="$1"
  local out_dir="$2"
  local out_name="$3"
  mkdir -p "${out_dir}"
  if [ -s "${out_dir}/${out_name}" ]; then
    echo "exists: ${out_dir}/${out_name}"
    return 0
  fi

  aria2c \
    -x "${ARIA2_CONNECTIONS}" \
    -s "${ARIA2_SPLIT}" \
    -k "${ARIA2_MIN_SPLIT_SIZE}" \
    --continue=true \
    --max-tries=5 \
    --retry-wait=5 \
    --allow-overwrite=true \
    --auto-file-renaming=false \
    -d "${out_dir}" \
    -o "${out_name}" \
    "${url}"
}

log "Install requested custom nodes only"
clone_or_update "https://github.com/sorryhyun/ComfyUI-Spectrum-KSampler.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Spectrum-KSampler"
install_requirements_only "${CUSTOM_NODES_DIR}/ComfyUI-Spectrum-KSampler"

clone_or_update "https://github.com/sorryhyun/ComfyUI-Anima-BlockCompile.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Anima-BlockCompile"
install_requirements_only "${CUSTOM_NODES_DIR}/ComfyUI-Anima-BlockCompile"

clone_or_update "https://github.com/sorryhyun/ComfyUI-Anima-PiD.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD"
install_requirements_only "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD"

log "Download requested ANIMA support models, excluding official bf16 diffusion model"
hf_aria \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/text_encoders/qwen_3_06b_base.safetensors?download=true" \
  "${MODELS_DIR}/text_encoders" \
  "qwen_3_06b_base.safetensors"

hf_aria \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors?download=true" \
  "${MODELS_DIR}/vae" \
  "qwen_image_vae.safetensors"

log "Download requested ANIMA INT8 diffusion models"
hf_aria \
  "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8rowwise.safetensors?download=true" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "anima-base-v1.0-int8rowwise.safetensors"

hf_aria \
  "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8convrot.safetensors?download=true" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "anima-base-v1.0-int8convrot.safetensors"

log "Install SageAttention, optional and non-fatal"
if [ "${INSTALL_SAGEATTENTION}" = "1" ]; then
  python -m pip install sageattention==2.2.0 --no-build-isolation || \
  warn "SageAttention install failed. Provisioning continues; install it manually later if needed."
else
  echo "INSTALL_SAGEATTENTION=0, skipped."
fi

log "Verify requested files"
ls -lh "${MODELS_DIR}/text_encoders/qwen_3_06b_base.safetensors" || true
ls -lh "${MODELS_DIR}/vae/qwen_image_vae.safetensors" || true
ls -lh "${MODELS_DIR}/diffusion_models/ANIMA/"*int8*.safetensors || true
ls -la "${CUSTOM_NODES_DIR}/ComfyUI-Spectrum-KSampler" | head || true
ls -la "${CUSTOM_NODES_DIR}/ComfyUI-Anima-BlockCompile" | head || true
ls -la "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD" | head || true

cat <<'EOF'

DONE.
Restart ComfyUI completely after provisioning.
EOF
