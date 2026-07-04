#!/usr/bin/env bash
set -euo pipefail

# ============================================
# VAST / ComfyUI ANIMA AiO v6.0 + PiD provisioning
# - No IPAdapter install/download
# - HF models via aria2c
# - Civitai template via curl only when explicitly enabled
# - Only default-use models: ANIMA core + SAM3 + PiD
# - AiO v6 custom-node deps are installed so the workflow opens cleanly
# ============================================

export COMFY_ROOT="${COMFY_ROOT:-/workspace/ComfyUI}"
CUSTOM_NODES_DIR="$COMFY_ROOT/custom_nodes"
MODELS_DIR="$COMFY_ROOT/models"

INSTALL_CUSTOM_NODES="${INSTALL_CUSTOM_NODES:-1}"
INSTALL_AIO_V60_DEPS="${INSTALL_AIO_V60_DEPS:-1}"
DOWNLOAD_ANIMA="${DOWNLOAD_ANIMA:-1}"
DOWNLOAD_SAM3="${DOWNLOAD_SAM3:-1}"
DOWNLOAD_PID="${DOWNLOAD_PID:-1}"
DOWNLOAD_OPTIONAL_LLLITE="${DOWNLOAD_OPTIONAL_LLLITE:-0}"
DOWNLOAD_OPTIONAL_UPSCALE="${DOWNLOAD_OPTIONAL_UPSCALE:-0}"
DOWNLOAD_OPTIONAL_COSMOS_LORA="${DOWNLOAD_OPTIONAL_COSMOS_LORA:-0}"
HF_TOKEN="${HF_TOKEN:-}"
CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"

mkdir -p "$CUSTOM_NODES_DIR"
mkdir -p "$MODELS_DIR"/{diffusion_models,text_encoders,vae,checkpoints,pid,controlnet,upscale_models,loras}

apt_install_if_missing () {
  local bin="$1"
  local pkg="$2"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[setup] installing $pkg..."
    apt-get update
    apt-get install -y "$pkg"
  fi
}

clone_or_update () {
  local repo_url="$1"
  local dst="$2"
  if [ -d "$dst/.git" ]; then
    echo "[git pull] $dst"
    git -C "$dst" pull --ff-only || true
  else
    echo "[git clone] $repo_url -> $dst"
    git clone "$repo_url" "$dst"
  fi
}

install_node_requirements () {
  local dst="$1"
  if [ -f "$dst/requirements.txt" ]; then
    echo "[pip] requirements: $dst"
    python -m pip install -r "$dst/requirements.txt"
  fi
  if [ -f "$dst/pyproject.toml" ]; then
    echo "[pip] editable: $dst"
    python -m pip install -e "$dst" || true
  fi
}

hf_aria () {
  local url="$1"
  local out_dir="$2"
  local out_name="$3"
  mkdir -p "$out_dir"
  if [ -f "$out_dir/$out_name" ]; then
    echo "[skip exists] $out_dir/$out_name"
    return 0
  fi
  local header_args=()
  if [ -n "$HF_TOKEN" ]; then
    header_args=(--header="Authorization: Bearer $HF_TOKEN")
  fi
  echo "[hf aria2c] $out_name"
  aria2c -c -x 16 -s 16 -k 1M \
    "${header_args[@]}" \
    --dir="$out_dir" \
    --out="$out_name" \
    "$url"
}

civitai_curl () {
  local model_version_id="$1"
  local out_dir="$2"
  local out_name="$3"
  mkdir -p "$out_dir"
  if [ -f "$out_dir/$out_name" ]; then
    echo "[skip exists] $out_dir/$out_name"
    return 0
  fi
  local url="https://civitai.com/api/download/models/${model_version_id}"
  if [ -n "$CIVITAI_TOKEN" ]; then
    url="${url}?token=${CIVITAI_TOKEN}"
  fi
  echo "[civitai curl] modelVersionId=$model_version_id -> $out_name"
  curl -L --fail --retry 5 --retry-delay 3 \
    "$url" \
    -o "$out_dir/$out_name"
}

