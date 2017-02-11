import "regent"

local c = regentlib.c

task printRegion(nums : region(ispace(int1d), int))
where reads(nums)
do
	-- c.printf("0\n")
	c.printf("print from %d to %d\n", [int](nums.bounds.lo), [int](nums.bounds.hi))
	return 0
end

local NUM = 32000
local REGIONS = 60
task main()
	var r_nums = region(ispace(int1d, NUM), int)
	var p_nums = partition(equal, r_nums, ispace(int1d, REGIONS))
	for color in p_nums.colors do
		printRegion(p_nums[color])
	end
end

regentlib.start(main)