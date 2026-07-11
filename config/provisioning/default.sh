#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Vast.ai ComfyUI ANIMA provisioning: default.sh
#
# - NO EasyUseAnima. Never install ComfyUI-EasyUseAnima here.
# - SageAttention is NOT installed or compiled here.
# - SageAttention for RTX 5090/sm120 will be installed manually
#   from the Jupyter Terminal after provisioning.
# - Installs ANIMA workflow custom nodes.
# - Installs INT8-Fast, rgthree Power LoRA Loader, and LLLite.
# - Downloads ANIMA INT8 x2, Qwen text encoder, Qwen VAE,
#   PiD QwenImage checkpoint, and SAM3.1 multiplex checkpoint.
# ============================================================

export WORKSPACE="${WORKSPACE:-/workspace}"
export COMFY_ROOT="${COMFY_ROOT:-${WORKSPACE}/ComfyUI}"
export CUSTOM_NODES_DIR="${COMFY_ROOT}/custom_nodes"
export MODELS_DIR="${COMFY_ROOT}/models"

export ARIA2_CONNECTIONS="${ARIA2_CONNECTIONS:-16}"
export ARIA2_SPLIT="${ARIA2_SPLIT:-16}"
export ARIA2_MIN_SPLIT_SIZE="${ARIA2_MIN_SPLIT_SIZE:-1M}"

# SAM3.1 multiplex checkpoint used by the detailer workflow.
# CheckpointLoaderSimple searches models/checkpoints.
export SAM31_MODEL_URL="${SAM31_MODEL_URL:-https://huggingface.co/Comfy-Org/sam3.1/resolve/main/checkpoints/sam3.1_multiplex_fp16.safetensors?download=true}"
export SAM31_MODEL_NAME="${SAM31_MODEL_NAME:-sam3.1_multiplex_fp16.safetensors}"

mkdir -p \
  "${CUSTOM_NODES_DIR}" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "${MODELS_DIR}/text_encoders" \
  "${MODELS_DIR}/vae" \
  "${MODELS_DIR}/pid" \
  "${MODELS_DIR}/checkpoints" \
  "${MODELS_DIR}/sams" \
  "${MODELS_DIR}/loras"

log() {
  echo -e "\n== $* =="
}

warn() {
  echo -e "\n[WARN] $*"
}

activate_venv() {
  if [ -f /venv/main/bin/activate ]; then
    # shellcheck disable=SC1091
    source /venv/main/bin/activate
  fi
}

clone_or_update() {
  local repo_url="$1"
  local dst="$2"

  if [ -d "${dst}/.git" ]; then
    git -C "${dst}" pull --ff-only || \
      git -C "${dst}" pull --rebase || \
      warn "git update failed for ${dst}; existing checkout retained."
  else
    git clone "${repo_url}" "${dst}"
  fi
}

install_node_deps() {
  local dst="$1"

  if [ -f "${dst}/requirements.txt" ]; then
    python -m pip install -r "${dst}/requirements.txt" || \
      warn "requirements install failed for ${dst}; continuing."
  fi

  if [ -f "${dst}/pyproject.toml" ]; then
    python -m pip install -e "${dst}" || \
      warn "editable install failed for ${dst}; continuing."
  fi

  if [ -f "${dst}/install.py" ]; then
    python "${dst}/install.py" || \
      warn "install.py failed for ${dst}; continuing."
  fi
}

hf_aria() {
  local url="$1"
  local out_dir="$2"
  local out_name="$3"
  local output_path="${out_dir}/${out_name}"

  mkdir -p "${out_dir}"

  if [ -s "${output_path}" ]; then
    echo "exists: ${output_path}"
    return 0
  fi

  aria2c \
    -x "${ARIA2_CONNECTIONS}" \
    -s "${ARIA2_SPLIT}" \
    -k "${ARIA2_MIN_SPLIT_SIZE}" \
    --continue=true \
    --allow-overwrite=true \
    --auto-file-renaming=false \
    --max-tries=5 \
    --retry-wait=5 \
    --timeout=60 \
    --connect-timeout=30 \
    -d "${out_dir}" \
    -o "${out_name}" \
    "${url}"
}

