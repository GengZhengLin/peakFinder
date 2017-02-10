import "regent"
local c = regentlib.c
local C = terralib.includecstring([[
#include "stdio.h"
#include "stdlib.h"
]])
local cstr = terralib.includec("string.h")
task printString(str : rawstring)
	c.printf("%s",str)
end

local str1 = "str1"
local str2 = "str2"
task main()
	var str = [str1 .. str2]
	printString(str)	
end

task concatString()
	var str : rawstring = "str"
	var numStr : char[20]
	var num : int = 20
	-- c.printf("%s\n", cstr.strcat(str,C.itoa(numStr,num,10)))
	c.sprintf(str,"str%d\n", 20)
	c.printf("%s",str)
end
regentlib.start(concatString)
