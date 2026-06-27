#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Vast.ai ComfyUI ANIMA provisioning: default.sh
# - ComfyUI version pin
# - Manager security config: weak + git/pip install flags
# - Custom nodes clone/update + requirements install
# - LoRA Manager/RvTools optional lookup through ComfyUI-Manager DB
# - Core models via aria2 + Civitai LoRA via parallel curl
# - Workflow JSON is NOT embedded or installed; import/upload it manually in ComfyUI
#
# Docker Options example:
#   -e HF_TOKEN=... -e CIVITAI_TOKEN=... -e COMFYUI_VERSION=v0.20.1 \
#   -e COMFYUI_ARGS="--disable-auto-launch --port 18188 --enable-cors-header --disable-xformers --enable-manager --disable-dynamic-vram"
# ============================================================

export WORKSPACE="${WORKSPACE:-/workspace}"
export COMFYUI_DIR="${COMFYUI_DIR:-${WORKSPACE}/ComfyUI}"
export COMFYUI_VERSION="${COMFYUI_VERSION:-v0.20.1}"
export COMFYUI_MANAGER_SECURITY_LEVEL="${COMFYUI_MANAGER_SECURITY_LEVEL:-weak}"
export COMFYUI_MANAGER_ALLOW_GIT_URL_INSTALL="${COMFYUI_MANAGER_ALLOW_GIT_URL_INSTALL:-true}"
export COMFYUI_MANAGER_ALLOW_PIP_INSTALL="${COMFYUI_MANAGER_ALLOW_PIP_INSTALL:-true}"
export COMFYUI_MANAGER_NETWORK_MODE="${COMFYUI_MANAGER_NETWORK_MODE:-public}"
export COMFYUI_MANAGER_BYPASS_SSL="${COMFYUI_MANAGER_BYPASS_SSL:-False}"
export RUN_NODE_INSTALL_PY="${RUN_NODE_INSTALL_PY:-true}"

# aria2 tuning
export ARIA2_CONNECTIONS="${ARIA2_CONNECTIONS:-16}"
export ARIA2_SPLIT="${ARIA2_SPLIT:-16}"
export ARIA2_CONCURRENT_DOWNLOADS="${ARIA2_CONCURRENT_DOWNLOADS:-4}"
export ARIA2_MIN_SPLIT_SIZE="${ARIA2_MIN_SPLIT_SIZE:-1M}"
export ARIA2_MAX_TRIES="${ARIA2_MAX_TRIES:-5}"
export ARIA2_RETRY_WAIT="${ARIA2_RETRY_WAIT:-5}"
export ARIA2_TIMEOUT="${ARIA2_TIMEOUT:-60}"
export ARIA2_CONNECT_TIMEOUT="${ARIA2_CONNECT_TIMEOUT:-30}"

# Civitai tuning
# Civitai signed B2 URLs often fail with aria2 multi-range downloads.
# Keep each Civitai file as a single curl stream, but download several files in parallel.
export CIVITAI_PARALLEL_DOWNLOADS="${CIVITAI_PARALLEL_DOWNLOADS:-4}"

APT_PACKAGES=(
    git
    curl
    wget
    aria2
    jq
    ca-certificates
)

PIP_PACKAGES=(
    GitPython
    matrix-client
)

# ------------------------------------------------------------
# Custom nodes
# ------------------------------------------------------------
CUSTOM_NODES=(
    # basics / manager
    "https://github.com/ltdrdata/ComfyUI-Manager"

    # nodes visible/used by ANIMA v5/v5.5 workflow
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/yolain/ComfyUI-Easy-Use"
    "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
    "https://github.com/ssitu/ComfyUI_UltimateSDUpscale"
    "https://github.com/WASasquatch/was-node-suite-comfyui"
    "https://github.com/alexopus/ComfyUI-Image-Saver"
    "https://github.com/ltdrdata/ComfyUI-Inspire-Pack"

    # ANIMA v5 manual nodes
    "https://github.com/sorryhyun/ComfyUI-Spectrum-KSampler"
    "https://github.com/DNT-LAB/comfyui-naia-bridge"
    "https://github.com/namemechan/ComfyUI-DCW"
    "https://github.com/kohya-ss/ComfyUI-Anima-LLLite"
    "https://github.com/ruwwww/ComfyUI-Spectrum-sdxl"

    # ANIMA v5.5 manual node
    "https://github.com/n0va39/ComfyUI-EasyUseAnima"
)

# Optional nodes resolved dynamically from ComfyUI-Manager custom-node-list.json.
# LoRA manager repo names can change, so this tries Manager DB first.
MANAGER_NODE_QUERIES=(
    "ComfyUI-Lora-Manager"
    "LoRA Manager"
    "RvTools"
    "ComfyUI-RvTools"
    "ComfyUI-RvTools_X2"
)

# ------------------------------------------------------------
# Core models referenced by the uploaded workflow note.
# Only direct URLs are enabled here. Page-style Civitai URLs can be
# resolved with civitai-model:<modelId> when CIVITAI_TOKEN is set.
# ------------------------------------------------------------
TEXT_ENCODER_MODELS=(
    "qwen_3_06b_base.safetensors|https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/text_encoders/qwen_3_06b_base.safetensors?download=true"
)

DIFFUSION_MODELS=(
    "anima-base-v1.0.safetensors|https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/diffusion_models/anima-base-v1.0.safetensors"
)

VAE_MODELS=(
    "qwen_image_vae.safetensors|https://huggingface.co/circlestone-labs/Anima/resolve/main/split_files/vae/qwen_image_vae.safetensors?download=true"
    # Optional resolver example; enable if needed after confirming file name:
    # "QwenimageVAE_liquid1087.safetensors|civitai-model:2487530"
)

LORA_UTIL_MODELS=(
    "dmd2_sdxl_4step_lora.safetensors|https://civitai.com/api/download/models/1820705?type=Model&format=SafeTensor"
    "Cosmos-Predict2.5-2B-base-distilled-LoRA.safetensors|https://huggingface.co/hanzogak/Anima-Comradeship/resolve/main/LoRA/Cosmos-Predict2.5-2B-base-distilled-LoRA.safetensors?download=true"
)

UPSCALE_MODELS=(
    "2x-AnimeSharpV4_Fast_RCAN_PU.safetensors|https://huggingface.co/Kim2091/2x-AnimeSharpV4/resolve/main/2x-AnimeSharpV4_Fast_RCAN_PU.safetensors?download=true"
)

ULTRALYTICS_SEGM_MODELS=(
    "yolo11m-seg.pt|https://huggingface.co/Ultralytics/YOLO11/resolve/365ed86341e7a7456dbc4cafc09f138814ce9ff1/yolo11m-seg.pt?download=true"
)

ULTRALYTICS_BBOX_MODELS=(
    # This resolves the latest/primary file from the Civitai model page.
    # If it picks the wrong file, replace with a direct api/download modelVersion URL.
    "pussy_yolov8v.pt|civitai-model:1835837"
)

