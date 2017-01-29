import "regent"

-- Helper module to handle command line arguments
local SlacConfig = require("slac_config")
local Queue = require("queue")
local Peak = require("peak")
local PeakHelper = require("peakHelper")

sqrt = terralib.intrinsic("llvm.sqrt.f64", double -> double)

local c = regentlib.c

--------------------------------------------------------------------------------
--                               Configuration                                --
--------------------------------------------------------------------------------

local EVENTS = 5
local SHOTS = 32
local WIDTH = 185
local HEIGHT = 388
local MAX_PEAKS = 200
local SON_MIN = 40
local r0 = 4
local dr = 0.1

terra get_t0()
	var t0 : double[5]
  t0[0] = 3500
	t0[1] = 5500
	t0[2] = 3700
	t0[3] = 3800
	t0[4] = 5000
  return t0
end

terra get_t1()
	var t0 : double[5]
  t0[0] = 3200
	t0[1] = 5200
	t0[2] = 3200
	t0[3] = 3300
	t0[4] = 4700
  return t0
end

terra ternary(cond : bool, T : int, F : int)
  if cond then return T else return F end
end
--------------------------------------------------------------------------------
--                                   Structs                                  --
--------------------------------------------------------------------------------

struct Pixel {
	intensity : double;
}

fspace Mask {
  mask : int;
}

struct WinType{
  left : int;
  top : int;
  right : int;
  bot : int
}

terra WinType:init(left : int, top : int, right : int, bot : int)
  self.left = left
  self.right = right
  self.top = top
  self.bot = bot
end


--------------------------------------------------------------------------------
--                                   Timing                                   --
--------------------------------------------------------------------------------

terra wait_for(x : int)
  return x
end

--------------------------------------------------------------------------------
--                                  Loading                                   --
--------------------------------------------------------------------------------

terra read_double(f : &c.FILE, number : &double)
  return c.fscanf(f, "%lf ", &number[0]) == 1
end

task load_events(r_shots : region(ispace(int3d), Pixel) )
where
  reads writes(r_shots)
do
  var f = c.fopen("slac/det.con", "rb")
  
  c.printf("Loading into panels %d through %d\n", r_shots.bounds.lo.x, r_shots.bounds.hi.x)
  
	var x : double[1]
	for i = 0, EVENTS * SHOTS do
		for row = 0, HEIGHT do
			for col = 0, WIDTH do
				if not read_double(f, x) then
					c.printf("Couldn't read data in shot %d\n", row)
					return 0
				end
        r_shots[{i, row, col}].intensity = x[0]
			end
		end
	end
  return 0
end

task duplicate_events(p_oshots : region(ispace(int3d), Pixel), p_shots : region(ispace(int3d), Pixel), p_points : region(ispace(int3d), Pixel))
where
  reads(p_oshots), 
  reads writes(p_shots)
do
  for i = p_points.bounds.lo.x, p_points.bounds.hi.x + 1 do
		for row = 0, HEIGHT do
			for col = 0, WIDTH do
        p_shots[{i, row, col}].intensity = p_oshots[{i % (EVENTS * SHOTS), row, col}].intensity
			end
		end
	end
  return 0 -- Used for timing purposes
end

task init_peaks(r_peaks : region(ispace(int3d), Peak), copies : int32)
where
	reads writes (r_peaks)
do
  fill(r_peaks.valid, false) 
end

--------------------------------------------------------------------------------
--                                 Processing                                 --
--------------------------------------------------------------------------------

terra in_ring(cx : int32, cy : int32, px : int32, py : int32)
  var dist = (cx - px) * (cx - px) + (cy - py) * (cy - py)
  return dist >= r0 * r0 and dist <= (r0 + dr) * (r0 + dr)
end

task generate_ring_map(r0 : double, dr :double, map : region(ispace(int2d),int))
where 
  writes(map)
do
  var half_width : int = [int](r0 + dr)
  var width : int = 2 * half_width + 1
  for i = 0, width do
    for j = 0, width do
      var dis_sqr : double = (i - half_width) * (i - half_width) + (j - half_width) * (j - half_width)
      if dis_sqr < r0 * r0 then
        map[{i,j}] = 0
      elseif dis_sqr <= (r0 + dr) * (r0 + dr) then
        map[{i,j}] = 1
      else
        map[{i,j}] = 0
      end
    end
  end
  return 0
end

task peakFinderV4r2(data : region(ispace(int3d), Pixel), peaks : region(ispace(int3d), Peak), rank : int, win : WinType, r_thr_high : region(ispace(int1d), double), r_thr_low : region(ispace(int1d), double), r0 : double, dr : double)
where
	reads (data, r_thr_low, r_thr_high), writes(peaks)
