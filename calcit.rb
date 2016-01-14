#!/usr/bin/env ruby
require 'descriptive_statistics'
require 'csv'
require 'json'
require 'Set'

def statify(values)
	stats = DescriptiveStatistics::Stats.new(values)
	{
		averag: stats.mean,
		stddev: stats.standard_deviation,
		quart1: stats.percentile(25),
		median: stats.median,
		quart3: stats.percentile(75),
		count:  values.count
	}
end

METRICS = ['bpp','ssim','ssim-l','ms-ssim','psnr']

DONE = Set.new()

sizes = Dir.glob('*').select {|f| File.directory? f and /^[0-9]+s$/.match f and !DONE.include? f}

['100s', '250s'].each do |s|
	xforms = Hash.new
	Dir.glob("#{s}/*.csv").each do |fname|
		CSV.foreach(fname, headers: true) do |row|
			xforms[row['format']] = Hash.new unless xforms[row['format']]
			xform = xforms[row['format']]
			xform[row['quality']] = METRICS.map {|m| [m, []] }.to_h unless xform[row['quality']]
			qual = xform[row['quality']]
			METRICS.each do |m|
				value = row[m].to_f
				qual[m] << row[m] if value > 0
			end
		end
	end

	xforms.each do |xform, qualities|
		qualities.each do |quality, metrics|
			processed = metrics.map do |metric, values|
				v = statify values
				# puts "#{s}, #{xform}, #{quality}, #{metric}, #{v[:median]}"
				[metric, v]
			end.to_h
			qualities[quality] = processed
		end
	end

	CSV.open("processed/#{s}.csv", "wb") do |csv|
		xforms.each do |xform, qualities|
			csv << ["#{xform}_Q"] + qualities.map{|k,v| k}.to_a
			csv << ["#{xform}_Count"] + qualities.map{|k,v| v['bpp'][:count]}
			METRICS.each do |metric|
				csv << ["#{xform}_#{metric}"] + qualities.map{|k,v| v[metric][:median]}
			end
		end
	end
end