activate_venv

log "Install base tools"

apt-get update -y

apt-get install -y \
  aria2 \
  git \
  curl \
  ca-certificates \
  build-essential \
  ninja-build \
  rsync || true

python -m pip install --upgrade \
  pip \
  setuptools \
  wheel \
  packaging \
  ninja \
  huggingface_hub

log "GPU / Python check"

nvidia-smi || true

python - <<'PY'
import sys

print("python:", sys.version)

try:
    import torch

    print("torch:", torch.__version__)
    print("torch cuda:", torch.version.cuda)
    print("cuda available:", torch.cuda.is_available())

    if torch.cuda.is_available():
        print("gpu:", torch.cuda.get_device_name(0))
        print("capability:", torch.cuda.get_device_capability(0))
except Exception as exc:
    print("torch check failed:", repr(exc))
PY

log "Install ANIMA workflow custom nodes"

clone_or_update \
  "https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI_JPS-Nodes"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI_JPS-Nodes"

clone_or_update \
  "https://github.com/jtydhr88/ComfyUI-Workflow-Encrypt.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Workflow-Encrypt"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Workflow-Encrypt"

clone_or_update \
  "https://github.com/ltdrdata/was-node-suite-comfyui.git" \
  "${CUSTOM_NODES_DIR}/was-node-suite-comfyui"
install_node_deps "${CUSTOM_NODES_DIR}/was-node-suite-comfyui"

clone_or_update \
  "https://github.com/sorryhyun/ComfyUI-Spectrum-KSampler.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Spectrum-KSampler"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Spectrum-KSampler"

clone_or_update \
  "https://github.com/sorryhyun/ComfyUI-Anima-BlockCompile.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Anima-BlockCompile"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Anima-BlockCompile"

clone_or_update \
  "https://github.com/kijai/ComfyUI-KJNodes.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-KJNodes"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-KJNodes"

log "Install INT8-Fast"

clone_or_update \
  "https://github.com/BobJohnson24/ComfyUI-INT8-Fast.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-INT8-Fast"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-INT8-Fast"

log "Install rgthree Power LoRA Loader"

clone_or_update \
  "https://github.com/rgthree/rgthree-comfy.git" \
  "${CUSTOM_NODES_DIR}/rgthree-comfy"
install_node_deps "${CUSTOM_NODES_DIR}/rgthree-comfy"

log "Install ANIMA PiD"

clone_or_update \
  "https://github.com/sorryhyun/ComfyUI-Anima-PiD.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD"

clone_or_update \
  "https://github.com/r-vage/ComfyUI-RvTools_v2.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-RvTools_v2"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-RvTools_v2"

log "Install Impact Pack and Impact Subpack"

clone_or_update \
  "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Pack"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Pack"

clone_or_update \
  "https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Subpack"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Subpack"

log "Install ControlNet LLLite"

clone_or_update \
  "https://github.com/kohya-ss/ControlNet-LLLite-ComfyUI.git" \
  "${CUSTOM_NODES_DIR}/ControlNet-LLLite-ComfyUI"
install_node_deps "${CUSTOM_NODES_DIR}/ControlNet-LLLite-ComfyUI"

mkdir -p \
  "${CUSTOM_NODES_DIR}/ControlNet-LLLite-ComfyUI/models"

log "Download ANIMA requested base models"

hf_aria \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/text_encoders/qwen_3_06b_base.safetensors?download=true" \
  "${MODELS_DIR}/text_encoders" \
  "qwen_3_06b_base.safetensors"

hf_aria \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors?download=true" \
  "${MODELS_DIR}/vae" \
  "qwen_image_vae.safetensors"

hf_aria \
  "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8rowwise.safetensors?download=true" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "anima-base-v1.0-int8rowwise.safetensors"

