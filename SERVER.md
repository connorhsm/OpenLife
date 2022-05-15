# How to setup and run an OpenLife server

Originally learnt from a lengthy explanation in TODO.md

Using a default DigitalOcean droplet (No custom image) with 2GB/2 Intel vCPU on Ubuntu 20.04

Find this as a script in `build_server.sh`

Install Haxe as according to https://haxe.org/download/linux/
```bash
sudo add-apt-repository ppa:haxe/releases -y
sudo apt update
sudo apt install haxe -y
mkdir ~/haxelib && haxelib setup ~/haxelib
```

Install dependencies
```bash
sudo apt install git gcc make -y
```

Install Hashlink to execute hl files https://github.com/HaxeFoundation/hashlink
```bash
# This requires almost 600MB kek
sudo apt install libpng-dev libturbojpeg-dev libvorbis-dev libopenal-dev libsdl2-dev libmbedtls-dev libuv1-dev libsqlite3-dev -y

git clone https://github.com/HaxeFoundation/hashlink
cd hashlink
make
make install
cd ..
```

Build OpenLife Server
```bash
git clone https://github.com/PXshadow/OpenLife
cd OpenLife
echo 0 | haxe setup_data_server.hxml
haxelib install format
haxe server.hxml
```

Finally, run the OpenLife server
```bash
hl server.hl
```

No errors, looks like its working!

Can now chuck it in a process manager like Screen or Tmux

Ctrl + C to stop the server

Find server settings in OpenLife/SaveFiles/ServerSettings.txt, the server checks for changes at startup and every 10 seconds
