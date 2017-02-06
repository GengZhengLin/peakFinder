import argparse

def AnalyzeRegentOutput(filename):
	f = open(filename,'r')
	lines = f.readlines()
	while 