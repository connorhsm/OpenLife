#!/usr/bin/env bash
set -e

# Install Haxe
sudo add-apt-repository ppa:haxe/releases -y
sudo apt update
sudo apt install haxe -y
mkdir ~/haxelib && haxelib setup ~/haxelib

# Install general dependencies
sudo apt install git gcc make -y

# Install Hashlink
sudo apt install libpng-dev libturbojpeg-dev libvorbis-dev libopenal-dev libsdl2-dev libmbedtls-dev libuv1-dev libsqlite3-dev -y
git clone https://github.com/HaxeFoundation/hashlink
cd hashlink
make
make install
cd ..

# Build OpenLife Server
git clone https://github.com/PXshadow/OpenLife
cd OpenLife
haxe setup_data.hxml
haxelib install format
haxe server.hxml

echo ""
echo "Build complete. Run `hl server.hl` to run server."
echo ""