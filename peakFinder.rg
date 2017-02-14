import "regent"

local c = regentlib.c
local SlacConfig = require("slac_config")
local AlImgProc = require("AlImgProc")

local hdf_dir = "/reg/neh/home/zhenglin/Tools/myhdf5/include"
local hdf5 = terralib.includec("hdf5.h", {"-I", hdf_dir})

-- there's some funny business in hdf5.h that prevents terra from being able to
--  see some of the #define's, so we fix it here, and hope the HDF5 folks don't
--  change the internals very often...
hdf5.H5F_ACC_TRUNC = 2
hdf5.H5T_STD_I32LE = hdf5.H5T_STD_I32LE_g
hdf5.H5T_STD_I64LE = hdf5.H5T_STD_I64LE_g
hdf5.H5T_IEEE_F64LE = hdf5.H5T_IEEE_F64LE_g
hdf5.H5P_DEFAULT = 0

-- local EVENTS = 5

-- local EVENTS = 1000
local SHOTS = 32
local HEIGHT = 185
local WIDTH = 388
local MAX_PEAKS = 200
local rank = 4
local r0 = 5
local dr = 0.05
local THR_LOW = 10
local THR_HIGH = 150
-- clustter test
local EVENTS = 1000
local data_file = "/reg/d/psdm/cxi/cxitut13/scratch/cpo/test1000.bin"

-- local test
-- local EVENTS = 5
-- local data_file = "small_test"
-- local dir = "/home/zhenglin/WinterProject/peakFinder"


task print_region(r : region(ispace(int3d), Pixel))
where
  reads (r)
do
  for i = r.bounds.lo.x, r.bounds.hi.x do
    c.printf("%f ", r[{i,0,0}].cspad)
  end
  c.printf("\n")
end

terra read_float(f : &c.FILE, number : &float)
  return c.fread(number, sizeof(float), 1, f) == 1
  -- return c.fscanf(f, "%f", &number[0]) == 1
end

task load_data(r_shots : region(ispace(int3d), Pixel))
where
  reads writes(r_shots)
do
  var f = c.fopen(data_file, "rb")
  
  c.printf("Loading %s into panels %d through %d\n", data_file, r_shots.bounds.lo.z, r_shots.bounds.hi.z)
  
  var x : float[1]
  for i = 0, EVENTS * SHOTS do
    for row = 0, HEIGHT do
      for col = 0, WIDTH do
        if not read_float(f, x) then
          c.printf("Couldn't read data in shot %d\n", row)
          return -1
        end
        r_shots[{col,row,i}].cspad = x[0]
      end
    end
  end
  c.printf('load data finished\n')
  return 0
end

task parallel_load_data(r_data : region(ispace(int3d), Pixel))
where reads writes (r_data)
do
  c.printf("Loading %s into panels %d through %d\n", data_file, r_data.bounds.lo.z, r_data.bounds.hi.z)
  var sizeofFloat : int = 4
  var offset = (r_data.bounds.lo.z) * WIDTH * HEIGHT * sizeofFloat
  var f = c.fopen(data_file, "rb")
  c.fseek(f,offset,c.SEEK_SET)
  var x : float[1]
  -- c.printf("r_data.bounds.lo.z, r_data.bounds.hi.z + 1 = %d, %d\n",r_data.bounds.lo.z, r_data.bounds.hi.z + 1)
  for i = r_data.bounds.lo.z, r_data.bounds.hi.z + 1 do
    for row = 0, HEIGHT do
      for col = 0, WIDTH do
        if not read_float(f, x) then
          c.printf("parallel_load_data: Couldn't read data in shot %d\n", i)
          return -1
        end
        r_data[{col,row,i}].cspad = x[0]
      end
    end
  end
  return 0
end

task printPeaks(r_peaks : region(ispace(int3d), Peak))
where
  reads(r_peaks)
do
  for event = 0, EVENTS do
    var count = 0
    for shot = 0, SHOTS do
      for i = 0, MAX_PEAKS do
        var peak : Peak = r_peaks[{0, i, SHOTS * event + shot}]
        if peak.valid then --break 
          count += 1
          -- c.printf("%3d %4d  %4d  %4d  %8.1lf\n",
          -- [int](peak.seg), [int](peak.row), [int](peak.col), [int](peak.npix), peak.amp_tot)
        end
      end
    end
    c.printf("In event %d there were %d peaks\n", event, count)
  end
end

