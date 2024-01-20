#!/usr/bin/env bash
# apply lda on the features extracted from s3prl SSL framework

stage=3
stop_stage=4
skip_stages=
skip_train=true # skip the training stage of the lda transformation matrix

feat_type=wavlm
datadir=data/${feat_type} # to store the scp file
expdir=exp/${feat_type} # to store the experiment
featdir=feat/${feat_type}/lda # to store the dimension reduced feature
dir=${expdir}/lda
alidir=exp/pca80_wavlm/tri4b/align_train_clean_100
lang=data/lang_nosp

lda_feat_type=lda80_wavlm
lda_datadir=data/${lda_feat_type} # to store the lda_feat scp file

silphonelist=`cat $lang/phones/silence.csl` || exit 1;
nj=`cat $alidir/num_jobs` || exit 1;
randprune=4.0 # This is approximately the ratio by which we will speed up the
              # LDA and MLLT calculations via randomized pruning.
splice_opts="--left-context=3 --right-context=3"
dim=80 # the dimension of the feature after the lda

# setup the train, dev and test set
train_set= #"train_clean_100"
#train_dev="dev"
test_sets="eval2000" #"test_clean test_other dev_clean dev_other"

. ./cmd.sh
. ./path.sh
. parse_options.sh
cmd=$train_cmd

set -e

if $skip_train; then
  skip_stages+=" 2"
fi
echo "skip stages: ${skip_stages}"

if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ] && ! [[ " ${skip_stages} " =~ [[:space:]]1[[:space:]] ]]; then
  #stage 1, copy the ssl feature from the dump dir to the data dir
    echo "stage 1: copy the ssl feature from the dump dir to the data dir"
    if "${skip_train}"; then
      _dsets="${test_sets}"
    else
      _dsets="${train_set} ${test_sets}"
    fi

    #for part in dev_clean test_clean dev_other test_other train_clean_100; do
    for part in ${_dsets}; do
    #steps/make_mfcc.sh --cmd "$train_cmd" --nj 40 data/$part exp/make_mfcc/$part $mfccdir
    utils/copy_data_dir.sh --validate_opts --non-print "data/${part}" "${datadir}/${part}"
    # copy feat_pca80.scp to feat_pca80_wavlm.scp from the source directory to the target directory
    # and add the lbi before each line
    source=/export/fs05/mliu121/espnet_data/librispeech_100_asr2/dump/extracted/wavlm_large/layer21/${part}/feats.scp
    #cp ${source} ${datadir}/${part}/feats.scp
    target=${datadir}/${part}/feats.scp
    # add the lbi on each line of the feats.scp
    if [ -f ${target} ]; then
      rm ${target}
    fi
    while IFS= read -r line; do
      echo "lbi-${line}" >> ${target}
    done < ${source}

    # copy the utt2num_frames from the source directory to the target directory
    source=/export/fs05/mliu121/espnet_data/librispeech_100_asr2/dump/extracted/wavlm_large/layer21/${part}/utt2num_frames
    target=${datadir}/${part}/utt2num_frames
    if [ -f ${target} ]; then
      rm ${target}
    fi
    while IFS= read -r line; do
      echo "lbi-${line}" >> ${target}
    done < ${source}

    # rewrite the frame_shift file is 0.02
    if [ -f ${datadir}/${part}/frame_shift ]; then
      rm ${datadir}/${part}/frame_shift
    fi
    echo "0.02" >> ${datadir}/${part}/frame_shift

    # don't compute the cmvn stats, since the dimension of the feature is too large 1024
    steps/compute_cmvn_stats.sh ${datadir}/${part} ${expdir}/make_cmvn/${part} ${featdir}
  done
