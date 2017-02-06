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
local EVENTS = 6000
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
-- local data_file = "test3.bin"
local data_file = "/reg/d/psdm/cxi/cxitut13/scratch/cpo/test6000.bin"
-- local data_file = "/reg/d/psdm/cxi/cxitut13/scratch/cpo/test1000.bin"
local h5_data_file = "small_test_resized.h5"

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
    -- c.printf('%f ', r_shots[{i,0,0}].cspad)
  end
  c.printf('load data finished\n')
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

task writePeaks(r_peaks : region(ispace(int3d), Peak))
where
  reads(r_peaks)
do
  var f = c.fopen("peakFindResult_regent",'w')
  c.printf("write to peakFindResult_regent\n")
  var hdr = 'Seg  Row  Col  Npix      Amax      Atot   rcent   ccent rsigma  csigma rmin rmax cmin cmax    bkgd     rms     son\n'
  for event = 0, EVENTS do
    c.fprintf(f,hdr)
    var count = 0
    for shot = 0, SHOTS do
      for i = 0, MAX_PEAKS do
        var peak : Peak = r_peaks[{0, i, SHOTS * event + shot}]
        if peak.valid then --break 
          count += 1
          c.fprintf(f,"%3d %4d %4d  %4d  %8.1f  %8.1f  %6.1f  %6.1f %6.2f  %6.2f %4d %4d %4d %4d  %6.2f  %6.2f  %6.2f\n",
            [int](peak.seg), [int](peak.row), [int](peak.col), [int](peak.npix), peak.amp_max, peak.amp_tot, peak.row_cgrav, peak.col_cgrav, peak.row_sigma, peak.col_sigma, 
            [int](peak.row_min), [int](peak.row_max), [int](peak.col_min), [int](peak.col_max), peak.bkgd, peak.noise, peak.son)
        end
      end
    end
    c.printf("In event %d there were %d peaks\n\n", event, count)
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
  var ts_start = c.legion_get_current_time_in_micros()
  var is = ispace(int1d, EVENTS * SHOTS)
  do
    var _ = load_data(r_data)
    wait_for(_)
  end
  var ts_stop = c.legion_get_current_time_in_micros()
  c.printf("Loading took %.4f seconds\n", (ts_stop - ts_start) * 1e-6)
  
  var p_data = partition(equal, r_data, p_colors)

  ts_start = c.legion_get_current_time_in_micros()
  do
    var _ = 0
    -- _+=AlImgProc.peakFinderV4r2(r_data, r_peaks, is, 4, m_win, THR_HIGH, THR_LOW, r0, dr)
    for color in p_data.colors do
      _ += AlImgProc.peakFinderV4r2(p_data[color], p_peaks[color], 4, m_win, THR_HIGH, THR_LOW, r0, dr)
    end
    wait_for(_)
  end

  ts_stop = c.legion_get_current_time_in_micros()
  c.printf("Processing took %.4f seconds\n", (ts_stop - ts_start) * 1e-6)
  
  printPeaks(r_peaks)
  -- writePeaks(r_peaks)

  -- AlImgProc.writePeaks(r_peaks)

end

regentlib.start(main)