task calSum(r_data : region(ispace(int3d), Pixel), r_sums : region(ispace(int3d), float))
where reads (r_data), writes(r_sums)
do
  -- var filename : rawstring = "                            "
  -- c.printf("r_data.bounds.lo.z, r_data.bounds.hi.z: (%d,%d)\n",r_data.bounds.lo.z, r_data.bounds.hi.z)
  -- c.sprintf(filename, "pixelSum_%d", parallelism)
  -- c.printf("Write to %s\n", filename)
  -- var f = c.fopen(filename,'w')
  -- var img_num = r_data.bounds.hi.z - r_data.bounds.lo.z + 1;
  -- var sums = region(ispace(int1d, img_num), float)
  for i = r_data.bounds.lo.z, r_data.bounds.hi.z+1 do
    var sum = 0.0
    for r = r_data.bounds.lo.y, r_data.bounds.hi.y+1 do
      for c = r_data.bounds.lo.z, r_data.bounds.hi.z+1 do
        sum += r_data[{c,r,i}].cspad
      end
    end
    r_sums[{0,0,i}] = sum
    -- c.printf("panelImage:%d,sum:%.4f\n",i,sum)
  end
  -- for i = r_data.bounds.lo.z, r_data.bounds.hi.z+1 do
  --   c.fprintf(f,"%.4f\n", sums[i])
  -- end
  return 0
end

task printSum(r_sums : region(ispace(int3d), float), parallelism : int)
where reads (r_sums)
do
  -- var filename : rawstring = "                                   "
  -- c.sprintf(filename, "pixelSum_%d", parallelism)
  -- var f = c.fopen(filename, 'w')
  for i = [int](r_sums.bounds.lo.z), [int](r_sums.bounds.hi.z)+1 do
    -- c.fprintf(f,"panelImage:%d,sum:%.4f\n",i,r_sums[{0,0,i}])
    c.printf("panelImage:%d,sum:%.4f\n",i,r_sums[{0,0,i}])
  end
end

task dummy_task(r_peaks : region(ispace(int3d), Peak))
where
  reads writes (r_peaks)
do
  return 1
end

-- task writePeaks(r_peaks : region(ispace(int3d), Peak), parallelism : int)
-- where
--   reads writes(r_peaks)
-- do
--   var filename : rawstring = "                                           "
--   c.sprintf(filename, "peakFindResult_regent_%d", parallelism)
--   var f = c.fopen(filename,'w')
--   c.printf("write to %s\n", filename)
--   var hdr = 'Seg  Row  Col  Npix      Amax      Atot   rcent   ccent rsigma  csigma rmin rmax cmin cmax    bkgd     rms     son\n'
--   for event = 0, EVENTS do
--     -- c.fprintf(f,"event:%d\n", event)
--     c.fprintf(f,hdr)
--     var count = 0
--     for shot = 0, SHOTS do
--       -- c.fprintf(f,"panels:%d\n",shot)
--       for i = 0, MAX_PEAKS do
--         var peak : Peak = r_peaks[{0, i, SHOTS * event + shot}]
--         if peak.valid then --break 
--           count += 1
--           c.fprintf(f,"%3d %4d %4d  %4d  %8.1f  %8.1f  %6.1f  %6.1f %6.2f  %6.2f %4d %4d %4d %4d  %6.2f  %6.2f  %6.2f\n",
--             [int](peak.seg), [int](peak.row), [int](peak.col), [int](peak.npix), peak.amp_max, peak.amp_tot, peak.row_cgrav, peak.col_cgrav, peak.row_sigma, peak.col_sigma, 
--             [int](peak.row_min), [int](peak.row_max), [int](peak.col_min), [int](peak.col_max), peak.bkgd, peak.noise, peak.son)
--         end
--       end
--     end
--     c.printf("In event %d there were %d peaks\n\n", event, count)
--   end
-- end

task writePeaks(r_peaks : region(ispace(int3d), Peak), color : int3d, parallelism : int)
where
  reads writes(r_peaks)
