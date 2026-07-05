#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Vast.ai ComfyUI ANIMA provisioning: default.sh
# - NO EasyUseAnima. Never install ComfyUI-EasyUseAnima here.
# - Installs custom nodes required by attached ANIMA speed JSON + requested additions.
# - Downloads ANIMA INT8 x2, Qwen text encoder, Qwen VAE, and PiD QwenImage checkpoint.
# - SageAttention: installs prebuilt 4090/sm89 wheel if available from your GitHub.
# - SAM: installs Impact Pack/Subpack and prepares models/sams. Non-Facebook SAM URL is env-controlled.
# ============================================================

export WORKSPACE="${WORKSPACE:-/workspace}"
export COMFY_ROOT="${COMFY_ROOT:-${WORKSPACE}/ComfyUI}"
export CUSTOM_NODES_DIR="${COMFY_ROOT}/custom_nodes"
export MODELS_DIR="${COMFY_ROOT}/models"

export ARIA2_CONNECTIONS="${ARIA2_CONNECTIONS:-16}"
export ARIA2_SPLIT="${ARIA2_SPLIT:-16}"
export ARIA2_MIN_SPLIT_SIZE="${ARIA2_MIN_SPLIT_SIZE:-1M}"

# Your repo path for the SageAttention wheel.
# Put the uploaded wheel here in GitHub:
#   config/wheels/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl
export SAGEATTENTION_WHEEL_URL="${SAGEATTENTION_WHEEL_URL:-https://raw.githubusercontent.com/dsafjkhjkwer23-wq/comfyui/main/config/wheels/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl}"
export INSTALL_SAGEATTENTION_WHEEL="${INSTALL_SAGEATTENTION_WHEEL:-1}"

# User requested: not the Facebook-hosted SAM URL.
# Put a non-Facebook mirror URL here when you decide the exact SAM checkpoint.
# Example filename expected by Impact Pack SAMLoader: sam_vit_b_01ec64.pth or compatible.
export SAM_MODEL_URL="${SAM_MODEL_URL:-}"
export SAM_MODEL_NAME="${SAM_MODEL_NAME:-sam_vit_b_01ec64.pth}"

mkdir -p \
  "${CUSTOM_NODES_DIR}" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "${MODELS_DIR}/text_encoders" \
  "${MODELS_DIR}/vae" \
  "${MODELS_DIR}/pid" \
  "${MODELS_DIR}/sams"

log() { echo -e "\n== $* =="; }
warn() { echo -e "\n[WARN] $*"; }

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
    git -C "${dst}" pull --ff-only || git -C "${dst}" pull --rebase
  else
    git clone "${repo_url}" "${dst}"
  fi
}

install_node_deps() {
  local dst="$1"
  if [ -f "${dst}/requirements.txt" ]; then
    python -m pip install -r "${dst}/requirements.txt"
  fi
  if [ -f "${dst}/pyproject.toml" ]; then
    python -m pip install -e "${dst}" || warn "editable install failed for ${dst}; continuing."
  fi
  if [ -f "${dst}/install.py" ]; then
    python "${dst}/install.py" || warn "install.py failed for ${dst}; continuing."
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
    --allow-overwrite=true \
    --auto-file-renaming=false \
    --max-tries=5 \
    --retry-wait=5 \
    -d "${out_dir}" \
    -o "${out_name}" \
    "${url}"
}

activate_venv

log "Install base tools"
apt-get update -y
apt-get install -y \
  aria2 git curl ca-certificates build-essential ninja-build rsync \
  libcusparse-dev-12-9 cuda-libraries-dev-12-9 cuda-cudart-dev-12-9 libcublas-dev-12-9 || true
python -m pip install --upgrade pip setuptools wheel packaging ninja huggingface_hub

log "GPU / Python check"
nvidia-smi || true
python - <<'PY'
import sys, torch
print('python:', sys.version)
print('torch:', torch.__version__)
print('torch cuda:', torch.version.cuda)
print('cuda available:', torch.cuda.is_available())
if torch.cuda.is_available():
    print('gpu:', torch.cuda.get_device_name(0))
    print('capability:', torch.cuda.get_device_capability(0))
PY

log "Install requested / JSON-required custom nodes only"
# Required by attached ANIMA speed JSON
clone_or_update "https://github.com/JPS-GER/ComfyUI_JPS-Nodes.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI_JPS-Nodes"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI_JPS-Nodes"

clone_or_update "https://github.com/jtydhr88/ComfyUI-Workflow-Encrypt.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Workflow-Encrypt"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Workflow-Encrypt"

clone_or_update "https://github.com/ltdrdata/was-node-suite-comfyui.git" \
  "${CUSTOM_NODES_DIR}/was-node-suite-comfyui"
install_node_deps "${CUSTOM_NODES_DIR}/was-node-suite-comfyui"

clone_or_update "https://github.com/sorryhyun/ComfyUI-Spectrum-KSampler.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Spectrum-KSampler"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Spectrum-KSampler"

clone_or_update "https://github.com/sorryhyun/ComfyUI-Anima-BlockCompile.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Anima-BlockCompile"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Anima-BlockCompile"

clone_or_update "https://github.com/kijai/ComfyUI-KJNodes.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-KJNodes"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-KJNodes"

clone_or_update "https://github.com/BobJohnson24/ComfyUI-INT8-Fast.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-INT8-Fast"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-INT8-Fast"

