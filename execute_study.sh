#!/bin/sh

# DEPENDENCIES:
# identify, convert: Parts of the ImageMagick package
# cwebp,dwebp: Executables from the webp package (http://downloads.webmproject.org/releases/webp/index.html)
# bpgenc,bpgdec: Executables from the BPG project (http://bellard.org/bpg)
# cjpeg: From the mozjpeg project. The normal one doesn't prove anything!
# dssim: Pornel's DSSIM tool (https://github.com/pornel/dssim)
# parallel: GNU parallel (https://www.gnu.org/software/parallel/)
for c in {identify,convert,cwebp,dwebp,bpgenc,bpgdec,cjpeg-moz,cjpeg-turbo,dssim,parallel}; do
	command -v $c >/dev/null 2>&1 || { echo >&2 "Cannot find required command '$c'. Aborting."; exit 1; }
done

SIZE_H=500
MIN_H=251

function process_result() {
	local TMPNAME=$1
	local FILETYPE=$2
	local QUALITY=$3

	convert /tmp/$TMPNAME/original.png -colorspace gray /tmp/$TMPNAME/original_gs.png
	convert /tmp/$TMPNAME/$QUALITY.png -colorspace gray /tmp/$TMPNAME/${QUALITY}_gs.png

	local SURFACE=`identify -format "%w * %h\n" /tmp/$TMPNAME/original.png | bc`
	local BYTE_COUNT=`stat -c "%s" /tmp/$TMPNAME/$QUALITY.out`
	local BPP=`echo "8 * $BYTE_COUNT / $SURFACE" | bc -l`

	local DSSIM=`dssim /tmp/$TMPNAME/original.png /tmp/$TMPNAME/$QUALITY.png | grep -Eo '^[0-9]+\.[0-9]+'`
	local SSIM=`echo "1/($DSSIM + 1)" | bc -l`

	local DSSIM_L=`dssim /tmp/$TMPNAME/original_gs.png /tmp/$TMPNAME/${QUALITY}_gs.png | grep -Eo '^[0-9]+\.[0-9]+'`
	local SSIM_L=`echo "1/($DSSIM_L + 1)" | bc -l`

	# local MSSSIM=`ms-ssim /tmp/$TMPNAME/original.png /tmp/$TMPNAME/$QUALITY.png`

	local PSNR=`compare -metric PSNR /tmp/$TMPNAME/original_gs.png /tmp/$TMPNAME/${QUALITY}_gs.png /dev/null 2>&1`

	echo $TMPNAME,$FILETYPE,$QUALITY,$BYTE_COUNT,$SURFACE,$BPP,$SSIM,$SSIM_L,$MSSSIM,$PSNR
}