do
  var filename : int8[256]
  c.sprintf([&int8](filename), "peaks_%d/peaks_%d_%d", parallelism, r_peaks.bounds.lo.z,r_peaks.bounds.hi.z)
  c.printf("write to %s\n", filename)
  var f = c.fopen(filename,'w')
  c.printf("color:%d,%d,%d\n", color.x, color.y, color.z)
  var hdr = 'Evt Seg  Row  Col  Npix      Amax      Atot   rcent   ccent rsigma  csigma rmin rmax cmin cmax    bkgd     rms     son\n'
  for j = r_peaks.bounds.lo.z, r_peaks.bounds.hi.z+1 do
    var event = j / SHOTS
    var shot = j % SHOTS
    for i = 0, MAX_PEAKS do
      var peak : Peak = r_peaks[{0, i, SHOTS * event + shot}]
      if peak.valid then --break 
        c.fprintf(f,"%3d %3d %4d %4d  %4d  %8.1f  %8.1f  %6.1f  %6.1f %6.2f  %6.2f %4d %4d %4d %4d  %6.2f  %6.2f  %6.2f\n", event,
          [int](peak.seg), [int](peak.row), [int](peak.col), [int](peak.npix), peak.amp_max, peak.amp_tot, peak.row_cgrav, peak.col_cgrav, peak.row_sigma, peak.col_sigma, 
          [int](peak.row_min), [int](peak.row_max), [int](peak.col_min), [int](peak.col_max), peak.bkgd, peak.noise, peak.son)
      end
    end
  end
end

terra wait_for(x : int)
  return x
end

task main()
  -- Configure --
  
  var config : SlacConfig
  config:initialize_from_command()
  
  var p_colors = ispace(int3d, {1, 1, config.parallelism})
  var r_peaks = region(ispace(int3d, {1, MAX_PEAKS, EVENTS * SHOTS}), Peak)
  var p_peaks = partition(equal, r_peaks, p_colors)

	c.printf("Loading in %d batches\n", config.parallelism)

  var m_win : WinType
  m_win:init(0,0,WIDTH-1,HEIGHT-1)
	c.printf("Processing in %d batches\n", config.parallelism)

  var r_data = region(ispace(int3d, {WIDTH, HEIGHT, EVENTS * SHOTS}), Pixel)
  var p_data = partition(equal, r_data, p_colors)
  var is = ispace(int1d, EVENTS * SHOTS)

  var r_sums = region(ispace(int3d, {1,1,EVENTS * SHOTS}), float);
  fill(r_sums, -1)
  var p_sums = partition(equal, r_sums, p_colors)
  -- load data
  var ts_start = c.legion_get_current_time_in_micros()
  c.printf("Start sending loading tasks at %.4f\n", (ts_start) * 1e-6)
  do
    var _ = 0
    for color in p_data.colors do
      _ += parallel_load_data(p_data[color])
    end
    wait_for(_)
  end

  -- do
  --   var _ = load_data(r_data)
  --   wait_for(_)
  -- end

  -- process data
  var r_conmap = region(ispace(int3d, {WIDTH,HEIGHT,is.volume}), uint32)
  var p_conmap = partition(equal, r_conmap, p_colors)
  ts_start = c.legion_get_current_time_in_micros()
  c.printf("Start sending out tasks at %.4f\n", (ts_start) * 1e-6)
  do
    -- _+=AlImgProc.peakFinderV4r2(r_data, r_peaks, is, 4, m_win, THR_HIGH, THR_LOW, r0, dr, r_conmap)
    -- var _ = 0
    __demand(__spmd)
    for color in p_data.colors do
      AlImgProc.peakFinderV4r2(p_data[color], p_peaks[color], 4, m_win, THR_HIGH, THR_LOW, r0, dr, p_conmap[color])
    end
  end
  -- ts_stop = c.legion_get_current_time_in_micros()
  -- c.printf("Processing took %.4f seconds\n", (ts_stop - ts_start) * 1e-6)
  
  -- printPeaks(r_peaks)
  for color in p_peaks.colors do
    writePeaks(p_peaks[color], color, config.parallelism)
  end

  return 0
end


if os.getenv('SAVEOBJ') == '1' then
  -- local dir = "/home/zhenglin/WinterProject/peakFinder"
  local dir = "/reg/neh/home/zhenglin/Code/peakFinder"
  local exe  = dir .. "/peakFinder"
  regentlib.saveobj(main, exe, "executable")
  print("Saved executable to " .. exe)
  -- local env = ""
  -- if os.getenv("DYLD_LIBRARY_PATH") then
  --   env = "DYLD_LIBRARY_PATH=" .. os.getenv("DYLD_LIBRARY_PATH") .. " "
  -- end
  -- print("env:" .. env)
  -- -- Pass the arguments along so that the child process is able to
  -- -- complete the execution of the parent.
  -- local args = ""
  -- for _, arg in ipairs(rawget(_G, "arg")) do
  --   args = args .. " " .. arg
  -- end
  -- assert(os.execute(env .. exe .. args) == 0)
else
  regentlib.start(main)
end


-- regentlib.start(main)