do
  var queue : Queue
  queue:init()
	var index : uint32 = 0
  var half_width : int = [int](r0 + dr)
 --  var width : int = 2 * half_width + 1
	-- var ring_map = region(ispace(int2d, {width, width}),int)
  -- generate_ring_map(r0,dr,ring_map)
  -- c.printf("p_data.bounds.lo.x:%d, p_data.bounds.hi.x:%d\n",peaks.bounds.lo.x, peaks.bounds.hi.x)
  var r_conmap = region(ispace(int2d, {HEIGHT, WIDTH}), uint32)
	for p_i = peaks.bounds.lo.x, peaks.bounds.hi.x + 1 do
    -- var i = [uint32](p_i) % (EVENTS * SHOTS)
    var i = p_i
    var thr_high = r_thr_high[p_i]
    var thr_low = r_thr_low[p_i]
    var shot_count = 0   
    fill(r_conmap, 0)
    for row = win.top, win.bot + 1 do
			for col = win.left, win.right + 1 do
				if data[{i, row, col}].intensity > thr_high and r_conmap[{row, col}] <= 0 then 
					index += 1 
					var set = index
          var significant = true
          var average : double = 0.0
          var variance : double = 0.0
          var count = 0
          -- check significance
          var r_min = ternary(row - half_width < win.top, win.top - row, -half_width)
          var r_max = ternary(row + half_width > win.bot, win.bot - row, half_width )
          var c_min = ternary(col - half_width < win.left, win.left - col, -half_width )
          var c_max = ternary(col + half_width > win.right, win.right - col, half_width )

          -- c.printf("row:%d,col:%d,r_min:%d,r_max:%d,c_min:%d,c_max:%d\n",row,col,r_min,r_max,c_min,c_max)

          for r = r_min, r_max do
            for c = c_min, c_max  do
              -- if ring_map[{r + half_width, c + half_width}] == 1 then
              if in_ring(0,0,r,c) then
                var intensity : double = data[{i, r + row, c + col}].intensity
                average += intensity
                variance += intensity * intensity
                count += 1
              end
            end
          end
          -- if count == 0 then c.printf("counter == 0!\n") end
          average /= [double](count)
          variance = variance / [double](count) - average * average
          var stddev : double = sqrt(variance)
          c.printf("i=%d, row=%d, col=%d, average: %f, stddev: %f\n",i,row,col,average,stddev)
          if data[{i, row, col}].intensity < average + SON_MIN * stddev then
            significant = false
          end
					
          if significant then
            var peak_helper : PeakHelper
            peak_helper:init(row,col,data[{i, row, col}].intensity,average,stddev,WIDTH,HEIGHT)
            
            r_conmap[{row, col}] = set
            queue:clear()
            queue:enqueue({i, row, col})
            peak_helper:add_point(data[{i, row, col}].intensity, row, col)

            r_min = ternary(win.top < row - rank, row - rank, win.top)
            r_max = ternary(win.bot > row + rank, row + rank, win.bot)
            c_min = ternary(win.left < col - rank, col - rank, win.left)
            c_max = ternary(win.right > col + rank, col + rank, win.right)

            while not queue:empty() do
              var p = queue:dequeue()
              var candidates : int3d[4]
              candidates[0] = {p.x, p.y - 1, p.z}
              candidates[1] = {p.x, p.y + 1, p.z}
              candidates[2] = {p.x, p.y, p.z - 1}
              candidates[3] = {p.x, p.y, p.z + 1}
              
              for j = 0, 4 do
                var t = candidates[j]
                if t.y >= r_min and t.y <= r_max and t.z >= c_min and t.z <= c_max then
                  if data[t].intensity > thr_low and r_conmap[{t.y,t.z}] == 0 then 
                    r_conmap[{t.y,t.z}] = set 
                    queue:enqueue(t)
                    peak_helper:add_point(data[t].intensity, t.y, t.z)
                  end
                end
              end
            end
            var peak : Peak = peak_helper:get_peak()
            -- var peak : Peak
            peak.valid = true
            peak.seg = index
            peaks[{p_i, shot_count, 0}] = peak
            shot_count += 1
            -- c.printf("peakFinderV4r2:index=%d\n",index)
          end
				end
			end
		end
	end
	
	return 0
end

task create_partition(r_shots : region(ispace(int3d), Pixel))
  var coloring = c.legion_domain_coloring_create()
  var bounds = r_shots.ispace.bounds
  c.legion_domain_coloring_color_domain(coloring, 0, bounds)
  var interior_image_partition = partition(disjoint, r_shots, coloring)
  c.legion_domain_coloring_destroy(coloring)
  return interior_image_partition
