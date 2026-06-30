# ============================================
# ANIMA manual-splice provisioning (minimal)
# - HF downloads: aria2c
# - Civitai downloads: curl
# - Download only what is actually used
# ============================================

set -euo pipefail

COMFY_ROOT="${COMFY_ROOT:-/workspace/ComfyUI}"
CUSTOM_NODES_DIR="$COMFY_ROOT/custom_nodes"
MODELS_DIR="$COMFY_ROOT/models"

mkdir -p "$CUSTOM_NODES_DIR"
mkdir -p "$MODELS_DIR"/{diffusion_models,text_encoders,vae,checkpoints,clip_vision,ipadapter}

clone_or_update () {
  local repo_url="$1"
  local dst="$2"
  if [ -d "$dst/.git" ]; then
    git -C "$dst" pull --ff-only
  else
    git clone "$repo_url" "$dst"
  fi
}

hf_aria () {
  local url="$1"
  local out_dir="$2"
  local out_name="$3"
  mkdir -p "$out_dir"
  aria2c -x 16 -s 16 -k 1M \
    --dir="$out_dir" \
    --out="$out_name" \
    "$url"
}

civitai_curl () {
  local url="$1"
  local out_dir="$2"
  local out_name="$3"
  mkdir -p "$out_dir"
  curl -L "$url" -o "$out_dir/$out_name"
}

# --------------------------------------------
# 1) REQUIRED custom nodes
# --------------------------------------------

# Group control / bookmark / context
clone_or_update "https://github.com/rgthree/rgthree-comfy.git" \
  "$CUSTOM_NODES_DIR/rgthree-comfy"

# ANIMA prompt studio + lora preset
clone_or_update "<EASYUSE-ANIMA-REPO-URL>" \
  "$CUSTOM_NODES_DIR/comfyui-easyuse-anima"

# Image Saver
clone_or_update "https://github.com/alexopus/ComfyUI-Image-Saver.git" \
  "$CUSTOM_NODES_DIR/ComfyUI-Image-Saver"

# PiD
clone_or_update "https://github.com/sorryhyun/ComfyUI-Anima-PiD.git" \
  "$CUSTOM_NODES_DIR/ComfyUI-Anima-PiD"

# IPAdapter (keep only if you actually wire IPAdapter)
clone_or_update "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git" \
  "$CUSTOM_NODES_DIR/ComfyUI_IPAdapter_plus"

# Face/Eye detailer later
clone_or_update "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
  "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack"

# --------------------------------------------
# 2) REQUIRED Hugging Face models (ANIMA core)
# --------------------------------------------

hf_aria \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/anima-base-v1.0.safetensors" \
  "$MODELS_DIR/diffusion_models" \
  "anima-base-v1.0.safetensors"

hf_aria \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/qwen_3_06b_base.safetensors" \
  "$MODELS_DIR/text_encoders" \
  "qwen_3_06b_base.safetensors"

hf_aria \
  "https://huggingface.co/circlestone-labs/Anima/resolve/main/qwen_image_vae.safetensors" \
  "$MODELS_DIR/vae" \
  "qwen_image_vae.safetensors"

# SAM3 model for later Face/Eye detailer
hf_aria \
  "https://huggingface.co/Comfy-Org/sam3.1/resolve/main/sam3.1_multiplex_fp16.safetensors" \
  "$MODELS_DIR/checkpoints" \
  "sam3.1_multiplex_fp16.safetensors"

# --------------------------------------------
# 3) IPAdapter models
# Keep ONLY if you will actually use IPAdapter
# --------------------------------------------

# Current workflow note expects:
# - CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors -> models/clip_vision
# - ip-adapter_sdxl.safetensors -> models/ipadapter
#
# Fill exact HF URLs you choose for those two files before enabling.

# hf_aria "<HF_URL_FOR_CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors>" \
#   "$MODELS_DIR/clip_vision" \
#   "CLIP-ViT-bigG-14-laion2B-39B-b160k.safetensors"

# hf_aria "<HF_URL_FOR_ip-adapter_sdxl.safetensors>" \
#   "$MODELS_DIR/ipadapter" \
#   "ip-adapter_sdxl.safetensors"

# --------------------------------------------
# 4) PiD weight
# Keep node install on, but model predownload is optional for now.
# Upstream post had filename/list churn, so leave this commented
# until you settle the exact release filename you want.
# --------------------------------------------

# hf_aria "<HF_URL_FOR_PID_WEIGHT>" \
#   "$MODELS_DIR/pid" \
#   "pid_qwenimage_2kto4k_4step.pth"

# --------------------------------------------
# 5) Civitai template
# Use only for models you truly attach later.
# Do not download unused LoRAs / checkpoints.
# --------------------------------------------

# civitai_curl \
#   "https://civitai.com/api/download/models/<MODEL_VERSION_ID>" \
#   "$MODELS_DIR/loras" \
#   "<your_lora_name>.safetensors"