# Format:
#   "filename|url"
# filename을 고정해야 workflow의 LoraLoader에서 바로 잡힙니다.
LORA_MODELS=(

    # ============================================================
    # Clothing
    # ============================================================

    # ------------------------------------------------------------
    # Clothing / Swimwear
    # ------------------------------------------------------------

    # Clothing / Swimwear / Base:Anima / X字マイクロビキニ/X micro bikini(SD,XL,illustrious,pony) / v1.0 anima
    "x micro bikini_anima_V1.0.safetensors|https://civitai.com/api/download/models/2922829?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / 競泳水着/competitive swimsuit(SD,XL,ill,pony) / v1.0 anima
    "competitive swimsuit_anima_V1.0.safetensors|https://civitai.com/api/download/models/2944201?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / スク水/school swimsuit(XL,ill,pony) / v1.0 anima
    "old school swimsuit_anime_V1.0.safetensors|https://civitai.com/api/download/models/2922767?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / メイドビキニ/maid bikini / v1.0 anima
    "maid bikini_anima_V1.0.safetensors|https://civitai.com/api/download/models/3055885?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Mesh Striped Slingshot Swimsuit / anima
    "MeshStripedSlingshotSwimsuitAnima.safetensors|https://civitai.com/api/download/models/3044038?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / 旧旧スクール水着/more old school swimsuit / v1.0 anima
    "more old school swimsuit_anima_V1.0.safetensors|https://civitai.com/api/download/models/2991570?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Slavekini, aka Slave Leia Outfit - Clothing [Anima, IL, Pony, SDXL] / Anima
    "slavekini_anima.safetensors|https://civitai.com/api/download/models/3002382?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Nipple Suspension Bikini ニプルフックビキニ - Anima P / v1.0 AP3
    "NippleSuspensionBikini_AnimaP_v01-000025.safetensors|https://civitai.com/api/download/models/2939080?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Crotchless Swimsuit for ZiT/Chroma/IL/PONY/NoobAI/Qwen/Anima / v1.0Anima-base-LoKr
    "CrotchlessSwimsuitAnimaBase-LoKr.safetensors|https://civitai.com/api/download/models/3032066?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Sling Swimsuit / sling one-piece swimsuit  [サイドカットスク水] / v1.0 [Anima]
    "sling_swimsuit.safetensors|https://civitai.com/api/download/models/3059892?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Micro Slingshot Bikini / Anima v1.0
    "M1cr0Sl1ng_Anim_v10.safetensors|https://civitai.com/api/download/models/3037083?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Zipper bikini / Anima
    "ZipperBikiniTG-000010.safetensors|https://civitai.com/api/download/models/2931588?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Spicy Hot Y2K Snake Print Swimsuit / anima
    "SpicyHotY2KSnakePrintSwimsuitAnima.safetensors|https://civitai.com/api/download/models/3036969?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / I-front Slingshot Swimsuit(IL) / Anima
    "IfrontAnimaV1.safetensors|https://civitai.com/api/download/models/3005584?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Lace-trimmed slingshot swimsuit 蕾丝边弹弓泳装，真蕾！for Anima ZiT & IL / anima v1.0
    "Lace-trimmed_slingshot_swimsuit_e60.safetensors|https://civitai.com/api/download/models/3007900?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Axolotl Swimsuit / anima
    "AxolotlSwimsuitAnima.safetensors|https://civitai.com/api/download/models/3027502?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Yu-Gi-Oh! - Millennium Eye Egyptian Bikini Lingerie - Anima + IL + ZIT / Anima
    "millennium_anima.safetensors|https://civitai.com/api/download/models/2981547?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Dragonfruit Swimsuit / anima
    "DragonfruitSwimsuitAnima.safetensors|https://civitai.com/api/download/models/3027552?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / [Anima Preview] hny swimsuit 2026 peony - Dolphin Wave / v0.1(Preview3)
    "hny-2026-peony_dw_anima_v0_1.safetensors|https://civitai.com/api/download/models/2925865?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / KK-75 Swimsuit / v1
    "KK-75_Swimsuit_Anima_v1-000003.safetensors|https://civitai.com/api/download/models/2990892?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Rubber1zed Swimsuit / Anima v1
    "Rubber1zed_Swimsuit_Anima_v1-000003.safetensors|https://civitai.com/api/download/models/2996934?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Lum's Bikini / Anima
    "Lum_Bikini_Anima.safetensors|https://civitai.com/api/download/models/3052504?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Sakayori Iroha (swim suite) / Cosmic Princess Kaguya! / Anima1.0
    "Anima-CPK-SwimSuiteIroha01.safetensors|https://civitai.com/api/download/models/3051523?type=Model&format=SafeTensor"

    # Clothing / Swimwear / Base:Anima / Ayatsumugi Roka (swim suite) / Cosmic Princess Kaguya! / Anima1.0
    "Anima-CPK-SwimSuiteRoka01.safetensors|https://civitai.com/api/download/models/3051496?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Lingerie & Underwear
    # ------------------------------------------------------------

    # Clothing / Lingerie & Underwear / Base:Anima / g-string / Clothing LoRA / v5.0 Anima Base v1.0 base
    "LoRAGStringAnimaV1.safetensors|https://civitai.com/api/download/models/2978201?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / 女児下着/girl's underwear(XL,ill,Pony) / v1.0 anima
    "girl underwear_anima_V1.0.safetensors|https://civitai.com/api/download/models/2951737?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / セクシーランジェリー/babydoll,sexy lingerie(SD,ILL,pony) / v1.0 anima
    "babydoll.safetensors|https://civitai.com/api/download/models/2881597?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / 猫ランジェリー/cat lingerie / v1.0 anima
    "cat lingerie_anima_V1.0.safetensors|https://civitai.com/api/download/models/2939201?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Halter Open Slip Lingerie / anima
    "HalterOpenSlipLingerieAnima.safetensors|https://civitai.com/api/download/models/3057484?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / アンダースコート/knickers(XL,ILL,pony) / v1.0 anima
    "undercoat_anima_V1.0.safetensors|https://civitai.com/api/download/models/2914736?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Lyvie Teddy Lingerie / anima
    "LyvieTeddyLingerieAnima.safetensors|https://civitai.com/api/download/models/3051489?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / スポーツブラ/sports bra(XL,ILL,pony) / v1.0 anima
    "sprots bra_anima_V1.0.safetensors|https://civitai.com/api/download/models/2909319?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / dudou-anima; 肚兜 / v1.0
    "dudou-anima.safetensors|https://civitai.com/api/download/models/2963563?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Japanese Floral Lingerie for Anima + IL - Wacoal ワコール Salute / Anima
    "JFL.safetensors|https://civitai.com/api/download/models/2973828?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Silk Babydoll Lingerie / anima
    "SilkBabydollLingerieAnima.safetensors|https://civitai.com/api/download/models/3058183?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Victoria's Secret Bombshell Bra - Classic Push-up Bra Lingerie [Anima, F.2K9B, Pony, IL, SDXL, Flux] / Anima
    "bombshell_anima.safetensors|https://civitai.com/api/download/models/2988353?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / 超ローライズショーツ / Super lowleg panties / anima v1.0
    "lowleg-anima.safetensors|https://civitai.com/api/download/models/3008586?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Ruched Sheer Negligee / anima
    "RuchedSheerNegligeeAnima.safetensors|https://civitai.com/api/download/models/3014128?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Seduluxe Lace Lingerie Set / anima
    "SeduluxeLaceLingerieSetAnima.safetensors|https://civitai.com/api/download/models/3037021?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / ボクサーパンツ/boxer panties / v1.0 anima
    "boxer panties_anima_V1.0.safetensors|https://civitai.com/api/download/models/2951752?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Wisteria Gothic Lingerie Set / anima
    "WisteriaGothicLingerieSetAnima.safetensors|https://civitai.com/api/download/models/2980089?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / 【COSTUME】Lace Bandeau Lingerie / anima
    "lacebandeaulingerie_anima.safetensors|https://civitai.com/api/download/models/2964322?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Backlit Evening Negligee / anima
    "BacklitEveningNegligeeAnima.safetensors|https://civitai.com/api/download/models/2957271?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / 【COSTUME】Pleated Lace Babydoll / anima
    "pleatedlacebabydoll_anima.safetensors|https://civitai.com/api/download/models/2961951?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / 【COSTUME】Satin Lingerie Set / anima
    "satinlingerieset_anima.safetensors|https://civitai.com/api/download/models/2958997?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Celestial Spark Lingerie / anima
    "CelestialSparkLingerieAnima.safetensors|https://civitai.com/api/download/models/2979844?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Eternal Blossom Lingerie / anima
    "EternalBlossomLingerieAnima.safetensors|https://civitai.com/api/download/models/2983586?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Cupless Bustier Mesh Lingerie Set / anima
    "CuplessBustierMeshLingerieSetAnima.safetensors|https://civitai.com/api/download/models/2963764?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Gold Floral Negligee / anima
    "GoldFloralNegligeeAnima.safetensors|https://civitai.com/api/download/models/2965501?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Blood Moon Lingerie Set / anima
    "BloodMoonLingerieSetAnima.safetensors|https://civitai.com/api/download/models/2958100?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Firey Lily Lingerie Set / anima
    "FireyLilyLingerieSetAnima.safetensors|https://civitai.com/api/download/models/2963998?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Batman Lingerie Set / anima
    "BatmanLingerieSetAnima.safetensors|https://civitai.com/api/download/models/3037069?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Firey Lily Lingerie Skirt Set / anima
    "FireyLilyLingerieSkirtSetAnima.safetensors|https://civitai.com/api/download/models/2964052?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Halloween_Dare_Succubus_Lingerie / v1.0
    "m44aafft_hdsl_1202_oizf_Anima_halloween_dare_succubus_lingerie-000005.safetensors|https://civitai.com/api/download/models/2920451?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / 【COSTUME】See-Through Lace Lingerie / anima
    "sheerlacelingerie_anima.safetensors|https://civitai.com/api/download/models/3033541?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Mint Trim Ruffled Red Velvet Lingerie / anima
    "MintTrimRuffledRedVelvetLingerieAnima.safetensors|https://civitai.com/api/download/models/2975186?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Neon Angel Lingerie Set / anima
    "NeonAngelLingerieSetAnima.safetensors|https://civitai.com/api/download/models/2975208?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / 【COSTUME】Off-Shoulder Lingerie / anima
    "offshoulderlingerie_anima.safetensors|https://civitai.com/api/download/models/3033662?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Metal Cupless Lingerie Set / anima
    "MetalCuplessLingerieSetAnima.safetensors|https://civitai.com/api/download/models/2975145?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Fufu Noir Haute Lingerie / anima
    "FufuNoirHauteLingerieAnima.safetensors|https://civitai.com/api/download/models/2965395?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Chinese bra-top and microskirt / Anima
    "minitopandmicroskirt2anima.safetensors|https://civitai.com/api/download/models/2952220?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Gaping bra Anima / Anima
    "GMV5QCJN7237JYDD48YHRH2P10.safetensors|https://civitai.com/api/download/models/3055034?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Superman Lingerie Set / anima
    "SupermanLingerieSetAnima.safetensors|https://civitai.com/api/download/models/3041648?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Punk Pinned Mesh Negligee / anima
    "PunkPinnedMeshNegligeeAnima.safetensors|https://civitai.com/api/download/models/2975481?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Glowing Frills Lingerie / anima
    "GlowingFrillsLingerieAnima.safetensors|https://civitai.com/api/download/models/2985802?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / 【COSTUME】Diamond Fringe Lingerie / anima
    "diamondbrathong_anima.safetensors|https://civitai.com/api/download/models/3068781?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Babydoll Bride | Somehow, with Modesty | ANIMA / ANIMA
    "Outfit_soph-BabydollBride-ANIMA.safetensors|https://civitai.com/api/download/models/2974517?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Chinese Lantren Lingerie / anima
    "ChineseLantrenLingerieAnima.safetensors|https://civitai.com/api/download/models/2985847?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / 【COSTUME】Tulle Layered Babydoll / anima
    "tullelayeredbabydoll_anima.safetensors|https://civitai.com/api/download/models/2963741?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Blacked Underwear LoRA (Anima Base 1) / v1.0
    "blackedclothing-step00001500.safetensors|https://civitai.com/api/download/models/2971309?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Hamburger Lingerie / anima
    "HamburgerLingerieAnima.safetensors|https://civitai.com/api/download/models/3051561?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Paint Brust Stroke Leather Lingerie Set / anima
    "PaintBrustStrokeLeatherLingerieSetAnima.safetensors|https://civitai.com/api/download/models/2975252?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / PSD Underwear [Anima] / v1.0
    "psd-step00001500.safetensors|https://civitai.com/api/download/models/2935507?type=Model&format=SafeTensor"

    # Clothing / Lingerie & Underwear / Base:Anima / Sea Sick Brain Lingerie Set / anima
    "SeaSickBrainLingerieSetAnima.safetensors|https://civitai.com/api/download/models/2979974?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Dress & Skirt
    # ------------------------------------------------------------

    # Clothing / Dress & Skirt / Base:Anima / y-string dress / v1.0 [Anima]
    "y_string_dress_anima.safetensors|https://civitai.com/api/download/models/3029164?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Dirndl / anima
    "DirndlAnima.safetensors|https://civitai.com/api/download/models/3031627?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Modakawa Dress / anima
    "ModakawaDressAnima.safetensors|https://civitai.com/api/download/models/2980410?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / ウェディングドレス/wedding dress(SD,XL,ill,pony) / v1.0 anime
    "wedding dress_anima_V1.0.safetensors|https://civitai.com/api/download/models/2922740?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Cute Maid Croptop Miniskirt / anima
    "CuteMaidCroptopMiniskirtAnima.safetensors|https://civitai.com/api/download/models/3015717?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / o-ring dress ビッチ化 [XL, pony,illus, ANIMA] / anima-preview3-base
    "sato_o_uuki.safetensors|https://civitai.com/api/download/models/3040227?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / スーツ(スカート)/suit(skirt)(SD,ill,pony) / v1.0 anima
    "suit skirt_anima_V1.0.safetensors|https://civitai.com/api/download/models/2980263?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / armored dress 鎧裝禮服  アーマードレス / ANIMA
    "Armored_dress_V03.safetensors|https://civitai.com/api/download/models/2975898?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Plunging Long Dress / anima
    "plunginglongdress_anima.safetensors|https://civitai.com/api/download/models/2963667?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Maid Costumes - AHS Maid / anima
    "AHSMaidDressAnima.safetensors|https://civitai.com/api/download/models/3015776?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Deep Plunging Neckline Handkerchief Dress / anima
    "DeepPlungingNecklineHandkerchiefDressAnima.safetensors|https://civitai.com/api/download/models/3048373?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Love Me Not Dress / anima
    "LoveMeNotDressAnima.safetensors|https://civitai.com/api/download/models/3028371?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Plunging Neckline Satin Gown / anima
    "PlungingNecklineSatinGownAnima.safetensors|https://civitai.com/api/download/models/2988582?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Patbo Long Chain Panel Dress / anima
    "PatboLongChainPanelDressAnima.safetensors|https://civitai.com/api/download/models/3052014?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Parabolas Curves Dress / anima
    "ParabolasCurvesDressAnima.safetensors|https://civitai.com/api/download/models/3051682?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Long Leather Corset Hobble Dress / anima
    "LongLeatherCorsetHobbleDressAnima.safetensors|https://civitai.com/api/download/models/3028529?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Sheer Flower Dress / anima
    "SheerFlowerDressAnima.safetensors|https://civitai.com/api/download/models/2988550?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Off Shoulder Long Mermaid Dress / anima
    "OffShoulderLongMermaidDressAnima.safetensors|https://civitai.com/api/download/models/2988874?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Princess Of The Nile 1954 Dress / anima
    "PrincessOfTheNile1954DressAnima.safetensors|https://civitai.com/api/download/models/3022022?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Plunging Glitter Dress / anima
    "plungingglitterdress_anima.safetensors|https://civitai.com/api/download/models/3024113?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Chronopattern Dress Outfit / v1.0
    "m44aafft_cd_5687_vhki_Anima_chronopattern_dress-000001.safetensors|https://civitai.com/api/download/models/2920390?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Cinched Waist Ditsy Floral Dress / anima
    "CinchedWaistDitsyFloralDressAnima.safetensors|https://civitai.com/api/download/models/3018563?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Pelvic curtain high slit dress / v1.0
    "maretyu_dress_v1.safetensors|https://civitai.com/api/download/models/2937661?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Inequalities Single Sleeve Dress / anima
    "InequalitiesSingleSleeveDressAnima.safetensors|https://civitai.com/api/download/models/3048856?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Quilted Red Rose Jacket Gown / anima
    "QuiltedRedRoseJacketGownAnima.safetensors|https://civitai.com/api/download/models/2975447?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / White Horse Princess Dress / anima
    "WhiteHorsePrincessDressAnima.safetensors|https://civitai.com/api/download/models/3019943?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Crochet Cutout Beach Dress / anima
    "CrochetCutoutBeachDressAnima.safetensors|https://civitai.com/api/download/models/2961294?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Les Amours De Lady Hamilton - 1968 - White Dress / anima
    "LesAmoursDeLadyHamilton1968Anima.safetensors|https://civitai.com/api/download/models/3022071?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Bicolour Rose Petal Gown / anima
    "BicolourRosePetalGownAnima.safetensors|https://civitai.com/api/download/models/2937929?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / マーメイドウェディングドレス/mermaid wedding dress / v1.0 anima
    "wedding dress mermaid_anima_V1.0.safetensors|https://civitai.com/api/download/models/2961572?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Rhinestone Denim Miniskirt & Tube Top / anima
    "RhinestoneDenimMiniskirtTubeTopAnima.safetensors|https://civitai.com/api/download/models/3057177?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Satin & Mesh Micro Skirt / anima
    "SatinMeshMicroSkirtAnima.safetensors|https://civitai.com/api/download/models/3055284?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Woah Baby Satin Mini Dress Cone Detail / anima
    "WoahBabySatinMiniDressConeDetailAnima.safetensors|https://civitai.com/api/download/models/3024407?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Modakawa Dress Outfit / v1.0
    "m44aafft_md_1783_fhpx_Anima_modakawa_dress-000004.safetensors|https://civitai.com/api/download/models/2920475?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Gilded Fay Gown / anima
    "GildedFayGownAnima.safetensors|https://civitai.com/api/download/models/2985772?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Marilyn Monroe Happy Birthday Mr.President Dress / anima
    "MarilynMonroeHappyBirthdayMrPresidentDressAnima.safetensors|https://civitai.com/api/download/models/3019845?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / latex & Mesh Dress / anima
    "LatexMeshDressAnima.safetensors|https://civitai.com/api/download/models/3048591?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Met Gala 2026 - Dior - Filmstrip Dress / anima
    "MetGala2026DiorFilmstripDressAnima.safetensors|https://civitai.com/api/download/models/3021364?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Cross Halter Tubetop & Skirt / anima
    "CrossHalterTubetopSkirtAnima.safetensors|https://civitai.com/api/download/models/2951833?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Son Of Paleface 1952 Dress / anima
    "SonOfPaleface1952DressAnima.safetensors|https://civitai.com/api/download/models/3019702?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Wrapped Halter Dress / anima
    "wrappedhalter_anima.safetensors|https://civitai.com/api/download/models/3033564?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Blue Chiffon Dress / anima
    "ruffledchiffondress_anima.safetensors|https://civitai.com/api/download/models/2958971?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Brown Dress and Bolero (Illustrious) / anima
    "brownbolerodress_anima.safetensors|https://civitai.com/api/download/models/3068809?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Dongtan Dress Outfit / v1.0
    "m44aafft_dd_6184_otby_Anima_dongtan_dress.safetensors|https://civitai.com/api/download/models/2920414?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Kana Lili Bridal Dancing Dress Set / anima
    "KanaLiliBridalDancingDressSetAnima.safetensors|https://civitai.com/api/download/models/3021993?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Nipple piercing dress [Anima] / Anima [3500 steps]
    "nipple_piercing_dress_3500steps.safetensors|https://civitai.com/api/download/models/2725488?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / [Malebolgia] Custom Goober 65 (Custom My 'Actual' Self Crossdressing Halloween Costume 'synthetic' dataset Style And Costume) Anima / v1.0
    "[Malebolgia] Custom Goober 65 (Custom My 'Actual' Self Crossdressing Halloween Costume 'synthetic' dataset Style And Costume) Anima.safetensors|https://civitai.com/api/download/models/3006256?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / French Cancan 1955 Ribbon Dress / anima
    "FrenchCancan1955RibbonDressAnima.safetensors|https://civitai.com/api/download/models/3019543?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Sheer Dress / anima
    "sheerdress_anima.safetensors|https://civitai.com/api/download/models/2964260?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Audrey Hepburn's Dress - My Fair Lady - 1964 / anima
    "AudreyHepburnsDressMyFairLady1964Anima.safetensors|https://civitai.com/api/download/models/3019517?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Long Lace-Sleeved Dress / anima
    "longlacedress_anima.safetensors|https://civitai.com/api/download/models/3036038?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Lace Corset w/ Layered Skirt / anima
    "LaceCorsetLayeredSkirtAnima.safetensors|https://civitai.com/api/download/models/3048548?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Sheer Collar Dress / anima
    "sheercollardress_anima.safetensors|https://civitai.com/api/download/models/3040912?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】V-Neck Dress / anima
    "vneckdress_anima.safetensors|https://civitai.com/api/download/models/3033557?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Lolita dress: pink lace tiered dress [IL, Anima] / Anima v1.0
    "pink lace tiered dress04206464142a_16.safetensors|https://civitai.com/api/download/models/3049382?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / White Jellyfish Gown / anima
    "WhiteJellyfishGownAnima.safetensors|https://civitai.com/api/download/models/3028868?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Zuhair Murad SS 2026 - High-Low Rhinestone Dress / anima
    "ZuhairMuradSS2026HighLowRhinestoneDressAnima.safetensors|https://civitai.com/api/download/models/3054930?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Wisteria Gothic Gown / anima
    "WisteriaGothicGownAnima.safetensors|https://civitai.com/api/download/models/2980062?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Wrap-Around Shoulder Gown | White Whales | ANIMA\ILXL / ANIMA3P
    "Outfit_soph-WraparoundGown-ANIMA3P.safetensors|https://civitai.com/api/download/models/2938591?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / St. Phoenix Corset Dress / anima
    "StPhoenixCorsetDressAnima.safetensors|https://civitai.com/api/download/models/3058593?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Strawberry Dress / anima
    "StrawberryDressAnima.safetensors|https://civitai.com/api/download/models/2980646?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Sheer Rhinestone-Sleeved Dress / anima
    "rhinstonesleeveddress_anima.safetensors|https://civitai.com/api/download/models/2959495?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / La Mujer De Todos 1946 Pearl Dress / anima
    "LaMujerDeTodos1946PearlDressAnima.safetensors|https://civitai.com/api/download/models/3019653?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Zuhair Murad SS 2026 - Satin Off-Shoulder Dress / anima
    "ZuhairMuradSS2026SatinOffShoulderDressAnima.safetensors|https://civitai.com/api/download/models/3054780?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Provocateur Mini Dress / Anima v1.0
    "Pr0v0c4t3ur_Anim_v10.safetensors|https://civitai.com/api/download/models/3062309?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Tiered Chiffon Dress / anima
    "tieredchiffondress_anima.safetensors|https://civitai.com/api/download/models/3024095?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Peony Slime Gown / anima
    "PeonySlimeGownAnima.safetensors|https://civitai.com/api/download/models/2975368?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】White Sequins Gown / anima
    "whitesequingown_anima.safetensors|https://civitai.com/api/download/models/2963923?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Floral Lace Dress / anima
    "florallacedress_anima.safetensors|https://civitai.com/api/download/models/2961838?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Tamara Ralph SS 2026 - Velvet Chain Dress / anima
    "TamaraRalphSS2026VelvetChainDressAnima.safetensors|https://civitai.com/api/download/models/3058437?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Into The Sea Neon Frilled High Low Dress / anima
    "IntoTheSeaNeonFrilledHighLowDressAnima.safetensors|https://civitai.com/api/download/models/2971990?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Red Gladiolus Gown / anima
    "RedGladiolusGownAnima.safetensors|https://civitai.com/api/download/models/2979925?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Chocolate Dress & Icing Boots / anima
    "ChocolateDressIcingBootsAnima.safetensors|https://civitai.com/api/download/models/3027741?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Strapless Dress with Sheer Bow / anima
    "sheerbackbow_anima.safetensors|https://civitai.com/api/download/models/2959396?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Blue Polka Dot Dress / anima
    "bluepolkadotdress_anima.safetensors|https://civitai.com/api/download/models/3024043?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Soft Blue Halterneck Gown / anima
    "SoftBlueHalterneckGownAnima.safetensors|https://civitai.com/api/download/models/2980009?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Crashing Waves Wedding Gown / anima
    "CrashingWavesWeddingGownAnima.safetensors|https://civitai.com/api/download/models/2979895?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Off Shoulder Butterfly Gown / anima
    "OffShoulderButterflyGownAnima.safetensors|https://civitai.com/api/download/models/2988965?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / High-waist Skirts [Anima] / v1.0
    "UltraHighWaist-IL-v1-08.safetensors|https://civitai.com/api/download/models/3050208?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / GreenNatureDress　IL ＆ ANIMA / ANIMA
    "NatureDress_ANIMA.safetensors|https://civitai.com/api/download/models/2979956?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Colour Shift Backless Dress / anima
    "ColourShiftBacklessDressAnima.safetensors|https://civitai.com/api/download/models/2988915?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Big-Frilled Dress / anima
    "bigfrilldress_anima.safetensors|https://civitai.com/api/download/models/3027194?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Glow Up Sequin Crochet Mini Dress / anima
    "GlowUpSequinCrochetMiniDressAnima.safetensors|https://civitai.com/api/download/models/3027623?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Tube dress and tube top / anima
    "tubetopanddress.safetensors|https://civitai.com/api/download/models/2908654?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / High slit wedding dress [IL, Anima] / anima v1.0
    "high slit wedding dress03153232142a_10.safetensors|https://civitai.com/api/download/models/3048566?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Fringe Wedding Gown / anima
    "FringeWeddingGownAnima.safetensors|https://civitai.com/api/download/models/2965221?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Ringdress Anima, Illustrious and PonyXL / ringdress Anima
    "ringdress Anima.safetensors|https://civitai.com/api/download/models/2976345?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Zuhair Murad SS 2026 - Rushed Hip Mermaid Dress / anima
    "ZuhairMuradSS2026RushedHipMermaidDressAnima.safetensors|https://civitai.com/api/download/models/3054893?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / puffer skirt / v1.0 anima
    "puffer skirt_anima_V1.0.safetensors|https://civitai.com/api/download/models/2933716?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / One-shoulder satin dress / Anima
    "oneshouldersatindressanima.safetensors|https://civitai.com/api/download/models/3022701?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Heller In Pink Tights 1960 White Dress / anima
    "HellerInPinkTights1960WhiteDressAnima.safetensors|https://civitai.com/api/download/models/3019593?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Rainbow Carnival Fringe | New Dress Hue Dis? | ANIMA / ANIMA
    "Outfit_soph-RainbowFringe-ANIMA.safetensors|https://civitai.com/api/download/models/2953696?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Met Gala 2026 - Schiaparelli - Illusion Of Undress / anima
    "MetGala2026SchiaparelliIllusionOfUndressAnima.safetensors|https://civitai.com/api/download/models/3021546?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Zipper Mermaid Dress / anima
    "ZipperMermaidDressAnima.safetensors|https://civitai.com/api/download/models/3055043?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Embellished Maxi Dress / anima
    "embellishedmaxidress_anima.safetensors|https://civitai.com/api/download/models/2972161?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Sheer Ghost Dress (by Shirowalker) / v1.0 ANIMA
    "Shiro_Sheer_Ghost_Dress_ANIMA.safetensors|https://civitai.com/api/download/models/3026710?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Gold Dress - Buccaneer's Girl 1950 / anima
    "GoldDressBuccaneersGirl1950Anima.safetensors|https://civitai.com/api/download/models/3019396?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Baba Konomi clothing8 Private dress +Alc KNMP_019_8 / Anima
    "knmp_019_8_privatedress.safetensors|https://civitai.com/api/download/models/3023121?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Spaghetti Dress / anima
    "SpaghettiDressAnima.safetensors|https://civitai.com/api/download/models/3014377?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / 【COSTUME】Short Plunging Neckline Dress / anima
    "shortplungingneckline_anima.safetensors|https://civitai.com/api/download/models/3036749?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Floral Bones Gown / anima
    "FloralBonesGownAnima.safetensors|https://civitai.com/api/download/models/2983637?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Pretty Woman Red Dress | Not On The Lips | ANIMA/ILXL / ANIMA
    "Outfit_soph-PrettyWomanRedDress-ANIMA3P.safetensors|https://civitai.com/api/download/models/2952221?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / White Sailor Dress Outfit / ANIMA
    "WSdress_Anima.safetensors|https://civitai.com/api/download/models/2904933?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Black Linked Panel 60's Dress | The Fate of Ophelia Style | ILXL/ANIMA / ANIMA
    "Outfit_soph-OpheliaBlackPanelDress-ANIMA.safetensors|https://civitai.com/api/download/models/2973201?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Geometric Pencil Skirt / anima
    "GeometricPencilSkirtAnima.safetensors|https://civitai.com/api/download/models/3027926?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Layered Plaid Skirt & Bustier / anima
    "LayeredPlaidSkirtBustierAnima.safetensors|https://civitai.com/api/download/models/2972174?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / PatBO - SS 2026 - Tulle Plunge Back Maxi Dress / anima
    "PatBOSS2026TullePlungeBackMaxiDressAnima.safetensors|https://civitai.com/api/download/models/3052082?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Josie and Meowmming short dress / Anima
    "josieandmeowmmingDressanima.safetensors|https://civitai.com/api/download/models/3065211?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / China dress -  Old Shanghai Beauty (老上海美女) / ANIMA
    "舊上海美人.safetensors|https://civitai.com/api/download/models/2957688?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Ninetailedfox dress / Anima
    "ninetailedfoxdressanima.safetensors|https://civitai.com/api/download/models/3068130?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Egalant  dress / Anima
    "EgalantShortdressanima.safetensors|https://civitai.com/api/download/models/3045358?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Matakawa Dress / Anima
    "MatakawaDress2anima.safetensors|https://civitai.com/api/download/models/2949405?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Tutu Wavy Skirt (Anima Edition) / v1.0
    "Tutu_Wavy_Skirt-Clothes-Anima-V1_0.safetensors|https://civitai.com/api/download/models/2946623?type=Model&format=SafeTensor"

    # Clothing / Dress & Skirt / Base:Anima / Assless Morticia Dress-Anima-GMR / Assless Morticia Dress-An
    "Assless Morticia Dress-Anima-GMR.safetensors|https://civitai.com/api/download/models/3067100?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Uniform & Maid
    # ------------------------------------------------------------

    # Clothing / Uniform & Maid / Base:Anima / Dallas Cowboys Cheerleaders Outfit (Clothes) [ZIT & IL] / ANIMA
    "DallasCowboysCheerleaders_ANIMA.safetensors|https://civitai.com/api/download/models/2713201?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / 婦警/female police(XL,ILL,pony) / v1.0 anima
    "police uniform_anima_V1.0.safetensors|https://civitai.com/api/download/models/2922732?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / 学生服/serafuku / v1.0 anima
    "serafuku_anima_V1.0.safetensors|https://civitai.com/api/download/models/2880518?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / Anima LoRA sailor leotard / v1.4(anima-preview2)
    "Anima_sailor_leotard_v1.4.safetensors|https://civitai.com/api/download/models/2807913?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / バレーボール　ユニフォーム/volleyball uniform(XL.ILL,pony) / v1.0 anima
    "volleyball uniform.safetensors|https://civitai.com/api/download/models/2903340?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / ブレザー/blazer / v1.0 anima
    "blazer_anime_v1.0.safetensors|https://civitai.com/api/download/models/2886915?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / 【COSTUME】Heart Maid / anima
    "heartmaid_anima.safetensors|https://civitai.com/api/download/models/2961842?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / [Anima] school gal - Dolphin Wave / v0.2
    "school-gal_dw_anima_v0_2.safetensors|https://civitai.com/api/download/models/2979061?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / 【COSTUME】Bandeau Maid (Pony/Illustrious) / anima
    "bandeaumaid_anima.safetensors|https://civitai.com/api/download/models/3024063?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / Potari Shrine Maiden / anima
    "potari_shrine_maidenAnima.safetensors|https://civitai.com/api/download/models/3013723?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / Succubus Cheer Uniform - Lucky Star Outfit / v1.0
    "Succubus Cheer Outfit Lucky Star-step00000900.safetensors|https://civitai.com/api/download/models/3005111?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / Ruched Frilly Maid | Ruch Hour | ANIMA / ANIMA
    "Outfit_soph-RuchedFrillyMaid-ANIMA.safetensors|https://civitai.com/api/download/models/3048196?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / coco's uniform (umamusume) / COCO'Sコラボ制服 (ウマ娘プリティーダービー) / ココ ス / Anima
    "cocosuniform_anima_v1.safetensors|https://civitai.com/api/download/models/3068841?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / Suzumiya Haruhi Cheer Uniform / v2.0
    "Suzumiya Haruhi Outfit Anima.safetensors|https://civitai.com/api/download/models/3052281?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / Temu "Satin" Croptop Maid | Right Off The Boat | ANIMA / ANIMA
    "Outfit_soph-FrilledCropMaid-ANIMA.safetensors|https://civitai.com/api/download/models/3002657?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / Milkman Uniform / anima
    "MilkManUniformAnima.safetensors|https://civitai.com/api/download/models/2996803?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / Sweet_Cafe_Uniform IL ＆ ANIMA / ANIMA
    "Sweet_Cafe_Uniform_ANIMA.safetensors|https://civitai.com/api/download/models/2982791?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / [Anima Preview] vacation mermaid - Dolphin Wave / v0.1
    "vacation-mermaid_dw_v0_1.safetensors|https://civitai.com/api/download/models/2860729?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / Polka Dot Satin Maid | Dot's The Way I Like It | ILXL / ANIMA
    "Outfit_soph-PolkaDotMaid-ANIMA.safetensors|https://civitai.com/api/download/models/3060054?type=Model&format=SafeTensor"

    # Clothing / Uniform & Maid / Base:Anima / Leukos School Uniform | Xenoblade: Genesis | ANIMA / ANIMA
    "Outfit_xbg-LeukosUniform-ANIMA.safetensors|https://civitai.com/api/download/models/3019293?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Traditional
    # ------------------------------------------------------------

    # Clothing / Traditional / Base:Anima / Sheer Kimono / anima
    "SheerKimonoAnima.safetensors|https://civitai.com/api/download/models/3030644?type=Model&format=SafeTensor"

    # Clothing / Traditional / Base:Anima / 巫女/miko(XL,illustrious,pony) / v1.0 anima
    "miko.safetensors|https://civitai.com/api/download/models/2889063?type=Model&format=SafeTensor"

    # Clothing / Traditional / Base:Anima / Tang Dynasty Hanfu / anima
    "TangDynastyHanfuAnima.safetensors|https://civitai.com/api/download/models/3022260?type=Model&format=SafeTensor"

    # Clothing / Traditional / Base:Anima / 漢服/Hanfu(XL,ill,Pony) / v1.0 anima
    "hanfu_anima_V1.0.safetensors|https://civitai.com/api/download/models/3024562?type=Model&format=SafeTensor"

    # Clothing / Traditional / Base:Anima / Sakura Miko - Loungewear | さくらみこ - ルームウェア / v1.0 [anima-preview]
    "anima-sakura-miko-loungewear-nlmix-e100.safetensors|https://civitai.com/api/download/models/2688060?type=Model&format=SafeTensor"

    # Clothing / Traditional / Base:Anima / Sakura Miko, Hoshimachi Suisei (miComet) | さくらみこ、星街すいせい(みこめっと) / v3.0 [anima-preview]
    "anima-micomet-nlmix-v3.safetensors|https://civitai.com/api/download/models/2705887?type=Model&format=SafeTensor"

    # Clothing / Traditional / Base:Anima / Kaguya (Yukata) / Cosmic Princess Kaguya! / Anima1.0
    "Anima-CPK-YukataKaguya02.safetensors|https://civitai.com/api/download/models/3073478?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Armor & Fantasy
    # ------------------------------------------------------------

    # Clothing / Armor & Fantasy / Base:Anima / The Space Marines Warhammer 40K | Flux + Pony + illustrious + Anima / Ultramarines Anima
    "AnimaUltraM40k.safetensors|https://civitai.com/api/download/models/3025964?type=Model&format=SafeTensor"

    # Clothing / Armor & Fantasy / Base:Anima / Monster Hunter - Demonlord Armor (EX魔界ノ主 装備) / Anima v1
    "Demonlord Armor Anima Sqq V1.safetensors|https://civitai.com/api/download/models/3012518?type=Model&format=SafeTensor"

    # Clothing / Armor & Fantasy / Base:Anima / Monster Hunter - Namielle armor -Beta (ネロミェール装備) / Anima v1
    "Namielle Armor Beta Anima Sqq V1-000010.safetensors|https://civitai.com/api/download/models/3011976?type=Model&format=SafeTensor"

    # Clothing / Armor & Fantasy / Base:Anima / LoRA / Anima / Rossi from Arknights (Cosplay+Character) / Rossi ANIMA
    "rossi_(arknights)_(anima).safetensors|https://civitai.com/api/download/models/3053454?type=Model&format=SafeTensor"

    # Clothing / Armor & Fantasy / Base:Anima / Spartan Armor (Halo) / v1.0
    "Spartan Armor (Halo).safetensors|https://civitai.com/api/download/models/3016829?type=Model&format=SafeTensor"

    # Clothing / Armor & Fantasy / Base:Anima / Monster Hunter (Wilds) - Lala Barina Armor (ラバラ・バリナ装備) / Anima v1
    "Lala Barina armor Anima Sqq V1.safetensors|https://civitai.com/api/download/models/3012297?type=Model&format=SafeTensor"

    # Clothing / Armor & Fantasy / Base:Anima / Monster Hunter (XX) - Violet Mizutsune Armor - Sword Master (陰陽ノ者 - ミツネ装備) illuXL - v1.0 / Anima v1
    "Violet Mizutsune Armor Anima Sqq V1.safetensors|https://civitai.com/api/download/models/3056464?type=Model&format=SafeTensor"

    # Clothing / Armor & Fantasy / Base:Anima / NOD trooper armor - C&C Tiberian Sun / Anima
    "nodtrooperanima.safetensors|https://civitai.com/api/download/models/2955433?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Bodysuit & Leotard
    # ------------------------------------------------------------

    # Clothing / Bodysuit & Leotard / Base:Anima / Anima LoRA super highleg / v3.3 (v1.0-base)
    "Anima_super_highleg_v3.3.safetensors|https://civitai.com/api/download/models/3039711?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Chase The Night Fishnet Bodysuit / anima
    "ChaseTheNightFishnetBodysuitAnima.safetensors|https://civitai.com/api/download/models/3034835?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Spicy Hot Mesh Halter Leotard / anima
    "SpicyHotMeshHalterLeotardAnima.safetensors|https://civitai.com/api/download/models/3044403?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Fishnet Bodysuit (Large Netting) | Dolphin-safe | ILXL / ANIMA
    "Outfit_soph-FishnetLarge-ANIMA.safetensors|https://civitai.com/api/download/models/2948559?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Spicy Hot Cross-Laced Skimpy Leotard / anima
    "SpicyHotCrossLacedSkimpyLeotardAnima.safetensors|https://civitai.com/api/download/models/3034881?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Apperloth Holographic Latex Highleg Leotard / anima
    "ApperlothHolographicLatexHighlegLeotardAnima.safetensors|https://civitai.com/api/download/models/3025011?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Evolved Virgin Killer Sweater / anima
    "EvolvedVirginKillerSweaterAnima.safetensors|https://civitai.com/api/download/models/3050860?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Latex & Mesh Frilled Leotard / anima
    "LatexMeshFrilledLeotardAnima.safetensors|https://civitai.com/api/download/models/3048693?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / mendou_reverse bunnysuit  [pony, xl, ill, ANIMA] / anima-preview3-base
    "mendo_kus_buni.safetensors|https://civitai.com/api/download/models/3046485?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Black Bird Cutout Leotard / anima
    "BlackBirdCutoutLeotardAnima.safetensors|https://civitai.com/api/download/models/2957796?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Reversed bunnysuit by Ryan Reos [Anima/Illustrious/Pony] / Anima
    "ryan_bnysuit_A.safetensors|https://civitai.com/api/download/models/3048063?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Gothic Cupless Leotard / anima
    "GothicCuplessLeotardAnima.safetensors|https://civitai.com/api/download/models/2971904?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Soft Leather Bodysuit + Corset + Laced Boots | TL;DR | ANIMA / ANIMA
    "Outfit_soph-CorsetLeatherBodysuit-ANIMA.safetensors|https://civitai.com/api/download/models/2968001?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Peony Slime Bound Leotard / anima
    "PeonySlimeBoundLeotardAnima.safetensors|https://civitai.com/api/download/models/2975320?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Desert Punk Leather Leotard & Pants / anima
    "DesertPunkLeatherLeotardPantsAnima.safetensors|https://civitai.com/api/download/models/2963878?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Future Street Bodysuit / v1.0
    "m44aafft_fsb_4614_cdpe_Anima_Future_Street_Bodysuit-000007.safetensors|https://civitai.com/api/download/models/2927634?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / living mask open (living bodysuit hodgepodge) / v1.5Anima
    "FT_living mask openv15A.safetensors|https://civitai.com/api/download/models/2974263?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Floral Gold Bodysuit / anima
    "FloralGoldBodysuitAnima.safetensors|https://civitai.com/api/download/models/2983678?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Stellar Blade bodysuit / ANIMA
    "Stellar_Blade.safetensors|https://civitai.com/api/download/models/3007738?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Bloody Geisha Leotard / anima
    "BloodyGeishaLeotardAnima.safetensors|https://civitai.com/api/download/models/2961035?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Chocolate Milkshake Leotard / anima
    "ChocolateMilkshakeLeotardAnima.safetensors|https://civitai.com/api/download/models/3027787?type=Model&format=SafeTensor"

    # Clothing / Bodysuit & Leotard / Base:Anima / Stitched Leotard / anima
    "StitchedLeotardAnima.safetensors|https://civitai.com/api/download/models/2994858?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Legwear
    # ------------------------------------------------------------

    # Clothing / Legwear / Base:Anima / ガーターベルト/garter belt(SD,XL,ILL,pony) / v1.0 anime
    "garter belt_anima_V1.0.safetensors|https://civitai.com/api/download/models/2926959?type=Model&format=SafeTensor"

    # Clothing / Legwear / Base:Anima / 濃い黒パンスト/deep black pantyhose / v1.0 anima
    "deep black pantyhose_anima_V1.0.safetensors|https://civitai.com/api/download/models/2960602?type=Model&format=SafeTensor"

    # Clothing / Legwear / Base:Anima / Anima · 雪糕滑块 (White Legwear Slider) / v1.0
    "white_legwear-slider_v3-step00000500.safetensors|https://civitai.com/api/download/models/3059240?type=Model&format=SafeTensor"

    # Clothing / Legwear / Base:Anima / 【COSTUME】Embroidered Thigh Highs (Commission) / anima
    "lacefloralthighhigh_anima.safetensors|https://civitai.com/api/download/models/3032608?type=Model&format=SafeTensor"

    # Clothing / Legwear / Base:Anima / Shiny pantyhose 油亮丝袜 【anima】 / v1.0
    "shiny pantyhose 2.safetensors|https://civitai.com/api/download/models/2972941?type=Model&format=SafeTensor"

    # Clothing / Legwear / Base:Anima / over-thigh-thighhighs / anima-base-v1.0
    "over-thigh-thighhighs-purged.safetensors|https://civitai.com/api/download/models/2989276?type=Model&format=SafeTensor"

    # Clothing / Legwear / Base:Anima / 【COSTUME】Opaque Pantyhose (Commission) / anima
    "opaquapantyhose_anima.safetensors|https://civitai.com/api/download/models/3069195?type=Model&format=SafeTensor"

    # Clothing / Legwear / Base:Anima / flesh_colored_stockings / v1.0
    "flesh_colored_stockings.safetensors|https://civitai.com/api/download/models/2992654?type=Model&format=SafeTensor"

    # Clothing / Legwear / Base:Anima / Fairy_Thighhighs / ANIMA
    "FairyThighhighsANIMA.safetensors|https://civitai.com/api/download/models/2910199?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Material & Texture
    # ------------------------------------------------------------

    # Clothing / Material & Texture / Base:Anima / MM Latex Bondage Prisoner Suit | Just Encase | ILXL / ANIMA
    "Outfit_soph-MMPrisoner-ANIMA.safetensors|https://civitai.com/api/download/models/3013668?type=Model&format=SafeTensor"

    # Clothing / Material & Texture / Base:Anima / 【COSTUME】Sheer Floral Embroidery Set / anima
    "sheerfloralembroidery_anima.safetensors|https://civitai.com/api/download/models/2962025?type=Model&format=SafeTensor"

    # Clothing / Material & Texture / Base:Anima / takanashi_kiara gold_cross-laced clothes [ill, ANIMA] / anima-preview3-base
    "yoskrrar_eekred_sgmesun-000004.safetensors|https://civitai.com/api/download/models/3032573?type=Model&format=SafeTensor"

    # Clothing / Material & Texture / Base:Anima / Peony Slime Satin Set / anima
    "PeonySlimeSatinSetAnima.safetensors|https://civitai.com/api/download/models/2975387?type=Model&format=SafeTensor"

    # Clothing / Material & Texture / Base:Anima / Mesh Top w/ Leather Corset & Baggy Pants / anima
    "MeshTopLeatherCorsetBaggyPantsAnima.safetensors|https://civitai.com/api/download/models/3048415?type=Model&format=SafeTensor"

    # Clothing / Material & Texture / Base:Anima / 【COSTUME】Flower Lace Corset / anima
    "flowerlacecorset_anima.safetensors|https://civitai.com/api/download/models/2963825?type=Model&format=SafeTensor"

    # Clothing / Material & Texture / Base:Anima / Daisy Latex Devil Suit / anima
    "DaisyLatexDevilSuitAnima.safetensors|https://civitai.com/api/download/models/3028704?type=Model&format=SafeTensor"

    # Clothing / Material & Texture / Base:Anima / Vintage Satin Halter-Neck and Hair | Two-fer Woof-er | ILXL\ANIMA / ANIMA
    "ElizSingerANIMA.safetensors|https://civitai.com/api/download/models/2962923?type=Model&format=SafeTensor"

    # Clothing / Material & Texture / Base:Anima / Detailed Fishnets: Anima / v0.1animav3preview
    "fishnets-000019.safetensors|https://civitai.com/api/download/models/2870275?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Accessory & Restraint
    # ------------------------------------------------------------

    # Clothing / Accessory & Restraint / Base:Anima / ホエールテイル/whale tail(clothing) / v1.0 anima
    "whale tail_anima_V1.0.safetensors|https://civitai.com/api/download/models/2939130?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / アナルプラグ/butt plug / v1.0
    "butt plug_anima_V1.0.safetensors|https://civitai.com/api/download/models/3010873?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / All gags (ball gag, harness, ring gag, plug gag, slime gag, dildo mask, bit gag, shared gag) / ANIMA v1.0
    "gag_test_2-step00002750.safetensors|https://civitai.com/api/download/models/2920295?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / Cupless Body Harness / anima
    "CuplessBodyHarnessAnima.safetensors|https://civitai.com/api/download/models/3045172?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / ランドセル/randoseru(Pony) / v1.0 anima
    "randoseru_anima_V1.0.safetensors|https://civitai.com/api/download/models/2980280?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / 手錠と首輪/wrists and collar bound / v1.0 anime
    "waist and collar bound_anima_V1.0.safetensors|https://civitai.com/api/download/models/2926951?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / ハーネス/harness(SD,XL,pony) / v1.0 anima
    "harness_anima_V1.0.safetensors|https://civitai.com/api/download/models/3064972?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / 革手錠（拘束前）/leather wrists cuffs / v1.1 anima
    "leather wrists cuffs_anima_V1.1.safetensors|https://civitai.com/api/download/models/2945687?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / Glowing Passion Harness / anima
    "GlowingPassionHarnessAnima.safetensors|https://civitai.com/api/download/models/2989008?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / O-ring Body Harness/Gag/Blindfold | Ring It On | ANIMA / ANIMA
    "Outfit_soph-OringHarness+Gag+Blindfold-ANIMA.safetensors|https://civitai.com/api/download/models/2982273?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / 裸タオル/naked towel / v1.0 anima
    "naked towel_anima_V1.0.safetensors|https://civitai.com/api/download/models/3054398?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / nipple piercing - ZIT/ IL/ Pony/ Flux / ANIMA
    "Pierced_nipples_-_anima_epoch_10.safetensors|https://civitai.com/api/download/models/3050316?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / O-ring belt_anima / v1.0
    "O-ring belt_anima.safetensors|https://civitai.com/api/download/models/3008419?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / Harness Panel Gag / ANIMA
    "Harness_Panel_Gag_Anima.safetensors|https://civitai.com/api/download/models/3015777?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / Bound Lily Set Anima / anima
    "BoundLilySetAnima.safetensors|https://civitai.com/api/download/models/2961236?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / Bound Crystal Statue Set / anima
    "BoundCrystalStatueSetAnima.safetensors|https://civitai.com/api/download/models/2961127?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / Crystal Angel Bustier Harness / anima
    "CrystalAngelBustierHarnessAnima.safetensors|https://civitai.com/api/download/models/2961339?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / Corset piercing (Anima) / v1.0
    "cp1B.safetensors|https://civitai.com/api/download/models/3049558?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / Handcuff Belt / anima
    "HandcuffBeltAnima.safetensors|https://civitai.com/api/download/models/3048507?type=Model&format=SafeTensor"

    # Clothing / Accessory & Restraint / Base:Anima / piercing through clothes 服装穿刺 / v1.0
    "anima_piercing_through_clothes_768v21_epoch5.safetensors|https://civitai.com/api/download/models/2956047?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Costume & Cosplay
    # ------------------------------------------------------------

    # Clothing / Costume & Cosplay / Base:Anima / [Anim] Princess Corruption / v1.0
    "Princess Corruption.safetensors|https://civitai.com/api/download/models/2992165?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / rio_(blue_archive) harem_outfit [pony, ill, ANIMA] / anima-preview3-base
    "tivur_ioblrmoet_eefirchauha.safetensors|https://civitai.com/api/download/models/3042976?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Misty Cosplay (Outfit) (Pokemon) [ANIMA] / ANIMA
    "MistyPokemonCosplay_ANIMA.safetensors|https://civitai.com/api/download/models/2705213?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Tentacle outfit | Wearable tentacles | Anima & Illustrious / v1.0 Anima
    "Tentacle_outfit_V1_Anima.safetensors|https://civitai.com/api/download/models/3047104?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / 【COSTUME】Frilly Cow Outfit / anima
    "frillycowoutfit_anima.safetensors|https://civitai.com/api/download/models/2963997?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Sexy Assassin Cloth [Blade & Soul] / ANIMA
    "Sexy Asassine_ANIMA.safetensors|https://civitai.com/api/download/models/3046068?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / [7-in-1] Sexy traditional chinese-style outfit [Anima] | 七合一古风情趣套 装 / Anima v1.0
    "sexy traditional chinese-style outfit (7in1)03206464144a_18.safetensors|https://civitai.com/api/download/models/3059678?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / おつまみシュリンプ / Otsumami Shrimp - DOAXVV Outfit (Anima) / v1.0
    "OtsumamiShrimp_Doaxvv_Anima_v1.safetensors|https://civitai.com/api/download/models/3006246?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / LoRA / Anima / Kaguya from Kuroinu (Cosplay+Character) / Kaguya ANIMA
    "kaguya_(kuroinu)_(anima).safetensors|https://civitai.com/api/download/models/3050324?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / [Anima] Ts Mahou Shoujo Corruption Form / v2.0
    "TS Mahou Shoujo Corruption.safetensors|https://civitai.com/api/download/models/3010761?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / living / tentacle costume (anima) / v1.0
    "living costume.safetensors|https://civitai.com/api/download/models/2976622?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Sexy bondage outfit 2 [IL, Anima] / Anima v1.0
    "Sexy bondage outfit2 03102424142a.safetensors|https://civitai.com/api/download/models/3050040?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / [Anima] Love Mary Lapis Outfit / v1.0
    "Love Mary Lapis.safetensors|https://civitai.com/api/download/models/3010889?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / [Anima] Love Mary Lip Outfit / v1.0
    "Love Mary Lip.safetensors|https://civitai.com/api/download/models/3010883?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / 【COSTUME】Dreamy Chemise / anima
    "dreamychemise_anima.safetensors|https://civitai.com/api/download/models/2963776?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Plegian Outfit - Anima / V1
    "plegianAnima.safetensors|https://civitai.com/api/download/models/3029593?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Black Tape Project Outfit / v1.0
    "m44aafft_btp_6396_brkt_Anima_black_tape_project.safetensors|https://civitai.com/api/download/models/2920371?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Shirogane Noel 9th costume | 白銀ノエル新衣装2025 / v1.0 [anima-preview]
    "anima-shirogane-noel-loungewear-nlmix-e52.safetensors|https://civitai.com/api/download/models/2688587?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Cosplay - Rouge the Bat 🦇 / ANIMAv1.0
    "rougeCosplayAnima.safetensors|https://civitai.com/api/download/models/2996640?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / LoRA / Anima / Prim Fiorire from Kuroinu (Cosplay+Character) / Prim Fiora ANIME
    "prim_fiorire_000001100.safetensors|https://civitai.com/api/download/models/3043826?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / [Anima] Love Mary Stella Outfit / v1.0
    "Love Mary Stella.safetensors|https://civitai.com/api/download/models/3010891?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / [costume] Piaキャロットへようこそ3 制服3種 / anima-preview3-v1.2
    "costume_pia3_anima_pre3_pr_bat10_1024_V1_2-step00000800.safetensors|https://civitai.com/api/download/models/2888284?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / [Anima] Mahou Shoujo Corruption [Miyashiro Ryuutarou Style] / v1.0
    "Mahou Shoujo Corruption [Miyashiro Ryuutarou Style].safetensors|https://civitai.com/api/download/models/2992125?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Slutty Frieren Cosplay | Snack in the Box | ANIMA3P / ANIMA3P
    "Outfit_soph-SluttyFrieren-ANIMA3P.safetensors|https://civitai.com/api/download/models/2935801?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / 【COSTUME】Ruffled Bloomers Set / anima
    "rufflebloomers_anima.safetensors|https://civitai.com/api/download/models/3024024?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Kosaki's Slutty Hero Costume [Anima/IL] / Anima(v1.0)
    "Pig_sentai_costume_Anima_v1.safetensors|https://civitai.com/api/download/models/3032389?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Catwoman Cosplay | Batman Returns | ANIMA / ANIMA
    "Outfit_soph-CatwomanBMR-ANIMA.safetensors|https://civitai.com/api/download/models/3037843?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / [Anima] Love Live! Costume Collection / ラブライブ！ 衣装コレクション / Koi ... Aquarium v0.04
    "Koiaku-AnimaBaseV1-V004.safetensors|https://civitai.com/api/download/models/3043380?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / トワイライトフィッシュ / Twilight Fish - DOAXVV Outfit (Anima) / v1.0
    "TwilightFish_Doaxvv_Anima_v1.safetensors|https://civitai.com/api/download/models/3049456?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Final Fantasy WhiteMage Costume ANIMA / v1.0
    "WhiteMageANIMA_V1.safetensors|https://civitai.com/api/download/models/2878900?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Zombie Girl Costume(端午节的节日食品) / v1.0
    "jiangshi_clothes.safetensors|https://civitai.com/api/download/models/3049945?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / 【COSTUME】Art Gala 2022 (Halle Bailey) / anima
    "artgalahallebailey_anima.safetensors|https://civitai.com/api/download/models/2961847?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Emma Frost Cosplay | X-Men First Class 2011 | ANIMA\ILXL / ANIMA
    "Char_xmen-EmmaFrostFirstClass-ANIMA.safetensors|https://civitai.com/api/download/models/2994695?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Cami/Bloomers Combo | Bloom Service | ILXL/ANIMA / ANIMA
    "Outfit_soph-CamisoleBloomers-ANIMA.safetensors|https://civitai.com/api/download/models/2979009?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / [Anima] Xenoblade SS Corruption [Miyashiro Ryuutarou Style] / v1.0
    "Xenoblade SS Corruption [Miyashiro Ryuutarou Style].safetensors|https://civitai.com/api/download/models/2992139?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / 【COSTUME】Frilled Strapless and Bloomers / anima
    "straplessfrill_anima.safetensors|https://civitai.com/api/download/models/3033633?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / 【COSTUME】Espresso (Sabrina Carpenter) / anima
    "espresso_anima.safetensors|https://civitai.com/api/download/models/2958903?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / グレースリリー / Grace Lily - DOAXVV Outfit (Anima) / v1.0
    "GraceLily_Doaxvv_Anima_v1.safetensors|https://civitai.com/api/download/models/3026302?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / LoRA / Anima / Rika Hoshizaki from Kanojo mo Kanojo (Cosplay+Character) / Rika ANIMA
    "rika_hoshizaki_(anima)_2750.safetensors|https://civitai.com/api/download/models/3040284?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / LoRA / Anima / Byakuya Rinne from Euphoria (Cosplay+Character) / Byakuya Rinne ANIMA
    "byakuya_rinne_(anima).safetensors|https://civitai.com/api/download/models/3056939?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Houshou Marine Paipai Mask 2 Outfits (Hololive) / Anima v0.1
    "Anima_Paipai_Mask-10.safetensors|https://civitai.com/api/download/models/3015820?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Agarthan Outfit - Anima / V1
    "AgarthanAnima.safetensors|https://civitai.com/api/download/models/3019940?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / [Dekinai] Hololive Cheer UP outfits Anima/Illustrious | Hololive / 1.0 Anima
    "hololivecheerupoutfitanima.safetensors|https://civitai.com/api/download/models/2991005?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / 【COSTUME】Decorated Denim Shorts (Illustrious) / anima
    "decoratedshorts_anima.safetensors|https://civitai.com/api/download/models/3068798?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / LoRA / Anima / Manaka Nemu from Euphoria (Cosplay+Character) / Manaka Nemu ANIMA
    "manaka_nemu_(anima).safetensors|https://civitai.com/api/download/models/3063361?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Runami Yachiyo / Cosmic Princess Kaguya! / Anima1.0
    "Anima-CPK-Yachiyo03.safetensors|https://civitai.com/api/download/models/3007508?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / LoRA / Anima / Sicily von Claude from Kenja no Mago (Cosplay+Character) / Sicily ANIMA
    "Sicily_von_Claude_(anima).safetensors|https://civitai.com/api/download/models/3066549?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Gymshark Interval Seamless Short Leggings OUTFIT / v1.0
    "m44aafft_iss_9862_kngy_Anima_Interval_Seamless_Shorts.safetensors|https://civitai.com/api/download/models/2927715?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Amane Kanata LOCK ON Live Outfit (Hololive) / Anima v0.1
    "Anima_Kanata_LockOn-08.safetensors|https://civitai.com/api/download/models/3030216?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Hot Limit Outfit / v1.0
    "m44aafft_hl_0785_uhlv_Anima_hot_limit.safetensors|https://civitai.com/api/download/models/2920464?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Kaguya / Cosmic Princess Kaguya! / Anima1.0
    "Anima-CPK-Kaguya03.safetensors|https://civitai.com/api/download/models/3007518?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Stellar Blade Wave Monokini Outfit / Anima
    "wave_mono-000005.safetensors|https://civitai.com/api/download/models/3058406?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Classic DoomGuy cosplay / Anima
    "olddoomguycosplayanima.safetensors|https://civitai.com/api/download/models/2946739?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Louis Vuitton Pop Romper | You Want It | ANIMA / ANIMA
    "Outfit_soph-LVPopRomper-ANIMA.safetensors|https://civitai.com/api/download/models/2971972?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Videl's Second Coming Outfit LoRA / v1.0
    "VidelsMovieOutfit-A3P_v1.safetensors|https://civitai.com/api/download/models/2916268?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Kaguya (Exo version) / Cosmic Princess Kaguya / Anima1.0
    "Anima-CPK-exoKaguya01.safetensors|https://civitai.com/api/download/models/3028286?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / Runami Yachiyo (Kassen version) / Cosmic Princess Kaguya! / Anima1.0
    "Anima-CPK-KassenYachiyo01.safetensors|https://civitai.com/api/download/models/3041365?type=Model&format=SafeTensor"

    # Clothing / Costume & Cosplay / Base:Anima / LoRA / Anima / Kira from Limbus Company (Cosplay+Character) / Kira ANIMA
    "kira_(limbus_company)_(anima).safetensors|https://civitai.com/api/download/models/3072688?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Tops & Outerwear
    # ------------------------------------------------------------

    # Clothing / Tops & Outerwear / Base:Anima / 裂けた服/torn clothes(ill,pony) / v1.0 anima
    "torn clothes_anima_V1.0.safetensors|https://civitai.com/api/download/models/3010969?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / 女児服/girl's clothes(XL,ill,Pony) / v1.0 anima
    "girl clothes_anima_V1.0.safetensors|https://civitai.com/api/download/models/3054405?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / 奴隷服/slave clothes / v1.0 anima
    "slave clothes_anima_V1.0.safetensors|https://civitai.com/api/download/models/2960412?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / 触手服/tentacles clothes(pony) / v1.0 anima
    "living clothes_anima_V1.0.safetensors|https://civitai.com/api/download/models/2920354?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / バスローブ/bathrobe / v1.0 anima
    "bathrobe_anima_V1.0.safetensors|https://civitai.com/api/download/models/3029915?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / 濡れた服/wet clothes / v1.0 anime
    "wet clothes_anima_V1.0.safetensors|https://civitai.com/api/download/models/2917906?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / Painted Clothes / Painted Clothes v1.0
    "painted_clothes_anima-000001.safetensors|https://civitai.com/api/download/models/3013374?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / Dystopian Denim Croptop / anima
    "DystopianDenimCroptopAnima.safetensors|https://civitai.com/api/download/models/2941143?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / フードなしダウンジャケット/down jacket no hood / v1.0 anima
    "down jacket no hood_anima_V1.0.safetensors|https://civitai.com/api/download/models/2932941?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / NASA T-Shirt | National Aeronautics and Space Administration (Clothes) [ANIMA & IL] / ANIMA
    "NASAShirtAnime_ANIMA.safetensors|https://civitai.com/api/download/models/2713202?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / Arabian Clothes NAI / Anima
    "BGX8KCCP3N38H2CJWY815P7AG0.safetensors|https://civitai.com/api/download/models/3017004?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / Dystopian Coveralls / anima
    "DystopianCoverallsAnima.safetensors|https://civitai.com/api/download/models/2940935?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / Defective Brooklyn Sweater / anima
    "DefectiveBrooklynSweaterAnima.safetensors|https://civitai.com/api/download/models/3050493?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / Down Jacket / Coat / Anima v1.0
    "Down Jacket - Coat (Anima) v1.safetensors|https://civitai.com/api/download/models/3060294?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / Straitjacket / v1.0
    "straitJ.safetensors|https://civitai.com/api/download/models/3048234?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / Transgender Pride Crop Top / v1.0 | Anima Base
    "Transgender_pride_print_crop_top.safetensors|https://civitai.com/api/download/models/2952240?type=Model&format=SafeTensor"

    # Clothing / Tops & Outerwear / Base:Anima / Loose Pajamas clothing lora / v1
    "anima_clothes_loose_pajamas_by_AuthorWangYi.safetensors|https://civitai.com/api/download/models/2939223?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Clothing / Other Clothing
    # ------------------------------------------------------------

    # Clothing / Other Clothing / Base:Anima / 地雷系/jirai kei / v1.0 anima
    "jiraikei_anima_V1.0.safetensors|https://civitai.com/api/download/models/2900865?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / チョコレート/chocolate(XL,ill,pony) / v1.0 anima
    "chocolate.safetensors|https://civitai.com/api/download/models/2922772?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Sao Combatant (Narumi Yuu Style) / v1.0
    "Narumi Yuu SAO Combatant Transformation.safetensors|https://civitai.com/api/download/models/2972971?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Bumpella Halter Romper / anima
    "BumpellaHalterRomperAnima.safetensors|https://civitai.com/api/download/models/3048012?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Pantyliners / Anima-Base-v1.0
    "PantylinersV8_NLP_FULL_CIVITAI_anima_baseV10_D32A8_ConON_9e-05_B12_Ga1_Sigmoid_Step1549_modified.safetensors|https://civitai.com/api/download/models/2986432?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / 赤ずきん/Little Red Riding Hood / v1.0 anima
    "Little Red Riding Hood_anima_V1.0.safetensors|https://civitai.com/api/download/models/2951748?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Mahou Shoujo Possession [Popura Style] / v1.0
    "Mahou Shoujo Possesion [Popura Style].safetensors|https://civitai.com/api/download/models/3010897?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / menishuki♡rush-sshu! (umamusume) / めにしゅき♡ラッシュっしゅ！(ウマ娘プ リティーダービー) / Anima
    "menishuki_anima_v1.safetensors|https://civitai.com/api/download/models/3065681?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / レトロナース/retro nurse / v1.0 anima
    "retro nurse_anima_V1.0.safetensors|https://civitai.com/api/download/models/2947071?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Ribbon Of Venus Corset / anima
    "RibbonOfVenusCorsetAnima.safetensors|https://civitai.com/api/download/models/3058362?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Clown Transformation  [Hiro Style] / v2.0
    "Clown Transformation [Hiro Style].safetensors|https://civitai.com/api/download/models/2992465?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Sexy Priest Cloth [Kingdom Under Fire] / ANIMA
    "Sexy_Priest_ANIMA.safetensors|https://civitai.com/api/download/models/3048929?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Sexy Judo Master Cloth [Blade & Soul] / ANIMA
    "Sexy Judo.safetensors|https://civitai.com/api/download/models/3039157?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Haigure Transformation / v3.0
    "Haigure Trasformation [Kitashi Style].safetensors|https://civitai.com/api/download/models/2992368?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Cockring [Anima] / 2Cockrings
    "Cockring [Anima]_modified.safetensors|https://civitai.com/api/download/models/3012048?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Magitech Drone / v1.0
    "Magitech Drone.safetensors|https://civitai.com/api/download/models/2992158?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Black Tape Project - Clothing Anima LORA / v1.0
    "TapeProject_AnimaPreview2_byKonan_style.safetensors|https://civitai.com/api/download/models/2795544?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Gyaru Transformation [深海ichigo Style] / v1.0
    "Gyaru [深海ichigo Style].safetensors|https://civitai.com/api/download/models/3010852?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Menpu_anima / v1.0
    "menpu_anima.safetensors|https://civitai.com/api/download/models/2996116?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / transparent raincoat / v1.0
    "clothing_raincoat.safetensors|https://civitai.com/api/download/models/3054571?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / bunnygirl / v1.0
    "bunnygirl_lora.safetensors|https://civitai.com/api/download/models/3028209?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Beige Torn Halterneck / anima
    "BeigeTornHalterneckAnima.safetensors|https://civitai.com/api/download/models/2951776?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Slave Trainer / v1.0
    "Slave Trainer.safetensors|https://civitai.com/api/download/models/2992739?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Makenki Hime / v2.0
    "Makenki Hime.safetensors|https://civitai.com/api/download/models/3010818?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Chain-Link Corset / anima
    "ChainLinkCorsetAnima.safetensors|https://civitai.com/api/download/models/3014318?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / o-ring Bodycon / v1.0 [Anima]
    "bodycon.safetensors|https://civitai.com/api/download/models/3056543?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] TS Mahou Shoujo Saint Cherry / v1.0
    "TS Mahou Shoujo Saint Cherry.safetensors|https://civitai.com/api/download/models/2992104?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Jirai Kei Mahou Shoujo / v1.0
    "Jirai Kei Mahou Shoujo.safetensors|https://civitai.com/api/download/models/3010879?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Astro Lumina Set / anima
    "AstroLuminaSetAnima.safetensors|https://civitai.com/api/download/models/2979810?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Belluem / v1.0
    "Belluem.safetensors|https://civitai.com/api/download/models/2992096?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Cotton Tights / Anima P3 | v1.0
    "CottonTightsA_v1.safetensors|https://civitai.com/api/download/models/2913700?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Seikou Tenshi [Torisan Style] / v1.0
    "Seikou Tenshi [Torisan Style].safetensors|https://civitai.com/api/download/models/2992153?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / アオザイ/ao dai / v1.0 anima
    "ao dai_anima_V1.0.safetensors|https://civitai.com/api/download/models/2924304?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Sexy Magician Cloth [Blade&Soul] / ANIMA
    "Julia.safetensors|https://civitai.com/api/download/models/3065251?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / 包帯/bandages / v1.0 anima
    "naked bandage_anima_V1.0.safetensors|https://civitai.com/api/download/models/2887112?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Dita Von Teese - Cupcake Wars Apron / anima
    "DitaVonTeeseCupcakeWarsApronAnima.safetensors|https://civitai.com/api/download/models/3013908?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Sexy Succubus Cloth [Mabinogi : Heros] / ANIMA
    "Sexy lady.safetensors|https://civitai.com/api/download/models/3055412?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Combatant [Miyashiro Ryuutarou Style] / v1.0
    "Combatant [Miyashiro Ryuutarou Style].safetensors|https://civitai.com/api/download/models/2992117?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Chuchu combatant / v1.0
    "Chuchu Combatant.safetensors|https://civitai.com/api/download/models/3010837?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / sumo mawashi （相撲 まわし） / v1.0
    "mawashi2.safetensors|https://civitai.com/api/download/models/3062016?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / live tentacles suit / v1.0
    "anima_live_tentacles_suit-000004.safetensors|https://civitai.com/api/download/models/2967022?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / ダウンベスト/down vest / v1.0 anima
    "down vest_anima_V1.0.safetensors|https://civitai.com/api/download/models/2933699?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Mega Malamar Transformation (Kutan style) / v1.0
    "Kutan Megamalamar Transformation.safetensors|https://civitai.com/api/download/models/2972469?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Anima Wardrobe Slider - Cover up & Strip down your Character / v1.0
    "anima_clothing_slider.safetensors|https://civitai.com/api/download/models/3069739?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Major Combatant / v1.0
    "Major Combatant.safetensors|https://civitai.com/api/download/models/2973460?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Mimic Heels - Mimic Shoes - Clothing Anima LORA / v1.0
    "MimicHeels_AnimaPreview2_byKonan_V2.safetensors|https://civitai.com/api/download/models/2826025?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / 舞蹈鞋/Uwabaki / v2.0
    "uwabaki-a-000005.safetensors|https://civitai.com/api/download/models/3017683?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima Preview] see-through sera - Dolphin Wave / v0.1(Preview3)
    "AnimaPreview3_seethrough-sera_dw.safetensors|https://civitai.com/api/download/models/2849338?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Zolder / v1.0
    "Zolder.safetensors|https://civitai.com/api/download/models/2992083?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / WINX CLUB ✨FASHION✨~ANIMA UPDATE~ / ANIMA
    "WINX_CLUB__ANIMA__RIXYN_LORA.safetensors|https://civitai.com/api/download/models/3034530?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Mankini / ANI_V1
    "mankini_ANI_V2.safetensors|https://civitai.com/api/download/models/2971764?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Alice And Her Dreams / anima
    "AliceAndHerDreamsAnima.safetensors|https://civitai.com/api/download/models/3047900?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / 2026年 サッカー日本代表ホームユニ Japan National Soccer Team Home Kit [Anima] / v1.0
    "jpn_nt_kit_Anima_v1-000040.safetensors|https://civitai.com/api/download/models/3023190?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Sexy exotic Cloth [Kingdom Under Fire] / ANIMA
    "Sexy Exotic.safetensors|https://civitai.com/api/download/models/3042758?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / 服装 HOT LIMIT / v1.0
    "hot_limit_v1-000005.safetensors|https://civitai.com/api/download/models/3065750?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Limbus Company Middle Finger / v1.0
    "Limbus Company Middle Finger Transformation.safetensors|https://civitai.com/api/download/models/2972619?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / HypnoShades - Anima / V1
    "HypnoshadesAnima.safetensors|https://civitai.com/api/download/models/3019952?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / [Anima] Squid Slave / v1.0
    "Squid Slave.safetensors|https://civitai.com/api/download/models/2992135?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / KNMP_019_BabaKonomi_clothing5-Monster girl series "Devil"- / Anima
    "KNMP_019_BabaKonomi_clothing5_anima.safetensors|https://civitai.com/api/download/models/3024120?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Augmented Reaction Suit Vanquish / Anima
    "SuitVanquishanima.safetensors|https://civitai.com/api/download/models/3022716?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / (n)EMO / Anima_v1.0
    "nemo.safetensors|https://civitai.com/api/download/models/2955571?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Roman Legionary / ANIMA
    "RomanLegionary.safetensors|https://civitai.com/api/download/models/2961261?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / ballet boots & ballet heels / v0.5
    "balletboots-v0.5.safetensors|https://civitai.com/api/download/models/3015435?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / T-back spats — Anima / v1.0
    "tbackspats-ngai-anima.safetensors|https://civitai.com/api/download/models/2978288?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Simple night suit / Anima
    "simplenightsuitanima.safetensors|https://civitai.com/api/download/models/3031799?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Baba Konomi clothing2 RED ZONE!!!! - Baba Konomi 馬場このみKNMP_019 / Anima
    "KNMP_019_BabaKonomi_clothing2_anima_epoch_5.safetensors|https://civitai.com/api/download/models/3017031?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Sexy Dark elf Cloth [Kingdom Under Fire] / ANIMA
    "Sexy Dark elf_ANIMA.safetensors|https://civitai.com/api/download/models/3045342?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Fighters girl / Clothing LoRA / v2.0 Anima Base v1.0
    "LoRAFightersGirlAnimaV1.safetensors|https://civitai.com/api/download/models/2987024?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / KNMP_019_BabaKonomi_clothing4  - sexy spy- Baba Konomi 馬場このみ / Anima
    "KNMP_019_BabaKonomi_clothing4_anima_epoch_10.safetensors|https://civitai.com/api/download/models/3030488?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Y2KJeans - Hip Hugging Low Rise Jeans / v1.0
    "Y2KJeans_-_Hip_Hugging_Low_Rise_Jeans_epoch_8.safetensors|https://civitai.com/api/download/models/3072624?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Traditional Style Blouse / v1.0
    "3lou5e-000015.safetensors|https://civitai.com/api/download/models/2960432?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / KNMP_019_BabaKonomi_clothing3- 4 Luxury" Makeup Fabulous!" - Baba Konomi  馬場このみ / Anima
    "KNMP_019_BabaKonomi_clothing3_anima.safetensors|https://civitai.com/api/download/models/3024029?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Shinomiya Karen race queen knmp_041 / Anima
    "KSYXNFZ1E1WQ4NBDTENZE67PK0.safetensors|https://civitai.com/api/download/models/3020749?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Shutter Shades (IL\ANI) / Shutter_Shades_ep10_ANI
    "FACE_-_Shutter_Shades_ep10_by_ME_ANI.safetensors|https://civitai.com/api/download/models/3043131?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Valor Dancer (Shiraishi An) / Project SEKAI / Anima1.0
    "Anima-vbs-GreatYellAn01.safetensors|https://civitai.com/api/download/models/2971820?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / How Many Meters Is It!? (Shiraishi An) / Project SEKAI / Anima1.0
    "Anima-vbs-UkaAn01.safetensors|https://civitai.com/api/download/models/2968921?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / Kon Kon Helmet / Anima v1
    "KonKon_Helmet_Anima-000004.safetensors|https://civitai.com/api/download/models/2995974?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / We're About To Open! (Shiraishi An) / Project SEKAI / Anima1.0
    "Anima-vbs-FlyerAn07.safetensors|https://civitai.com/api/download/models/3010449?type=Model&format=SafeTensor"

    # Clothing / Other Clothing / Base:Anima / UF-16 Inspector (Helldivers 2) / v1.0
    "UF16_Inspector_Anima_V1.safetensors|https://civitai.com/api/download/models/2924290?type=Model&format=SafeTensor"


    # ============================================================
    # Concepts
    # ============================================================

    # ------------------------------------------------------------
    # Concepts / Quality & Detail
    # ------------------------------------------------------------

    # Concepts / Quality & Detail / Base:Anima / Aesthetic Quality Modifiers - Masterpiece / v5.1 [anima-base-1]
    "anima-base-1-masterpiece-v51.safetensors|https://civitai.com/api/download/models/2961717?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Anima Detail Tweaker / background_detailer_base
    "background_detailer_v1-step00000200.safetensors|https://civitai.com/api/download/models/3026718?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Anima Lighting Atmosphere Enhancer / exposure
    "exposure_Lighting-step00000300.safetensors|https://civitai.com/api/download/models/3034647?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Anima Quality Enhance Slider / basev10
    "anima_base_slider_step800.safetensors|https://civitai.com/api/download/models/2945328?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Areolae size slider / Anima - v1.0
    "large_areolae_addift_anima.safetensors|https://civitai.com/api/download/models/2964180?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Scenery Enhancer / Anima-P3
    "Scenery_enchancer-Anima-P3.safetensors|https://civitai.com/api/download/models/2920606?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / [Anima] Pregnant Belly Slider / v2
    "pregnant_slider_animav2.safetensors|https://civitai.com/api/download/models/2974349?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Nipple length slider / Anima - v1.0
    "long_nipples_addift_anima.safetensors|https://civitai.com/api/download/models/2964186?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Anima Real Skin Enhancer / v1.0
    "real_skin-step00000200.safetensors|https://civitai.com/api/download/models/2981675?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Nipple color slider. Light ====> Dark nipples / Anima
    "Nipple-color-slider-Anima2_sig4.safetensors|https://civitai.com/api/download/models/3022949?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Detailer - Anime Booster / v1.0
    "Detailer-AnimeBooster.safetensors|https://civitai.com/api/download/models/3025966?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Cum Slider LoRA / Anima-v1.0
    "cum_slider.safetensors|https://civitai.com/api/download/models/3042649?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Abs Slider / Anima
    "Abs-slider-Anima_dat8.safetensors|https://civitai.com/api/download/models/3023777?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Muscle Slider / Anima
    "MuscleSliderAnimafin2.safetensors|https://civitai.com/api/download/models/3027299?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / POV Slider / anima-V0.1
    "POV_Slider.safetensors|https://civitai.com/api/download/models/3028390?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Large anus slider | Puffy anus slider / Anima - v1.0
    "large_anus_anima.safetensors|https://civitai.com/api/download/models/2964194?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Anima Environment Lighting Tweaker / midnight
    "midninght_lighting-step00000200.safetensors|https://civitai.com/api/download/models/2993312?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Low/High-Angle Slider / Anima-v1.0
    "AngleAdjustment.safetensors|https://civitai.com/api/download/models/3031527?type=Model&format=SafeTensor"

    # Concepts / Quality & Detail / Base:Anima / Anima Fantasy & Sci-Fi detailer - By HailoKnight / v1.0
    "AnimaFantasyDetailer.safetensors|https://civitai.com/api/download/models/2882448?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Concepts / Lighting & Scene
    # ------------------------------------------------------------

    # Concepts / Lighting & Scene / Base:Anima / Light Concepts / v3.1 [anima-base-1]
    "anima-base-1-light-concepts-v31.safetensors|https://civitai.com/api/download/models/2952873?type=Model&format=SafeTensor"

    # Concepts / Lighting & Scene / Base:Anima / Anime screencap [Anima] / new_EP9
    "screenshot_v5-000009.safetensors|https://civitai.com/api/download/models/2903778?type=Model&format=SafeTensor"

    # Concepts / Lighting & Scene / Base:Anima / Anima background ehancer / v1.0
    "背景强化v2.5-step00000300.safetensors|https://civitai.com/api/download/models/3026780?type=Model&format=SafeTensor"

    # Concepts / Lighting & Scene / Base:Anima / Scenery - Anima / v1.0 base
    "scenery-anima-base.safetensors|https://civitai.com/api/download/models/2949815?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Concepts / Composition & Comic
    # ------------------------------------------------------------

    # Concepts / Composition & Comic / Base:Anima / Hentai Comic Random Generator (FULL COLOR) Anima / Pony / IL XL | フルカラーエロ漫画ランダムジェネレーター / Anima
    "FComic1to1000_Anima_V1.safetensors|https://civitai.com/api/download/models/3008158?type=Model&format=SafeTensor"

    # Concepts / Composition & Comic / Base:Anima / Upskirt/Pantyshot | Multiple views/2koma | Concept version | Anima/Illustrious/NoobAI / Anima
    "Upskirt_ANIMA.safetensors|https://civitai.com/api/download/models/2988963?type=Model&format=SafeTensor"

    # Concepts / Composition & Comic / Base:Anima / Character Design / キャラクターデザイン (V2) / v1.0
    "Character_DesignV2.safetensors|https://civitai.com/api/download/models/3007246?type=Model&format=SafeTensor"

    # Concepts / Composition & Comic / Base:Anima / Hentai Comic Random Generator (HARD CORE) Anima / Pony / IL XL | ハードコ ア エロ漫画 ランダムジェネレーター / Anima
    "FComicHardCore_Anima_V1.safetensors|https://civitai.com/api/download/models/3014282?type=Model&format=SafeTensor"

    # Concepts / Composition & Comic / Base:Anima / Hentai Comic Random Generator (ANIMA Prototype) (FULL COLOR) | (試作)フル カラーエロ漫画ランダムジェネレーター / Anima_V1
    "FComic1to1000_Anima.safetensors|https://civitai.com/api/download/models/2919739?type=Model&format=SafeTensor"

    # Concepts / Composition & Comic / Base:Anima / Hentai Comic Random Generator (START STORY) (1Page to 3Page) Anima / Pony / IL XL | エロ漫画ランダムジェネレーター（ストーリ序盤 ）1ページ～3ページ / Anima
    "FComic1To3Page_Anima_V1.safetensors|https://civitai.com/api/download/models/3014531?type=Model&format=SafeTensor"

    # Concepts / Composition & Comic / Base:Anima / Hentai Comic Random Generator (LastPage) (FinalPage) / Anima Pony IL XL | エロ漫画ランダムジェネレーター（最終ページ） / Anima
    "FComic_lastPage_Anima_V1.safetensors|https://civitai.com/api/download/models/3018129?type=Model&format=SafeTensor"

    # Concepts / Composition & Comic / Base:Anima / Manga Doujinshi Colorizer ANIMA Edit lora / v1.0
    "colorMangaAnima.safetensors|https://civitai.com/api/download/models/3015470?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Concepts / Expression & Face
    # ------------------------------------------------------------

    # Concepts / Expression & Face / Base:Anima / 睨み顔 angry expression / v1.0
    "angry_expression.safetensors|https://civitai.com/api/download/models/3002388?type=Model&format=SafeTensor"

    # Concepts / Expression & Face / Base:Anima / 顔踏み / stepping on face / V1
    "54ATE3J7NW08978JEZMTJ20WA0.safetensors|https://civitai.com/api/download/models/2971246?type=Model&format=SafeTensor"

    # Concepts / Expression & Face / Base:Anima / 大量ぶっかけ  顏射 /  massive bukkake  Slider   ,  cum on face / v1.0
    "massive_bukkake.safetensors|https://civitai.com/api/download/models/3063368?type=Model&format=SafeTensor"

    # Concepts / Expression & Face / Base:Anima / Kakegurui face expression Anima/Illustrious/Pony / Anima
    "Kakegurui_face_expression-step00001150.safetensors|https://civitai.com/api/download/models/2832719?type=Model&format=SafeTensor"

    # Concepts / Expression & Face / Base:Anima / Asshugger (Anima, ILXL, Pony) / Anima-v1.5
    "facehugger animav3-000009.TA_trained.safetensors|https://civitai.com/api/download/models/3054768?type=Model&format=SafeTensor"

    # Concepts / Expression & Face / Base:Anima / Lipstick Ring - Anima P / v1.0 AP3
    "LipstickRing_AnimaP_v01.safetensors|https://civitai.com/api/download/models/2872174?type=Model&format=SafeTensor"

    # Concepts / Expression & Face / Base:Anima / Chin Grab - Villainous Face Hold - Concept - Anima LORA / BaseV1.0
    "ChinGrab_AnimaBaseV10_byKonan.safetensors|https://civitai.com/api/download/models/3053592?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Concepts / Body & Anatomy
    # ------------------------------------------------------------

    # Concepts / Body & Anatomy / Base:Anima / Sagging Breasts / anima-v4.1
    "sagging-anima-v4.1.safetensors|https://civitai.com/api/download/models/3052892?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / [Anima] Nipple LoRa/ 乳首LoRa / AnimaB1-NP45iV2
    "AnimaB1-NP45iV2.safetensors|https://civitai.com/api/download/models/3036905?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Breast Grab Under Clothes 服の中で乳揉み (V2)   hand under clothes / v1.0
    "handunder_clothesV2.safetensors|https://civitai.com/api/download/models/2983466?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Breasts gravity slider (Perky ====> Sagging breasts) / Anima
    "Perky-saggingBreastsAnima.safetensors|https://civitai.com/api/download/models/2974276?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Breast Implants (Round Breasts) - Illustrious + Anima / Anima v2.0
    "breast_implants_anima_v2.safetensors|https://civitai.com/api/download/models/2984102?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / 乳もみ/grabbing breasts / v1.0 anima
    "grabbing breasts_anima_V1.1.safetensors|https://civitai.com/api/download/models/2933804?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Ass/booty slider (flat ===> huge ass) / Anima
    "Ass-Slider-Anima5.safetensors|https://civitai.com/api/download/models/3017358?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Anima Furry Domain Lora / v6.0
    "Furry Domain .10.3-000014.safetensors|https://civitai.com/api/download/models/3017264?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Anima age slider / potent
    "age_slider000200.safetensors|https://civitai.com/api/download/models/2987396?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Thighs slider / Anima
    "ThighsSliderAnima4.safetensors|https://civitai.com/api/download/models/2985370?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Body weight slider. (Skinny ===> Fat slider) / Anima
    "Body-WeightSliderAnimaCaut.safetensors|https://civitai.com/api/download/models/3014212?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / 乳首責め/nipple pull / v1.0 anima
    "nipple pull_anima_V1.0.safetensors|https://civitai.com/api/download/models/2961607?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Mecha Girl - Mechabare | メカ娘 ・メカバレ / v3.0 [anima-base-1]
    "anima-base-1-mechabare-v3.safetensors|https://civitai.com/api/download/models/2955489?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Age Slider LoRA | ANIMA / v0.9 - Initial Release
    "StS_Age_Slider_v0.9_ANIMA.safetensors|https://civitai.com/api/download/models/3051160?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Ass ripple / v0.1,0
    "ass_ripple_ta_v.0.1.0.safetensors|https://civitai.com/api/download/models/2982218?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Hips slider / Anima
    "Hips-Slider-Anima.safetensors|https://civitai.com/api/download/models/3016692?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Mechanism concept / Anima-P3
    "Mechanism-Anima_P3.safetensors|https://civitai.com/api/download/models/2909126?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / breast pull / v0.1.0
    "breast_pull_ta_v0.1.0.safetensors|https://civitai.com/api/download/models/2994465?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Nipple Gape, Penetration, Plugs, etc. / v1.0
    "Nipple Penetration and Gaping Anima Base-step00001800.safetensors|https://civitai.com/api/download/models/2951001?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Side view two character (hand on another's shoulder/breast grab/ass grab/hand on anothers waist) (Anima) / V1
    "6TEGF0P7M3YX2BX1M2H8FHDAQ0.safetensors|https://civitai.com/api/download/models/3037232?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / grabbing_nipples_strong-anima / v1.0
    "grabbing_nipples_strong-anima-v1.safetensors|https://civitai.com/api/download/models/3009927?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / 乳首チェーン/nipples chain(SD,XL,Pony) / v1.0 anima
    "nipple chain_anima_V1.0.safetensors|https://civitai.com/api/download/models/2969140?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Breast Shape Slider (Round breast implants / Sagging Breasts) – for Anima / v1.0AnimaBase
    "BreastShapeSliderAnimaBase.safetensors|https://civitai.com/api/download/models/3034817?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / nipple_afterimage-anima / v1.0
    "nipple_afterimage-anima-v1.safetensors|https://civitai.com/api/download/models/2970048?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Perky Breasts with Implants and High Nipples (Anima + IL) / Anima v1.0
    "perky_round_breasts_anima_v1.safetensors|https://civitai.com/api/download/models/2976653?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Hyper Breasts / v1.0
    "hyper_breasts.safetensors|https://civitai.com/api/download/models/2902360?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Hanging Breasts / anima-v4.1
    "hanging-anima-v4.1.safetensors|https://civitai.com/api/download/models/3031869?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Thigh Grab Lifting sex / Anima v1
    "living_onahole_anima.safetensors|https://civitai.com/api/download/models/3059330?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Ass Stacking / v1.0 Anima
    "Ass_Stack_epoch_7.safetensors|https://civitai.com/api/download/models/3020992?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / 胸ちら(後ろから)/breasts view from behind / v1.0 anime
    "breasts view from behind_anima_V1.0.safetensors|https://civitai.com/api/download/models/2922709?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Ass ripple (for Anima), also known as: ass assault, booty bounce, cheek clapping, dumper devastation, endowment engagement, fanny flapping, glutes grinding, hiney humping, impressive rear invigoration, jelly buns jam, keister kick, lump lunges, moon mashing, nether region navigation, orbit ownage, posterior pounding, quad quacking, rump ravaging, seat slamming, tush tendering, underneath usurping, velvet cushion vaulting, wobbler whomping, x-tra thick booty x-traction, yonder cheeks yelping, and zonker zipping / Anima 1.0, V1
    "Ass_ripple_.safetensors|https://civitai.com/api/download/models/2957431?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Breast Size Adjuster (Anima) - Proper Gigantic & Hyper Breasts / v1.0
    "Breast Size Adjuster Anima V1.safetensors|https://civitai.com/api/download/models/2921639?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Condom on Nipples / 乳首にコンドーム [Anima] / v1.0
    "cndom_nipp.safetensors|https://civitai.com/api/download/models/2989576?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Multi  breasts concept for Anima / v1.0
    "sagging_and_pull_breasts_v1.safetensors|https://civitai.com/api/download/models/2886794?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Vertical-Slit Inverted Nipples 縦陥没乳首 - IL/Anima P / v1.0-AnimaPreview
    "Vertical-Slit_Inverted_Nipples_AnimaP_v01-000010.safetensors|https://civitai.com/api/download/models/2740168?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Tentacle Breast Latch [Anm, IL] / Anima_v1
    "Ttcl_breast_latch_Anima_v1-000024.safetensors|https://civitai.com/api/download/models/2954001?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Wide Breast concept / anima
    "Wide Breast.safetensors|https://civitai.com/api/download/models/2938458?type=Model&format=SafeTensor"

    # Concepts / Body & Anatomy / Base:Anima / Milf Meter/Saggy Breasts & More! / anima
    "BoobTypesAnima.safetensors|https://civitai.com/api/download/models/3047337?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Concepts / Creature & Nonhuman
    # ------------------------------------------------------------

    # Concepts / Creature & Nonhuman / Base:Anima / Tentacle Lactation / anima-v4.1
    "tentacles-anima-v4.1.safetensors|https://civitai.com/api/download/models/3029787?type=Model&format=SafeTensor"

    # Concepts / Creature & Nonhuman / Base:Anima / Tentacle Oviposition (Anima, ILXL, PONY, SD 1.5) / Anima-v1.5
    "oviposition anima 2 -000008.TA_trained.safetensors|https://civitai.com/api/download/models/2972346?type=Model&format=SafeTensor"

    # Concepts / Creature & Nonhuman / Base:Anima / 機械姦/sex machine(XL,ill,pony) / v1.0 anima
    "sex machine_anima_V1.0.safetensors|https://civitai.com/api/download/models/2952118?type=Model&format=SafeTensor"

    # Concepts / Creature & Nonhuman / Base:Anima / Translucent gelly body / v1.0 anima-v1-base
    "gel_body_scaled_anima_lora.safetensors|https://civitai.com/api/download/models/2967047?type=Model&format=SafeTensor"

    # Concepts / Creature & Nonhuman / Base:Anima / Tentacle Breeding Facility (Anima, IL, Noob) / Anima v1
    "TBF_Anima_v1-000018.safetensors|https://civitai.com/api/download/models/2949430?type=Model&format=SafeTensor"

    # Concepts / Creature & Nonhuman / Base:Anima / Tentacle "impalement" (Anima, ILXL, Pony) / Anima-v1.5
    "impaled anima v2 -000006.TA_trained.safetensors|https://civitai.com/api/download/models/2969299?type=Model&format=SafeTensor"

    # Concepts / Creature & Nonhuman / Base:Anima / tentacle_tweak_under_clothes-anima / v1.0
    "tentacle_tweak_under_clothes-anima-v1.safetensors|https://civitai.com/api/download/models/3009537?type=Model&format=SafeTensor"

    # Concepts / Creature & Nonhuman / Base:Anima / Tentacle Birth [Anm, IL] / Anima_v1
    "Ttcl_Birth_Anima_v1-000024.safetensors|https://civitai.com/api/download/models/3000366?type=Model&format=SafeTensor"

    # Concepts / Creature & Nonhuman / Base:Anima / octopus_tentacles-anima / v1.0
    "octopus_tentacles-anima-v1.safetensors|https://civitai.com/api/download/models/3017848?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Concepts / Scene & Environment
    # ------------------------------------------------------------

    # Concepts / Scene & Environment / Base:Anima / 例のプール /  rei no pool / v1.0
    "reino_pool.safetensors|https://civitai.com/api/download/models/3025276?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Concepts / Interaction Concept
    # ------------------------------------------------------------

    # Concepts / Interaction Concept / Base:Anima / Balls Deep / Deep(er) Penetration / ANIMA (Pre3) V1
    "BallsDeep-Anima-V1F-Re.safetensors|https://civitai.com/api/download/models/2885588?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Defeated waifu | Imminent penetration | Concept version | Anima/Illustrious/NoobAI/Pony / Anima
    "Defeated_waifu_ANIMA.safetensors|https://civitai.com/api/download/models/2966794?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / [concept]dildo under clothes xl / Anima-Base-1.0 Ver
    "toy-3-next-b1-36.safetensors|https://civitai.com/api/download/models/2959172?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / [Pov] FootWorship - Anima | NAI VPRED | Illustrious | Pony / v0.5 [Anima Preview 1]
    "midis_FootWorship_V0.5[Anima].safetensors|https://civitai.com/api/download/models/2741922?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / [ANIMA] Concept - Vaginal Gaping (Cervix View) 膣開き（子宮口） / ana-v1.0
    "vaginal_gaping_cervix-v2-ana-concept-soralz.safetensors|https://civitai.com/api/download/models/2956220?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Cheating/Netorare | Prostitution | Concept version | Anima/Illustrious/NoobAI / Anima
    "NTRcheating_ANIMA.safetensors|https://civitai.com/api/download/models/2988964?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Stuck In Objects / v2.0
    "stuck_in_objects-simple.safetensors|https://civitai.com/api/download/models/3044998?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Giant Dom IL | Fantasy Sex concept / Dragon-AnimaV1
    "GiantDom-DragonV2IL_epoch_4.safetensors|https://civitai.com/api/download/models/2992858?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / (ANIMA) Rear Naked Choke / 裸絞め / v1.0
    "choke_hold_rnc_anima_v1.safetensors|https://civitai.com/api/download/models/3023030?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / フェラチオとオナニー/ fellatio and masturbation / v1.0 anima
    "fellatio and masturbation.safetensors|https://civitai.com/api/download/models/3000440?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / フェラチオ(複数)/cooperative fellatio(XL,pony) / v1.0 anima
    "cooperative fellatio_anima_V1.0.safetensors|https://civitai.com/api/download/models/2960407?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / ペットプレイ/pet play(XL,ill,Pony) / v1.0 anima
    "pet play_anima_V1.0.safetensors|https://civitai.com/api/download/models/2951719?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / X-ray Deepthroat fellatio oral | Anima |Illustrious / x-ray_deepthroat_Anima_V1
    "x-ray_deepthroat_V1_Anima.safetensors|https://civitai.com/api/download/models/2955554?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / セルフ挿入/guided penetration(ill,pony) / v1.0 anima
    "guided penetration_anima_V1.0.safetensors|https://civitai.com/api/download/models/3011601?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Stealth/Hidden sex | Netorare/Netorase | Concept version | Anima/Illustrious/NoobAI / Anima
    "Stealth sex_ANIMA.safetensors|https://civitai.com/api/download/models/3007070?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Concept Uncencored Anima / v01
    "uncencored-Anima-v01.safetensors|https://civitai.com/api/download/models/3002835?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Human Onahole | Fantasy Sex Concept Collection / HledBYgiantANIMA-V1
    "HumanOnahole-Anima_epoch_9.safetensors|https://civitai.com/api/download/models/2987156?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / NTR/netorare / v1.0 anima
    "netorare_anima_V1.0.safetensors|https://civitai.com/api/download/models/2936598?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / side view fellatio / 横からフェラ / v1.0
    "sideview_fellatio.safetensors|https://civitai.com/api/download/models/3021029?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / 8P  / 8人乱交   group sex / v1.0
    "8P.safetensors|https://civitai.com/api/download/models/3070249?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Rough Sex/Fucked Silly IL&Chroma | Shrekman Hentai Loras / FuckedSenslessAnima
    "fucked_sensless_Anima_epoch_8.safetensors|https://civitai.com/api/download/models/2974206?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Pussy grip and anal grip concept for Anima / v1.0
    "pussy_and_anal_gripv1.safetensors|https://civitai.com/api/download/models/2954332?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / NTR Picture / Secret Picture / v1.0 [Anima]
    "ntr_picture_anima.safetensors|https://civitai.com/api/download/models/3029153?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Pony play | Pet play | Concept version | Anima/Illustrious/NoobAI/Pony / Anima
    "Pony play_ANIMA.safetensors|https://civitai.com/api/download/models/3007069?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / バックセックス/sex from behind(ill,pony) / v1.0 anima
    "sex from behind_anima_V1.0.safetensors|https://civitai.com/api/download/models/2980425?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / 子宮貫通/deep penetration / v1.0 anima
    "cervix penetration_anima_V1.0.safetensors|https://civitai.com/api/download/models/2925669?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Masturbation with dildo / Object insertion / Anima v1.0
    "Masturbation with dildo - object insertion (Anima) v1.safetensors|https://civitai.com/api/download/models/3057069?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / multiple penetrations / v1.0 anima
    "multiple penetration_anima_V1.0.safetensors|https://civitai.com/api/download/models/2958545?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / 歯磨きフェラ/cheek bulge fellatio / v1.0 anima
    "cheek bulge fellatio_anima_V1.0.safetensors|https://civitai.com/api/download/models/3011766?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / 2way-afterimage / v0.0.3
    "concept_2way-afterimage_v0.0.3-000010.safetensors|https://civitai.com/api/download/models/3065121?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / 相互オナニー/mutual masturbation / v1.0 anima
    "mutual masturbation_anima_V1.0.safetensors|https://civitai.com/api/download/models/2978611?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / マンコ拡張/gaping pussy / v1.0 anima
    "gaping pussy_anima_V1.0.safetensors|https://civitai.com/api/download/models/3031443?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / 隠姦(ドア)/stealth sex(door) / v1.0 anima
    "stealth sex door_anima_V1.0.safetensors|https://civitai.com/api/download/models/2933692?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Ball Licking Concept - Anima / Ball-Licking-AnimaV1
    "balllickingV1Anima.safetensors|https://civitai.com/api/download/models/2743910?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Taimanin RPGX Character collection (CONCEPT) Anima / IL / Pony | 対魔忍RPGXキャラクターコレクション（コンセプト） / Anima
    "TaimaninCC_Anima_V01.safetensors|https://civitai.com/api/download/models/3051237?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Deeper  Penetration Deepthroat and something else / v1.0
    "deeper penetration.safetensors|https://civitai.com/api/download/models/3042522?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Queen's Blade GameBook Defeats (CONCEPT) Anima / IL / PONY | クイーンズブ レイド ゲームブック 敗北ポーズ集（コンセプト） / Anima
    "QB_Defeat_Anima_V01.safetensors|https://civitai.com/api/download/models/3051558?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Handjob from side (POV) / Anima v1
    "hj_from_side_v3-000009.safetensors|https://civitai.com/api/download/models/3055317?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Plantvore (Anima, Pony & Illus) / Anima-v1.0
    "plantsex anima-000006.TA_trained.safetensors|https://civitai.com/api/download/models/2980861?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / [Anima / illustrious] Flat chastity / Pov flat chastity / Anima
    "[Anima][Concept]flat_chastity_cage-10.safetensors|https://civitai.com/api/download/models/3020542?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Monster Lair/Gangbang | Fantasy Sex Concept Collection / GoblinLairV1-ANIMA
    "GoblinLairV2-ANIMA_epoch_4.safetensors|https://civitai.com/api/download/models/2987180?type=Model&format=SafeTensor"

    # Concepts / Interaction Concept / Base:Anima / Bimbofication Sequence - Bimbo - Concept - Anima LORA / BaseV1.0
    "Bimbofication_AnimaBaseV10_byKonan.safetensors|https://civitai.com/api/download/models/2968092?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Concepts / Other Concepts
    # ------------------------------------------------------------

    # Concepts / Other Concepts / Base:Anima / Freaky dicks ( Anima - Illustrious ) / Anima
    "freaky_dicks_anima.safetensors|https://civitai.com/api/download/models/2984285?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / uncensored pussy / 無修正まんこ / v1.0
    "uncensored_pussy.safetensors|https://civitai.com/api/download/models/3013861?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Small Dom Big Sub / v1.0 Anima
    "Small_Dom_Big_Sub_epoch_7.safetensors|https://civitai.com/api/download/models/3026577?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / マン汁/pussy juice / v1.0 anima
    "pussy juice_anima_V1.0.safetensors|https://civitai.com/api/download/models/2981405?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / (ANIMA) Meat Armor (cock-sleeve) / 肉鎧 / v1.0
    "meat_armor_anima_v1.safetensors|https://civitai.com/api/download/models/3001549?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / plump pussy  / ぷにまん / v1.0
    "plump_pussy.safetensors|https://civitai.com/api/download/models/3010360?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / グロマン Meaty Labia/Slutty Pussy[Anima/IL ] / Anima(v1.0)
    "slutty_pussy_anima_v1-000025.safetensors|https://civitai.com/api/download/models/2972992?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Skinsuit for Anima | 2333333 / v1.0
    "skinsuit_anima_233.safetensors|https://civitai.com/api/download/models/2751605?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / saliva/juice/fluid on penis / v0.1.1
    "saliva_juice_fluid_on_penis_ta_v0.1.1-000010.safetensors|https://civitai.com/api/download/models/3065048?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / anima3) BLACKED LORA / v1.0
    "blacked anima 3 ver.safetensors|https://civitai.com/api/download/models/2900923?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / multiple pussy / v1.0 anima
    "multiple pussy_anima_V1.0.safetensors|https://civitai.com/api/download/models/2981119?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Gyaru for Anima / v3.0 Anima Base v1
    "LoRAGalAnimaV1.safetensors|https://civitai.com/api/download/models/3036215?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Overstuffed Futanari Bottoms(Anima + IL + Pony + SD1.5) / Anima(Preview 3)
    "OverstuffedFutaBottomsAnimaV1.safetensors|https://civitai.com/api/download/models/2875205?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / (ANIMA) Kankaku Shadan Trap / 感覚遮断落とし穴 / v1.0
    "kankaku_shadan_anima_v1.safetensors|https://civitai.com/api/download/models/2944727?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / pantyjob / パンツコキ   パンコキ / v1.0
    "pantyjobV1.safetensors|https://civitai.com/api/download/models/2991489?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / RPG Character Sprite [Anima] [Illustrious] / v1.0 Anima Base v1.0
    "rpgchara-anima-base1-v1.safetensors|https://civitai.com/api/download/models/2964160?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / クロッチずらし/panties aside(XL,Pony) / v1.0 anima
    "clothing aside_anima_V1.0.safetensors|https://civitai.com/api/download/models/3010400?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / 縛り/shibari(SD,XL,ILL,pony) / v1.0 anima
    "shibari_anima_V1.0.safetensors|https://civitai.com/api/download/models/2944205?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / huge cum (anima) / v1.0
    "cum_anima_epoch_9.safetensors|https://civitai.com/api/download/models/3051396?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / AurAnima / ARB010LL04
    "auranima_arb010ll04.safetensors|https://civitai.com/api/download/models/3028468?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / better pussy and anus / v2.0
    "pussy.safetensors|https://civitai.com/api/download/models/2750177?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / フィンガリング/fingering / v1.0 anima
    "fingering_anima_V1.0.safetensors|https://civitai.com/api/download/models/3054388?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / covering privates(XL,ill,pony) / v1.0 anima
    "covering privates_anima_V1.0.safetensors|https://civitai.com/api/download/models/2923124?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / 潮吹き/ female ejaculation / v1.0 anima
    "female ejaculation_anima_V1.0.safetensors|https://civitai.com/api/download/models/2980272?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / ハーレム/harem / v1.0 anima
    "harem_anima_V1.0.safetensors|https://civitai.com/api/download/models/2922803?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / hand in panties / v1.0 anima
    "hand in panties_anima_V1.0.safetensors|https://civitai.com/api/download/models/2928187?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / doggy with anal fingering / バックでアナル指入れ (ANIMA) / v1.0
    "doggywith_analfingeringANIMA.safetensors|https://civitai.com/api/download/models/3005705?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Cum beam / Cum blast / Hyper projectile cum / Anima Preview 3 1st
    "cum_beam_anima.safetensors|https://civitai.com/api/download/models/2850392?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Shortstack Body (Illustrious + Anima) / Anima P3 v1.0
    "shortstack_anima_v1.safetensors|https://civitai.com/api/download/models/2934100?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / [Anima] Flash 8 steps cfg 1 distilled / v4-baseV10
    "ep80.safetensors|https://civitai.com/api/download/models/3040588?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / SAGGY FLOPPY TITTIES / Floppy Titties Anima v4.0
    "Floppy Titties Anima v4.safetensors|https://civitai.com/api/download/models/2946671?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / スジマン/innie pussy / v1.0 anima
    "innie pussy_anima_V1.0.safetensors|https://civitai.com/api/download/models/2940835?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / ローションまみれ  lotion-covered body / v1.0
    "lotion-covered_body.safetensors|https://civitai.com/api/download/models/3044147?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Goblin Rider / Frog embrace position / v1.0 [Anima]
    "goblin_rider_anima.safetensors|https://civitai.com/api/download/models/3029266?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / OOO_Anima / V10
    "oooAnima_v10.safetensors|https://civitai.com/api/download/models/2961949?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / 仕込みローター/ vibrator under clothes(ILL,pony) / v1.0 anima
    "vibrator under clothes_anima_V1.0.safetensors|https://civitai.com/api/download/models/2980339?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Fantasy Wizard & Witches / Anima V2
    "AnimaMagicV2-000008.safetensors|https://civitai.com/api/download/models/3021113?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Anima, Pony V7 & illustrious-SDXL 𝓊𝓃𝓇ℯ𝓉𝓇𝒶𝒸𝓉ℯ𝒹 𝒻ℴ𝓇ℯ𝓈𝓀𝒾𝓃 𝒹𝒾𝒸𝓀 LoRA (Foreskin) / Anima V2
    "Anima_unretracted_foreskin_lora_v2.safetensors|https://civitai.com/api/download/models/2778061?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / 鵯越の逆落とし / Dynamic Riding Position  (V2)  48手 / v1.0
    "Dynamic_RidingPositionV2.safetensors|https://civitai.com/api/download/models/3050548?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / ビラビラ引っ張り Pinch and Pull Labia [Anima/IL] / Anima(v1.0)
    "pulling_labia_anima_v1-000030.safetensors|https://civitai.com/api/download/models/2978823?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Penis Size Difference / v1.0 Anima
    "Penis_Size_Difference_epoch_2.safetensors|https://civitai.com/api/download/models/3027209?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Cumtube feeding (Pony, Illus & Anima) / Anima v1.5
    "cumtube anima v2-000006.TA_trained.safetensors|https://civitai.com/api/download/models/2955364?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Condom left inside (Anima & Illustrious) / Anima-v1.5
    "Condom_inside_animav2_epoch_9.safetensors|https://civitai.com/api/download/models/3051993?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Anima LoRA Excessive pubic hair + pubic hair peek / excessive pubic hair v2.0
    "Anima_excessive_pubic_hair_v2.0.safetensors|https://civitai.com/api/download/models/3045532?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Anal Grip for Anima / v2.0 Anima Base v1.0
    "LoRAAnalGripAnimaV1.safetensors|https://civitai.com/api/download/models/3041926?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / 浣腸/enema(pony) / v1.0 anima
    "syringe enema_anime_V1.0.safetensors|https://civitai.com/api/download/models/3019797?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Futanari Side Bulge((Anima + IL + Pony) / Anima(Preview 3)
    "SideBulgeV1.safetensors|https://civitai.com/api/download/models/2905254?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / defeatGLGB(Garbage/Trash girl) / ver.Anima
    "defeatGLGBAN.safetensors|https://civitai.com/api/download/models/2923207?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / パンツの皺/panties wrinkles / v1.0 anima
    "panties wrinkles_anima_V1.0.safetensors|https://civitai.com/api/download/models/2932702?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / ロ○巨乳/Bust Size (Big)(XL,ill,pony) / v1.0 anima
    "lkp_anima_V1.0.safetensors|https://civitai.com/api/download/models/3045581?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / パンツを履く/dressing panties / v1.0 anime
    "dressing panties_anima_V1.0.safetensors|https://civitai.com/api/download/models/2922718?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / ディルド　イン　パンティー/dildo under panties / v1.0 anima
    "dildo under clothes_anima_V1.0.safetensors|https://civitai.com/api/download/models/3054672?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / shortstack (Ver. Anima, Illustrious, flux, NoobAi) / vAnima
    "shortstack_vAnima.safetensors|https://civitai.com/api/download/models/2927008?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / secretly photographed / v1.0
    "daos_lora_lora-000005.safetensors|https://civitai.com/api/download/models/3043613?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Shower Stimulation -Anima / v1.1 Anima base-v1.0
    "326_shower_stimulation_1.1.safetensors|https://civitai.com/api/download/models/2989116?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Huge penis insertion (Illustrious) / v1.0 Anima base
    "huge-penis-insertion-anima-base.safetensors|https://civitai.com/api/download/models/2956169?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Giantess / anima-v1
    "gts-anima-v1.safetensors|https://civitai.com/api/download/models/2977736?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / League of Legends Splash Art / 1.0-anima
    "league of legends official art.safetensors|https://civitai.com/api/download/models/3036250?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / 裸リボン/naked ribbon(SD,XL,ill,pony) / v1.0 anima
    "naked ribbon.safetensors|https://civitai.com/api/download/models/2951761?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Rough Gang Bang IL&Chroma | Shrekman Hentai Loras / Anima-KuroinuPoseV1
    "OlgaPoseGangbang_epoch_8.safetensors|https://civitai.com/api/download/models/3001256?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Better Pregnant Belly (Illustrious & Anima) / Anima v1.0
    "better_pregnant_belly_anima_V1.safetensors|https://civitai.com/api/download/models/2944189?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Spiderwebbed (Anima, ILXL, Pony) / Anima-v1.5
    "spiderwebbed anima 2 -000007.TA_trained.safetensors|https://civitai.com/api/download/models/2966613?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Boss Battle - By HailoKnight / Anima
    "AnimaBossBattleV1-000009.safetensors|https://civitai.com/api/download/models/2912978?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / 使用済みコンドーム/used condom on penis / v1.0 anima
    "used condom on penis_anima_V1.0.safetensors|https://civitai.com/api/download/models/2906477?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Forearm Cock / v1.0 Anima
    "Forearm_Cock_epoch_4.safetensors|https://civitai.com/api/download/models/3017052?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / はみケツ/underbutt / v1.0 anima
    "hamiketsu_anima_V1.0.safetensors|https://civitai.com/api/download/models/2960680?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Improved Horsecock(Anima + IL + Pony) / Anima(Preview 3)
    "ImprovedEquinePenisAnimaV1.safetensors|https://civitai.com/api/download/models/2888882?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Anima Highres Boost(2K Resolution) / 2560*1472 basev1
    "highres_fix-step00000300.safetensors|https://civitai.com/api/download/models/3001940?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / 悪落ち/corruption / v1.0 anima
    "corruption_anima_V1.0.safetensors|https://civitai.com/api/download/models/2980322?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / 茶臼のばし / Millstone motion pose (V2) 48手 / v1.0
    "Millstone_motionposeV2.safetensors|https://civitai.com/api/download/models/3030966?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Futanari Up Bulge(Anima + IL + Pony) / Anima(Preview 3)
    "NorthBulgeV1.safetensors|https://civitai.com/api/download/models/2883382?type=Model&format=SafeTensor"

    # Concepts / Other Concepts / Base:Anima / Slime Body + Internal Organs Lora / v1.0
    "Slime_Internal_Organs_V1.1_1024x.safetensors|https://civitai.com/api/download/models/2968554?type=Model&format=SafeTensor"


    # ============================================================
    # Poses
    # ============================================================

    # ------------------------------------------------------------
    # Poses / Viewpoint & POV
    # ------------------------------------------------------------

    # Poses / Viewpoint & POV / Base:Anima / Female POV / anima
    "FemPOVAnima.safetensors|https://civitai.com/api/download/models/2948925?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / The Look / v1.0 Anima Preview
    "The-Look-Anima3-800.safetensors|https://civitai.com/api/download/models/2997490?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / [Anima] Canny control LoRA (ControlNet-like) / v0.2
    "anima-preview-canny-v0.2.safetensors|https://civitai.com/api/download/models/2748244?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / [Illu/Anima] Male Bottom POV / v3.0 Anima Edition
    "Male_Bottom_POV_epoch_5.safetensors|https://civitai.com/api/download/models/3004046?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / Civitai  ローアングルはだけ服（anima） / low angle open clothes.（anima） / v1.0
    "laoc-anima_v1_1024_8gb_bf16.safetensors|https://civitai.com/api/download/models/2959117?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / Male Bottom Pov / Anima
    "male_bottom_pov_Anima.safetensors|https://civitai.com/api/download/models/2975059?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / POV Full Spread Legs Pussy Mirror [Anima] / v1.0
    "pov pssy mirror anima.safetensors|https://civitai.com/api/download/models/2954078?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / Step on Crotch - POV / Anima Preview 3
    "step_on_crotch_anima.safetensors|https://civitai.com/api/download/models/2935763?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / VHS_package_ple (meme) ANIMA LORA / 001　preview2
    "MEME_VHS_package_pleANIMA001.safetensors|https://civitai.com/api/download/models/2936359?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / Yandere Pov Vaginal [Anima] / v1.0
    "yandere cowgirl pov.safetensors|https://civitai.com/api/download/models/2954258?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / shadowHandBra - Trend Pose LoRA , artistic censorship / Preview3
    "pose_ShadowHandBra.safetensors|https://civitai.com/api/download/models/2893691?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / Jaou Ensatsu Kokuryuha / Yu Yu Hakusho / Pose LoRA / NoobAI / v2.0 Anima Preview3
    "LoRAKokuryuhaAnimaPreview3.safetensors|https://civitai.com/api/download/models/2911614?type=Model&format=SafeTensor"

    # Poses / Viewpoint & POV / Base:Anima / Empowerment Flex - Flexing one biceps with hand on own arm / anima-preview_v1.0
    "EmpowerFlex_ani_v1.safetensors|https://civitai.com/api/download/models/2812223?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Poses / Pose Helper & Control
    # ------------------------------------------------------------

    # Poses / Pose Helper & Control / Base:Anima / Posing Dynamics / v1.0 Anima base
    "posing-dynamics-anima-base-800.safetensors|https://civitai.com/api/download/models/3026653?type=Model&format=SafeTensor"

    # Poses / Pose Helper & Control / Base:Anima / Jack-O Challenge Pose Helper (REAR & FRONT) ANIMA / v1.0
    "jacko-000003.safetensors|https://civitai.com/api/download/models/2886534?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Poses / Meme & Challenge
    # ------------------------------------------------------------

    # Poses / Meme & Challenge / Base:Anima / Amen pose (meme) / v1
    "AmenPose.safetensors|https://civitai.com/api/download/models/2948071?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / he_wants_to_order_(meme) / v1.0
    "m44aafft_hwtom_9071_lyvi_Anima_he_wants_to_order_meme-000003.safetensors|https://civitai.com/api/download/models/2918051?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / amen_pose_(meme) / v1.0
    "m44aafft_apm_9367_tknh_Anima_amen_pose_meme-000005.safetensors|https://civitai.com/api/download/models/2915684?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / Amen Pose (Meme) [Anima] / Anima base v1.0
    "amenposemxi.safetensors|https://civitai.com/api/download/models/3062172?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / (Anima Pose) Smoking at No Smoking Sign (meme) / v1.0
    "smoking_sign_anima_1_d16.safetensors|https://civitai.com/api/download/models/2968340?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / lace_pantyhose_hooked_on_heel_(meme) / v1.0
    "m44aafft_lphohm_3399_jufk_Anima_lace_pantyhose_hooked_on_heel_meme-000003.safetensors|https://civitai.com/api/download/models/2916900?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / Mirai Nikki Yandere Face - Meme Concept / Anima V1
    "Mirai_Nikki_Yandere_Face_epoch_10.safetensors|https://civitai.com/api/download/models/3066232?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / do_you_want_to_pet_my_cat_(meme) / v1.0
    "m44aafft_dywtpmcm_7475_wjww_Anima_do_you_want_to_pet_my_cat_meme.safetensors|https://civitai.com/api/download/models/2918065?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / hand_shadow_covering_breasts_(meme) / v1.0
    "m44aafft_hscbm_0687_czfh_Anima_hand_shadow_covering_breasts_meme-000003.safetensors|https://civitai.com/api/download/models/2915864?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / dressed_shadow_(meme) / v1.0
    "m44aafft_dsm_3485_bvor_Anima_dressed_shadow_meme.safetensors|https://civitai.com/api/download/models/2918372?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / cat_shadow_puppet_(meme) / v1.0
    "m44aafft_cspm_7747_vifa_Anima_cat_shadow_puppet_meme-000003.safetensors|https://civitai.com/api/download/models/2915807?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / effort effort (meme エッホエッホ) / Pose LoRA / NoobAI / v2.0 AnimaYume v025
    "LoRAEffortEffortAnimaYume_v025.safetensors|https://civitai.com/api/download/models/2796416?type=Model&format=SafeTensor"

    # Poses / Meme & Challenge / Base:Anima / Civitai ネットミーム マカンコウサッポウ（Anima） / Makankosappo with meme.（Anima） / v1.0
    "mknspo-anima_v1_1024_8gb_bf16.safetensors|https://civitai.com/api/download/models/2956199?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Poses / Hand & Gesture
    # ------------------------------------------------------------

    # Poses / Hand & Gesture / Base:Anima / girl on top licking nipple and nipple tweak / Anima and NoobAI / v4.0 Anima Base v1.0
    "LoRALickingNippleAnimaV1.safetensors|https://civitai.com/api/download/models/3041529?type=Model&format=SafeTensor"

    # Poses / Hand & Gesture / Base:Anima / sex and anal fingering for Anima / v2.0 Anima Base v1.0
    "LoRASexAndAnalFingeringAnimaV1.safetensors|https://civitai.com/api/download/models/3039459?type=Model&format=SafeTensor"

    # Poses / Hand & Gesture / Base:Anima / 尻上げ姿勢/bottom up and hands between legs / v1.0 anima
    "arms between legs_anima_V1.0.safetensors|https://civitai.com/api/download/models/2980300?type=Model&format=SafeTensor"

    # Poses / Hand & Gesture / Base:Anima / Handgag (Anima/Illustrious) / Anima (Prev 3)
    "Handgag_AnimaP3_v1.safetensors|https://civitai.com/api/download/models/2934408?type=Model&format=SafeTensor"

    # Poses / Hand & Gesture / Base:Anima / スカートを抑える/skirt tug(SD,XL,pony) / v1.0 anima
    "skirt tug_anima_V1.0.safetensors|https://civitai.com/api/download/models/2969154?type=Model&format=SafeTensor"

    # Poses / Hand & Gesture / Base:Anima / Fingering X-ray / v1.0 AnimaBase v1.0
    "LoRAFingeringXrayAnimaV1.safetensors|https://civitai.com/api/download/models/3044687?type=Model&format=SafeTensor"

    # Poses / Hand & Gesture / Base:Anima / Penetration Gesture -Anima / v1.0 Anima base1.0
    "349_penetration_gesture_v1.0_Anima.safetensors|https://civitai.com/api/download/models/3040275?type=Model&format=SafeTensor"

    # Poses / Hand & Gesture / Base:Anima / (Anima Pose) Finger Frame Over Eye / v1.0
    "finger_frame_over_eye_anima_1_final.safetensors|https://civitai.com/api/download/models/3024626?type=Model&format=SafeTensor"

    # Poses / Hand & Gesture / Base:Anima / Nipple tweak with crossed arms / Anima
    "Nipple_tweak_with_crossed_arms_epoch_5_modified.safetensors|https://civitai.com/api/download/models/3023031?type=Model&format=SafeTensor"

    # Poses / Hand & Gesture / Base:Anima / Thinking Abs | DaBerry!🧠💪 / 🌳🌳ANIMA🌳🌳
    "DaShirtLiftbyonehand_epoch_3.safetensors|https://civitai.com/api/download/models/3021947?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Poses / Floor & Leg Pose
    # ------------------------------------------------------------

    # Poses / Floor & Leg Pose / Base:Anima / だいしゅきホールド/leg lock / v1.0 anima
    "leg lock_anima_V1.0.safetensors|https://civitai.com/api/download/models/2951709?type=Model&format=SafeTensor"

    # Poses / Floor & Leg Pose / Base:Anima / まんぐり返し/folded pose / v1.0 anima
    "manguri_anima_V1.0.safetensors|https://civitai.com/api/download/models/2923111?type=Model&format=SafeTensor"

    # Poses / Floor & Leg Pose / Base:Anima / 雌犬ポーズ/paw pose / v1.0 anima
    "paw pose_anima_V1.0.safetensors|https://civitai.com/api/download/models/2903345?type=Model&format=SafeTensor"

    # Poses / Floor & Leg Pose / Base:Anima / 股割り/splits / v1.0 anima
    "split_anima_V1.0.safetensors|https://civitai.com/api/download/models/3032440?type=Model&format=SafeTensor"

    # Poses / Floor & Leg Pose / Base:Anima / 押し車/Wheelbarrow position / v1.0 anima
    "wheelbarrow position_anima_V1.0.safetensors|https://civitai.com/api/download/models/3065012?type=Model&format=SafeTensor"

    # Poses / Floor & Leg Pose / Base:Anima / 座礼/zarei(ILL,pony) / v1.0 anima
    "zarei_anima_V1.0.safetensors|https://civitai.com/api/download/models/2988383?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Poses / Standing & Dance
    # ------------------------------------------------------------

    # Poses / Standing & Dance / Base:Anima / ポールダンス/pole dancing / v1.0 anima
    "pole dancing_anima_V1.0.safetensors|https://civitai.com/api/download/models/2969086?type=Model&format=SafeTensor"

    # Poses / Standing & Dance / Base:Anima / miaomiao pentagram pose  五角星姿势 / v1.0
    "miaomiaoPentagramPose_v10.safetensors|https://civitai.com/api/download/models/2973067?type=Model&format=SafeTensor"

    # Poses / Standing & Dance / Base:Anima / Pose : BDSM standing pillory / Anima 0.1
    "mai_bdsm_pillory2_anima.safetensors|https://civitai.com/api/download/models/2981061?type=Model&format=SafeTensor"

    # Poses / Standing & Dance / Base:Anima / 空中バック | Lifted Standing Doggy | 托举后入姿势 / Anima
    "LiftedStandingDoggy.safetensors|https://civitai.com/api/download/models/3067940?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Poses / Action & Interaction Pose
    # ------------------------------------------------------------

    # Poses / Action & Interaction Pose / Base:Anima / 2FSpreadAnus / Pose LoRA / Anima and NoobAI XL and Illustrious-XL / v6.1 Anima Base v1.0
    "LoRA2FSpreadAnusAnimaV1.safetensors|https://civitai.com/api/download/models/3038932?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / Kissy face / Thick Lips & Thick tongue / v3.0 Anima Base v1
    "LoRABuchuKissAnimaV1.safetensors|https://civitai.com/api/download/models/3019071?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / Hentai Pussy inspection 2shot Anima / Pony / IL  | まんこ検査（完全着衣立 絵と全裸くぱぁの2ショット） / Anima
    "Hentai_Pussy_inspection2_Anima_V01.safetensors|https://civitai.com/api/download/models/3055825?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / 貝合わせ/tribadism / v1.0 anima
    "tribadism_anima_V1.0.safetensors|https://civitai.com/api/download/models/2971467?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / Hentai Pussy inspection Anima / Pony / IL XL |  満珍楼 (COSiNE) / Anima
    "Hentai_Pussy_inspection_Anima_V01.safetensors|https://civitai.com/api/download/models/3055248?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / Check This ASS Pose / v1.0 [Anima]
    "ass_pose_anima.safetensors|https://civitai.com/api/download/models/3026281?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / [Anima] 交尾結合/butt to butt copulation (human) Pose / v1.0
    "b2bc_v1_epoch56.safetensors|https://civitai.com/api/download/models/3066227?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / negative space cunnilingus(anima) / v0.5
    "negative_space_cunnilingus.safetensors|https://civitai.com/api/download/models/2702811?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / BBL Ass Pose / v1.0 [Anima]
    "bbl_pose.safetensors|https://civitai.com/api/download/models/3039472?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / Licking butt plug (IL\ANI) / LBP_ep10_ANI_by_ME
    "POSE_-_Licking_butt_plug_ep10_ANI_by_ME.safetensors|https://civitai.com/api/download/models/3049783?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / Irrumatio / v1.0 [Anima]
    "irrumatio.safetensors|https://civitai.com/api/download/models/3059515?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / Anima ballbusting / v0.1
    "2spzn_piro-000005.safetensors|https://civitai.com/api/download/models/2949607?type=Model&format=SafeTensor"

    # Poses / Action & Interaction Pose / Base:Anima / girl_and_tulpa / AN_basev1
    "girl_and_tulpa_AN_basev1.safetensors|https://civitai.com/api/download/models/3027862?type=Model&format=SafeTensor"


    # ------------------------------------------------------------
    # Poses / Other Poses
    # ------------------------------------------------------------

    # Poses / Other Poses / Base:Anima / Clothes Lifted By Tail / anima
    "LiftedByTailAnima.safetensors|https://civitai.com/api/download/models/3063629?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / clothes lift and presenting / v1.0
    "anima_clothes_lift_and_presenting.safetensors|https://civitai.com/api/download/models/2688746?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / NSFW动作/姿势/视角二次元Lora / v1.0
    "my_anima_lora-step00003000.safetensors|https://civitai.com/api/download/models/2993504?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Arasoe / anima-v4.0
    "arasoe-anima-v4.0.safetensors|https://civitai.com/api/download/models/2947805?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / crotch blowjob / v1.0
    "bpg_concept.safetensors|https://civitai.com/api/download/models/3012139?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Blue Lock Feet Fetish |Anima| / Anima
    "blue_lock_feet_fetish-000006.safetensors|https://civitai.com/api/download/models/3056542?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / 69 Face Focus     [Anima + IL] / Anima 69ff
    "XBJ9P16C4SAE9K9AAXWZK0K2H0.safetensors|https://civitai.com/api/download/models/3068355?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Head insertion in pussy / ANIMA
    "head pussy.safetensors|https://civitai.com/api/download/models/3070911?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Protrusion uterine[sex,grab,spraying cum] / ANIMA
    "uterine protrusion.safetensors|https://civitai.com/api/download/models/3064900?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Sneaker Job / Anima
    "Sneaker_Job_Anima.safetensors|https://civitai.com/api/download/models/3014166?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / cum in mouth and facial / v1.0
    "lrxb_concept.safetensors|https://civitai.com/api/download/models/3015050?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / BD2 - Latex / anima base v1.0
    "latexturn_anima_base_v1.safetensors|https://civitai.com/api/download/models/2953388?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Forbidden Pants Outfit / v1.0
    "m44aafft_fp_0557_ydgv_Anima_forbidden_pants.safetensors|https://civitai.com/api/download/models/2920423?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / shibari squat / v1.0
    "gjf.safetensors|https://civitai.com/api/download/models/3015001?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / 汉堡姿势 （hamburger pose） / v1.0
    "hamburger_pose_v1.safetensors|https://civitai.com/api/download/models/3030114?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / 神無月の巫女EDパロ/神无月的巫女ED巫女抱/Kannazuki no Miko Ed Parodies(Anima) / v1.0
    "ed_anima5-step00001200.safetensors|https://civitai.com/api/download/models/2980551?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / (Anima Pose) Foot Archery / v1.0
    "foot_archery_anima_1.safetensors|https://civitai.com/api/download/models/3070008?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Dunk shot / Basketball / v2.0 Anima Base v1.0
    "LoRADunkShotAnimaV1.safetensors|https://civitai.com/api/download/models/2993877?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Footjob / v1.0 [Anima]
    "footjob.safetensors|https://civitai.com/api/download/models/3059530?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / horayo328518 / v1.0
    "horayo328518-step00004000.safetensors|https://civitai.com/api/download/models/2976221?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / When It Finally Hits You - Reaction Image / Anima
    "WhenItFinallyHitsYouAnima.safetensors|https://civitai.com/api/download/models/3030753?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Curled Toes/Toe scrunch / px1024-v1.0
    "Toe_scrunch_1024_v1.safetensors|https://civitai.com/api/download/models/2902052?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Penis Around Waist / anima
    "Penis around waist.safetensors|https://civitai.com/api/download/models/3058564?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / Gojo Satoru Honored One Pose | 五条悟 天上天下唯我独尊 经典姿势 LoRA / v1.0
    "tianshangtianxia_anima_lora12138.safetensors|https://civitai.com/api/download/models/2964245?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / onigiri shaped under armpit / AN_v1
    "OSUA_AN_v1.safetensors|https://civitai.com/api/download/models/2886037?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / 520 Sign Holder / 举520牌子 LoRA / v1.0
    "520anima12138.safetensors|https://civitai.com/api/download/models/2960991?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / one_arm_hanging_down / AN_basev1
    "one_arm_hanging_down_AN_basev1.safetensors|https://civitai.com/api/download/models/3047850?type=Model&format=SafeTensor"

    # Poses / Other Poses / Base:Anima / tatuno_kuchi_pose / AN_v1
    "train_AN_v1.safetensors|https://civitai.com/api/download/models/2867537?type=Model&format=SafeTensor"


    # ============================================================
    # Style
    # Manual
    # ============================================================

    # Style / TODO
    # "example.safetensors|https://civitai.com/api/download/models/0000000?type=Model&format=SafeTensor"


    # ============================================================
    # Action
    # Manual
    # ============================================================

    # Action / TODO
    # "example.safetensors|https://civitai.com/api/download/models/0000000?type=Model&format=SafeTensor"

)


