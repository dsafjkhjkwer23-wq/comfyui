#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Vast.ai ComfyUI ANIMA benchmark provisioning
# Goal: compare normal workflow vs optimized workflow on the same instance.
# Downloads:
#   - Official ANIMA support files only: Qwen text encoder + Qwen VAE
#   - ANIMA INT8 diffusion models: rowwise + convrot
# Installs:
#   - Spectrum-KSampler
#   - Anima Block Compile
#   - Anima PiD
# Optional:
#   - SageAttention
# Does NOT download official bf16 anima-base-v1.0.safetensors.
# ============================================================

export WORKSPACE="${WORKSPACE:-/workspace}"
export COMFY_ROOT="${COMFY_ROOT:-${WORKSPACE}/ComfyUI}"
export CUSTOM_NODES_DIR="${COMFY_ROOT}/custom_nodes"
export MODELS_DIR="${COMFY_ROOT}/models"

export ARIA2_CONNECTIONS="${ARIA2_CONNECTIONS:-16}"
export ARIA2_SPLIT="${ARIA2_SPLIT:-16}"
export ARIA2_MIN_SPLIT_SIZE="${ARIA2_MIN_SPLIT_SIZE:-1M}"
export INSTALL_SAGEATTENTION="${INSTALL_SAGEATTENTION:-1}"
export INSTALL_EASYUSE_ANIMA="${INSTALL_EASYUSE_ANIMA:-0}"

mkdir -p "${CUSTOM_NODES_DIR}"
mkdir -p "${MODELS_DIR}/diffusion_models/ANIMA" \
         "${MODELS_DIR}/text_encoders" \
         "${MODELS_DIR}/vae" \
         "${MODELS_DIR}/pid"

log() { echo -e "\n== $* =="; }

clone_or_update() {
  local repo_url="$1"
  local dst="$2"
  if [ -d "${dst}/.git" ]; then
    git -C "${dst}" pull --ff-only || git -C "${dst}" pull --rebase
  else
    git clone "${repo_url}" "${dst}"
  fi
}

install_requirements_if_any() {
  local dst="$1"
  if [ -f "${dst}/requirements.txt" ]; then
    python -m pip install -r "${dst}/requirements.txt"
  fi
  if [ -f "${dst}/pyproject.toml" ]; then
    python -m pip install -e "${dst}"
  fi
}

hf_aria() {
  local url="$1"
  local out_dir="$2"
  local out_name="$3"
  if [ -s "${out_dir}/${out_name}" ]; then
    echo "exists: ${out_dir}/${out_name}"
    return 0
  fi
  mkdir -p "${out_dir}"
  aria2c \
    -x "${ARIA2_CONNECTIONS}" \
    -s "${ARIA2_SPLIT}" \
    -k "${ARIA2_MIN_SPLIT_SIZE}" \
    --continue=true \
    --allow-overwrite=true \
    --auto-file-renaming=false \
    -d "${out_dir}" \
    -o "${out_name}" \
    "${url}"
}

log "GPU / CUDA check"
nvidia-smi || true
python - <<'PY'
import torch
print('torch:', torch.__version__)
print('cuda:', torch.version.cuda)
print('gpu:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'NO CUDA')
PY

log "Install downloader/build tools"
apt-get update -y
apt-get install -y aria2 git curl ca-certificates build-essential ninja-build
python -m pip install --upgrade pip setuptools wheel packaging ninja

log "Install custom nodes: Spectrum, BlockCompile, PiD"
clone_or_update "https://github.com/sorryhyun/ComfyUI-Spectrum-KSampler.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Spectrum-KSampler"
install_requirements_if_any "${CUSTOM_NODES_DIR}/ComfyUI-Spectrum-KSampler"

clone_or_update "https://github.com/sorryhyun/ComfyUI-Anima-BlockCompile.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Anima-BlockCompile"
install_requirements_if_any "${CUSTOM_NODES_DIR}/ComfyUI-Anima-BlockCompile"

clone_or_update "https://github.com/sorryhyun/ComfyUI-Anima-PiD.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD"
install_requirements_if_any "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD"

if [ "${INSTALL_EASYUSE_ANIMA}" = "1" ]; then
  log "Install EasyUseAnima, optional"
  clone_or_update "https://github.com/n0va39/ComfyUI-EasyUseAnima.git" \
    "${CUSTOM_NODES_DIR}/ComfyUI-EasyUseAnima"
  install_requirements_if_any "${CUSTOM_NODES_DIR}/ComfyUI-EasyUseAnima"
fi

log "Install SageAttention, optional but recommended for optimized benchmark"
if [ "${INSTALL_SAGEATTENTION}" = "1" ]; then
  python -m pip install sageattention==2.2.0 --no-build-isolation || \
  python -m pip install sageattention --no-build-isolation
fi

log "Download official ANIMA support files, excluding bf16 diffusion model"
hf_aria \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/text_encoders/qwen_3_06b_base.safetensors?download=true" \
  "${MODELS_DIR}/text_encoders" \
  "qwen_3_06b_base.safetensors"

hf_aria \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors?download=true" \
  "${MODELS_DIR}/vae" \
  "qwen_image_vae.safetensors"

log "Download ANIMA INT8 diffusion models"
hf_aria \
  "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8rowwise.safetensors?download=true" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "anima-base-v1.0-int8rowwise.safetensors"

hf_aria \
  "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8convrot.safetensors?download=true" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "anima-base-v1.0-int8convrot.safetensors"

log "Verify"
ls -lh "${MODELS_DIR}/text_encoders/qwen_3_06b_base.safetensors" || true
ls -lh "${MODELS_DIR}/vae/qwen_image_vae.safetensors" || true
ls -lh "${MODELS_DIR}/diffusion_models/ANIMA/"*int8*.safetensors || true
ls -la "${CUSTOM_NODES_DIR}/ComfyUI-Spectrum-KSampler" | head
ls -la "${CUSTOM_NODES_DIR}/ComfyUI-Anima-BlockCompile" | head
ls -la "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD" | head

python - <<'PY'
try:
    import sageattention
    print('sageattention: OK', getattr(sageattention, '__version__', 'unknown'))
except Exception as e:
    print('sageattention: not available or failed:', repr(e))
PY

cat <<'EOF'

DONE.
Restart ComfyUI completely.
Benchmark rule:
  1) Same GPU instance
  2) Same workflow except model/sampler/compile nodes
  3) Same width/height/seed/steps/cfg/sampler/scheduler
  4) Run 1 warm-up, then record 3 runs from ComfyUI console: "Prompt executed in ... seconds"
EOF
