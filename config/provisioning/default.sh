#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Vast.ai ComfyUI ANIMA provisioning: default.sh
# FINAL_REV=2026-07-05-cuda132-official-int8-ready
#
# Target template:
#   vastai/comfy:v0.27.0-cuda-13.2-py312
#
# Notes:
# - NO EasyUseAnima.
# - Removes CUDA 12.9 dev package install block.
# - Keeps RTX 4090 / sm89 / Python 3.12 SageAttention wheel install.
# - Installs ANIMA speed workflow custom nodes.
# - Downloads ANIMA INT8 rowwise + convrot, Qwen text encoder, Qwen VAE, PiD, SAM3.1.
# ============================================================

export WORKSPACE="${WORKSPACE:-/workspace}"
export COMFY_ROOT="${COMFY_ROOT:-${WORKSPACE}/ComfyUI}"
export CUSTOM_NODES_DIR="${COMFY_ROOT}/custom_nodes"
export MODELS_DIR="${COMFY_ROOT}/models"

export ARIA2_CONNECTIONS="${ARIA2_CONNECTIONS:-16}"
export ARIA2_SPLIT="${ARIA2_SPLIT:-16}"
export ARIA2_MIN_SPLIT_SIZE="${ARIA2_MIN_SPLIT_SIZE:-1M}"

