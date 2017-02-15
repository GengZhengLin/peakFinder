import "regent"

-- Helper module to handle command line arguments
local SlacConfig = require("slac_config")
local Queue = require("queue")
local Peak = require("peak")
local PeakHelper = require("peakHelper")

local sqrt = regentlib.sqrt(double)

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
local BUFFER_SIZE = 400

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

-- __demand(__cuda)
task AlImgProc.peakFinderV4r2(data : region(ispace(int3d), Pixel), peaks : region(ispace(int3d), Peak),  rank : int, win : WinType, thr_high : double, thr_low : double, r0 : double, dr : double, r_conmap : region(ispace(int3d), uint32))
where
	reads (data), writes(peaks), reads writes(r_conmap)
do
  var ts_start = c.legion_get_current_time_in_micros()
	var index : uint32 = 1
  var half_width : int = [int](r0 + dr)
  -- c.printf("p_data.bounds.lo.x:%d, p_data.bounds.hi.x:%d\n",peaks.bounds.lo.x, peaks.bounds.hi.x)
  var HEIGHT = data.bounds.hi.y + 1
  var WIDTH = data.bounds.hi.x + 1
  var idx_x : int[BUFFER_SIZE]
  var idx_y : int[BUFFER_SIZE]
  -- c.printf("height:%d,width:%d\n",HEIGHT,WIDTH)
  -- var r_conmap = region(ispace(int2d, {WIDTH,HEIGHT}), uint32)
  -- for p_i in is do
  for i = data.bounds.lo.z, data.bounds.hi.z + 1 do
    for j = 0, MAX_PEAKS do
      peaks[{0,j,i}].valid = false
    end 
  end
  
	for p_i = data.bounds.lo.z, data.bounds.hi.z + 1 do
    var queue : Queue
    queue:init()
    var shot_count = 0   
    for ty = 0, HEIGHT do
      for tx = 0, WIDTH do
        r_conmap[{tx, ty, p_i}] = 0
      end
    end

    for row = win.top, win.bot + 1 do
			for col = win.left, win.right + 1 do
        -- if (row == 182 and col == 31 and p_i == 65) then
        --   c.printf('row == 182 and col == 31, data[{col, row, i}].cspad: %.4f, r_conmap[{col, row, p_i}]:%d\n', data[{col, row, i}].cspad, r_conmap[{col, row, p_i}])
        -- end
				if data[{col, row, p_i}].cspad > thr_high and r_conmap[{col, row, p_i}] <= 0 and shot_count <= MAX_PEAKS then
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

          for r = r_min, r_max + 1 do
            for c = c_min, c_max + 1 do
              if in_ring(c,r,r0,dr) and data[{c + col, r + row, p_i}].cspad < thr_low then
                var cspad : double = data[{c + col, r + row, p_i}].cspad
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
					
          if significant then
            -- clear buffer
            for i = 0, (2*rank+1)*(2*rank+1) do
              idx_x[i] = -1
              idx_y[i] = -1
            end

            r_min = ternary(win.top < row - rank, row - rank, win.top)
            r_max = ternary(win.bot > row + rank, row + rank, win.bot)
            c_min = ternary(win.left < col - rank, col - rank, win.left)
            c_max = ternary(win.right > col + rank, col + rank, win.right)

            var pix_counter = 0
            var peak_helper : PeakHelper
            -- c.printf("i:%d,row:%d,col:%d,cspad:%f\n",i,row,col,data[{i, row, col}].cspad)
            peak_helper:init(row,col,data[{col,row,p_i}].cspad,average,stddev, p_i%SHOTS, WIDTH,HEIGHT)

            queue:clear()
            queue:enqueue({col,row,p_i})
            idx_x[pix_counter] = col
            idx_y[pix_counter] = row
            pix_counter += 1
            r_conmap[{col, row, p_i}] = set
            -- c.printf("r_min:%d,r_max:%d,c_min:%d,c_max:%d\n",r_min,r_max,c_min,c_max)
            var is_local_maximum = true
            while not queue:empty() do
              if not is_local_maximum then break end
              var p = queue:dequeue()
              var candidates : int3d[4]
              candidates[0] = {p.x - 1, p.y, p.z}
              candidates[1] = {p.x + 1, p.y, p.z}
              candidates[2] = {p.x, p.y - 1, p.z}
              candidates[3] = {p.x, p.y + 1, p.z}
              
              for j = 0, 4 do
                var t = candidates[j]
                if t.y >= r_min and t.y <= r_max and t.x >= c_min and t.x <= c_max then
                  if data[t].cspad > thr_low and r_conmap[{t.x, t.y, p_i}] == 0 then 
                    is_local_maximum = data[t].cspad <= data[{col, row, p_i}].cspad
                    if not is_local_maximum then break end
                    queue:enqueue(t)
                    idx_x[pix_counter] = t.x
                    idx_y[pix_counter] = t.y
                    pix_counter += 1
                    r_conmap[{t.x, t.y, p_i}] = set 
                  end
                end
              end
            end
            -- c.printf("After flood fill\n")
            var add_point_success = false
            if is_local_maximum then
              for i = 0, pix_counter do
                var x = idx_x[i]
                var y = idx_y[i]
                peak_helper:add_point(data[{x,y,p_i}].cspad, y, x)
              end
              var peak : Peak = peak_helper:get_peak()
              -- c.printf("peak_helper:get_peak()\n")
              if peakIsPreSelected(peak) then
                peak.valid = true
                peaks[{0, shot_count, p_i}] = peak
                add_point_success = true
                -- c.printf("peaks[{p_i, shot_count, 0}] = peak\n")
                shot_count += 1
              end
            else
              for i = 0, pix_counter do
                r_conmap[{idx_x[i], idx_y[i], p_i}] = 0
              end
            end
            -- c.printf("After setting peaks\n")
          end
				end
			end
		end
	end
	var ts_stop = c.legion_get_current_time_in_micros()
  c.printf("peakFinderTask: (%d - %d) starts from %.4f, ends at %.4f\n", data.bounds.lo.z, data.bounds.hi.z + 1, (ts_start) * 1e-6, (ts_stop) * 1e-6)
  -- c.printf("data.bounds.lo.z:%d, data.bounds.hi.z:%d, peaks.bounds.lo.z:%d, peaks.bounds.hi.z:%d, equal:%d\n", data.bounds.lo.z, data.bounds.hi.z, peaks.bounds.lo.z, peaks.bounds.hi.z, 
  --     (data.bounds.lo.z == peaks.bounds.lo.z) and (data.bounds.hi.z == peaks.bounds.hi.z))
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

