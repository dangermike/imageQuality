.PHONY: run
all: build run

build: Dockerfile
	docker build -t imagequality .

run:
	docker run \
		--rm \
		-it \
		imagequality \
		/bin/sh
