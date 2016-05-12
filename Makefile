.PHONY: run
all: build run

build: Dockerfile
	docker build -t imagequality .

test:
	docker run \
		-v $(shell pwd):/opt \
		-v $(shell pwd)/results:/results \
		-v $(shell pwd)/originals:/originals \
		--rm \
		-it \
		imagequality \
		/bin/bash

run:
	docker run \
		-v $(shell pwd):/opt \
		-v $(shell pwd)/results:/results \
		-v $(shell pwd)/originals:/originals \
		--rm \
		imagequality
