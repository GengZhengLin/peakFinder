import "regent"

-- Helper module to handle command line arguments
local SlacConfig = require("slac_config")
local Queue = require("queue")

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

--------------------------------------------------------------------------------
--                                   Structs                                  --
--------------------------------------------------------------------------------

struct Pixel {
	intensity : double;
	set : uint32;
	recent : uint32;
}

struct Peak {
  origin : int2d;
  valid  : bool;
}

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

task load_events(r_shots : region(ispace(int3d), Pixel))
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
					return
				end
        r_shots[{i, row, col}].intensity = x[0]
			end
		end
	end
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
  for shot = 0, EVENTS * SHOTS * copies do
    for i = 0, MAX_PEAKS do
      r_peaks[{shot, i, 0}].valid = false
    end
  end  
end

--------------------------------------------------------------------------------
--                                 Processing                                 --
--------------------------------------------------------------------------------

terra in_ring(cx : int32, cy : int32, px : int32, py : int32)
  var dist = (cx - px) * (cx - px) + (cy - py) * (cy - py)
  return dist >= r0 * r0 and dist <= (r0 + dr) * (r0 + dr)
end

task process_event(p_shots : region(ispace(int3d), Pixel), p_points : region(ispace(int3d), Pixel), p_peaks : region(ispace(int3d), Peak), t0 : double[5], t1 : double[5])
where
	reads writes (p_shots, p_peaks)
