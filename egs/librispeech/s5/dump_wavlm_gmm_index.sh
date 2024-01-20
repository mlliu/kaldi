#!/usr/bin/env bash

# Copyright   2012  Johns Hopkins University (Author: Daniel Povey)
#             2013  Daniel Povey
#             2016  Brno University of Technology (Author: Karel Vesely)
# Apache 2.0.

# This script trains a diagonal UBM that we'll use in online iVector estimation,
# where the online-estimated iVector will be used as a secondary input to a deep
# neural net for single-pass DNN-based decoding.

# This script was modified from ../../sre08/v1/sid/train_diag_ubm.sh.
# It trains a diagonal UBM on top of input features. We use the original features,
# assuming they are already normalized (or transformed).

# This script does not use the trained model from the source directory to
# initialize the diagonal GMM; instead, we initialize the GMM using
# gmm-global-init-from-feats, which sets the means to random data points and
# then does some iterations of E-M in memory.  After the in-memory
# initialization we train for a few iterations in parallel.
# Note that there is a slight mismatch in that the source LDA+MLLT matrix
# (final.mat) will have been estimated using standard CMVN, and we're using
# online CMVN.  We don't think this will have much effect.


# Begin configuration section.
nj=10
cmd=run.pl

num_gselect=1 # Number of Gaussian-selection indices to use while training
               # the model.
# End configuration section.

echo "$0 $@"  # Print the command line for logging

[ -f ./path.sh ] && . ./path.sh; # source the path.
. parse_options.sh || exit 1;

if [ $# != 2 ]; then
  echo "Usage: $0  <data>  <output-dir>"
  echo " e.g.: $0 data/train exp/diag_ubm/gmm_index"
  echo "Options: "
  echo "  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --nj <num-jobs|4>                                # number of parallel jobs to run."
  exit 1;
fi

set -euo pipefail

data=$1 # data/wavlm/train_clean_100, which contains feats.scp
dir=$2 # exp/wavlm/diag_ubm/gmm_index_train_clean_100, which is to store the gmm_index



sdata=$data/split$nj
mkdir -p $dir
mkdir -p $dir/log
utils/split_data.sh $data $nj || exit 1;

for f in $data/feats.scp; do
   [ ! -f "$f" ] && echo "$0: expecting file $f to exist" && exit 1
done

# Note: there is no point subsampling all_feats, because gmm-global-init-from-feats
# effectively does subsampling itself (it keeps a random subset of the features).
#feats="ark,s,cs:copy-feats scp:$sdata/JOB/feats.scp ark:- |" # subsample-feats --n=$subsample ark:- ark:- |"

# apply the cmvn
feats="ark,s,cs:apply-cmvn --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:$sdata/JOB/feats.scp ark:- |"

  # defaultly, the gmm model is stored at the above folder of dir
gmmdir=$dir/../
echo "$gmmdir $nj $dir"
$cmd JOB=1:$nj ${dir}/log/gselect.JOB.log \
  gmm-gselect --n=1 ${gmmdir}/final.dubm "$feats" \
   ark,t:${dir}/gmm_index.JOB || exit 1;
#  "ark:|gzip -c >$dir/gselect.JOB.gz" || exit 1;


# conbine the gselect.JOB.gz to a single readable file
#for n in $(seq $nj); do
#  gunzip -c $dir/gselect.$n.gz || exit 1;
#done > $dir/gmm_index || exit 1;
cat $dir/gmm_index.* > $dir/gmm_index || exit 1;

exit 0 # Done!

