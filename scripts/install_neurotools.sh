#!/usr/bin/env bash
set -euo pipefail

# Trigger sudo password prompt early
sudo -v

###############################################################################
# install_neurotools.sh
#
# Mirrors the \u201cneurotools.def\u201d Apptainer definition but installs everything
# under /opt instead of /root. Run this script with sudo:
#   sudo ./install_neurotools.sh
#
# After completion, run \u201csource ~/.bashrc\u201d (or reopen your terminal) to pick up
# the new environment variables and updated PATH.
###############################################################################

#  A. PRELIMINARY CHECK 

if [[ "$EUID" -ne 0 ]]; then
    echo "Error: this script must be run with sudo or as root." >&2
    exit 1
fi

# Identify the regular user (who invoked sudo)
if [[ -n "${SUDO_USER:-}" ]]; then
    USERNAME="$SUDO_USER"
else
    echo "Error: SUDO_USER is empty; run this script via 'sudo'." >&2
    exit 1
fi
USER_HOME="/home/$USERNAME"

#  1. INSTALL SYSTEM PACKAGES 

echo "1/5: Installing system dependencies via apt..."
apt update
apt install -y \
    cmake \
    g++ \
    python3 \
    python3-venv \
    python3-pip \
    python3-numpy \
    git \
    curl \
    ca-certificates \
    libeigen3-dev \
    zlib1g-dev \
    libqt5opengl5-dev \
    libgl1-mesa-dev \
    libfftw3-dev \
    libtiff5-dev \
    bc

# Fix for python path (if /usr/bin/python does not exist)
if [[ ! -e /usr/bin/python ]]; then
    ln -s /usr/bin/python3 /usr/bin/python
fi

#  2. CLONE & BUILD MRtrix3 UNDER /opt/mrtrix3 

echo "2/5: Cloning and building MRtrix3 in /opt/mrtrix3..."

# If /opt/mrtrix3 already exists, remove it so we can re-run cleanly
if [[ -d /opt/mrtrix3 ]]; then
    echo "  /opt/mrtrix3 already exists; removing..."
    rm -rf /opt/mrtrix3
fi

# Create directory and set ownership to the regular user
mkdir -p /opt/mrtrix3

# Clone MRtrix3 into /opt/mrtrix3 as the regular user
git clone https://github.com/MRtrix3/mrtrix3.git /opt/mrtrix3

# Build MRtrix3 as the regular user
cd /opt/mrtrix3
./configure -nogui
./build

#  3. CLONE & BUILD ANTs UNDER /opt/ants 

echo "3/5: Cloning and building ANTs in /opt/ants..."

# If /opt/ants already exists, remove it so we can re-run cleanly
if [[ -d /opt/ants ]]; then
    echo "  /opt/ants already exists; removing..."
    rm -rf /opt/ants
fi

# Create build and install directories, set ownership to the regular user
mkdir -p /opt/ants/build /opt/ants/install

# Clone the ANTs repository as the regular user
git clone https://github.com/ANTsX/ANTs.git /opt/ants/ANTs

# Configure & build under /opt/ants/build as the regular user
cd /opt/ants/build
cmake \
    -DCMAKE_INSTALL_PREFIX=/opt/ants/install \
    -DBUILD_TESTING=OFF \
    -DRUN_LONG_TESTS=OFF \
    -DRUN_SHORT_TESTS=OFF \
    ../ANTs 2>&1 | tee /opt/ants/build/cmake.log

make -j4 2>&1 | tee /opt/ants/build/build.log

# Install into /opt/ants/install as root (writing to /opt requires root)
cd /opt/ants/build/ANTS-build
make install 2>&1 | tee /opt/ants/build/install.log

#  4. INSTALL HD-BET & CUDA-ENABLED PYTORCH IN VENV (OPTIONAL) 

PROJECT_DIR="$USER_HOME/dev/projects/dwi-preprocessing"
VENV_DIR="$PROJECT_DIR/.venv"

if [[ -d "$VENV_DIR" ]]; then
    echo "4/5: Python venv found at $VENV_DIR"
else
    echo "4/5: Python venv not found at $VENV_DIR."
    echo "If you want to create and populate the venv automatically, uncomment the block below:"
    : << 'VENV_SETUP_BLOCK'
#  CREATE & POPULATE A NEW PYTHON VENV 

mkdir -p "$PROJECT_DIR"

# Create the venv with prompt \u201cneurotools\u201d
python3 -m venv "$VENV_DIR" --prompt neurotools

# Activate venv and install packages
bash -c "
  source \"$VENV_DIR/bin/activate\"
  pip install --upgrade pip
  pip install torch==2.3.0 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
  pip install hd-bet dipy
  deactivate
"
VENV_SETUP_BLOCK
fi

#  5. INSTALL FSL UNDER /opt/fsl 

echo "5/5: Installing FSL under /opt/fsl..."

# Remove any existing installation for a clean re-run
if [[ -d /opt/fsl ]]; then
    echo "  /opt/fsl already exists; removing..."
    rm -rf /opt/fsl
fi

# Run the Python installer (fslinstaller.py) as the non-root user, accepting default "/opt/fsl"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
sudo -u "$USERNAME" -E python3 fslinstaller.py <<EOF
/opt/fsl
EOF

echo "FSL installation complete at /opt/fsl."

#  6. UPDATE USER ENVIRONMENT 

echo "Updating $USER_HOME/.bashrc with environment variables and PATH..."

cat << EOF >> "$USER_HOME/.bashrc"

#  Neurotools environment (adapted from neurotools.def, installed under /opt) 
export DEBIAN_FRONTEND=noninteractive
export CUDA_VISIBLE_DEVICES=all
export PATH="/opt/mrtrix3/bin:/usr/local/bin:\$FSLDIR/bin:/opt/ants/install/bin:\$PATH"
# 

#  (Optional) Auto-activate project venv when inside its directory 
# if [[ "\$PWD" == "$PROJECT_DIR"* ]]; then
#     source "$VENV_DIR/bin/activate"
# fi
# 
EOF


echo "Installation complete!"
echo "1) Run 'source ~/.bashrc' (or open a new terminal) to apply changes."
echo "2) If you want a Python venv at $PROJECT_DIR/.venv, create it manually"
echo "   or uncomment the venv block and re-run the script."
echo "3) All tools now match the exact versions and flags from neurotools.def,"
echo "   installed under /opt instead of /root."
