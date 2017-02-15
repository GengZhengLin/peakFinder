import argparse
import re
def AnalyzeRegentOutput(filename):
	f = open(filename,'r')
	lines = f.readlines()
	starts = []
	ends = []
	r = re.compile(r"\d+\.\d+")
	for line in lines:
		if line.startswith("peakFinderTask"):
			nums = r.findall(line)
			starts.append(float(nums[0]))
			ends.append(float(nums[1]))
	first_start = min(starts)
	last_start = max(starts)
	last_end = max(ends)
	execution = [ends[i] - starts[i] for i in range(len(starts))]
	max_execution = max(execution)
	avg_execution = sum(execution) / len(execution)
	print("tasks starts from {0}, ends at {1}. task running time: {2:.4f} secs".format(first_start, last_end, last_end - first_start))
	print("max execution: {0:.4f} secs, avg execution:{1:.4f}".format(max_execution,avg_execution))
	print("min start:{0:4f}, max start:{1:4f}, max-min:{2:.4f}".format(first_start,last_start,last_start-first_start))

if __name__ == '__main__':
	parser = argparse.ArgumentParser(description='analyze regent output file')
	parser.add_argument("f")
	args = parser.parse_args()

	AnalyzeRegentOutput(args.f)