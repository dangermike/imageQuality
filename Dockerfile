FROM alpine:latest

ENV LIBBPG_VERSION 0.9.6
ENV DSSIM_VERSION 1.3.2

RUN apk add --update \
	imagemagick \
	libwebp-tools \
	make g++ cmake yasm \
	libpng-dev libjpeg-turbo-dev sdl-dev sdl_image-dev \
	libjpeg-turbo-utils \
	parallel \
	&& rm -rf /var/cache/apk/*

RUN wget -qO- http://bellard.org/bpg/libbpg-${LIBBPG_VERSION}.tar.gz | tar xvz -C /tmp \
	&& make install -C /tmp/libbpg-${LIBBPG_VERSION}

RUN wget -qO- https://github.com/pornel/dssim/archive/${DSSIM_VERSION}.tar.gz | tar xvz -C /tmp/dssim \
	&& make -C /tmp/dssim/${DSSIM_VERSION} \
	&& cp /tmp/dssim/${DSSIM_VERSION}/bin/dssim /bin
