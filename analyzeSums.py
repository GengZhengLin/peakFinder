import argparse
import re
def AnalyzeSum(filename, num_of_images):
	f = open(filename,'r')
	lines = f.readlines()
	sums = [0.0] * num_of_images
	idxs = []
	r = re.compile(r"\d+\.\d+")
	rd = re.compile(r"\d+")
	for line in lines:
		if line.startswith("panelImage"):
			idx = rd.search(line).group()
			sum = r.search(line).group()
			sums[int(idx)] = float(sum)
			idxs.append(int(idx))

	f.close()
	f = open(filename + "_sum", "w")
	for sum in sums:
		f.write(str(sum)+"\n")
	f.close()
	idxs.sort()
	print(idxs)
	print(len(idxs))
	idx = 0
	for i in range(num_of_images):
		if 

if __name__ == '__main__':
	parser = argparse.ArgumentParser(description='analyze regent output file')
	parser.add_argument("f")
	args = parser.parse_args()

	AnalyzeSum(args.f,1000*32)