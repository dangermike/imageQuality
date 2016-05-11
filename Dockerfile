FROM alpine:edge
# Need edge for sdl2

RUN apk add --update \
	# Generic build tools that things need
	make \
	g++ \
	cmake \
	yasm \
	parallel \
	bash \
	bc \
	git \
	autoconf \
	automake \
 	libtool \
	openssl \
	# Standalone tools
	imagemagick \
	libwebp-tools \
	x264 \
	ffmpeg \
	# TODO: Which package were these for
	libpng-dev \
	libjpeg-turbo-dev \
	# TODO: Which package were these for
	libogg-dev \
	sdl2-dev \
	check-dev \
	&& rm -rf /var/cache/apk/*

RUN wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.0.2/dumb-init_1.0.2_amd64
RUN chmod +x /usr/local/bin/dumb-init

RUN ln -snf /bin/bash /bin/sh

RUN git clone https://github.com/xiph/daala.git /tmp/daala \
	&& (cd /tmp/daala \
		&& ./autogen.sh \
		&& ./configure \
		&& make tools \
		&& make install \
		) \
	&& cp /tmp/daala/tools/y4m2png /bin \
	&& cp /tmp/daala/tools/png2y4m /bin

#####
# Everything below this will be affected if the versions change
#####

ENV LIBBPG_VERSION 		0.9.6
ENV DSSIM_VERSION 		1.3.2
ENV MOZJPEG_VERSION 	3.1
ENV JPEGOPTIM_VERSION 1.4.3
ENV JPEGTURBO_VERSION 1.4.90

RUN wget -qO- http://bellard.org/bpg/libbpg-${LIBBPG_VERSION}.tar.gz | tar xvz -C /tmp \
	&& make install -C /tmp/libbpg-${LIBBPG_VERSION}

RUN wget -qO- http://github.com/pornel/dssim/archive/${DSSIM_VERSION}.tar.gz | tar xvz -C /tmp/ \
	&& make -C /tmp/dssim-${DSSIM_VERSION} \
	&& cp /tmp/dssim-${DSSIM_VERSION}/bin/dssim /bin

RUN wget -qO- http://github.com/mozilla/mozjpeg/releases/download/v${MOZJPEG_VERSION}/mozjpeg-${MOZJPEG_VERSION}-release-source.tar.gz | tar xvz -C /tmp \
	&& (cd /tmp/mozjpeg && ./configure) \
	&& make -C /tmp/mozjpeg \
	&& cp /tmp/mozjpeg/cjpeg /bin/cjpeg-moz

RUN wget -qO- https://github.com/tjko/jpegoptim/archive/RELEASE.${JPEGOPTIM_VERSION}.tar.gz | tar xvz -C /tmp \
	&& (cd /tmp/jpegoptim-RELEASE.${JPEGOPTIM_VERSION} && ./configure) \
	&& make install -C /tmp/jpegoptim-RELEASE.${JPEGOPTIM_VERSION}

RUN wget -qO- https://github.com/libjpeg-turbo/libjpeg-turbo/archive/${JPEGTURBO_VERSION}.tar.gz | tar xvz -C /tmp \
	&& (cd /tmp/libjpeg-turbo-${JPEGTURBO_VERSION} \
		&& autoreconf -fiv \
		&& ./configure \
		) \
	&& make -C /tmp/libjpeg-turbo-${JPEGTURBO_VERSION} \
	&& cp /tmp/libjpeg-turbo-${JPEGTURBO_VERSION}/cjpeg /bin/cjpeg-turbo

COPY originals /originals
COPY ./execute_study.sh /
CMD ["dumb-init", "./execute_study.sh"]