# Requested additions
clone_or_update "https://github.com/sorryhyun/ComfyUI-Anima-PiD.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD"

clone_or_update "https://github.com/r-vage/ComfyUI-RvTools_v2.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-RvTools_v2"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-RvTools_v2"

# SAM support, not EasyUseAnima.
clone_or_update "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Pack"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Pack"

clone_or_update "https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Subpack"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Subpack"

log "Install SageAttention wheel for RTX 4090 / sm89 only"
if [ "${INSTALL_SAGEATTENTION_WHEEL}" = "1" ]; then
  if python - <<'PY'
import sys, torch
ok = torch.cuda.is_available() and torch.cuda.get_device_capability(0) == (8, 9) and sys.version_info[:2] == (3, 12)
raise SystemExit(0 if ok else 1)
PY
  then
    mkdir -p /tmp/sage_wheel
    if aria2c -x 8 -s 8 -k 1M --allow-overwrite=true --auto-file-renaming=false \
      -d /tmp/sage_wheel -o sageattention-2.2.0-cp312-cp312-linux_x86_64.whl \
      "${SAGEATTENTION_WHEEL_URL}"; then
      python -m pip install --force-reinstall /tmp/sage_wheel/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl || \
        warn "SageAttention wheel install failed; continuing."
    else
      warn "SageAttention wheel download failed from ${SAGEATTENTION_WHEEL_URL}; continuing."
    fi
  else
    warn "SageAttention wheel skipped: not Python 3.12 + RTX 4090/sm89."
  fi
fi

log "Download ANIMA requested base models"
hf_aria "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/text_encoders/qwen_3_06b_base.safetensors?download=true" \
  "${MODELS_DIR}/text_encoders" "qwen_3_06b_base.safetensors"

hf_aria "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors?download=true" \
  "${MODELS_DIR}/vae" "qwen_image_vae.safetensors"

hf_aria "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8rowwise.safetensors?download=true" \
  "${MODELS_DIR}/diffusion_models/ANIMA" "anima-base-v1.0-int8rowwise.safetensors"

hf_aria "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8convrot.safetensors?download=true" \
  "${MODELS_DIR}/diffusion_models/ANIMA" "anima-base-v1.0-int8convrot.safetensors"

log "Download PiD QwenImage checkpoint"
if [ ! -s "${MODELS_DIR}/pid/pid_qwenimage_2kto4k_4step.pth" ]; then
  rm -rf /tmp/pid
  hf download nvidia/PiD \
    --local-dir /tmp/pid \
    --include "checkpoints/PiD_res2kto4k_sr4x_official_qwenimage_distill_4step/*" || \
    warn "hf download nvidia/PiD failed; PiD node can still auto-download on first use."
  if [ -s /tmp/pid/checkpoints/PiD_res2kto4k_sr4x_official_qwenimage_distill_4step/model_ema_bf16.pth ]; then
    cp /tmp/pid/checkpoints/PiD_res2kto4k_sr4x_official_qwenimage_distill_4step/model_ema_bf16.pth \
      "${MODELS_DIR}/pid/pid_qwenimage_2kto4k_4step.pth"
  fi
else
  echo "exists: ${MODELS_DIR}/pid/pid_qwenimage_2kto4k_4step.pth"
fi

log "Download SAM model if non-Facebook mirror URL is provided"
if [ -n "${SAM_MODEL_URL}" ]; then
  hf_aria "${SAM_MODEL_URL}" "${MODELS_DIR}/sams" "${SAM_MODEL_NAME}"
else
  warn "SAM_MODEL_URL is empty. Impact Pack/Subpack installed and models/sams prepared, but no Facebook SAM URL was used."
fi

log "Block EasyUseAnima check"
if find "${CUSTOM_NODES_DIR}" -maxdepth 1 -type d -iname '*EasyUseAnima*' | grep -q .; then
  echo "ERROR: EasyUseAnima directory found, removing because it is explicitly banned."
  rm -rf "${CUSTOM_NODES_DIR}"/*EasyUseAnima*
fi

log "Verify installed custom node folders"
for d in \
  ComfyUI_JPS-Nodes \
  ComfyUI-Workflow-Encrypt \
  was-node-suite-comfyui \
  ComfyUI-Spectrum-KSampler \
  ComfyUI-Anima-BlockCompile \
  ComfyUI-KJNodes \
  ComfyUI-INT8-Fast \
  ComfyUI-Anima-PiD \
  ComfyUI-RvTools_v2 \
  ComfyUI-Impact-Pack \
  ComfyUI-Impact-Subpack; do
  test -d "${CUSTOM_NODES_DIR}/${d}" && echo "OK: ${d}" || echo "MISSING: ${d}"
done

log "Verify requested model files"
ls -lh "${MODELS_DIR}/text_encoders/qwen_3_06b_base.safetensors" || true
ls -lh "${MODELS_DIR}/vae/qwen_image_vae.safetensors" || true
ls -lh "${MODELS_DIR}/diffusion_models/ANIMA/"*int8*.safetensors || true
ls -lh "${MODELS_DIR}/pid/"*qwenimage* 2>/dev/null || true
ls -lh "${MODELS_DIR}/sams/"* 2>/dev/null || true

log "DONE"
echo "Restart ComfyUI completely after provisioning."
