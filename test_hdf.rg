import "regent"

local c = regentlib.c

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

struct ImgContext{
	EVENTS : int;
	SHOTS : int;
	WIDTH : int;
	HEIGHT : int;
	MAX_PEAKS : int;
	SON_MIN : int;
}

struct ImgWrapper{
	cspad : float
}


terra ImgContext:init()
	self.EVENTS = 5
	self.SHOTS = 32
	self.HEIGHT = 185
	self.WIDTH = 388
	self.MAX_PEAKS = 200
	self.SON_MIN = 40
end

local filename = "small_test_resized.h5"

task print_region(r : region(ispace(int3d), ImgWrapper))
where
	reads (r)
do
	for i = r.bounds.lo.x, r.bounds.hi.x do
		c.printf("%f ", r[{i,0,0}].cspad)
	end
	c.printf("\n")
end

task main()
	var ctx : ImgContext;
	ctx:init();
	var r_img = region(ispace(int3d, {ctx.EVENTS * ctx.SHOTS, ctx.HEIGHT, ctx.WIDTH}), ImgWrapper)
	var p_img = partition(equal, r_img, ispace(int3d, {5, 1, 1}))
	attach(hdf5, r_img, filename, regentlib.file_read_only)
	acquire(r_img)
	for color in p_img.colors do
		-- acquire((p_img[color]))
		print_region(p_img[color])
		-- release((p_img[color]))
	end
	release(r_img)
	detach(hdf5, r_img)
end

regentlib.start(main)