apt_install_if_missing aria2c aria2
apt_install_if_missing curl curl
apt_install_if_missing git git

if [ "$INSTALL_CUSTOM_NODES" = "1" ]; then
  # Core workflow/control nodes
  clone_or_update "https://github.com/rgthree/rgthree-comfy.git" \
    "$CUSTOM_NODES_DIR/rgthree-comfy"

  clone_or_update "https://github.com/kijai/ComfyUI-KJNodes.git" \
    "$CUSTOM_NODES_DIR/ComfyUI-KJNodes"
  install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI-KJNodes"

  clone_or_update "https://github.com/n0va39/ComfyUI-EasyUseAnima.git" \
    "$CUSTOM_NODES_DIR/ComfyUI-EasyUseAnima"
  install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI-EasyUseAnima"

  clone_or_update "https://github.com/alexopus/ComfyUI-Image-Saver.git" \
    "$CUSTOM_NODES_DIR/ComfyUI-Image-Saver"
  install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI-Image-Saver"

  # PiD: the only extra node we are bringing in for final upscale/decode.
  clone_or_update "https://github.com/sorryhyun/ComfyUI-Anima-PiD.git" \
    "$CUSTOM_NODES_DIR/ComfyUI-Anima-PiD"
  install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI-Anima-PiD"

  # AiO v6.0 dependencies. These are custom-node packages only; optional section models remain off below.
  if [ "$INSTALL_AIO_V60_DEPS" = "1" ]; then
    clone_or_update "https://github.com/sorryhyun/ComfyUI-Anima-DAVE.git" \
      "$CUSTOM_NODES_DIR/ComfyUI-Anima-DAVE"
    install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI-Anima-DAVE"

    clone_or_update "https://github.com/kohya-ss/ComfyUI-Anima-LLLite.git" \
      "$CUSTOM_NODES_DIR/ComfyUI-Anima-LLLite"
    install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI-Anima-LLLite"

    clone_or_update "https://github.com/namemechan/ComfyUI-DCW.git" \
      "$CUSTOM_NODES_DIR/ComfyUI-DCW"
    install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI-DCW"

    clone_or_update "https://github.com/sorryhyun/ComfyUI-Spectrum-KSampler.git" \
      "$CUSTOM_NODES_DIR/ComfyUI-Spectrum-KSampler"
    install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI-Spectrum-KSampler"

    clone_or_update "https://github.com/ruwwww/ComfyUI-Spectrum-sdxl.git" \
      "$CUSTOM_NODES_DIR/ComfyUI-Spectrum-sdxl"
    install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI-Spectrum-sdxl"

    clone_or_update "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
      "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack"
    install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI-Impact-Pack"

    # AiO v6 still contains a USDU section. Keep the node package only so the workflow can open,
    # but do not download the AnimeSharp upscale model unless DOWNLOAD_OPTIONAL_UPSCALE=1.
    clone_or_update "https://github.com/ssitu/ComfyUI_UltimateSDUpscale.git" \
      "$CUSTOM_NODES_DIR/ComfyUI_UltimateSDUpscale"
    install_node_requirements "$CUSTOM_NODES_DIR/ComfyUI_UltimateSDUpscale"
  fi
fi

# Required ANIMA core, using the AiO v6.0 split_files paths.
if [ "$DOWNLOAD_ANIMA" = "1" ]; then
  hf_aria \
    "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/diffusion_models/anima-base-v1.0.safetensors" \
    "$MODELS_DIR/diffusion_models" \
    "anima-base-v1.0.safetensors"

  hf_aria \
    "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/text_encoders/qwen_3_06b_base.safetensors?download=true" \
    "$MODELS_DIR/text_encoders" \
    "qwen_3_06b_base.safetensors"

  hf_aria \
    "https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors?download=true" \
    "$MODELS_DIR/vae" \
    "qwen_image_vae.safetensors"