do
  var queue : Queue
  queue:init()
	var index : uint32
	index = 0
	c.printf("p_points.bounds.lo.x:%d, p_points.bounds.hi.x: %d\n",p_points.bounds.lo.x,p_points.bounds.hi.x)
	for i = p_points.bounds.lo.x, p_points.bounds.hi.x + 1 do
		var event = [uint32](i / SHOTS) % EVENTS
    var shot_count = 0
    for row = 0, HEIGHT do
			for col = 0, WIDTH do
				if p_shots[{i, row, col}].intensity > t0[event] then 
					index += 1 
					var set = index
          var significant = true
          if p_shots[{i, row, col}].set <= 0 then
            var total = 0
            var count = 0
            for r = max(0, [int32](row - r0 - dr)), min(HEIGHT, [int32](row + r0 + dr)) do
              for c = max(0, [int32](col - r0 - dr)), min(WIDTH, [int32](col + r0 + dr)) do
                if in_ring(row, col, r, c) then
                  total += p_shots[{i, r, c}].intensity
                  count += 1
                end
              end
            end
            var average = total / [double](count)
            var variance = 0.0
            for r = max(0, [int32](row - r0 - dr)), min(HEIGHT, [int32](row + r0 + dr)) do
              for c = max(0, [int32](col - r0 - dr)), min(WIDTH, [int32](col + r0 + dr)) do
                if in_ring(row, col, r, c) then
                  variance += (p_shots[{i, r, c}].intensity - average) * (p_shots[{i, r, c}].intensity - average)
                end
              end
            end
            var stddev = sqrt(variance / count)
            -- c.printf("i=%d, row=%d, col=%d, average=%f, stddev=%f\n",i,row,col,average,stddev)
            if p_shots[{i, row, col}].intensity < average + SON_MIN * stddev then
              significant = false
            else
              p_peaks[{i, shot_count, 0}].valid = true
              p_peaks[{i, shot_count, 0}].origin = {row, col}
              shot_count += 1
            end
            queue:clear()
            queue:enqueue({i, row, col})
            while not queue:empty() and significant do
              var p = queue:dequeue()
              var candidates : int3d[4]
              candidates[0] = {p.x, p.y - 1, p.z}
              candidates[1] = {p.x, p.y + 1, p.z}
              candidates[2] = {p.x, p.y, p.z - 1}
              candidates[3] = {p.x, p.y, p.z + 1}
              
              for j = 0, 4 do
                var t = candidates[j]
                if t.y >= 0 and t.y < HEIGHT and t.z >= 0 and t.z < WIDTH then
                  if p_shots[t].intensity > t1[event] and (p_shots[t].set == 0 or (p_shots[t].set == set and not p_shots[t].recent == index)) then 
                    if p_shots[t].set == 0 then 
                      p_shots[t].set = set 
                    end
                    p_shots[t].recent = index
                    queue:enqueue(t)
                  end
                end
              end
            end          
          end


					-- if p_shots[{i, row, col}].set > 0 then
					-- 	set = p_shots[{i, row, col}].set
     --      else
     --        var total = 0
     --        var count = 0
     --        for r = max(0, [int32](row - r0 - dr)), min(HEIGHT, [int32](row + r0 + dr)) do
     --          for c = max(0, [int32](col - r0 - dr)), min(WIDTH, [int32](col + r0 + dr)) do
     --            if in_ring(row, col, r, c) then
     --              total += p_shots[{i, r, c}].intensity
     --              count += 1
     --            end
     --          end
     --        end
     --        var average = total / [double](count)
     --        var variance = 0.0
     --        for r = max(0, [int32](row - r0 - dr)), min(HEIGHT, [int32](row + r0 + dr)) do
     --          for c = max(0, [int32](col - r0 - dr)), min(WIDTH, [int32](col + r0 + dr)) do
     --            if in_ring(row, col, r, c) then
     --              variance += (p_shots[{i, r, c}].intensity - average) * (p_shots[{i, r, c}].intensity - average)
     --            end
     --          end
     --        end
     --        var stddev = sqrt(variance / count)
     --        if p_shots[{i, row, col}].intensity < average + SON_MIN * stddev then
     --          significant = false
     --        else
     --          p_peaks[{i, shot_count, 0}].valid = true
     --          p_peaks[{i, shot_count, 0}].origin = {row, col}
     --          shot_count += 1
     --        end
					-- end
					
     --      queue:clear()
     --      queue:enqueue({i, row, col})
          
     --      while not queue:empty() and significant do
     --        var p = queue:dequeue()
     --        var candidates : int3d[4]
     --        candidates[0] = {p.x, p.y - 1, p.z}
     --        candidates[1] = {p.x, p.y + 1, p.z}
     --        candidates[2] = {p.x, p.y, p.z - 1}
     --        candidates[3] = {p.x, p.y, p.z + 1}
            
     --        for j = 0, 4 do
     --          var t = candidates[j]
     --          if t.y >= 0 and t.y < HEIGHT and t.z >= 0 and t.z < WIDTH then
     --            if p_shots[t].intensity > t1[event] and (p_shots[t].set == 0 or (p_shots[t].set == set and not p_shots[t].recent == index)) then 
     --              if p_shots[t].set == 0 then 
     --                p_shots[t].set = set 
     --              end
     --              p_shots[t].recent = index
     --              queue:enqueue(t)
     --            end
     --          end
     --        end
     --      end
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
        var peak :Peak = r_peaks[{event * EVENTS + shot, i, 0}]
        if peak.valid then
          c.fprintf(f,"%3d, %10d, %10d\n", counter, peak.origin.x, peak.origin.y)
          counter += 1
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
  
  var r_initial_events = region(ispace(int3d, {EVENTS * SHOTS, HEIGHT, WIDTH}), Pixel)
  var r_events = region(ispace(int3d, {EVENTS * SHOTS * config.copies, HEIGHT, WIDTH}), Pixel)
  
  var r_peaks = region(ispace(int3d, {EVENTS * SHOTS * config.copies, MAX_PEAKS, 1}), Peak)
  init_peaks(r_peaks, config.copies)
  var dummy = dummy_task(r_peaks)
  wait_for(dummy)
  
  var r_points = create_partition(r_events)[0]
  var p_colors = ispace(int3d, {config.parallelism, 1, 1})
  var p_points = partition(equal, r_points, p_colors)
  var p_events = partition(equal, r_events, p_colors)
  var p_peaks = partition(equal, r_peaks, p_colors)
  
  -- Load all event data --  
  
	c.printf("Loading in %d batches\n", config.parallelism)
	var ts_start = c.legion_get_current_time_in_micros()
  do
    load_events(r_initial_events)
    
    var _ = 0
    __demand(__parallel)
    for color in p_points.colors do
      _ += duplicate_events(r_initial_events, p_events[color], p_points[color])
    end
    wait_for(_)
  end
	var ts_stop = c.legion_get_current_time_in_micros()
	c.printf("Loading took %.4f seconds\n", (ts_stop - ts_start) * 1e-6)
  
  -- Process all event data --
  
	c.printf("Processing in %d batches\n", config.parallelism)
	ts_start = c.legion_get_current_time_in_micros()
  do
    var _ = 0
    __demand(__parallel)
    for color in p_points.colors do
      _ += process_event(p_events[color], p_points[color], p_peaks[color], t0, t1)
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