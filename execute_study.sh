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
RESDIR=/results
RESFILE=${RESDIR}/${SIZE_H}px_$(date -u -Iseconds).csv

functional_party() {
	if [ -z "${1}" ]; then
		echo "filename,format,quality,bytes,pixels,bpp,ssim,ssim-l,ms-ssim,psnr"
		return
	fi

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

	# Isolate files for mktemp
	tpd=$(mktemp -td)
	mktemp() {
		echo $(/bin/mktemp -tp ${tpd})
	}

	# Clean up temp dirs on script exit
	trap "rm -rf /tmp/${TMPNAME}" EXIT
	trap "rm -rf ${tpd}" EXIT

	declare -A files
	files[original_png]=$(mktemp).png
	files[original_ppm]=$(mktemp).ppm
	files[original_y4m]=$(mktemp).y4m
	files[original_gs]=$(mktemp)

	convert originals/$FNAME -strip -colorspace RGB -resize "${SIZE_H}x${SIZE_V}>" -colorspace sRGB png24:${files[original_png]}
	convert ${files[original_png]} ${files[original_ppm]}
	convert ${files[original_png]} -colorspace gray ${files[original_gs]}
	png2y4m --chroma-444 -o ${files[original_y4m]} ${files[original_png]} 2> /dev/null

	# since we have likely resized the original, width and height need to be recalculated
	local dims=$(identify -format "%wx%h" ${files[original_png]})
	local width=$(echo $dims | cut -d x -f 1)
	local height=$(echo $dims | cut -d x -f 2)
	local surface=`identify -format "%w * %h\n" ${files[original_png]} | bc`

	process_result() {
		local FILETYPE=$1
		local q=$2
		local outfile=$3
		local q_file=$4

		local original_file=${files[original_png]}
		local original_gs=${files[original_gs]}
		local quality_gs=$(mktemp)

		# TODO: Calculate this once
		convert ${q_file} -colorspace gray ${quality_gs}

		local BYTE_COUNT=`stat -c "%s" ${outfile}`
		local BPP=`echo "8 * $BYTE_COUNT / $surface" | bc -l`

		local DSSIM=`dssim ${original_file} ${q_file} | grep -Eo '^[0-9]+\.[0-9]+'`
		local SSIM=`echo "1/($DSSIM + 1)" | bc -l`

		local DSSIM_L=`dssim ${original_gs} ${quality_gs} | grep -Eo '^[0-9]+\.[0-9]+'`
		local SSIM_L=`echo "1/($DSSIM_L + 1)" | bc -l`

		# local MSSSIM=`ms-ssim ${original_file} ${q_file}

		local PSNR=`compare -metric PSNR ${original_gs} ${quality_gs} /dev/null 2>&1`

		echo $TMPNAME,$FILETYPE,$q,$BYTE_COUNT,$surface,$BPP,$SSIM,$SSIM_L,$MSSSIM,$PSNR

		rm ${quality_gs} ${outfile} ${q_file}
		if [[ $RUN_ONCE ]]; then break; fi
	}

	for q in $(seq 50 5 70; seq 75 1 99); do
		local outfile=$(mktemp)
		local q_file=$(mktemp)

		cjpeg-turbo -q $q ${files[original_ppm]} > ${outfile}
		convert ${outfile} png24:${q_file}
		process_result JPEG $q ${outfile} ${q_file}
	done

	for q in $(seq 50 5 70; seq 75 1 99); do
		local outfile=$(mktemp)
		local q_file=$(mktemp)

		cjpeg-moz -q $q ${files[original_ppm]} > ${outfile}
		convert ${outfile} png24:${q_file}
		process_result MOZJPEG $q ${outfile} ${q_file}
	done

	# TODO: Broken? -dc-scan-opt doesnt appear to be valid in this version
	# for q in $(seq 50 5 70; seq 75 1 99); do
	# 	local outfile=$(mktemp)
	# 	local q_file=$(mktemp)
	# 	cjpeg-moz -dc-scan-opt 2 -quality $q ${files[original_ppm]} > ${outfile}
	# 	convert ${outfile} png24:${q_file}
	# 	process_result MOZJPEG-dcso2 $q ${outfile} ${q_file}
	# done

	cjpeg-turbo -q 100 ${files[original_ppm]} > /tmp/$TMPNAME/preoptim.jpg
	mkdir /tmp/$TMPNAME/optim
	for q in $(seq 100 -1 75); do
		local outfile=$(mktemp)
		local q_file=$(mktemp)

		jpegoptim -q --force -d/tmp/$TMPNAME/optim -o -m$q /tmp/$TMPNAME/preoptim.jpg
		mv /tmp/$TMPNAME/optim/preoptim.jpg ${outfile}
		convert ${outfile} png24:${q_file}
		process_result JPEGOPTIM $q ${outfile} ${q_file}
	done

	# disabled because we don't have a license for this on Amazon
	#	for q in $(seq 0 4); do
	# 	local outfile=$(mktemp)
	# 	local q_file=$(mktemp)
	#		jpegmini -lvl=0 -prg=2 -qual=$q -f=/tmp/$TMPNAME/preoptim.jpg -o=${outfile} > /dev/null
	#		convert ${outfile} png24:${q_file}
	#		process_result JPEGMINI $q ${outfile} ${q_file}
	#	done

	for q in $(seq 50 5 70; seq 75 1 99); do
		local outfile=$(mktemp)
		local q_file=$(mktemp)

		cwebp -noalpha -preset picture -quiet -q $q ${files[original_png]} -o ${outfile}
		dwebp ${outfile} -o ${q_file} &> /dev/null
		process_result WEBP $q ${outfile} ${q_file}
	done

	for q in $(seq 50 5 70; seq 75 1 99); do
		local outfile=$(mktemp)
		local q_file=$(mktemp)

		cwebp -noalpha -preset picture -m 6 -pass 10 -quiet -q $q ${files[original_png]} -o ${outfile}
		dwebp ${outfile} -o ${q_file} &> /dev/null
		process_result WEBP-m6p10 $q ${outfile} ${q_file}
	done

	local LASTSIZE=0
	# aiming for 0.5 - 4 bits per pixel
	for q in $(seq 0.5 0.25 4); do
		local outfile=$(mktemp)
		local q_file=$(mktemp)

		local TRG_SIZE=$(echo "$q * $surface / 8.0" | bc -l)
		cwebp -noalpha -preset picture -size $TRG_SIZE -m 6 -pass 10 -quiet ${files[original_png]} -o ${outfile}

		local CURRSIZE=$(stat -c "%s" ${outfile})
		if [ "$LASTSIZE" = "$CURRSIZE" ]; then
			break
		fi
		local LASTSIZE=$CURRSIZE

		dwebp ${outfile} -o ${q_file} &> /dev/null
		process_result WEBP-m6p10-size $q ${outfile} ${q_file}
	done

	for q in $(seq 0 2 30); do
		local outfile=$(mktemp)
		local q_file=$(mktemp)

		bpgenc -m 8 -q $q -o ${outfile} ${files[original_png]}
		bpgdec -o ${q_file} ${outfile}
		process_result BPG-m8 $q ${outfile} ${q_file}
	done

	# for q in $(seq 0 2 30); do
	# 	local outfile=$(mktemp)
	# 	local q_file=$(mktemp)

	# 	bpgenc_x265 -m 8 -q $q -o ${outfile} ${files[original_png]}
	# 	bpgdec -o ${q_file} ${outfile}
	# 	process_result BPG-m8-x265 $q ${outfile} ${q_file}
	# done

	for q in $(seq 0 2 30); do
		local outfile=$(mktemp)
		local q_file=$(mktemp)

		bpgenc -q $q -o ${outfile} ${files[original_png]}
		bpgdec -o ${q_file} ${outfile}
		process_result BPG $q ${outfile} ${q_file}
	done

	# for q in $(seq 0 15 && seq 16 4 32); do
	# 	local outfile=$(mktemp)
	#		local q_file=$(mktemp)

	# 	daala_enc -v $q -o ${outfile} ${files[original_y4m]} 2> /dev/null
	# 	daala_dec -o /tmp/$TMPNAME/$q.y4m ${outfile} 2> /dev/null
	# 	y4m2png -o ${q_file} /tmp/$TMPNAME/$q.y4m 2> /dev/null
	# 	process_result DAALA $q ${outfile} ${q_file}
	# done

	# Y4M TEST!!!!!
	for q in $(seq 1); do
		local outfile=$(mktemp)
		local q_file=$(mktemp)
		cp ${files[original_y4m]} ${outfile}
		y4m2png -o ${q_file} ${files[original_y4m]} 2> /dev/null
		process_result Y4M test ${outfile} ${q_file}
	done
	# END Y4M TEST

	new_width=$(((($width+1)/2)*2))
	new_height=$(((($height+1)/2)*2))
	new_surface=$(($new_height*$new_width))

	# make a new thing with dimensions divisible by 2
	# that doubles the last row or column as necessary
	convert ${files[original_png]} -resize $new_width\!x$new_height\! png:- | \
	composite ${files[original_png]} - /tmp/$TMPNAME/even.png

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
	#		local q_file=$(mktemp)
	# 	convert - -crop $dims -delete 1--1 ${q_file}
	#
	# 	local outfile=$(mktemp)
	# 	mv /tmp/$TMPNAME/even.mkv ${outfile}
	#
	# 	process_result H264_420_QP_MKV $q ${outfile} ${q_file}
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
	#		local q_file=$(mktemp)
	# 	convert - -crop $dims -delete 1--1 png24:${q_file}
	#
	#		local outfile=$(mktemp)
	# 	mv /tmp/$TMPNAME/even.mkv ${outfile}
	#
	# 	process_result H264_420_AQ_MKV $q ${outfile} ${q_file}
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
	# 		${files[original_y4m]} \
	# 		-o /tmp/$TMPNAME/$q.mkv 2> /dev/null
	#
	#		local q_file=$(mktemp)
	# 	ffmpeg \
	# 		-v error \
	# 		-y \
	# 		-i /tmp/$TMPNAME/$q.mkv \
	# 		-f APNG \
	# 		${q_file}
	#
	# 	local outfile=$(mktemp)
	# 	mv /tmp/$TMPNAME/$q.mkv ${outfile}
	#
	# 	process_result H264_444_QP_MKV $q ${outfile} ${q_file}
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
	# 		${files[original_y4m]} \
	# 		-o /tmp/$TMPNAME/the.mkv 2> /dev/null
	#
	# 	local CURRSIZE=$(stat -c "%s" /tmp/$TMPNAME/the.mkv)
	# 	if [ "$LASTSIZE" = "$CURRSIZE" ]; then
	# 		break
	# 	fi
	# 	local LASTSIZE=$CURRSIZE
	#
	#		local q_file=$(mktemp)
	# 	ffmpeg \
	# 		-v error \
	# 		-y \
	# 		-i /tmp/$TMPNAME/the.mkv \
	# 		-f APNG \
	# 		${q_file}
	#
	# 	local outfile=$(mktemp)
	# 	mv /tmp/$TMPNAME/the.mkv ${outfile}
	#
	# 	process_result H264_444_AQ_MKV $q ${outfile} ${q_file}
	# done
	##############################
	#############################

	for i in "${!files[@]}"; do
		rm ${files[$i]}
	done
}

export -f functional_party

mkdir -p $(dirname ${RESFILE})
echo "# Generated - $(date)" > ${RESFILE}
functional_party >> ${RESFILE}
start=`date +%s`
ls originals | parallel --lb "functional_party {} $SIZE_H $MIN_H" | tee -a ${RESFILE}
end=`date +%s`
runtime=$( echo "$end - $start" | bc -l )
echo "# Runtime ${runtime}s" | tee -a ${RESFILE}