# ============================================================
# Functions
# ============================================================
function log() {
    printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

function pip_install() {
    if command -v uv >/dev/null 2>&1; then
        uv pip install --system "$@" || python -m pip install "$@"
    else
        python -m pip install "$@"
    fi
}

function provisioning_get_apt_packages() {
    log "Installing apt packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y || true
    apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}" || true
    update-ca-certificates || true
}

function provisioning_get_pip_packages() {
    log "Installing pip packages"
    for pkg in "${PIP_PACKAGES[@]}"; do
        pip_install "$pkg" || true
    done
}

function provisioning_pin_comfyui_version() {
    log "Pinning ComfyUI to ${COMFYUI_VERSION}"
    if [[ ! -d "${COMFYUI_DIR}/.git" ]]; then
        echo "WARNING: ${COMFYUI_DIR} is not a git checkout. Skipping ComfyUI version pin."
        return 0
    fi
    (
        cd "${COMFYUI_DIR}" || exit 0
        git fetch --tags --force origin || true
        git checkout -f "${COMFYUI_VERSION}" || git checkout -f "64b8457" || true
    )
    if [[ -f "${COMFYUI_DIR}/requirements.txt" ]]; then
        pip_install -r "${COMFYUI_DIR}/requirements.txt" || true
    fi
}