hf_aria \
  "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8convrot.safetensors?download=true" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "anima-base-v1.0-int8convrot.safetensors"

log "Download PiD QwenImage checkpoint"

PID_OUTPUT="${MODELS_DIR}/pid/pid_qwenimage_2kto4k_4step.pth"

if [ ! -s "${PID_OUTPUT}" ]; then
  rm -rf /tmp/pid

  hf download nvidia/PiD \
    --local-dir /tmp/pid \
    --include \
    "checkpoints/PiD_res2kto4k_sr4x_official_qwenimage_distill_4step/*" || \
    warn "hf download nvidia/PiD failed; PiD may auto-download on first use."

  PID_SOURCE="/tmp/pid/checkpoints/PiD_res2kto4k_sr4x_official_qwenimage_distill_4step/model_ema_bf16.pth"

  if [ -s "${PID_SOURCE}" ]; then
    cp "${PID_SOURCE}" "${PID_OUTPUT}"
  else
    warn "PiD checkpoint source file was not found after download."
  fi
else
  echo "exists: ${PID_OUTPUT}"
fi

log "Download SAM3.1 multiplex checkpoint"

hf_aria \
  "${SAM31_MODEL_URL}" \
  "${MODELS_DIR}/checkpoints" \
  "${SAM31_MODEL_NAME}"

# Keep a compatibility symlink under models/sams without storing
# a second copy. The workflow itself uses CheckpointLoaderSimple,
# so models/checkpoints is the primary location.
if [ -s "${MODELS_DIR}/checkpoints/${SAM31_MODEL_NAME}" ]; then
  ln -sfn \
    "../checkpoints/${SAM31_MODEL_NAME}" \
    "${MODELS_DIR}/sams/${SAM31_MODEL_NAME}"
fi

log "Block EasyUseAnima"

while IFS= read -r banned_dir; do
  [ -n "${banned_dir}" ] || continue
  echo "Removing banned node directory: ${banned_dir}"
  rm -rf "${banned_dir}"
done < <(
  find "${CUSTOM_NODES_DIR}" \
    -maxdepth 1 \
    -type d \
    -iname '*EasyUseAnima*' \
    2>/dev/null || true
)

log "Verify installed custom node folders"

for d in \
  ComfyUI_JPS-Nodes \
  ComfyUI-Workflow-Encrypt \
  was-node-suite-comfyui \
  ComfyUI-Spectrum-KSampler \
  ComfyUI-Anima-BlockCompile \
  ComfyUI-KJNodes \
  ComfyUI-INT8-Fast \
  rgthree-comfy \
  ComfyUI-Anima-PiD \
  ComfyUI-RvTools_v2 \
  ComfyUI-Impact-Pack \
  ComfyUI-Impact-Subpack \
  ControlNet-LLLite-ComfyUI
do
  if [ -d "${CUSTOM_NODES_DIR}/${d}" ]; then
    echo "OK: ${d}"
  else
    echo "MISSING: ${d}"
  fi
done

log "Verify requested model files"

ls -lh \
  "${MODELS_DIR}/text_encoders/qwen_3_06b_base.safetensors" || true

ls -lh \
  "${MODELS_DIR}/vae/qwen_image_vae.safetensors" || true

ls -lh \
  "${MODELS_DIR}/diffusion_models/ANIMA/"*int8*.safetensors || true

ls -lh \
  "${MODELS_DIR}/pid/"*qwenimage* 2>/dev/null || true

ls -lh \
  "${MODELS_DIR}/checkpoints/${SAM31_MODEL_NAME}" || true

ls -lh \
  "${MODELS_DIR}/sams/${SAM31_MODEL_NAME}" || true

log "DONE"

echo "SageAttention was intentionally not installed."
echo "Install and compile RTX 5090/sm120 SageAttention manually in Jupyter Terminal."
echo "Restart ComfyUI completely after provisioning."