fi

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ] && ! [[ " ${skip_stages} " =~ [[:space:]]2[[:space:]] ]]; then
    # acc-lda and est-lda to calculate the lda matrix based on train_clean_100
    # split the training data into nj parts for parallel computing
    echo "stage 2: acc-lda and est-lda to calculate the lda matrix based on train_clean_100"
    sdata=$datadir/train_clean_100/split$nj;
    split_data.sh $datadir/train_clean_100 $nj || exit 1;

    # splice features with left and right context
    # why we nned to use left and right context?
    # because we need to use the context information to predict the current frame
    splicedfeats="ark,s,cs:splice-feats $splice_opts scp:$sdata/JOB/feats.scp ark:- |"

    echo "$0: Accumulating LDA statistics."
    #rm $dir/lda.*.acc 2>/dev/null
    $cmd JOB=1:$nj $dir/log/lda_acc.JOB.log \
    ali-to-post "ark:gunzip -c $alidir/ali.JOB.gz|" ark:- \| \
      weight-silence-post 0.0 $silphonelist $alidir/final.mdl ark:- ark:- \| \
      acc-lda --rand-prune=$randprune $alidir/final.mdl "$splicedfeats" ark,s,cs:- \
      $dir/lda.JOB.acc || exit 1;

#      # because the size of alignment and the size of feature are not the same
#      # so we need to perform the subsampling on the alignment based on the feature
#
#      # first we get the posteriors from the alignment and write it to ark file, and then
#      # we read the ark file and perform the subsampling
#      ali-to-post "ark:gunzip -c $alidir/ali.JOB.gz|" ark,t


    echo "$0: Estimating LDA matrix."
    est-lda --write-full-matrix=$dir/full.mat --dim=$dim $dir/0.mat $dir/lda.*.acc \
      2>$dir/log/lda_est.log || exit 1;
    rm $dir/lda.*.acc
fi

if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ] && ! [[ " ${skip_stages} " =~ [[:space:]]3[[:space:]] ]]; then
  # apply the lda matrix on the feature stored at datadir, and store the feature in the featdir
  # use transform-feats to apply the lda matrix on the feature
  echo  "stage 3: apply the lda matrix on the feature stored at datadir, and store the feature in the featdir"
  if "${skip_train}"; then
    _dsets="${test_sets}"
  else
    _dsets="${train_set} ${test_sets}"
  fi

  #for part in dev_clean test_clean dev_other test_other train_clean_100; do
  for part in ${_dsets}; do
    # if the featdir does not exist, then create it
    if [ ! -d ${featdir}/${part} ]; then
      mkdir -p ${featdir}/${part}
    fi

    # split the training data into nj parts for parallel computing
    sdata=${datadir}/${part}/split$nj;
    split_data.sh ${datadir}/${part} $nj || exit 1;
    splicedfeats="ark,s,cs:splice-feats $splice_opts scp:$sdata/JOB/feats.scp ark:- |"

    # apply the lda matrix on the feature
    $cmd JOB=1:$nj $dir/log/lda_transform.JOB.log \
    transform-feats $dir/0.mat \
     "${splicedfeats}" \
     ark,scp:${featdir}/${part}/feats.lda.JOB.ark,${featdir}/${part}/feats.lda.JOB.scp || exit 1;

      # merge the scp files
      for n in $(seq $nj); do
        cat ${featdir}/${part}/feats.lda.${n}.scp
      done > ${featdir}/${part}/feats.lda.scp

  done
fi

if [ ${stage} -le 4 ] && [ ${stop_stage} -ge 4 ] && ! [[ " ${skip_stages} " =~ [[:space:]]4[[:space:]] ]]; then
  #  compute the cmvn stats for the lda feature, and then copy the data dir to the lda_datadir
  echo "stage 4: compute the cmvn stats for the lda feature, and then copy the data dir to the lda_datadir"
  if "${skip_train}"; then
    _dsets="${test_sets}"
  else
    _dsets="${train_set} ${test_sets}"
  fi

  for part in ${_dsets}; do
  #for part in dev_clean test_clean dev_other test_other train_clean_100; do
    utils/fix_data_dir.sh  ${datadir}/${part}

    utils/copy_data_dir.sh --validate_opts --non-print "${datadir}/${part}" "${lda_datadir}/${part}"
    # copy the feats.lda.scp to feats.scp
    source=${featdir}/${part}/feats.lda.scp
    target=${lda_datadir}/${part}/feats.scp
    if [ -f ${target} ]; then
      rm ${target}
    fi
    while IFS= read -r line; do
      echo "${line}" >> ${target}
    done < ${source}

    utils/fix_data_dir.sh ${lda_datadir}/${part}

    # compute the cmvn stats for the lda feature
    steps/compute_cmvn_stats.sh ${lda_datadir}/${part} ${expdir}/make_cmvn/${part} ${featdir}
  done
fi