# this python script applies the map file to the input file and writes the output to the output file

import sys
import os
from collections import defaultdict
import argparse

def apply_map(map_file, input_file, output_file):
    lexicon = defaultdict(list)
    with open(map_file, 'r') as f:
        map_lines = f.readlines()
    for line in map_lines:
        line = line.strip()
        word = line.split()[0]
        phones = line.split()[1:]
        lexicon[word] = phones
    with open(input_file, 'r') as f:
        input_lines = f.readlines()
    total_count= 0
    total_words = 0
    count = 0
    with open(output_file, 'w') as f:
        for line in input_lines:
            count += 1
            line = line.strip()
            uttid = line.split()[0]
            words = line.split()[1:]
            phones = []
            for word in words:
                total_words += 1
                if word in lexicon:
                    phones.extend(lexicon[word])
                    total_count += len(lexicon[word])
                else:
                    # if the word is not in the lexicon, we assume it is a OOV and we map it to the OOV symbol
                    phones.append('<unk>')
                    count += 1
            f.write(uttid + ' ' + ' '.join(phones) + '\n')
    print('ratio of out of vocabulary phones: ', count/total_count)
    print('ratio of out of vocabulary words: ', count/total_words)
    return

def main():
    parser = argparse.ArgumentParser(description='Apply map file to input file')
    parser.add_argument('map_file', type=str, help='map file')
    parser.add_argument('input_file', type=str, help='input file')
    parser.add_argument('output_file', type=str, help='output file')
    args = parser.parse_args()
    apply_map(args.map_file, args.input_file, args.output_file)

if __name__ == '__main__':
    main()