import os
import argparse
import re

parser = argparse.ArgumentParser(description='merge Files')
parser.add_argument('folder')

args = parser.parse_args()

files = os.listdir(args.folder)

numToName = {}
r = re.compile(r'\d+')
for file in files:
	if file.startswith('peaks'):
		nums=r.findall(file)
		numToName[int(nums[0])] = file

# print(numToName)
num = 0
f = open(args.folder+"/merged",'w')
while True:
	if not num in numToName:
		break;
	file = numToName[num]
	fr = open(args.folder+"/"+file,'r')
	lines = fr.readlines()
	if len(lines) == 0:
		print(file + ": emplty!")
	f.writelines(lines)
	nums = r.findall(file)
	num = int(nums[1])+1
print("num:{0}".format(num))