function repo_name_from_url() {
    local url="$1"
    local name="${url##*/}"
    name="${name%.git}"
    echo "$name"
}

function clone_or_update_node() {
    local repo="$1"
    local name
    name="$(repo_name_from_url "$repo")"
    local dest="${COMFYUI_DIR}/custom_nodes/${name}"

    mkdir -p "${COMFYUI_DIR}/custom_nodes"

    if [[ -d "${dest}/.git" ]]; then
        log "Updating node: ${name}"
        (cd "$dest" && git pull --ff-only || true)
    else
        log "Cloning node: ${name}"
        git clone --depth=1 "$repo" "$dest" || true
    fi

    if [[ -f "${dest}/requirements.txt" ]]; then
        log "Installing requirements for ${name}"
        pip_install -r "${dest}/requirements.txt" || true
    fi

    if [[ -f "${dest}/install.py" ]]; then
        log "Running install.py for ${name}"
        (cd "$dest" && python install.py) || true
    fi
}


function resolve_manager_node_repos() {
    local query="$1"
    local manager_dir="${COMFYUI_DIR}/custom_nodes/comfyui-manager"
    local node_list="${manager_dir}/custom-node-list.json"

    if [[ ! -f "${node_list}" ]]; then
        log "WARNING: ComfyUI-Manager custom-node-list.json not found; cannot resolve: ${query}"
        return 0
    fi

    python3 - "${node_list}" "${query}" <<'PY_RESOLVE'
import json, re, sys
from pathlib import Path

path = Path(sys.argv[1])
query = sys.argv[2].lower()
query_words = [w for w in re.split(r"[^a-z0-9]+", query) if w]

try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    sys.exit(0)

url_re = re.compile(r"https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:\.git)?")
candidates = []

def iter_dicts(obj):
    if isinstance(obj, dict):
        yield obj
        for v in obj.values():
            yield from iter_dicts(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from iter_dicts(v)

for d in iter_dicts(data):
    dumped = json.dumps(d, ensure_ascii=False).lower()
    if query in dumped or all(w in dumped for w in query_words):
        urls = []
        for u in re.findall(url_re, json.dumps(d, ensure_ascii=False)):
            if u not in urls:
                urls.append(u)
        if urls:
            score = 0
            for key in ("title", "name", "id", "description"):
                val = str(d.get(key, "")).lower()
                if query in val:
                    score += 10
                if all(w in val for w in query_words):
                    score += 5
            candidates.append((score, urls))

candidates.sort(key=lambda x: x[0], reverse=True)
printed = []
for _, urls in candidates:
    for url in urls:
        if url not in printed:
            printed.append(url)
            print(url)
            if len(printed) >= 3:
                sys.exit(0)
PY_RESOLVE
}

function provisioning_get_manager_db_nodes() {
    local query repo_url found_any
    for query in "${MANAGER_NODE_QUERIES[@]}"; do
        found_any="false"
        while IFS= read -r repo_url; do
            [[ -n "${repo_url}" ]] || continue
            found_any="true"
            log "Resolved optional node: ${query} -> ${repo_url}"
            clone_or_update_node "${repo_url}"
        done < <(resolve_manager_node_repos "${query}")

        if [[ "${found_any}" != "true" ]]; then
            log "WARNING: optional Manager DB node not resolved: ${query}"
        fi
    done
}

function provisioning_get_extra_nodes() {
    if [[ -z "${EXTRA_CUSTOM_NODES:-}" ]]; then
        return 0
    fi

    log "Installing EXTRA_CUSTOM_NODES"
    # shellcheck disable=SC2206
    local extra_nodes=( ${EXTRA_CUSTOM_NODES} )
    local repo
    for repo in "${extra_nodes[@]}"; do
        clone_or_update_node "$repo"
    done
}

function provisioning_get_nodes() {
    for repo in "${CUSTOM_NODES[@]}"; do
        clone_or_update_node "$repo"
    done

    provisioning_get_manager_db_nodes
    provisioning_get_extra_nodes
}

function provisioning_set_manager_config() {
    log "Setting ComfyUI-Manager config: security_level=${COMFYUI_MANAGER_SECURITY_LEVEL}"

    local config_dirs=(
        "${COMFYUI_DIR}/user/__manager"
        "${COMFYUI_DIR}/user/default/ComfyUI-Manager"
    )

    for config_dir in "${config_dirs[@]}"; do
        mkdir -p "$config_dir"
        cat > "${config_dir}/config.ini" <<EOF_CFG
[default]
security_level = ${COMFYUI_MANAGER_SECURITY_LEVEL}
allow_git_url_install = ${COMFYUI_MANAGER_ALLOW_GIT_URL_INSTALL}
allow_pip_install = ${COMFYUI_MANAGER_ALLOW_PIP_INSTALL}
network_mode = ${COMFYUI_MANAGER_NETWORK_MODE}
bypass_ssl = ${COMFYUI_MANAGER_BYPASS_SSL}
file_logging = True
default_cache_as_channel_url = False
preview_method = auto
badge_mode = none
channel_url = https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main
EOF_CFG
        log "ComfyUI-Manager config written: ${config_dir}/config.ini"
    done
}

function append_token_to_url() {
    local url="$1"
    local token="$2"

    if [[ -z "$token" ]]; then
        echo "$url"
        return 0
    fi

    if [[ "$url" == *"civitai.com/api/download"* || "$url" == *"civitai.red/api/download"* ]]; then
        if [[ "$url" == *"?"* ]]; then
            echo "${url}&token=${token}"
        else
            echo "${url}?token=${token}"
        fi
    else
        echo "$url"
    fi
}

function resolve_civitai_page_url() {
    local filename="$1"
    local raw_url="$2"
    local model_id=""

    if [[ "$raw_url" =~ ^civitai-model:([0-9]+)$ ]]; then
        model_id="${BASH_REMATCH[1]}"
    elif [[ "$raw_url" =~ civitai\.(com|red)/models/([0-9]+) ]]; then
        model_id="${BASH_REMATCH[2]}"
    else
        echo "$raw_url"
        return 0
    fi

    local api="https://civitai.com/api/v1/models/${model_id}"
    local auth_args=()
    if [[ -n "${CIVITAI_TOKEN:-}" ]]; then
        auth_args=(-H "Authorization: Bearer ${CIVITAI_TOKEN}")
    fi

    local json
    json="$(curl -fsSL "${auth_args[@]}" "$api")" || {
        echo "WARNING: Failed to resolve Civitai model ${model_id}; skipping ${filename}" >&2
        echo ""
        return 0
    }

    local version_id
    version_id="$(jq -r --arg fn "$filename" '
        def safe_files: .modelVersions[]? as $v | $v.files[]? | {vid: $v.id, fname: .name, primary: (.primary // false)};
        ([safe_files | select(.fname == $fn)][0].vid)
        // ([safe_files | select(.primary == true)][0].vid)
        // (.modelVersions[0].id // empty)
    ' <<< "$json")"

    if [[ -z "$version_id" || "$version_id" == "null" ]]; then
        echo "WARNING: No modelVersion id found for Civitai model ${model_id}; skipping ${filename}" >&2
        echo ""
        return 0
    fi

    if [[ "$filename" == *.safetensors ]]; then
        echo "https://civitai.com/api/download/models/${version_id}?type=Model&format=SafeTensor"
    else
        echo "https://civitai.com/api/download/models/${version_id}?type=Model"
    fi
}

function download_civitai_with_curl() {
    local dest_dir="$1"
    local filename="$2"
    local url="$3"
    local outfile="${dest_dir}/${filename}"
    local tmpfile="${outfile}.part"

    rm -f "$tmpfile"

    # Civitai redirects to a short-lived b2.civitai.com signed URL.
    # aria2 may send ranged/multi-connection requests and may also replay headers
    # across redirects, which often causes systematic 403 responses from B2.
    # Use a fresh single-stream curl request for Civitai instead.
    curl \
        -fL \
        --retry "${ARIA2_MAX_TRIES}" \
        --retry-delay "${ARIA2_RETRY_WAIT}" \
        --retry-all-errors \
        --connect-timeout "${ARIA2_CONNECT_TIMEOUT}" \
        --progress-bar \
        -o "$tmpfile" \
        "$url" && mv "$tmpfile" "$outfile" && return 0

    echo "WARNING: Civitai curl download failed: ${filename}" >&2
    rm -f "$tmpfile"
    return 0
}

function download_one() {
    local dest_dir="$1"
    local entry="$2"
    local filename="${entry%%|*}"
    local url="${entry#*|}"

    if [[ -z "$filename" || -z "$url" || "$filename" == "$url" ]]; then
        echo "WARNING: malformed model entry: $entry" >&2
        return 0
    fi

    mkdir -p "$dest_dir"

    if [[ -s "${dest_dir}/${filename}" ]]; then
        echo "Already exists: ${dest_dir}/${filename}"
        return 0
    fi

    if [[ -f "${dest_dir}/${filename}" ]]; then
        echo "Removing empty/incomplete file: ${dest_dir}/${filename}"
        rm -f "${dest_dir}/${filename}"
    fi

    url="$(resolve_civitai_page_url "$filename" "$url")"
    if [[ -z "$url" ]]; then
        return 0
    fi
    url="$(append_token_to_url "$url" "${CIVITAI_TOKEN:-}")"

    log "Downloading ${filename}"

    if [[ "$url" == *"civitai.com"* || "$url" == *"civitai.red"* ]]; then
        download_civitai_with_curl "$dest_dir" "$filename" "$url"
        return 0
    fi

    local aria_headers=()
    if [[ "$url" == *"huggingface.co"* && -n "${HF_TOKEN:-}" ]]; then
        aria_headers+=(--header="Authorization: Bearer ${HF_TOKEN}")
    fi

    aria2c \
        --max-connection-per-server="${ARIA2_CONNECTIONS}" \
        --split="${ARIA2_SPLIT}" \
        --min-split-size="${ARIA2_MIN_SPLIT_SIZE}" \
        --continue=true \
        --always-resume=true \
        --allow-overwrite=false \
        --auto-file-renaming=false \
        --summary-interval=10 \
        --console-log-level=notice \
        --download-result=full \
        --timeout="${ARIA2_TIMEOUT}" \
        --connect-timeout="${ARIA2_CONNECT_TIMEOUT}" \
        --max-tries="${ARIA2_MAX_TRIES}" \
        --retry-wait="${ARIA2_RETRY_WAIT}" \
        --file-allocation=none \
        "${aria_headers[@]}" \
        -d "$dest_dir" \
        -o "$filename" \
        "$url" || true
}

function download_models_to_dir() {
    local dest_dir="$1"
    shift
    local arr=("$@")
    for entry in "${arr[@]}"; do
        download_one "$dest_dir" "$entry"
    done
}

function download_models_to_dir_parallel() {
    local dest_dir="$1"
    local parallel="$2"
    shift 2
    local arr=("$@")
    local running=0

    if ! [[ "$parallel" =~ ^[0-9]+$ ]] || (( parallel < 1 )); then
        parallel=1
    fi

    log "Parallel download to ${dest_dir} with ${parallel} worker(s)"
    mkdir -p "$dest_dir"

    for entry in "${arr[@]}"; do
        (
            download_one "$dest_dir" "$entry"
        ) &

        running=$((running + 1))

        if (( running >= parallel )); then
            wait -n || true
            running=$((running - 1))
        fi
    done

    wait || true
}

function provisioning_get_models() {
    log "Downloading core models"
    download_models_to_dir "${COMFYUI_DIR}/models/text_encoders" "${TEXT_ENCODER_MODELS[@]}"
    download_models_to_dir "${COMFYUI_DIR}/models/diffusion_models" "${DIFFUSION_MODELS[@]}"
    download_models_to_dir "${COMFYUI_DIR}/models/vae" "${VAE_MODELS[@]}"
    download_models_to_dir "${COMFYUI_DIR}/models/loras" "${LORA_UTIL_MODELS[@]}"
    download_models_to_dir "${COMFYUI_DIR}/models/upscale_models" "${UPSCALE_MODELS[@]}"
    download_models_to_dir "${COMFYUI_DIR}/models/upscale-models" "${UPSCALE_MODELS[@]}"
    download_models_to_dir "${COMFYUI_DIR}/models/ultralytics/segm" "${ULTRALYTICS_SEGM_MODELS[@]}"
    download_models_to_dir "${COMFYUI_DIR}/models/ultralytics/bbox" "${ULTRALYTICS_BBOX_MODELS[@]}"

    log "Downloading user LoRA pack"
    download_models_to_dir_parallel "${COMFYUI_DIR}/models/loras" "${CIVITAI_PARALLEL_DOWNLOADS}" "${LORA_MODELS[@]}"
}


function provisioning_write_notes() {
    local note_dir="${WORKSPACE}/ANIMA_PROVISIONING_NOTES"
    mkdir -p "$note_dir"
    cat > "${note_dir}/README.txt" <<EOF_NOTE
ANIMA Vast.ai provisioning complete.

Workflow JSON:
  - This script does NOT embed or install workflow JSON.
  - Import/upload your animaAllInOne_v55.json manually in ComfyUI.

Recommended GitHub layout:
  default.sh

Recommended Vast Environment Variables:
  COMFYUI_VERSION: v0.20.1
  COMFYUI_ARGS: "--disable-auto-launch --port 18188 --enable-cors-header --disable-xformers --enable-manager --disable-dynamic-vram"
  PROVISIONING_SCRIPT: https://raw.githubusercontent.com/<user>/<repo>/<branch>/default.sh
  COMFYUI_MANAGER_SECURITY_LEVEL: weak
  COMFYUI_MANAGER_ALLOW_GIT_URL_INSTALL: true
  COMFYUI_MANAGER_ALLOW_PIP_INSTALL: true
  HF_TOKEN: your_hf_token
  CIVITAI_TOKEN: your_civitai_token
EOF_NOTE
}

function provisioning_start() {
    log "Starting ANIMA provisioning"
    provisioning_get_apt_packages
    provisioning_get_pip_packages
    provisioning_pin_comfyui_version
    provisioning_get_nodes
    provisioning_set_manager_config
    provisioning_get_models
    provisioning_write_notes
    log "Provisioning finished. Restart ComfyUI if it was already running."
}

provisioning_start
