FROM ubuntu:22.04

WORKDIR /app

# These dependencies take a rather long time to build, avoid changing this or above layers
RUN apt-get update
RUN apt-get install --yes software-properties-common
RUN add-apt-repository ppa:haxe/releases
RUN apt-get install --yes libpng-dev libturbojpeg-dev libvorbis-dev libopenal-dev libsdl2-dev libmbedtls-dev libuv1-dev libsqlite3-dev

# Install additional build dependencies
RUN apt-get install --yes haxe git curl gcc make

# Setup haxe haxelib
RUN mkdir ./haxelib && haxelib setup ./haxelib

# Install hashlink
RUN curl -0 -L https://github.com/HaxeFoundation/hashlink/archive/1.12.tar.gz --output hl.tar.gz \
&& tar -xzvf hl.tar.gz \
&& cd hashlink-1.12 \
&& make \
&& make install \
&& cd ..

# Build OpenLife
COPY . .
RUN haxelib install format
RUN echo 0 | haxe setup_data.hxml
RUN haxe server.hxml

EXPOSE 8005

COPY ./docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]