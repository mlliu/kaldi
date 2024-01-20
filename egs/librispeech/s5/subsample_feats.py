# this python code is used to read the mfcc features from the kaldi format
# and then subsample the features to 2 times the original frame rate, make sure that it numbe rof frames is euqal to wavLM data
# write the subsampled features to the kaldi format

import kaldiio
from kaldiio import WriteHelper
from kaldiio import ReadHelper
import numpy as np
#import soundfile
#import torch
import re

datadir= "data/"
outputdir= "data/subsample"
wavlm_dir= "data/wavlm"

dataset=["train_clean_100","dev_clean","dev_other","test_clean","test_other"]



# for data in ["test_clean"]:
#     print(data)
#
#     #open the utt2num_frames file in the wavLM data, to get the number of frames for each utterance
#
#     with open(f"{wavlm_dir}/{data}/utt2num_frames", "r") as f:
#         utt2num_frames = {line.split()[0]: int(line.split()[1]) for line in f}
#
#     # open the feats.scp file in the wavLM data, to get the path of the mfcc features for each utterance
#     with ReadHelper(f"scp:{datadir}/{data}/feats.scp") as reader:
#         for key, array in reader:
#             print("key",key)
#             print("array shape",array.shape)
#             print("target number of frames",utt2num_frames[key])
#             # subsample the features to 2 times the original frame rate
#             array=array[::2,:]
#             # compare the array's shape with the target number of frames
#
#             print("array shape after subsampling",array.shape)
#             # write the subsampled features to the kaldi format
#             #with WriteHelper(f"ark,scp:{outputdir}/{data}/feats.ark,{outputdir}/{data}/feats.scp") as writer:
#             #    writer[key] = array

# read 1.post and for each line, its format is like this: utt-ids [ 2 1 ] [ 1 1 ]
# split each line into format like this: utt-ids, [ 2 1 ], [ 1 1 ]

file=open("1.post","r")
count=0
for line in file:
    line=line.strip()
    # each line is like this: utt-ids [ 2 1 ] [ 1 1 ]
    # split each line into format like this: utt-ids, [ 2 1 ], [ 1 1 ]
    utt_id=line.split()[0]
    print(utt_id)
    # get each element, like [ 2 1 ]
    pattern=re.compile(r'\[.*?\]')
    post=pattern.findall(line)




