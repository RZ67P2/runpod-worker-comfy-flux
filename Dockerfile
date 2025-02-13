#FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu20.04

# Stage 1: Base image with common dependencies
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04 as base

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1 
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3-pip \
    git \
    wget \
    libgl1 \
    expect \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/comfyanonymous/ComfyUI.git comfyui
RUN echo "After ComfyUI clone:" && pwd && ls -la

# Install torch
RUN pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install requirements
RUN pip install -r requirements.txt

# Install ComfyUI-Manager in the correct location
WORKDIR /comfyui/custom_nodes
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager ComfyUI-Manager && \
    chmod +x ComfyUI-Manager/cm-cli.py && \
    echo "After Manager install:" && pwd && ls -la

# Print the current directory and list of files
RUN echo "Current directory:" && pwd && ls -la

# go back to comfyui
WORKDIR /comfyui

# Install runpod
RUN pip install runpod requests

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Go back to the root
WORKDIR /

# Add scripts
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json ./
RUN chmod +x /start.sh /restore_snapshot.sh

# Optionally copy the snapshot file
ADD *snapshot*.json /

# Restore the snapshot to install custom nodes
RUN /restore_snapshot.sh

# Single CMD at the end
CMD ["/start.sh"]

# Stage 2: Download models
FROM base as downloader

# Define ARG and ENV with a default empty value
ARG HUGGINGFACE_ACCESS_TOKEN
ENV HUGGINGFACE_TOKEN=$HUGGINGFACE_ACCESS_TOKEN

# Add more verbose token checking
RUN echo "Checking Hugging Face token..." && \
    if [ -z "$HUGGINGFACE_TOKEN" ]; then \
        echo "Error: HUGGINGFACE_ACCESS_TOKEN is not set"; \
        exit 1; \
    else \
        echo "Token is present (length: ${#HUGGINGFACE_TOKEN})"; \
    fi

# Change working directory to ComfyUI
WORKDIR /comfyui

# Create necessary directories
RUN mkdir -p models/checkpoints models/vae models/unet models/clip models/loras models/upscale_models

RUN set -e && \
echo "Starting model downloads..." && \
for URL in \
    "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors models/clip/clip_l.safetensors noauth" \
    "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors models/vae/ae.safetensors auth" \
    "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors models/unet/flux1-dev.safetensors auth" \
    "https://huggingface.co/BeichenZhang/LongCLIP-L/resolve/main/longclip-L.pt models/clip/longclip-L.pt noauth" \
    "https://huggingface.co/ai-forever/Real-ESRGAN/resolve/main/RealESRGAN_x2.pth models/upscale_models/RealESRGAN_x2.pth noauth" \
    "https://huggingface.co/nerijs/dark-fantasy-illustration-flux/resolve/main/darkfantasy_illustration_v2.safetensors models/loras/darkfantasy_illustration_v2.safetensors noauth" \
    "https://huggingface.co/comfyanonymous/flux_RealismLora_converted_comfyui/resolve/main/flux_realism_lora.safetensors models/loras/flux_realism_lora.safetensors noauth" \
    "https://huggingface.co/k0n8/IshmaelV3/resolve/main/1shm43l_v3.safetensors models/loras/1shm43l_v3.safetensors noauth" \
    "https://huggingface.co/k0n8/Queequengv4/resolve/main/Qu33qu3g_v4.safetensors models/loras/Qu33qu3g_v4.safetensors noauth" \
    "https://huggingface.co/XLabs-AI/flux-RealismLora/resolve/main/lora.safetensors models/loras/flux-RealismLora.safetensors noauth"; \
do \
    SRC=$(echo $URL | cut -d' ' -f1); \
    DEST=$(echo $URL | cut -d' ' -f2); \
    AUTH=$(echo $URL | cut -d' ' -f3); \
    echo "Starting download of $(basename $DEST)..."; \
    if [ "$AUTH" = "auth" ]; then \
        wget --progress=bar:force:noscroll --header="Authorization: Bearer ${HUGGINGFACE_TOKEN}" \
            --tries=5 --timeout=120 --waitretry=60 --continue \
            -O "$DEST" "$SRC" || exit 1; \
    else \
        wget --progress=bar:force:noscroll \
            --tries=5 --timeout=120 --waitretry=60 --continue \
            -O "$DEST" "$SRC" || exit 1; \
    fi; \
    echo "Completed download of $(basename $DEST)"; \
    echo "Disk space after downloading $(basename $DEST):"; \
    df -h; \
done
    
# Stage 3: Final image
FROM base as final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Start container
CMD ["/start.sh"]

#--platform linux/amd64