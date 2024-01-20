#!/usr/bin/env bash

data=data/wavlm
gmmdir=exp/wavlm/diag_ubm_normalized

stage=1 # start from stage 6
stop_stage=3

. ./cmd.sh
. ./path.sh
. parse_options.sh



if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ] && ! [[ " ${skip_stages} " =~ [[:space:]]1[[:space:]] ]]; then
  echo "stage 1: train the diagnoal UBM model for wavlm features"

  # the trained gmm model is stored in exp/wavlm/diag_ubm
  # use the script steps/nnet/ivector/train_wavlm_diag_ubm.sh
  # currently, without applying the normalization on the wavlm features
  # to be consistent with the original k-means clustering

  train_wavlm_diag_ubm.sh --nj 40 --cmd "$train_cmd" \
    --num-threads 8 \
    --num-frames 500000 \
    --num-iters 20 \
    --num-gselect 30 \
    --subsample 2 \
    --initial-gauss-proportion 0.5 \
    --cleanup true \
    --min-gaussian-weight 0.0001 \
    --remove-low-count-gaussians true \
    --num-threads 8 \
    ${data}/train_clean_100 2000 ${gmmdir}
fi

if [ ${stage} -le 2 ] && [ ${stop_stage} -ge 2 ] && ! [[ " ${skip_stages} " =~ [[:space:]]2[[:space:]] ]]; then
  echo "stage 2: dump the best gmm index for wavlm features"
  # the gmm index is stored in exp/wavlm/diag_ubm/gmm_index
  # use the gmm-gselect
  for test in test_clean test_other dev_clean dev_other train_clean_100; do
    #feats="ark,s,cs:apply-cmvn --norm-vars=false --utt2spk=ark:data/${test}/utt2spk scp:data/${test}/cmvn.scp scp:data/${test}/feats.scp ark:- |"
    # without applying the cmvn on the wavlm features first
#    feats="ark,s,cs:copy-feats scp:$data/${test}/feats.scp ark:- |"
#    gmm-gselect --n=1 ${gmmdir}/final.dubm \
#      "$feats" ark,t:- | \
#      awk '{print $2}' > ${gmmdir}/gmm_index/${test}.gmm_index
#  nj=20
#  target_folder=${gmmdir}/${test}_gmm_index
#  $cmd JOB=1:$nj ${target_folder}/log/gselect.JOB.log \
#    gmm-gselect --n=1 ${gmmdir}/final.dubm "$feats" \
#      "ark,t:${target_folder}/${test}_gmm_index.JOB"
#
#  # conbine the gselect.JOB.gmm_index to a single readable file
#  cat ${target_folder}/${test}_gmm_index.* > ${target_folder}/${test}_gmm_index

  dump_wavlm_gmm_index.sh --nj 10 --cmd "$train_cmd" \
    ${data}/${test} ${gmmdir}/gmm_index_${test}
  done

fi
if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ] && ! [[ " ${skip_stages} " =~ [[:space:]]3[[:space:]] ]]; then
  # the generated gmm index look like this: lbi-103-1240-0001 99 ; 429 ; 139 ; 1025 ; 643 ; 405 ; 194 ; 1132 ; 17 ; 1227 ; 1227 ; 1227 ; 1347 ; 606 ; 268
  # what we want to in this stage is to remove the ";" between the numbers
  echo "stage 3: remove the '; ' between the numbers in the gmm index"
  for test in test_clean test_other dev_clean dev_other train_clean_100; do
    sed -i 's/; //g' ${gmmdir}/gmm_index_${test}/gmm_index
  done
  # the generated gmm index look like this: lbi-103-1240-0001 99  429  139  1025  643  405
  # 194  1132  17  1227  1227  1227  1347  606  268
#  # we need to replace the two spaces with one space
#  for test in test_clean test_other dev_clean dev_other train_clean_100; do
#    sed -i 's/  / /g' ${gmmdir}/gmm_index_${test}/gmm_index
#  done

fi







