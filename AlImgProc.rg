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
local AlImgProc = {}

local SHOTS = 32
local MAX_PEAKS = 200
local npix_min = 2
local npix_max = 50
local amax_thr = 10
local atot_thr = 20
local son_min = 5
local SON_MIN = 5


terra ternary(cond : bool, T : int, F : int)
  if cond then return T else return F end
end
--------------------------------------------------------------------------------
--                                   Structs                                  --
--------------------------------------------------------------------------------

struct Pixel {
	cspad : float
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
--                                 Processing                                 --
--------------------------------------------------------------------------------

terra in_ring(dx : int32, dy : int32, r0 : double, dr : double)
  var dist = dx * dx + dy * dy
  return dist >= r0 * r0 and dist <= (r0 + dr) * (r0 + dr)
end

terra peakIsPreSelected(peak : Peak)
  if peak.son < son_min then return false end
  if peak.npix < npix_min then return false end
  if peak.npix > npix_max then return false end
  if peak.amp_max < amax_thr then return false end
  if peak.amp_tot < atot_thr then return false end
  return true
end

task AlImgProc.peakFinderV4r2(data : region(ispace(int3d), Pixel), peaks : region(ispace(int3d), Peak), rank : int, win : WinType, thr_high : double, thr_low : double, r0 : double, dr : double)
where
	reads (data), writes(peaks)
do
  var queue : Queue
  queue:init()
	var index : uint32 = 0
  var half_width : int = [int](r0 + dr)
 --  var width : int = 2 * half_width + 1
	-- var ring_map = region(ispace(int2d, {width, width}),int)
  -- generate_ring_map(r0,dr,ring_map)
  -- c.printf("p_data.bounds.lo.x:%d, p_data.bounds.hi.x:%d\n",peaks.bounds.lo.x, peaks.bounds.hi.x)
  var HEIGHT = data.bounds.hi.y + 1
  var WIDTH = data.bounds.hi.x + 1
  var r_conmap = region(ispace(int2d, {WIDTH,HEIGHT}), uint32)
	for p_i = peaks.bounds.lo.z, peaks.bounds.hi.z + 1 do
    -- var i = [uint32](p_i) % (EVENTS * SHOTS)
    var i = p_i
    -- var thr_high = r_thr_high[p_i]
    -- var thr_low = r_thr_low[p_i]
    var shot_count = 0   
    for ele in r_conmap do
      @ele = 0
    end
    for row = win.top, win.bot + 1 do
			for col = win.left, win.right + 1 do
				if data[{col, row, i}].cspad > thr_high and r_conmap[{col, row}] <= 0 and shot_count <= MAX_PEAKS then
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
          -- c.printf("i:%d,row:%d,col:%d\n",i,row,col)

          for r = r_min, r_max + 1 do
            for c = c_min, c_max + 1 do
              -- if ring_map[{r + half_width, c + half_width}] == 1 then
              if in_ring(r,c,r0,dr) and data[{c + col, r + row, i}].cspad < thr_low then
                var cspad : double = data[{c + col, r + row, i}].cspad
                average += cspad
                variance += cspad * cspad
                count += 1
              end
            end
          end
          -- if count == 0 then c.printf("counter == 0!\n") end
          var stddev : double = 0.0
          if count > 0 then
            average /= [double](count)
            variance = variance / [double](count) - average * average
            stddev = sqrt(variance)
          end
          -- c.printf("i=%d, row=%d, col=%d, average: %f, stddev: %f\n",i,row,col,average,stddev)

          -- hack
          -- if data[{i, row, col}].cspad < average + SON_MIN * stddev then
          --   significant = false
          -- end
          -- c.printf("significant:%d\n",significant)
					
          if significant then

            r_min = ternary(win.top < row - rank, row - rank, win.top)
            r_max = ternary(win.bot > row + rank, row + rank, win.bot)
            c_min = ternary(win.left < col - rank, col - rank, win.left)
            c_max = ternary(win.right > col + rank, col + rank, win.right)

            var is_local_maximum = true
            for r = r_min, r_max + 1 do
              for c = c_min, c_max + 1 do
                if data[{c,r,i}].cspad > data[{col,row,i}].cspad then
                  is_local_maximum = false
                  break
                end
              end
              if not is_local_maximum then break end
            end

            if is_local_maximum then
              var peak_helper : PeakHelper
              -- c.printf("i:%d,row:%d,col:%d,cspad:%f\n",i,row,col,data[{i, row, col}].cspad)
              peak_helper:init(row,col,data[{col,row,i}].cspad,average,stddev, p_i%SHOTS, WIDTH,HEIGHT)
              
              r_conmap[{col,row}] = set
              queue:clear()
              queue:enqueue({col,row,i})
              peak_helper:add_point(data[{col,row,i}].cspad, row, col)
              -- c.printf("r_min:%d,r_max:%d,c_min:%d,c_max:%d\n",r_min,r_max,c_min,c_max)
              while not queue:empty() do
                var p = queue:dequeue()
                var candidates : int3d[4]
                candidates[0] = {p.x - 1, p.y, p.z}
                candidates[1] = {p.x + 1, p.y, p.z}
                candidates[2] = {p.x, p.y - 1, p.z}
                candidates[3] = {p.x, p.y + 1, p.z}
                
                for j = 0, 4 do
                  var t = candidates[j]
                  if t.y >= r_min and t.y <= r_max and t.x >= c_min and t.x <= c_max then
                    if data[t].cspad > thr_low and r_conmap[{t.x,t.y}] == 0 then 
                      r_conmap[{t.x,t.y}] = set 
                      queue:enqueue(t)
                      peak_helper:add_point(data[t].cspad, t.y, t.x)
                    end
                  end
                end
              end
              -- c.printf("After flood fill\n")
              var peak : Peak = peak_helper:get_peak()
              -- c.printf("peak_helper:get_peak()\n")
              -- var peak : Peak
              if peakIsPreSelected(peak) then
                peak.valid = true
                peaks[{0, shot_count, p_i}] = peak
                -- c.printf("peaks[{p_i, shot_count, 0}] = peak\n")
                shot_count += 1
              end
              -- c.printf("After setting peaks\n")
            end
          end
				end
			end
		end
	end
	
	return 0
end

-- task AlImgProc.writePeaks(r_peaks : region(ispace(int3d), Peak))
-- where
--   reads(r_peaks)
-- do
--   var f = c.fopen("peaks.txt",'w')
--   for event = r_peaks.bounds.lo.x, r_peaks.bounds.hi.x + 1 do
--     for i = r_peaks.bounds.lo.y, r_peaks.bounds.hi.y + 1 do
--       var peak : Peak = r_peaks[{event, i, 0}]
--       if peak.valid then
--         c.fprintf(f,"%3d, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f, %10.2f\n",
--           [int](peak.seg), peak.row, peak.col, peak.npix, peak.npos, peak.amp_max, peak.amp_tot, peak.row_cgrav, peak.col_cgrav, peak.row_sigma, peak.col_sigma, peak.row_min, peak.row_max, 
--           peak.col_min, peak.col_max, peak.bkgd, peak.noise, peak.son)
--       end
--     end
--   end
--   c.fclose(f)
-- end

return AlImgProc

