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
# Add the Python 3.11 site-packages directory to the PYTHONPATH
ENV PYTHONPATH="/usr/local/lib/python3.11/site-packages:${PYTHONPATH}"

# Install Python, git and other necessary tools
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
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Install pip for Python 3.11 specifically
RUN wget https://bootstrap.pypa.io/get-pip.py && \
    python3.11 get-pip.py && \
    python3.11 -m pip install --upgrade pip && \
    rm get-pip.py

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/comfyanonymous/ComfyUI.git comfyui

# Install torch
RUN pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu124

# Change working directory to ComfyUI
WORKDIR /comfyui

# Install requirements
RUN pip install -r requirements.txt

WORKDIR /
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager /comfyui/custom_nodes/ComfyUI-Manager && \
    chmod +x /comfyui/custom_nodes/ComfyUI-Manager/cm-cli.py && \
    pip install -r /comfyui/custom_nodes/ComfyUI-Manager/requirements.txt && \
    # Debug info
    echo "Python path: $(which python)" && \
    echo "Python version: $(python --version)" && \
    echo "Pip version: $(pip --version)" && \
    echo "Installed packages:" && \
    pip list | grep typer 

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

# Before running restore_snapshot.sh, verify Python environment and typer
RUN echo "Verifying Python environment:" && \
    python --version && \
    pip --version && \
    echo "Installing typer..." && \
    pip install typer==0.15.1 && \
    echo "Verifying typer installation:" && \
    python -c "import typer; print(f'Typer is installed at: {typer.__file__}')"

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
    "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors models/unet/flux1-dev.safetensors auth"; \
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