strip_outer_quotes() {
  local v="${1:-}"
  v="${v%$'\r'}"
  if [[ "${v}" == \"*\" && "${v}" == *\" ]]; then
    v="${v:1:${#v}-2}"
  fi
  if [[ "${v}" == \'*\' && "${v}" == *\' ]]; then
    v="${v:1:${#v}-2}"
  fi
  printf '%s' "${v}"
}

# SageAttention wheel location in your GitHub repo.
# Put the wheel here:
# config/wheels/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl
export SAGEATTENTION_WHEEL_URL="$(strip_outer_quotes "${SAGEATTENTION_WHEEL_URL:-https://raw.githubusercontent.com/dsafjkhjkwer23-wq/comfyui/main/config/wheels/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl}")"
export INSTALL_SAGEATTENTION_WHEEL="$(strip_outer_quotes "${INSTALL_SAGEATTENTION_WHEEL:-1}")"

export SAM_MODEL_URL="$(strip_outer_quotes "${SAM_MODEL_URL:-https://huggingface.co/Comfy-Org/sam3.1/resolve/main/checkpoints/sam3.1_multiplex_fp16.safetensors?download=true}")"
export SAM_MODEL_NAME="$(strip_outer_quotes "${SAM_MODEL_NAME:-sam3.1_multiplex_fp16.safetensors}")"

mkdir -p \
  "${CUSTOM_NODES_DIR}" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "${MODELS_DIR}/text_encoders" \
  "${MODELS_DIR}/vae" \
  "${MODELS_DIR}/pid" \
  "${MODELS_DIR}/sams"

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
    git -C "${dst}" pull --ff-only || git -C "${dst}" pull --rebase || warn "git pull failed for ${dst}; continuing."
  else
    git clone "${repo_url}" "${dst}" || warn "git clone failed for ${repo_url}; continuing."
  fi
}

install_node_deps() {
  local dst="$1"

  if [ -f "${dst}/requirements.txt" ]; then
    python -m pip install -r "${dst}/requirements.txt" || warn "requirements install failed for ${dst}; continuing."
  fi

  if [ -f "${dst}/pyproject.toml" ]; then
    python -m pip install -e "${dst}" || warn "editable install failed for ${dst}; continuing."
  fi

  if [ -f "${dst}/install.py" ]; then
    python "${dst}/install.py" || warn "install.py failed for ${dst}; continuing."
  fi
}

download_file() {
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
    "${url}" || warn "download failed: ${out_name}"
}

activate_venv

log "Install base tools"
apt-get update -y

apt-get install -y \
  aria2 git curl ca-certificates build-essential ninja-build rsync \
  || warn "base apt packages failed; continuing."

python -m pip install --upgrade pip setuptools wheel packaging ninja huggingface_hub

log "Pin / verify comfy-kitchen for official INT8"
python -m pip install -U comfy-kitchen==0.2.16 || warn "comfy-kitchen install failed; continuing."

log "GPU / Python / backend check"
nvidia-smi || true

python - <<'PY'
import sys
import torch

print("python:", sys.version)
print("torch:", torch.__version__)
print("torch cuda:", torch.version.cuda)
print("cuda available:", torch.cuda.is_available())

if torch.cuda.is_available():
    print("gpu:", torch.cuda.get_device_name(0))
    print("capability:", torch.cuda.get_device_capability(0))
PY

log "Install requested / JSON-required custom nodes only"

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

clone_or_update "https://github.com/sorryhyun/ComfyUI-Anima-PiD.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Anima-PiD"

clone_or_update "https://github.com/r-vage/ComfyUI-RvTools_v2.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-RvTools_v2"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-RvTools_v2"

clone_or_update "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Pack"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Pack"

clone_or_update "https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git" \
  "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Subpack"
install_node_deps "${CUSTOM_NODES_DIR}/ComfyUI-Impact-Subpack"

log "Install SageAttention wheel for RTX 4090 / sm89 only"

if [ "${INSTALL_SAGEATTENTION_WHEEL}" = "1" ]; then
  if python - <<'PY'
import sys
import torch

ok = (
    torch.cuda.is_available()
    and torch.cuda.get_device_capability(0) == (8, 9)
    and sys.version_info[:2] == (3, 12)
)

raise SystemExit(0 if ok else 1)
PY
  then
    mkdir -p /tmp/sage_wheel

    if aria2c \
      -x 8 \
      -s 8 \
      -k 1M \
      --allow-overwrite=true \
      --auto-file-renaming=false \
      -d /tmp/sage_wheel \
      -o sageattention-2.2.0-cp312-cp312-linux_x86_64.whl \
      "${SAGEATTENTION_WHEEL_URL}"; then

      python -m pip install --force-reinstall /tmp/sage_wheel/sageattention-2.2.0-cp312-cp312-linux_x86_64.whl || \
        warn "SageAttention wheel install failed; continuing."
    else
      warn "SageAttention wheel download failed from ${SAGEATTENTION_WHEEL_URL}; continuing."
    fi
  else
    warn "SageAttention wheel skipped: not Python 3.12 + RTX 4090/sm89."
  fi
else
  warn "INSTALL_SAGEATTENTION_WHEEL is not 1; skipping SageAttention wheel."
fi

log "Download ANIMA requested base models"

download_file \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/text_encoders/qwen_3_06b_base.safetensors?download=true" \
  "${MODELS_DIR}/text_encoders" \
  "qwen_3_06b_base.safetensors"

download_file \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors?download=true" \
  "${MODELS_DIR}/vae" \
  "qwen_image_vae.safetensors"

download_file \
  "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8rowwise.safetensors?download=true" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "anima-base-v1.0-int8rowwise.safetensors"

download_file \
  "https://huggingface.co/Bedovyy/Anima-INT8/resolve/main/anima-base-v1.0-int8convrot.safetensors?download=true" \
  "${MODELS_DIR}/diffusion_models/ANIMA" \
  "anima-base-v1.0-int8convrot.safetensors"

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

log "Download SAM3.1 model"

download_file \
  "${SAM_MODEL_URL}" \
  "${MODELS_DIR}/sams" \
  "${SAM_MODEL_NAME}"

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

log "Final backend smoke test"

python - <<'PY'
try:
    import comfy.quant_ops
    import comfy_kitchen as ck
    import torch

    print("torch:", torch.__version__)
    print("torch cuda:", torch.version.cuda)
    print("comfy_kitchen:", getattr(ck, "__version__", "unknown"))
    print("backends:", ck.list_backends())
except Exception as e:
    print("backend smoke test failed:", repr(e))
PY

log "DONE"
echo "Restart ComfyUI completely after provisioning."
