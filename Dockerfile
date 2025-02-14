FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_PREFER_BINARY=1
ENV PYTHONUNBUFFERED=1 
ENV CMAKE_BUILD_PARALLEL_LEVEL=8
ENV PYTHONPATH="/usr/local/lib/python3.11/site-packages:${PYTHONPATH}"

# Install Python and tools
RUN apt-get update && apt-get install -y \
    python3.11 \
    python3.11-distutils \
    python3.11-venv \
    python3-pip \
    git \
    wget \
    libgl1 \
    expect \
    && ln -sf /usr/bin/python3.11 /usr/bin/python3 \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install pip for Python 3.11
RUN wget https://bootstrap.pypa.io/get-pip.py && \
    python3.11 get-pip.py && \
    python3.11 -m pip install --upgrade pip && \
    rm get-pip.py

# Clone and setup ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git comfyui

# Install torch and requirements
WORKDIR /comfyui
RUN pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124 && \
    pip install -r requirements.txt

# Install ComfyUI-Manager
WORKDIR /
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager /comfyui/custom_nodes/ComfyUI-Manager && \
    chmod +x /comfyui/custom_nodes/ComfyUI-Manager/cm-cli.py && \
    pip install -r /comfyui/custom_nodes/ComfyUI-Manager/requirements.txt

# Install runpod and other requirements
RUN pip install runpod requests typer==0.15.1

# Create model directories and download models
RUN mkdir -p /comfyui/models/checkpoints /comfyui/models/vae /comfyui/models/unet /comfyui/models/clip /comfyui/models/loras /comfyui/models/upscale_models

# Download models with your original wget commands
RUN set -e && \
    echo "Starting model downloads..." && \
    for URL in \
        "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors /comfyui/models/clip/clip_l.safetensors noauth" \
        "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors /comfyui/models/vae/ae.safetensors auth" \
        "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors /comfyui/models/unet/flux1-dev.safetensors auth"; \
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

# Add configuration files
ADD src/extra_model_paths.yaml /comfyui/
ADD src/start.sh src/restore_snapshot.sh src/rp_handler.py test_input.json /
ADD *snapshot*.json /

# Set permissions
RUN chmod +x /start.sh /restore_snapshot.sh

# Restore snapshot
RUN /restore_snapshot.sh

CMD ["/start.sh"]
