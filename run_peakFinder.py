import os
from datetime import datetime
import argparse

def run_peafFinder():

	parser = argparse.ArgumentParser(description='run peakFinder')
	parser.add_argument('-nodes', type=int, default=10)
	parser.add_argument('-py', action='store_true')
	parser.add_argument('-gpu',action='store_true')
	parser.add_argument('-cmd',action='store_true')

	args = parser.parse_args()
	# log_file = "log/log-"+datetime.now().strftime('%m-%d-%H:%M:%S')+".log"

	if args.gpu:
		for i in range(16,129,16):
			command = "python /reg/neh/home/zhenglin/legion/language/regent.py peakFinder.rg -p {0} -ll:fsize 10000 -ll:csize 10000".format(i)
			print(command)
			os.system(command)
		return

	nodes = args.nodes
	log_file = "log/log_{0}".format(nodes)
	if args.py:
		log_file += '_py'
		command = "bsub -q psfehprioq -n {1} -o {0}  \"mpirun python benchmark_peakFInder.py\"".format(log_file, nodes*16)
	else:
		command = "bsub -q psfehprioq -n {1} -o {0}  \"LAUNCHER='mpirun --bind-to none -np {2} -npernode 1' python /reg/neh/home/zhenglin/legion/language/regent.py peakFinder.rg -p {3} -ll:csize 40000 -ll:cpu 15\"".format(log_file, nodes*16, nodes, nodes*15)
	print(command)
	if args.cmd:
		if os.path.isfile(log_file):
			print('delete '+log_file)
			os.remove(log_file)
		os.system(command)
# os.system(command)

run_peafFinder()