fi

# SAM3 for AiO v6 Face/Eye detailer. No legacy sam_vit_b / YOLO models are downloaded.
if [ "$DOWNLOAD_SAM3" = "1" ]; then
  hf_aria \
    "https://huggingface.co/Comfy-Org/sam3.1/resolve/main/sam3.1_multiplex_fp16.safetensors" \
    "$MODELS_DIR/checkpoints" \
    "sam3.1_multiplex_fp16.safetensors"
fi

# PiD weight. You can also rely on AnimaPiDLoader auto-download, but this provisions it directly.
if [ "$DOWNLOAD_PID" = "1" ]; then
  hf_aria \
    "https://huggingface.co/nvidia/PiD/resolve/main/checkpoints/PiD_res2kto4k_sr4x_official_qwenimage_distill_4step/model_ema_bf16.pth" \
    "$MODELS_DIR/pid" \
    "pid_qwenimage_2kto4k_4step.pth"
fi

# Optional AiO section models are off by default.
if [ "$DOWNLOAD_OPTIONAL_LLLITE" = "1" ]; then
  hf_aria \
    "https://huggingface.co/kohya-ss/Anima-LLLite/resolve/main/anima-lllite-inpainting-v1.safetensors" \
    "$MODELS_DIR/controlnet" \
    "anima-lllite-inpainting-v1.safetensors"
fi

if [ "$DOWNLOAD_OPTIONAL_UPSCALE" = "1" ]; then
  hf_aria \
    "https://huggingface.co/Kim2091/2x-AnimeSharpV4/resolve/main/2x-AnimeSharpV4_Fast_RCAN_PU.safetensors?download=true" \
    "$MODELS_DIR/upscale_models" \
    "2x-AnimeSharpV4_Fast_RCAN_PU.safetensors"
fi

if [ "$DOWNLOAD_OPTIONAL_COSMOS_LORA" = "1" ]; then
  hf_aria \
    "https://huggingface.co/hanzogak/Anima-Comradeship/resolve/main/LoRA/Cosmos-Predict2.5-2B-base-distilled-LoRA.safetensors?download=true" \
    "$MODELS_DIR/loras" \
    "Cosmos-Predict2.5-2B-base-distilled-LoRA.safetensors"
fi

# Civitai template. Nothing runs by default.
# civitai_curl "<MODEL_VERSION_ID>" "$MODELS_DIR/loras" "my_anima_lora.safetensors"

echo "==== custom_nodes check ===="
for d in \
  rgthree-comfy \
  ComfyUI-KJNodes \
  ComfyUI-EasyUseAnima \
  ComfyUI-Image-Saver \
  ComfyUI-Anima-PiD \
  ComfyUI-Anima-DAVE \
  ComfyUI-Anima-LLLite \
  ComfyUI-DCW \
  ComfyUI-Spectrum-KSampler \
  ComfyUI-Spectrum-sdxl \
  ComfyUI-Impact-Pack \
  ComfyUI_UltimateSDUpscale
  do
    if [ -d "$CUSTOM_NODES_DIR/$d" ]; then echo "[OK] $d"; else echo "[MISS] $d"; fi
  done

echo
echo "==== model check ===="
for f in \
  "$MODELS_DIR/diffusion_models/anima-base-v1.0.safetensors" \
  "$MODELS_DIR/text_encoders/qwen_3_06b_base.safetensors" \
  "$MODELS_DIR/vae/qwen_image_vae.safetensors" \
  "$MODELS_DIR/checkpoints/sam3.1_multiplex_fp16.safetensors" \
  "$MODELS_DIR/pid/pid_qwenimage_2kto4k_4step.pth"
  do
    if [ -f "$f" ]; then du -h "$f" | awk '{print "[OK] " $2 "  " $1}'; else echo "[MISS] $f"; fi
  done

echo
echo "[done] Restart ComfyUI after provisioning. IPAdapter is intentionally not installed or downloaded."