end

task dummy_task(r_peaks : region(ispace(int3d), Peak))
where
	reads writes (r_peaks)
do
  return 1
end

task writePeaks(r_peaks : region(ispace(int3d), Peak))
where
  reads(r_peaks)
do
  var f = c.fopen("peaks.txt",'w')
  var counter=0
  for event = 0,EVENTS do
    var counter = 0
    for shot  = 0, SHOTS do
      for i = 0, MAX_PEAKS do
        var peak : Peak = r_peaks[{event * EVENTS + shot, i, 0}]
        if peak.valid then
          c.fprintf(f,"%3d, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f\n",
            [int](peak.seg), peak.row, peak.col, peak.npix, peak.npos, peak.amp_max, peak.amp_tot, peak.row_cgrav, peak.col_cgrav, peak.row_sigma, peak.col_sigma, peak.row_min, peak.row_max, 
            peak.col_min, peak.col_max, peak.bkgd, peak.noise, peak.son)
        end
      end
    end
  end
  c.fclose(f)
end



task main()
  -- Configure --
  
  var config : SlacConfig
  config:initialize_from_command()
	
  var t0 = get_t0()
	var t1 = get_t1()
  
  c.printf("**********************************\n")
  c.printf("*          Peak Finder           *\n")
  c.printf("* Parallelism:          %*d *\n", 8, config.parallelism)
  c.printf("* Copies:               %*d *\n", 8, config.copies)
  c.printf("**********************************\n")
  -- Create event regions/partitions --
  
  var r_data = region(ispace(int3d, {EVENTS * SHOTS, HEIGHT, WIDTH}), Pixel)
  var r_peaks = region(ispace(int3d, {EVENTS * SHOTS * config.copies, MAX_PEAKS, 1}), Peak)
  init_peaks(r_peaks, config.copies)
  
  var p_colors = ispace(int3d, {config.parallelism, 1, 1})
  var p_peaks = partition(equal, r_peaks, p_colors)

  -- var r_p_data = region(ispace(int3d, {EVENTS * SHOTS * config.copies, HEIGHT, WIDTH}), Pixel)
  -- var p_data = partition(equal, r_p_data, p_colors)

  -- set threshold regions
  var r_thr_high = region(ispace(int1d, EVENTS * SHOTS * config.copies), double)
  var r_thr_low = region(ispace(int1d, EVENTS * SHOTS * config.copies), double)
  for i = 0, EVENTS * SHOTS * config.copies do
    var event = [uint32](i / SHOTS) % EVENTS
    r_thr_high[i] = t0[event]
    r_thr_low[i] = t1[event]
  end
  -- Load all event data --  
  
	c.printf("Loading in %d batches\n", config.parallelism)
	var ts_start = c.legion_get_current_time_in_micros()
  do
    var _ = 0
    _ += load_events(r_data)
    -- load_events(r_data)
    -- var _ = 0
    -- __demand(__parallel)
    -- for color in p_data.colors do
    --   _ += duplicate_events(r_data, p_data[color], p_data[color])
    -- end
    wait_for(_)
  end
	var ts_stop = c.legion_get_current_time_in_micros()
	c.printf("Loading took %.4f seconds\n", (ts_stop - ts_start) * 1e-6)
  
  -- Process all event data --
  var m_win : WinType
  m_win:init(0,0,WIDTH-1,HEIGHT-1)
	c.printf("Processing in %d batches\n", config.parallelism)
	ts_start = c.legion_get_current_time_in_micros()
  do
    var _ = 0
    __demand(__parallel)
    for color in p_peaks.colors do
      -- c.printf("p_data.bounds.lo.x:%d, p_data.bounds.hi.x:%d\n",p_data[color].bounds.lo.x, p_data[color].bounds.hi.x)
      _ += peakFinderV4r2(r_data, p_peaks[color], 1000, m_win, r_thr_high, r_thr_low, r0, dr)
      -- _ += peakFinderV4r2(p_data[color], p_peaks[color], r_thr_high, r_thr_low, r0, dr)
    end
    wait_for(_)
  end
	ts_stop = c.legion_get_current_time_in_micros()
	c.printf("Processing took %.4f seconds\n", (ts_stop - ts_start) * 1e-6)
  
  
  for event = 0, EVENTS do
    var count = 0
    for shot = 0, SHOTS do
      for i = 0, MAX_PEAKS do
        if not r_peaks[{SHOTS * event + shot, i, 0}].valid then --break 
        else count += 1 end
      end
    end
    c.printf("In event %d there were %d peaks\n", event, count)
  end
  writePeaks(r_peaks)
end

regentlib.start(main)