sudo apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    bat \
    unzip \
    ripgrep \
    fd-find \
    build-essential \
    cmake \
    gettext \
    libtool \
    libtool-bin \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    sudo \
    && rm -rf /var/lib/apt/lists/*;

cd $HOME/Downloads/;

curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz;

tar -xzf nvim-linux-x86_64.tar.gz;