functional_party() {
	local FNAME=$1
	local TMPNAME="${FNAME%.*}"
	local SIZE_H=$2
	local SIZE_V=$((((3 * $SIZE_H)/2)))
	local MIN_H=$3

	local dims=$(identify -format "%wx%h" originals/$FNAME)
	local width=$(echo $dims | cut -d x -f 1)
	local height=$(echo $dims | cut -d x -f 2)

	if [ "$width" -lt "$MIN_H" ]; then
		echo "Skipping $FNAME because it is too small"
		rm -rf /tmp/$TMPNAME
		exit
	fi

	rm -rf /tmp/$TMPNAME
	mkdir /tmp/$TMPNAME
	local RESFILE=/tmp/$TMPNAME/results.csv

	convert originals/$FNAME -strip -colorspace RGB -resize "${SIZE_H}x${SIZE_V}>" -colorspace sRGB png24:/tmp/$TMPNAME/original.png
	convert /tmp/$TMPNAME/original.png /tmp/$TMPNAME/original.ppm
	png2y4m --chroma-444 -o /tmp/$TMPNAME/original.y4m /tmp/$TMPNAME/original.png 2> /dev/null

	# since we have likely resized the original, width and height need to be recalculated
	local dims=$(identify -format "%wx%h" /tmp/$TMPNAME/original.png)
	local width=$(echo $dims | cut -d x -f 1)
	local height=$(echo $dims | cut -d x -f 2)
	local surface=`identify -format "%w * %h\n" /tmp/$TMPNAME/original.png | bc`

	echo "filename,format,quality,bytes,pixels,bpp,ssim,ssim-l,ms-ssim,psnr" | tee $RESFILE

	for q in $(seq 50 5 70; seq 75 1 99); do
		cjpeg-turbo -q $q /tmp/$TMPNAME/original.ppm > /tmp/$TMPNAME/$q.out
		convert /tmp/$TMPNAME/$q.out png24:/tmp/$TMPNAME/$q.png
		process_result $TMPNAME JPEG $q | tee -a $RESFILE
		rm /tmp/$TMPNAME/$q.*
	done

	for q in $(seq 50 5 70; seq 75 1 99); do
		cjpeg-moz -quality $q /tmp/$TMPNAME/original.ppm > /tmp/$TMPNAME/$q.out
		convert /tmp/$TMPNAME/$q.out png24:/tmp/$TMPNAME/$q.png
		process_result $TMPNAME MOZJPEG $q | tee -a $RESFILE
		rm /tmp/$TMPNAME/$q.*
	done

	# TODO: Broken? -dc-scan-opt doesnt appear to be valid in this version
	# for q in $(seq 50 5 70; seq 75 1 99); do
	# 	cjpeg-moz -dc-scan-opt 2 -quality $q /tmp/$TMPNAME/original.ppm > /tmp/$TMPNAME/$q.out
	# 	convert /tmp/$TMPNAME/$q.out png24:/tmp/$TMPNAME/$q.png
	# 	process_result $TMPNAME MOZJPEG-dcso2 $q | tee -a $RESFILE
	# 	rm /tmp/$TMPNAME/$q.*
	# done

	cjpeg-turbo -q 100 /tmp/$TMPNAME/original.ppm > /tmp/$TMPNAME/preoptim.jpg
	mkdir /tmp/$TMPNAME/optim
	for q in $(seq 100 -1 75); do
		jpegoptim -q --force -d/tmp/$TMPNAME/optim -o -m$q /tmp/$TMPNAME/preoptim.jpg
		mv /tmp/$TMPNAME/optim/preoptim.jpg /tmp/$TMPNAME/$q.out
		convert /tmp/$TMPNAME/$q.out png24:/tmp/$TMPNAME/$q.png
		process_result $TMPNAME JPEGOPTIM $q | tee -a $RESFILE
		rm /tmp/$TMPNAME/$q.*
	done

# disabled because we don't have a license for this on Amazon
#	for q in $(seq 0 4); do
#		jpegmini -lvl=0 -prg=2 -qual=$q -f=/tmp/$TMPNAME/preoptim.jpg -o=/tmp/$TMPNAME/$q.out > /dev/null
#		convert /tmp/$TMPNAME/$q.out png24:/tmp/$TMPNAME/$q.png
#		process_result $TMPNAME JPEGMINI $q | tee -a $RESFILE
#		rm /tmp/$TMPNAME/$q.*
#	done

	for q in $(seq 50 5 70; seq 75 1 99); do
		cwebp -noalpha -preset picture -quiet -q $q /tmp/$TMPNAME/original.png -o /tmp/$TMPNAME/$q.out
		dwebp /tmp/$TMPNAME/$q.out -o /tmp/$TMPNAME/$q.png &> /dev/null
		process_result $TMPNAME WEBP $q | tee -a $RESFILE
		rm /tmp/$TMPNAME/$q.*
	done

	for q in $(seq 50 5 70; seq 75 1 99); do
		cwebp -noalpha -preset picture -m 6 -pass 10 -quiet -q $q /tmp/$TMPNAME/original.png -o /tmp/$TMPNAME/$q.out
		dwebp /tmp/$TMPNAME/$q.out -o /tmp/$TMPNAME/$q.png &> /dev/null
		process_result $TMPNAME WEBP-m6p10 $q | tee -a $RESFILE
		rm /tmp/$TMPNAME/$q.*
	done

	local LASTSIZE=0
	# aiming for 0.5 - 4 bits per pixel
	for q in $(seq 0.5 0.25 4); do
		local TRG_SIZE=$(echo "$q * $surface / 8.0" | bc -l)
		cwebp -noalpha -preset picture -size $TRG_SIZE -m 6 -pass 10 -quiet /tmp/$TMPNAME/original.png -o /tmp/$TMPNAME/$q.out

		local CURRSIZE=$(stat -c "%s" /tmp/$TMPNAME/$q.out)
		if [ "$LASTSIZE" = "$CURRSIZE" ]; then
			break
		fi
		local LASTSIZE=$CURRSIZE

		dwebp /tmp/$TMPNAME/$q.out -o /tmp/$TMPNAME/$q.png &> /dev/null
		process_result $TMPNAME WEBP-m6p10-size $q | tee -a $RESFILE
		rm /tmp/$TMPNAME/$q.*
	done

	for q in $(seq 0 2 30); do
		bpgenc -m 8 -q $q -o /tmp/$TMPNAME/$q.out /tmp/$TMPNAME/original.png
		bpgdec -o /tmp/$TMPNAME/$q.png /tmp/$TMPNAME/$q.out
		process_result $TMPNAME BPG-m8 $q | tee -a $RESFILE
		rm /tmp/$TMPNAME/$q.*
	done

	# for q in $(seq 0 2 30); do
	# 	bpgenc_x265 -m 8 -q $q -o /tmp/$TMPNAME/$q.out /tmp/$TMPNAME/original.png
	# 	bpgdec -o /tmp/$TMPNAME/$q.png /tmp/$TMPNAME/$q.out
	# 	process_result $TMPNAME BPG-m8-x265 $q | tee -a $RESFILE
	# 	rm /tmp/$TMPNAME/$q.*
	# done

	for q in $(seq 0 2 30); do
		bpgenc -q $q -o /tmp/$TMPNAME/$q.out /tmp/$TMPNAME/original.png
		bpgdec -o /tmp/$TMPNAME/$q.png /tmp/$TMPNAME/$q.out
		process_result $TMPNAME BPG $q | tee -a $RESFILE
		rm /tmp/$TMPNAME/$q.*
	done

	# for q in $(seq 0 15 && seq 16 4 32); do
	# 	daala_enc -v $q -o /tmp/$TMPNAME/$q.out /tmp/$TMPNAME/original.y4m 2> /dev/null
	# 	daala_dec -o /tmp/$TMPNAME/$q.y4m /tmp/$TMPNAME/$q.out 2> /dev/null
	# 	y4m2png -o /tmp/$TMPNAME/$q.png /tmp/$TMPNAME/$q.y4m 2> /dev/null
	# 	process_result $TMPNAME DAALA $q | tee -a $RESFILE
	# 	rm /tmp/$TMPNAME/$q.*
	# done

	# Y4M TEST!!!!!
	cp /tmp/$TMPNAME/original.y4m /tmp/$TMPNAME/test.out
	y4m2png -o /tmp/$TMPNAME/test.png /tmp/$TMPNAME/original.y4m 2> /dev/null
	process_result $TMPNAME Y4M test
	rm /tmp/$TMPNAME/test.*
	# END Y4M TEST

	new_width=$(((($width+1)/2)*2))
	new_height=$(((($height+1)/2)*2))
	new_surface=$(($new_height*$new_width))

	# make a new thing with dimensions divisible by 2
	# that doubles the last row or column as necessary
	convert /tmp/$TMPNAME/original.png -resize $new_width\!x$new_height\! png:- | \
		composite /tmp/$TMPNAME/original.png - /tmp/$TMPNAME/even.png

	png2y4m --chroma-444 -o /tmp/$TMPNAME/even.y4m /tmp/$TMPNAME/even.png 2> /dev/null

	# for q in $(seq 48 -4 0); do
	# 	# convert the raw y4m into H.264 like a boss
	# 	x264 \
	# 		--quiet \
	# 		--no-progress \
	# 		--fps 1 \
	# 		--qp $q \
	# 		--trellis 2 \
	# 		--tune stillimage \
	# 		--overscan crop \
	# 		--level 4.1 \
	# 		/tmp/$TMPNAME/even.y4m \
	# 		-o /tmp/$TMPNAME/even.mkv 2> /dev/null
	#
	# 	# H.264 back into PNG, potentially with an extra row or column
	# 	ffmpeg \
	# 		-v error \
	# 		-y \
	# 		-i /tmp/$TMPNAME/even.mkv \
	# 		-f APNG - | \
	# 	convert - -crop $dims -delete 1--1 /tmp/$TMPNAME/$q.png
	#
	# 	mv /tmp/$TMPNAME/even.mkv /tmp/$TMPNAME/$q.out
	#
	# 	process_result $TMPNAME H264_420_QP_MKV $q | tee -a $RESFILE
	#
	# 	rm /tmp/$TMPNAME/$q.*
	# done

	# local LASTSIZE=0
	# for q in $(seq 0.2 0.2 10); do
	# 	# bitrate is in kilobits. 8192 seems to work
	# 	bitrate=$(echo "$q * $new_surface / 8192" | bc -l | sed -E "s/([0-9]+)\.[0-9]+/\1/g")
	#
	# 	# convert the raw y4m into H.264 like a boss
	# 	x264 \
	# 		--quiet \
	# 		--no-progress \
	# 		--fps 1 \
	# 		--bitrate $bitrate \
	# 		--aq-mode 1 \
	# 		--trellis 2 \
	# 		--tune stillimage \
	# 		--overscan crop \
	# 		--level 4.1 \
	# 		/tmp/$TMPNAME/even.y4m \
	# 		-o /tmp/$TMPNAME/even.mkv 2> /dev/null
	#
	# 	local CURRSIZE=$(stat -c "%s" /tmp/$TMPNAME/even.mkv)
	# 	if [ "$LASTSIZE" = "$CURRSIZE" ]; then
	# 		break
	# 	fi
	# 	local LASTSIZE=$CURRSIZE
	#
	# 	# H.264 back into PNG, potentially with an extra row or column
	# 	ffmpeg \
	# 		-v error \
	# 		-y \
	# 		-i /tmp/$TMPNAME/even.mkv \
	# 		-f APNG - | \
	# 		convert - -crop $dims -delete 1--1 png24:/tmp/$TMPNAME/$q.png
	#
	# 	mv /tmp/$TMPNAME/even.mkv /tmp/$TMPNAME/$q.out
	#
	# 	process_result $TMPNAME H264_420_AQ_MKV $q | tee -a $RESFILE
	# 	rm /tmp/$TMPNAME/$q.*
	# done

	# for q in $(seq 48 -4 0); do
	# 	# convert the raw y4m into H.264 like a boss
	# 	x264 \
	# 		--quiet \
	# 		--no-progress \
	# 		--output-csp i444 \
	# 		--fps 1 \
	# 		--qp $q \
	# 		--trellis 2 \
	# 		--tune stillimage \
	# 		--overscan crop \
	# 		--level 4.1 \
	# 		/tmp/$TMPNAME/original.y4m \
	# 		-o /tmp/$TMPNAME/$q.mkv 2> /dev/null
	#
	# 	ffmpeg \
	# 		-v error \
	# 		-y \
	# 		-i /tmp/$TMPNAME/$q.mkv \
	# 		-f APNG \
	# 		/tmp/$TMPNAME/$q.png
	#
	# 	mv /tmp/$TMPNAME/$q.mkv /tmp/$TMPNAME/$q.out
	#
	# 	process_result $TMPNAME H264_444_QP_MKV $q | tee -a $RESFILE
	#
	# 	rm /tmp/$TMPNAME/$q.*
	# done


	# local LASTSIZE=0
	# for q in $(seq 0.2 0.2 10); do
	# 	# bitrate is in kilobits. 8192 seems to work
	# 	bitrate=$(echo "$q * $surface / 8192" | bc -l | sed -E "s/([0-9]+)\.[0-9]+/\1/g")
	#
	# 	# convert the raw y4m into H.264 like a boss
	# 	x264 \
	# 		--no-progress \
	# 		--output-csp i444 \
	# 		--fps 1 \
	# 		--bitrate $bitrate \
	# 		--aq-mode 1 \
	# 		--trellis 2 \
	# 		--tune stillimage \
	# 		--overscan crop \
	# 		--level 4.1 \
	# 		/tmp/$TMPNAME/original.y4m \
	# 		-o /tmp/$TMPNAME/the.mkv 2> /dev/null
	#
	# 	local CURRSIZE=$(stat -c "%s" /tmp/$TMPNAME/the.mkv)
	# 	if [ "$LASTSIZE" = "$CURRSIZE" ]; then
	# 		break
	# 	fi
	# 	local LASTSIZE=$CURRSIZE
	#
	# 	ffmpeg \
	# 		-v error \
	# 		-y \
	# 		-i /tmp/$TMPNAME/the.mkv \
	# 		-f APNG \
	# 		/tmp/$TMPNAME/$q.png
	#
	# 	mv /tmp/$TMPNAME/the.mkv /tmp/$TMPNAME/$q.out
	#
	# 	process_result $TMPNAME H264_444_AQ_MKV $q | tee -a $RESFILE
	# 	rm /tmp/$TMPNAME/$q.*
	# done
##############################
#############################

	mv $RESFILE ./${SIZE_H}s/$TMPNAME.csv
	rm -rf /tmp/$TMPNAME
}

export -f process_result
export -f functional_party

rm -rf ./${SIZE_H}s
mkdir ${SIZE_H}s
ls originals | parallel --lb "functional_party {} $SIZE_H $MIN_H"
