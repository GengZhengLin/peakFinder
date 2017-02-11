

task peakFinder(data : region(ispace(int3d), Pixel), peaks : region(ispace(int3d), Peak))
where 
	reads(data), writes(peaks)
do
	for i = peaks.bounds.lo.x, peaks.bounds.hi.x do
		var j = i % COPIES
		read from data[i]
		write to peaks[j]
	end
end

task main()
	var paralism = 4
	var data = region(ispace(int3d, {num, WIDTH, HEIGHT}), Pixel)
	var peaks = region(ispace(int3d), {num * COPIES, 1, 1}, Peak)
	var p_peaks = partition(equal, peaks, paralism)
	for color in p_peaks.colors do
		peakFinder(data, peaks[color])
	end
end

task peakFinder(data : region(ispace(int3d), Pixel), peaks : region(ispace(int3d), Peak))
where 
	reads(data), writes(peaks)
do
	for i = peaks.bounds.lo.x, peaks.bounds.hi.x do
		read from data[i]
		write to peaks[i]
	end
end

task main()
	var paralism = 4
	var data = region(ispace(int3d, {num, WIDTH, HEIGHT}), Pixel)
	var copied_data = region(ispace(int3d, {num * COPIES, WIDTH, HEIGHT}), Pixel)
	-- copy data to copied_data
	var peaks = region(ispace(int3d), {num * COPIES, 1, 1}, Peak)
	var p_peaks = partition(equal, peaks, paralism)
	var p_data = partition(equal, copied_data, paralism)
	for color in peaks.colors do
		peakFinder(p_data[color], peaks[color])
	end
end
